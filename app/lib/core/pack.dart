/// 資料包的檔案格式（GitHub Actions 每天產生，App 下載）。純 Dart。
///
/// release「data」裡放：
/// - `daily-YYYY.json.gz`：那一年每個交易日的收盤、加權指數、報酬指數、
///   本益比／淨值比／殖利率、三大法人。三年以前的只留收盤和成交量（長期分析用不到開高低）。
/// - `recent.json.gz`：最近 30 個交易日（App 每天只要下載這個小檔）。
/// - `revenue.json.gz`：上市公司每月營收。
/// - `dividends.json.gz`：除權息事件。
/// - `intl.json.gz`：國際指標（費半、Nasdaq、VIX、美元台幣、美債殖利率）。
/// - `manifest.json`：每個檔案的大小、雜湊、涵蓋日期，App 用來判斷要不要重抓。
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;

import '../models/daily_bar.dart';
import 'sources.dart';

/// 存檔用的數字：四捨五入到 [dp] 位，整數就存成整數（檔案小很多）。
num packNum(double x, [int dp = 2]) {
  final f = math.pow(10, dp).toDouble();
  final r = (x * f).roundToDouble() / f;
  return r == r.truncateToDouble() && r.abs() < 1e15 ? r.toInt() : r;
}

List<num> barRow(DailyBar b, {bool compact = false}) => compact
    ? [packNum(b.close), b.volumeLots, if (b.change != null) packNum(b.change!)]
    : [
        packNum(b.open),
        packNum(b.high),
        packNum(b.low),
        packNum(b.close),
        b.volumeLots,
        if (b.change != null) packNum(b.change!),
      ];

/// 一列收盤資料：完整的是 [開, 高, 低, 收, 張, 漲跌?]，精簡的是 [收, 張, 漲跌?]。
extension PackRow on List<num> {
  bool get isFull => length >= 5;
  double get close => (isFull ? this[3] : this[0]).toDouble();
  int get lots => (isFull ? this[4] : this[1]).toInt();
  double? get change {
    final i = isFull ? 5 : 2;
    return length > i ? this[i].toDouble() : null;
  }

  DailyBar? toBar(String date) => isFull
      ? DailyBar(
          date: date,
          open: this[0].toDouble(),
          high: this[1].toDouble(),
          low: this[2].toDouble(),
          close: close,
          volumeLots: lots,
          change: change,
        )
      : null;
}

class PackDay {
  final String date;
  final double? taiex;

  /// 發行量加權股價報酬指數（含息），回測的比較基準。
  final double? tri;
  final Map<String, List<num>> twse;
  final Map<String, List<num>> tpex;

  /// [本益比, 股價淨值比, 殖利率%]。
  final Map<String, List<num?>> val;

  /// [外資, 投信, 自營商] 買賣超張數。
  final Map<String, List<int>> inst;

  const PackDay({
    required this.date,
    this.taiex,
    this.tri,
    this.twse = const {},
    this.tpex = const {},
    this.val = const {},
    this.inst = const {},
  });

  PackDay copyWith({
    double? taiex,
    double? tri,
    Map<String, List<num>>? twse,
    Map<String, List<num>>? tpex,
    Map<String, List<num?>>? val,
    Map<String, List<int>>? inst,
  }) => PackDay(
    date: date,
    taiex: taiex ?? this.taiex,
    tri: tri ?? this.tri,
    twse: twse ?? this.twse,
    tpex: tpex ?? this.tpex,
    val: val ?? this.val,
    inst: inst ?? this.inst,
  );

  /// 只留收盤和成交量（給三年以前的資料用）。
  PackDay compacted() => copyWith(
    twse: {
      for (final e in twse.entries)
        e.key: e.value.isFull ? [e.value[3], e.value[4], if (e.value.length > 5) e.value[5]] : e.value,
    },
    tpex: const {},
  );

  /// 有完整開高低收的話，轉成 App 原本的「一天全市場行情」。
  DaySnapshot? snapshot() {
    if (twse.isEmpty || !twse.values.first.isFull) return null;
    final bars = <String, DailyBar>{};
    for (final m in [tpex, twse]) {
      for (final e in m.entries) {
        final b = e.value.toBar(date);
        if (b != null) bars[e.key] = b;
      }
    }
    return DaySnapshot(date: date, trading: true, bars: bars, taiex: taiex);
  }

  Map<String, dynamic> toJson() => {
    'd': date,
    if (taiex != null) 'ix': packNum(taiex!),
    if (tri != null) 'tr': packNum(tri!),
    't': twse,
    if (tpex.isNotEmpty) 'o': tpex,
    if (val.isNotEmpty) 'f': val,
    if (inst.isNotEmpty) 'i': inst,
  };

