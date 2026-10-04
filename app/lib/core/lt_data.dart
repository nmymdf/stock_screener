/// 長期分析用的精簡資料：十幾年、上千檔上市普通股，只留分析需要的東西。
///
/// - 每檔每天一個「總報酬指數」（收盤價＋除權息再投入，用交易所的參考價判斷除權息），
///   只往前算、不回頭調整，所以任何一天的值都只用到當天以前的資料。
/// - 每月檢視日（每月 11 日以後的第一個交易日，月營收 10 日前公布完）存一份快照：
///   收盤、本益比、淨值比、殖利率、近 60 日法人買賣超、成交量、成交值。
/// - 月營收、除權息、國際指標原樣保留，用的時候再依日期決定「當時看得到哪些」。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'pack.dart';
import 'sources.dart';

const double kNaN = double.nan;
bool isOk(double x) => !x.isNaN;

class LtStock {
  final String code;
  String name;

  /// 第一個有資料的交易日（在 [LtData.dates] 的位置）。
  final int start;

  /// 從 [start] 開始每天的總報酬指數；那天沒成交是 NaN。
  final Float32List tr;
  LtStock(this.code, this.name, this.start, this.tr);

  /// 第 t 天（含）以前最近一次成交的總報酬指數；還沒上市是 NaN。
  double trAt(int t) {
    var k = t - start;
    if (k < 0) return kNaN;
    if (k >= tr.length) k = tr.length - 1;
    for (; k >= 0; k--) {
      final v = tr[k];
      if (!v.isNaN) return v;
    }
    return kNaN;
  }

  /// 第 t 天有沒有成交。
  bool tradedAt(int t) {
    final k = t - start;
    return k >= 0 && k < tr.length && !tr[k].isNaN;
  }

  /// 最後一個有成交的交易日。
  int get lastTraded {
    for (var k = tr.length - 1; k >= 0; k--) {
      if (!tr[k].isNaN) return start + k;
    }
    return start;
  }
}

/// 每月檢視日的橫斷面快照，陣列依 [LtData.stocks] 的順序。
class LtSample {
  final int t;
  final String date;

  /// 最新一天（不是固定的檢視日，用來看「現在」）。
  final bool live;
  final Float32List close, pe, pb, yld, fi60, it60, vol60, val60;
  LtSample(
    this.t,
    this.date,
    this.live,
    this.close,
    this.pe,
    this.pb,
    this.yld,
    this.fi60,
    this.it60,
    this.vol60,
    this.val60,
  );
}

class LtData {
  final List<String> dates;
  final List<LtStock> stocks;
  final Map<String, int> index;
  final Float64List taiex;

  /// 加權報酬指數（含息）；早期沒有的日子是 NaN。
  final Float64List tri;
  final List<LtSample> samples;
  final RevenueData revenue;
  final DividendData dividends;
  final IntlData intl;

  LtData({
    required this.dates,
    required this.stocks,
    required this.taiex,
    required this.tri,
    required this.samples,
    required this.revenue,
    required this.dividends,
    required this.intl,
  }) : index = {for (var i = 0; i < stocks.length; i++) stocks[i].code: i};

  int get nd => dates.length;
  String? get lastDate => dates.isEmpty ? null : dates.last;
  LtStock? stock(String code) {
    final i = index[code];
    return i == null ? null : stocks[i];
  }

  /// 日期 → 位置（找不到回傳最接近的前一天）。
  int dateIndex(String date) {
    var lo = 0, hi = dates.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (dates[mid].compareTo(date) <= 0) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// 第 t 天的比較基準：有報酬指數用報酬指數，沒有就用加權指數（不含息，會低估基準）。
  bool get hasTri => tri.any((x) => !x.isNaN);
}

/// 長度不固定的 Float32 陣列（避免 `List<double>` 每個數字都另外配置記憶體）。
class _F32 {
  Float32List _b = Float32List(64);
  int length = 0;
  void add(double v) {
    if (length == _b.length) {
      final n = Float32List(_b.length * 2);
      n.setRange(0, length, _b);
      _b = n;
    }
    _b[length++] = v;
  }

  Float32List take() => Float32List.sublistView(_b, 0, length);
}

class _State {
  final int idx;
  final int start;
  final _F32 tr = _F32();
  double lastClose = kNaN, lastTr = kNaN;
  int lastT = -1; // 最後一次更新 ring 的日子
  final Float32List rVal = Float32List(60), rVol = Float32List(60), rFi = Float32List(60), rIt = Float32List(60);
  double sVal = 0, sVol = 0, sFi = 0, sIt = 0;
  double pe = kNaN, pb = kNaN, yld = kNaN;
  int valT = -1000;
  _State(this.idx, this.start);

