/// 長期資料的來源解析（純 Dart，App 和 GitHub Actions 的資料包程式共用）：
///
/// - 證交所 MI_INDEX：每日收盤（在 history_service）＋加權指數、加權報酬指數（含息）。
/// - 證交所 BWIBBU_d：每檔的本益比、股價淨值比、殖利率（每天）。
/// - 證交所 T86：三大法人每天買賣超。
/// - 證交所 TWT49U：除權息事件。
/// - 公開資訊觀測站：上市公司每月營收。
/// - 國際指標：FRED（美國聯準會資料庫）CSV、Yahoo 的日線 JSON。
///
/// 欄位位置交易所改過好幾次，所以一律用欄位名稱找欄位。
library;

import '../services/history_service.dart' show twseTables;
import '../services/quote_service.dart' show parseNum;

String _norm(Object? f) => f.toString().replaceAll(RegExp(r'\s'), '');

/// 一般普通股：四位數字、不是 0 開頭（0 開頭是 ETF）。特別股、存託憑證、權證都不是。
bool isCommonStockCode(String code) => RegExp(r'^[1-9]\d{3}$').hasMatch(code);

/// MI_INDEX 的「報酬指數」表：發行量加權股價報酬指數（含現金股利再投入）。
double? parseTaiexTotalReturn(Map<String, dynamic> body) {
  for (final (fields, data) in twseTables(body)) {
    final names = [for (final f in fields) _norm(f)];
    final nameCol = names.indexWhere((n) => n == '指數' || n == '報酬指數');
    final closeCol = names.indexWhere((n) => n.contains('收盤指數'));
    if (nameCol < 0 || closeCol < 0) continue;
    for (final row in data) {
      if (row is List && row.length > closeCol && _norm(row[nameCol]).contains('發行量加權股價報酬指數')) {
        return parseNum(row[closeCol]);
      }
    }
  }
  return null;
}

/// MI_INDEX 的每檔名稱（下市的股票內建清單裡沒有，資料包自己記）。
Map<String, String> parseTwseNames(Map<String, dynamic> body) {
  for (final (fields, data) in twseTables(body)) {
    final names = [for (final f in fields) _norm(f)];
    final code = names.indexWhere((n) => n.contains('證券代號'));
    final name = names.indexWhere((n) => n.contains('證券名稱'));
    if (code < 0 || name < 0) continue;
    final out = <String, String>{};
    for (final row in data) {
      if (row is List && row.length > name) out[row[code].toString().trim()] = row[name].toString().trim();
    }
    if (out.isNotEmpty) return out;
  }
  return {};
}

/// BWIBBU_d：代號 → [本益比, 股價淨值比, 殖利率%]，沒有（例如虧損沒有本益比）是 null。
Map<String, List<double?>> parseBwibbu(Map<String, dynamic> body) {
  for (final (fields, data) in twseTables(body)) {
    final names = [for (final f in fields) _norm(f)];
    final code = names.indexWhere((n) => n.contains('代號'));
    final pe = names.indexWhere((n) => n.startsWith('本益比'));
    final pb = names.indexWhere((n) => n.startsWith('股價淨值比'));
    final yld = names.indexWhere((n) => n.startsWith('殖利率'));
    if (code < 0 || (pe < 0 && pb < 0 && yld < 0)) continue;
    final out = <String, List<double?>>{};
    for (final row in data) {
      if (row is! List) continue;
      double? at(int i) {
        if (i < 0 || i >= row.length) return null;
        final v = parseNum(row[i]);
        return v == null || v <= 0 ? null : v;
      }

      final c = row[code].toString().trim();
      if (c.isEmpty) continue;
      out[c] = [at(pe), at(pb), at(yld)];
    }
    return out;
  }
  return {};
}

/// T86：代號 → [外資, 投信, 自營商] 買賣超（張）。外資＝外陸資（不含外資自營商）＋外資自營商。
Map<String, List<int>> parseT86(Map<String, dynamic> body) {
  for (final (fields, data) in twseTables(body)) {
    final names = [for (final f in fields) _norm(f)];
    final code = names.indexWhere((n) => n.contains('代號'));
    final foreign = <int>[
      for (var i = 0; i < names.length; i++)
        if (names[i].contains('外') && names[i].contains('買賣超') && !names[i].startsWith('外資自營商')) i,
    ];
    final foreignDealer = names.indexWhere((n) => n.startsWith('外資自營商買賣超'));
    final trust = names.indexWhere((n) => n.startsWith('投信買賣超'));
    var dealer = names.indexWhere((n) => n == '自營商買賣超股數');
    if (dealer < 0) dealer = names.indexWhere((n) => n.startsWith('自營商買賣超'));
    if (code < 0 || foreign.isEmpty || trust < 0) continue;
    final out = <String, List<int>>{};
    for (final row in data) {
      if (row is! List) continue;
      double at(int i) => i < 0 || i >= row.length ? 0 : (parseNum(row[i]) ?? 0);
      final c = row[code].toString().trim();
      if (c.isEmpty) continue;
      final f = at(foreign.first) + at(foreignDealer);
      out[c] = [(f / 1000).round(), (at(trust) / 1000).round(), (at(dealer) / 1000).round()];
    }
    return out;
  }
  return {};
}