  static PackDay fromJson(Map<String, dynamic> j) {
    Map<String, List<num>> rows(Object? m) => {
      for (final e in ((m as Map?) ?? const {}).entries) e.key as String: [for (final x in e.value as List) x as num],
    };
    return PackDay(
      date: j['d'] as String,
      taiex: (j['ix'] as num?)?.toDouble(),
      tri: (j['tr'] as num?)?.toDouble(),
      twse: rows(j['t']),
      tpex: rows(j['o']),
      val: {
        for (final e in ((j['f'] as Map?) ?? const {}).entries)
          e.key as String: [for (final x in e.value as List) x as num?],
      },
      inst: {
        for (final e in ((j['i'] as Map?) ?? const {}).entries)
          e.key as String: [for (final x in e.value as List) (x as num).toInt()],
      },
    );
  }
}

/// 一年的資料檔。
class PackYear {
  final int year;
  final Map<String, PackDay> days;

  /// 抓過、確定沒開盤的平日（颱風假、年假），不用再抓。
  final Set<String> closed;

  /// 代號 → 名稱（含已下市的股票）。
  final Map<String, String> names;

  /// 有缺的部分，之後再補：日期 → ['f'（本益比）, 'i'（法人）, 'o'（上櫃）]。
  final Map<String, List<String>> partial;

  PackYear(
    this.year, {
    Map<String, PackDay>? days,
    Set<String>? closed,
    Map<String, String>? names,
    Map<String, List<String>>? partial,
  }) : days = days ?? {},
       closed = closed ?? {},
       names = names ?? {},
       partial = partial ?? {};

  List<PackDay> get sortedDays => days.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  String? get lastDate => days.isEmpty ? null : (days.keys.toList()..sort()).last;
  String? get firstDate => days.isEmpty ? null : (days.keys.toList()..sort()).first;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'year': year,
    'days': [for (final d in sortedDays) d.toJson()],
    'closed': closed.toList()..sort(),
    'names': names,
    if (partial.isNotEmpty) 'partial': partial,
  };

  static PackYear fromJson(Map<String, dynamic> j) => PackYear(
    (j['year'] as num).toInt(),
    days: {for (final d in j['days'] as List) (d as Map<String, dynamic>)['d'] as String: PackDay.fromJson(d)},
    closed: {for (final d in (j['closed'] as List? ?? const [])) d as String},
    names: {for (final e in ((j['names'] as Map?) ?? const {}).entries) e.key as String: e.value as String},
    partial: {
      for (final e in ((j['partial'] as Map?) ?? const {}).entries)
        e.key as String: [for (final x in e.value as List) x as String],
    },
  );
}

/// 上市公司每月營收（千元）。
class RevenueData {
  /// 第一個月 yyyy-MM。
  final String start;

  /// 代號 → 從 [start] 開始每個月的營收，沒有是 null。
  final Map<String, List<double?>> byCode;

  RevenueData(this.start, Map<String, List<double?>>? byCode) : byCode = byCode ?? {};

  static int monthIndex(String ym) => int.parse(ym.substring(0, 4)) * 12 + int.parse(ym.substring(5, 7)) - 1;
  static String monthOf(int idx) => '${idx ~/ 12}-${(idx % 12 + 1).toString().padLeft(2, '0')}';

  int get startIdx => monthIndex(start);

  /// 有資料的最後一個月。
  String? get lastMonth {
    var best = -1;
    for (final l in byCode.values) {
      for (var k = l.length - 1; k > best; k--) {
        if (l[k] != null) {
          best = k;
          break;
        }
      }
    }
    return best < 0 ? null : monthOf(startIdx + best);
  }

  /// 這個月有多少家公司公布了營收。
  int countFor(String ym) {
    final k = monthIndex(ym) - startIdx;
    if (k < 0) return 0;
    return byCode.values.where((l) => k < l.length && l[k] != null).length;
  }

  double? at(String code, int monthIdx) {
    final l = byCode[code];
    final k = monthIdx - startIdx;
    if (l == null || k < 0 || k >= l.length) return null;
    return l[k];
  }

  void put(String code, int monthIdx, double v) {
    final k = monthIdx - startIdx;
    if (k < 0) return;
    final l = byCode[code] ??= [];
    while (l.length <= k) {
      l.add(null);
    }
    l[k] = v;
  }