  /// 把 (lastT, t] 之間沒成交的日子補成 0，讓 60 日加總正確滾動。
  void advance(int t) {
    if (lastT < 0) {
      lastT = t - 1;
    }
    final from = math.max(lastT + 1, t - 59);
    for (var k = from; k <= t; k++) {
      final s = k % 60;
      sVal -= rVal[s];
      sVol -= rVol[s];
      sFi -= rFi[s];
      sIt -= rIt[s];
      rVal[s] = rVol[s] = rFi[s] = rIt[s] = 0;
    }
    lastT = t;
  }

  void put(int t, double value, double vol, double fi, double it) {
    final s = t % 60;
    rVal[s] = value;
    rVol[s] = vol;
    rFi[s] = fi;
    rIt[s] = it;
    sVal += value;
    sVol += vol;
    sFi += fi;
    sIt += it;
  }
}

/// 一天一天餵資料進來（由舊到新），最後 [build]。
/// 資料可以來自 App 用的長期資料檔（[addLtYear]）或完整的一天（[addDay]，最近 30 天的小檔）。
class LtDataBuilder {
  /// 證交所公布的除權息（有的話用它的參考價，最準）：代號 → 日期 → 事件。
  final Map<String, Map<String, DivEvent>> _div;
  LtDataBuilder({DividendData? dividends})
    : _div = {
        for (final e in (dividends?.byCode ?? const <String, List<DivEvent>>{}).entries)
          e.key: {for (final x in e.value) x.date: x},
      };

  /// 偵測到的除權息天數（驗證用）：用證交所事件的、用漲跌價差推算的。
  int eventsFromTwse = 0, eventsFromChange = 0;

  final List<String> dates = [];
  final List<double> _taiex = [], _tri = [];
  final Map<String, _State> _st = {};
  final List<String> _codes = [];
  final Map<String, String> names = {};
  final List<_SampleBuf> _samples = [];
  int _lastSampleMonth = -1;
  int _t = -1;

  String? get lastDate => dates.isEmpty ? null : dates.last;

  /// 開始新的一天；日期重複或比已有的舊就回傳 false（整天跳過）。
  bool _begin(String date, double? taiex, double? tri) {
    if (dates.isNotEmpty && date.compareTo(dates.last) <= 0) return false;
    _t = dates.length;
    dates.add(date);
    _taiex.add(taiex ?? (_taiex.isEmpty ? kNaN : _taiex.last));
    _tri.add(tri ?? kNaN);
    return true;
  }

  /// [chg] 是交易所的漲跌價差（跟參考價比）；null 表示這天沒有除權息、參考價就是前一天收盤。
  void _stock(String code, double close, int lots, double? chg, int fi, int it) {
    if (close <= 0 || !isCommonStockCode(code)) return;
    final t = _t;
    final st = _st[code] ??= _newState(code, t);
    while (st.start + st.tr.length < t) {
      st.tr.add(kNaN);
    }
    double tr;
    if (st.lastClose.isNaN) {
      tr = close;
    } else {
      var base = st.lastClose;
      final ev = _div[code]?[dates[t]];
      if (ev != null && ev.before > 0 && ev.ref > 0 && ev.ref < ev.before) {
        base = st.lastClose * ev.ref / ev.before;
        eventsFromTwse++;
      } else if (chg != null && (close - st.lastClose - chg).abs() >= 0.006) {
        final ref = close - chg;
        final f = ref / st.lastClose;
        if (ref > 0 && f >= 0.5 && f <= 2 && (f - 1).abs() >= 0.001) {
          base = ref;
          eventsFromChange++;
        }
      }
      tr = st.lastTr * close / base;
    }
    st.tr.add(tr);
    st.lastClose = close;
    st.lastTr = tr;
    st.advance(t);
    // 收盤 × 張數 = 千元，再除 1000 = 百萬元
    st.put(t, close * lots / 1000, lots.toDouble(), fi.toDouble(), it.toDouble());
  }

  void _val(String code, List<num?> v) {
    final st = _st[code];
    if (st == null) return;
    st.pe = (v.isNotEmpty ? v[0] : null)?.toDouble() ?? kNaN;
    st.pb = (v.length > 1 ? v[1] : null)?.toDouble() ?? kNaN;
    st.yld = (v.length > 2 ? v[2] : null)?.toDouble() ?? 0; // 有資料但殖利率空白＝沒配息
    st.valT = _t;
  }

  void _end() {
    final d = dates[_t];
    final mk = int.parse(d.substring(0, 4)) * 12 + int.parse(d.substring(5, 7));
    if (int.parse(d.substring(8, 10)) >= 11 && mk != _lastSampleMonth) {
      _lastSampleMonth = mk;
      _samples.add(_snapshot(_t, false));
    }
  }

  /// 完整的一天（資料包的最近 30 天、或 App 當天直接抓的收盤）。
  void addDay(PackDay d, {Map<String, String>? dayNames}) {
    if (!_begin(d.date, d.taiex, d.tri)) return;
    for (final e in d.twse.entries) {
      final row = e.value;
      final inst = d.inst[e.key];
      _stock(e.key, row.close, row.lots, row.change, inst?[0] ?? 0, (inst?.length ?? 0) > 1 ? inst![1] : 0);
    }
    for (final e in d.val.entries) {
      _val(e.key, e.value);
    }
    if (dayNames != null) names.addAll(dayNames);
    _end();
  }