/// 除權息事件。
class DivEvent {
  final String date; // 除權息日 yyyy-MM-dd
  final double before; // 除權息前收盤價
  final double ref; // 除權息參考價
  final double value; // 權值＋息值（每股）
  final String kind; // 息／權／權息

  const DivEvent(this.date, this.before, this.ref, this.value, this.kind);

  /// 有配現金（純配股的沒有）。
  bool get cash => kind.contains('息');

  List<Object> toRow() => [date, before, ref, value, kind];
  static DivEvent fromRow(List r) => DivEvent(
    r[0] as String,
    (r[1] as num).toDouble(),
    (r[2] as num).toDouble(),
    (r[3] as num).toDouble(),
    r[4] as String,
  );
}

/// 民國日期（113年01月02日、113/01/02、1130102）轉 yyyy-MM-dd。
String? rocToIso(String s) {
  final t = s.trim();
  var m = RegExp(r'^(\d{2,3})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(t);
  m ??= RegExp(r'^(\d{3})(\d{2})(\d{2})$').firstMatch(t);
  if (m == null) return null;
  final y = int.parse(m.group(1)!) + 1911;
  final mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return '$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// TWT49U：代號 → 除權息事件。
Map<String, List<DivEvent>> parseTwt49u(Map<String, dynamic> body) {
  final out = <String, List<DivEvent>>{};
  for (final (fields, data) in twseTables(body)) {
    final names = [for (final f in fields) _norm(f)];
    final date = names.indexWhere((n) => n.contains('日期'));
    final code = names.indexWhere((n) => n.contains('代號'));
    final before = names.indexWhere((n) => n.contains('前收盤'));
    final ref = names.indexWhere((n) => n == '除權息參考價');
    final value = names.indexWhere((n) => n.contains('權值') && n.contains('息值'));
    final kind = names.indexWhere((n) => n == '權/息');
    if ([date, code, before, ref, value].any((i) => i < 0)) continue;
    for (final row in data) {
      if (row is! List || row.length <= [date, code, before, ref, value].reduce((a, b) => a > b ? a : b)) continue;
      final d = rocToIso(row[date].toString());
      final b = parseNum(row[before]), r = parseNum(row[ref]), v = parseNum(row[value]);
      if (d == null || b == null || r == null || v == null) continue;
      final k = kind >= 0 && kind < row.length ? row[kind].toString().replaceAll(RegExp(r'<[^>]*>|\s'), '') : '';
      (out[row[code].toString().trim()] ??= []).add(DivEvent(d, b, r, v, k.isEmpty ? '息' : k));
    }
  }
  return out;
}

/// 每月營收：代號 → (當月營收, 去年當月營收)，單位千元。
typedef MonthRevenue = Map<String, (double, double?)>;

/// 公開資訊觀測站的營收彙總表（t21sc03 HTML）。舊檔是 Big5 編碼，這裡只讀數字和代號
/// （用 latin1 解碼也不會把 Big5 中文的位元組誤認成 `<`、數字），不需要中文名稱。
MonthRevenue parseRevenueHtml(String html) {
  final out = <String, (double, double?)>{};
  final rowRe = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
  final cellRe = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);
  for (final m in rowRe.allMatches(html)) {
    final cells = [
      for (final c in cellRe.allMatches(m.group(1)!))
        c.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim(),
    ];
    if (cells.length < 5 || !RegExp(r'^\d{4}$').hasMatch(cells[0])) continue;
    final cur = parseNum(cells[2]);
    if (cur == null) continue;
    out[cells[0]] = (cur, parseNum(cells[4]));
  }
  return out;
}

/// 營收 CSV（觀測站下載檔）：用標題列找「公司代號」「當月營收」「去年當月營收」。
MonthRevenue parseRevenueCsv(String csv) {
  final lines = csv.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return {};
  List<String> split(String l) {
    final out = <String>[];
    final sb = StringBuffer();
    var q = false;
    for (final ch in l.split('')) {
      if (ch == '"') {
        q = !q;
      } else if (ch == ',' && !q) {
        out.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString().trim());
    return out;
  }

  final head = [for (final h in split(lines.first)) _norm(h).replaceAll('﻿', '')];
  final code = head.indexWhere((h) => h.contains('公司代號'));
  final cur = head.indexWhere((h) => h.contains('當月營收') && !h.contains('累計') && !h.contains('去年'));
  final prev = head.indexWhere((h) => h.contains('去年當月營收'));
  if (code < 0 || cur < 0) return {};
  final out = <String, (double, double?)>{};
  for (final l in lines.skip(1)) {
    final r = split(l);
    if (r.length <= cur || r.length <= code) continue;
    final c = r[code].trim();
    final v = parseNum(r[cur]);
    if (!RegExp(r'^\d{4}$').hasMatch(c) || v == null) continue;
    out[c] = (v, prev >= 0 && prev < r.length ? parseNum(r[prev]) : null);
  }
  return out;
}

/// 證交所 OpenAPI t187ap05_L（最新一個月的上市公司營收）：回傳 (資料年月 yyyy-MM, 營收)。
(String?, MonthRevenue) parseRevenueOpenApi(List<dynamic> rows) {
  String? ym;
  final out = <String, (double, double?)>{};
  for (final r in rows) {
    if (r is! Map) continue;
    String? find(bool Function(String) test) {
      for (final e in r.entries) {
        if (test(_norm(e.key))) return e.value?.toString();
      }
      return null;
    }

    final c = find((k) => k.contains('公司代號'))?.trim();
    final v = parseNum(find((k) => k.contains('當月營收') && !k.contains('累計') && !k.contains('去年')));
    final p = parseNum(find((k) => k.contains('去年當月營收')));
    final ymRaw = find((k) => k.contains('資料年月'));
    if (ymRaw != null) {
      final m = RegExp(r'^(\d{2,3})/?(\d{1,2})$').firstMatch(ymRaw.trim());
      if (m != null) ym = '${int.parse(m.group(1)!) + 1911}-${m.group(2)!.padLeft(2, '0')}';
    }
    if (c == null || v == null || !RegExp(r'^\d{4}$').hasMatch(c)) continue;
    out[c] = (v, p);
  }
  return (ym, out);
}

/// 一條國際指標的日線（日期是當地交易日）。
class IntlSeries {
  final String key;
  final String source;

  /// 資料要晚幾天才能用：美國收盤在台灣隔天開盤前，所以至少 1 天；
  /// FRED 的資料隔天才更新、匯率每週公布，要更晚。回測只用「當時已經知道」的值。
  final int lagDays;
  final List<String> dates;
  final List<double> values;
  const IntlSeries(this.key, this.source, this.lagDays, this.dates, this.values);

  Map<String, dynamic> toJson() => {'src': source, 'lag': lagDays, 'd': dates, 'v': values};
  static IntlSeries fromJson(String key, Map<String, dynamic> j) => IntlSeries(
    key,
    j['src'] as String? ?? '',
    (j['lag'] as num?)?.toInt() ?? 1,
    [for (final d in j['d'] as List) d as String],
    [for (final v in j['v'] as List) (v as num).toDouble()],
  );
}

/// FRED 的 CSV：`observation_date,NASDAQCOM` 下面每列一天，沒資料是「.」。
(List<String>, List<double>) parseFredCsv(String csv) {
  final d = <String>[], v = <double>[];
  for (final l in csv.split(RegExp(r'\r?\n')).skip(1)) {
    final p = l.split(',');
    if (p.length < 2 || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p[0].trim())) continue;
    final x = double.tryParse(p[1].trim());
    if (x == null) continue;
    d.add(p[0].trim());
    v.add(x);
  }
  return (d, v);
}

/// Yahoo 的 v8 chart JSON。時間戳記是交易所當地開盤時間，加上 gmtoffset 換成當地日期。
(List<String>, List<double>) parseYahooChart(Map<String, dynamic> body) {
  final d = <String>[], v = <double>[];
  final res = (body['chart'] as Map?)?['result'];
  if (res is! List || res.isEmpty) return (d, v);
  final r = res.first as Map;
  final ts = r['timestamp'] as List? ?? const [];
  final off = ((r['meta'] as Map?)?['gmtoffset'] as num?)?.toInt() ?? 0;
  final quotes = ((r['indicators'] as Map?)?['quote'] as List?) ?? const [];
  if (quotes.isEmpty) return (d, v);
  final close = (quotes.first as Map)['close'] as List? ?? const [];
  for (var i = 0; i < ts.length && i < close.length; i++) {
    final c = close[i];
    if (c is! num) continue;
    final t = DateTime.fromMillisecondsSinceEpoch(((ts[i] as num).toInt() + off) * 1000, isUtc: true);
    final s =
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    if (d.isNotEmpty && d.last == s) {
      v[v.length - 1] = c.toDouble();
      continue;
    }
    d.add(s);
    v.add(c.toDouble());
  }
  return (d, v);
}