  /// 加入一個月的營收；順便用「去年當月營收」補上去年同月缺的資料。
  void addMonth(String ym, MonthRevenue m) {
    final idx = monthIndex(ym);
    for (final e in m.entries) {
      put(e.key, idx, e.value.$1);
      final p = e.value.$2;
      if (p != null && p > 0 && at(e.key, idx - 12) == null) put(e.key, idx - 12, p);
    }
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'start': start,
    'data': {
      for (final e in byCode.entries) e.key: [for (final x in e.value) x == null ? null : packNum(x, 0)],
    },
  };

  static RevenueData fromJson(Map<String, dynamic> j) => RevenueData(j['start'] as String, {
    for (final e in ((j['data'] as Map?) ?? const {}).entries)
      e.key as String: [for (final x in e.value as List) (x as num?)?.toDouble()],
  });
}

class DividendData {
  final Map<String, List<DivEvent>> byCode;
  DividendData([Map<String, List<DivEvent>>? byCode]) : byCode = byCode ?? {};

  /// 合併新抓的事件（同一天同一檔以新的為準）。
  void merge(Map<String, List<DivEvent>> add) {
    for (final e in add.entries) {
      final m = {for (final x in byCode[e.key] ?? const <DivEvent>[]) x.date: x};
      for (final x in e.value) {
        m[x.date] = x;
      }
      byCode[e.key] = m.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    }
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'events': {
      for (final e in byCode.entries) e.key: [for (final x in e.value) x.toRow()],
    },
  };

  static DividendData fromJson(Map<String, dynamic> j) => DividendData({
    for (final e in ((j['events'] as Map?) ?? const {}).entries)
      e.key as String: [for (final r in e.value as List) DivEvent.fromRow(r as List)],
  });
}

class IntlData {
  final Map<String, IntlSeries> series;
  const IntlData(this.series);

  Map<String, dynamic> toJson() => {
    'v': 1,
    'series': {for (final e in series.entries) e.key: e.value.toJson()},
  };

  static IntlData fromJson(Map<String, dynamic> j) => IntlData({
    for (final e in ((j['series'] as Map?) ?? const {}).entries)
      e.key as String: IntlSeries.fromJson(e.key as String, e.value as Map<String, dynamic>),
  });
}

/// 最近 N 個交易日（App 每天的小更新）。
class RecentPack {
  final List<PackDay> days;
  final Map<String, String> names;
  const RecentPack(this.days, this.names);

  Map<String, dynamic> toJson() => {
    'v': 1,
    'days': [for (final d in days) d.toJson()],
    'names': names,
  };

  static RecentPack fromJson(Map<String, dynamic> j) => RecentPack(
    [for (final d in j['days'] as List) PackDay.fromJson(d as Map<String, dynamic>)],
    {for (final e in ((j['names'] as Map?) ?? const {}).entries) e.key as String: e.value as String},
  );
}

List<int> encodeGz(Map<String, dynamic> json) => gzip.encode(utf8.encode(jsonEncode(json)));
Map<String, dynamic> decodeGz(List<int> bytes) => jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;

/// 簡單的檔案指紋（FNV-1a 32 位元），判斷檔案有沒有變。
String fingerprint(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// manifest 裡的一個檔案。
class PackFileInfo {
  final String name;
  final int size;
  final String hash;
  final String? first, last;
  const PackFileInfo(this.name, this.size, this.hash, {this.first, this.last});

  Map<String, dynamic> toJson() => {'size': size, 'hash': hash, 'first': ?first, 'last': ?last};
  static PackFileInfo fromJson(String name, Map<String, dynamic> j) => PackFileInfo(
    name,
    (j['size'] as num).toInt(),
    j['hash'] as String,
    first: j['first'] as String?,
    last: j['last'] as String?,
  );
}

class PackManifest {
  final String updated; // ISO 時間（UTC）
  final String? lastDate; // 最新的交易日
  final Map<String, PackFileInfo> files;
  const PackManifest(this.updated, this.lastDate, this.files);

  List<int> get years => [
    for (final n in files.keys)
      if (RegExp(r'^daily-(\d{4})\.json\.gz$').hasMatch(n)) int.parse(n.substring(6, 10)),
  ]..sort();

  Map<String, dynamic> toJson() => {
    'v': 1,
    'updated': updated,
    'lastDate': lastDate,
    'files': {for (final e in files.entries) e.key: e.value.toJson()},
  };

  static PackManifest fromJson(Map<String, dynamic> j) =>
      PackManifest(j['updated'] as String? ?? '', j['lastDate'] as String?, {
        for (final e in ((j['files'] as Map?) ?? const {}).entries)
          e.key as String: PackFileInfo.fromJson(e.key as String, e.value as Map<String, dynamic>),
      });
}