  /// App 用的長期資料檔（見 [ltYearJson]）。
  void addLtYear(Map<String, dynamic> j) {
    final dates = [for (final d in j['dates'] as List) d as String];
    final ix = j['ix'] as List, tr = j['tr'] as List;
    final stocks = <(String, List, List, List?, List?, Map<int, double>)>[];
    for (final e in ((j['s'] as Map?) ?? const {}).entries) {
      final m = e.value as Map;
      final x = <int, double>{
        for (final p in (m['x'] as List?) ?? const []) ((p as List)[0] as num).toInt(): (p[1] as num).toDouble(),
      };
      stocks.add((e.key as String, m['c'] as List, m['v'] as List, m['f'] as List?, m['i'] as List?, x));
    }
    final val = (j['val'] as Map?) ?? const {};
    for (final e in ((j['names'] as Map?) ?? const {}).entries) {
      names[e.key as String] = e.value as String;
    }
    for (var k = 0; k < dates.length; k++) {
      if (!_begin(dates[k], (ix[k] as num?)?.toDouble(), (tr[k] as num?)?.toDouble())) continue;
      for (final (code, c, v, f, i, x) in stocks) {
        final close = c[k] as num?;
        if (close == null) continue;
        _stock(
          code,
          close.toDouble(),
          (v[k] as num).toInt(),
          x[k],
          (f?[k] as num?)?.toInt() ?? 0,
          (i?[k] as num?)?.toInt() ?? 0,
        );
      }
      final dv = val[dates[k]] as Map?;
      if (dv != null) {
        for (final e in dv.entries) {
          _val(e.key as String, [for (final x in e.value as List) x as num?]);
        }
      }
      _end();
    }
  }

  _State _newState(String code, int t) {
    _codes.add(code);
    return _State(_codes.length - 1, t);
  }

  _SampleBuf _snapshot(int t, bool live) {
    final n = _codes.length;
    final s = _SampleBuf(t, dates[t], live, n);
    for (final st in _st.values) {
      final i = st.idx;
      if (st.lastClose.isNaN) continue;
      st.advance(t);
      s.close[i] = st.lastClose;
      final fresh = t - st.valT <= 40;
      s.pe[i] = fresh ? st.pe : kNaN;
      s.pb[i] = fresh ? st.pb : kNaN;
      s.yld[i] = fresh ? st.yld : kNaN;
      s.fi60[i] = st.sFi;
      s.it60[i] = st.sIt;
      s.vol60[i] = st.sVol;
      s.val60[i] = st.sVal / 60; // 近 60 個交易日平均每天成交值（百萬元）
    }
    return s;
  }

  LtData build({RevenueData? revenue, DividendData? dividends, IntlData? intl}) {
    // 除權息在建構時就要用到；這裡只是一起帶進結果
    final n = _codes.length;
    final nd = dates.length;
    final samples = <LtSample>[for (final s in _samples) s.finish(n)];
    if (nd > 0 && (samples.isEmpty || samples.last.t != nd - 1)) samples.add(_snapshot(nd - 1, true).finish(n));
    final stocks = List<LtStock?>.filled(n, null);
    for (final e in _st.entries) {
      final st = e.value;
      stocks[st.idx] = LtStock(e.key, names[e.key] ?? '', st.start, st.tr.take());
    }
    return LtData(
      dates: List.unmodifiable(dates),
      stocks: [for (final s in stocks) s!],
      taiex: Float64List.fromList(_taiex),
      tri: Float64List.fromList(_tri),
      samples: samples,
      revenue: revenue ?? RevenueData('2013-01'),
      dividends: dividends ?? DividendData(),
      intl: intl ?? const IntlData({}),
    );
  }
}

class _SampleBuf {
  final int t;
  final String date;
  final bool live;
  final Float32List close, pe, pb, yld, fi60, it60, vol60, val60;
  _SampleBuf(this.t, this.date, this.live, int n)
    : close = _nan(n),
      pe = _nan(n),
      pb = _nan(n),
      yld = _nan(n),
      fi60 = _nan(n),
      it60 = _nan(n),
      vol60 = _nan(n),
      val60 = _nan(n);

  static Float32List _nan(int n) => Float32List(n)..fillRange(0, n, kNaN);
  static Float32List _pad(Float32List a, int n) {
    if (a.length >= n) return a;
    final b = _nan(n);
    b.setRange(0, a.length, a);
    return b;
  }

  LtSample finish(int n) => LtSample(
    t,
    date,
    live,
    _pad(close, n),
    _pad(pe, n),
    _pad(pb, n),
    _pad(yld, n),
    _pad(fi60, n),
    _pad(it60, n),
    _pad(vol60, n),
    _pad(val60, n),
  );
}
