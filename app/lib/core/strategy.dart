/// 穩健＋進攻策略（用 2014–2026 真實資料檢驗過，規則固定、不調參數）：
///
/// - 穩健（70%）：0050。大盤（加權報酬指數）站在 200 日均線上就持有，跌破就改放現金；每月檢視一次。
///   報酬跟一直持有差不多，最大跌幅少三分之一（Faber 的 10 個月均線擇時）。
/// - 進攻（30%）：趨勢模板（Minervini／O'Neil）＋營收成長，每月挑 10 檔平均；
///   任何一檔收盤跌破 50 日均線，當天賣出放現金，下次檢視再挑。不足 10 檔的部分放 0050。
///
/// 其他檢驗過但沒採用的：全市場評分、神奇公式、趨勢價值、低波動、產業動能、市值加權去地雷（約等於 0050）。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'bluechip.dart' show capRanking, etfWeights;
import 'factors.dart';
import 'lt_data.dart';

class StrategyConfig {
  final double aggressive; // 進攻比例
  final int picks;
  final double rsQuantile; // 一年漲幅要在全市場前 (1 − rsQuantile)
  final double revMin; // 近 3 個月營收年增
  final double minValue; // 每天平均成交（百萬元）
  final int marketMa, stopMa;
  final double buyCost, sellCost, cashRate;
  final String startDate;
  const StrategyConfig({
    this.aggressive = 0.30,
    this.picks = 10,
    this.rsQuantile = 0.70,
    this.revMin = 0.20,
    this.minValue = 200,
    this.marketMa = 200,
    this.stopMa = 50,
    this.buyCost = 0.002425,
    this.sellCost = 0.005425,
    this.cashRate = 0.01,
    this.startDate = '2014-01-01',
  });
}

/// 地雷：虧損、年線下彎又營收衰退、殖利率陷阱、成交量太小（進攻名單不買）。
bool _mine(LtScore x) =>
    x.flags.contains(LtFlag.loss) ||
    (x.flags.contains(LtFlag.downtrend) && x.flags.contains(LtFlag.revenueDrop)) ||
    x.flags.contains(LtFlag.yieldTrap) ||
    x.flags.contains(LtFlag.illiquid);

/// 第 t 天以前 [n] 個交易日的含息均價（停牌日跳過；資料不到八成回傳 NaN）。
double trMa(LtStock st, int t, int n) {
  var sum = 0.0, c = 0;
  for (var k = 0; k < n; k++) {
    final v = st.trAt(t - k);
    if (!v.isNaN) {
      sum += v;
      c++;
    }
  }
  return c < n * 0.8 ? double.nan : sum / c;
}

double _tri(LtData d, int t) {
  for (var k = t; k >= 0; k--) {
    if (!d.tri[k].isNaN) return d.tri[k];
  }
  return double.nan;
}

/// 大盤（加權報酬指數）第 t 天比 [n] 日均線高多少（正的＝在均線上）。
double marketGap(LtData d, int t, [int n = 200]) {
  var sum = 0.0;
  for (var k = 0; k < n; k++) {
    sum += _tri(d, t - k);
  }
  return _tri(d, t) / (sum / n) - 1;
}

/// 進攻名單的一檔：為什麼入選。
class TrendPick {
  final int si;
  final double mom12, revYoy3, distHigh; // 一年漲幅、近 3 個月營收年增、離一年高點
  const TrendPick(this.si, this.mom12, this.revYoy3, this.distHigh);
}

/// 趨勢模板：價 > 50MA > 150MA > 200MA、200MA 上升、離一年高點 25% 內、比一年低點高 30% 以上、
/// 一年漲幅全市場前 30%、近 3 個月營收年增 ≥ 20%、每天成交 2 億以上、沒有地雷；取一年漲幅最強的 [picks] 檔。
List<TrendPick> trendPicks(LtData d, SampleScores sc, [StrategyConfig cfg = const StrategyConfig()]) {
  final t = sc.t;
  final all = [
    for (final x in sc.ranked)
      if (!x.raw.mom12.isNaN) x.raw.mom12,
  ]..sort();
  if (all.isEmpty) return const [];
  final rsCut = all[(all.length * cfg.rsQuantile).floor().clamp(0, all.length - 1)];
  final out = <TrendPick>[];
  for (final x in sc.ranked) {
    if (!x.investable || x.raw.val60.isNaN || x.raw.val60 < cfg.minValue || _mine(x)) continue;
    if (x.raw.mom12.isNaN || x.raw.mom12 < rsCut || !(x.raw.revYoy3 >= cfg.revMin)) continue;
    final st = d.stocks[x.si];
    final px = st.trAt(t);
    final m50 = trMa(st, t, 50), m150 = trMa(st, t, 150), m200 = trMa(st, t, 200), m200b = trMa(st, t - 21, 200);
    if ([px, m50, m150, m200, m200b].any((v) => v.isNaN)) continue;
    var hi = -1e18, lo = 1e18;
    for (var k = 0; k < 250; k++) {
      final v = st.trAt(t - k);
      if (v.isNaN) continue;
      hi = math.max(hi, v);
      lo = math.min(lo, v);
    }
    if (px > m50 && m50 > m150 && m150 > m200 && m200 > m200b && px >= hi * 0.75 && px >= lo * 1.3) {
      out.add(TrendPick(x.si, x.raw.mom12, x.raw.revYoy3, px / hi - 1));
    }
  }
  out.sort((a, b) => b.mom12.compareTo(a.mom12));
  return out.take(cfg.picks).toList();
}

class StPeriod {
  final String label, from, to;

  /// 年化、最大跌幅：策略、穩健、進攻、0050、大盤。
  final List<(double, double)> v;
  const StPeriod(this.label, this.from, this.to, this.v);
}

class StYear {
  final int year;
  final List<double> v; // 同上順序
  final bool partial;
  const StYear(this.year, this.v, this.partial);
}

/// 進攻名單某一檔的現況。
class PickStatus {
  final TrendPick pick;

  /// 收盤比 50 日均線高多少（負的＝跌破）。
  final double gap50;

  /// 檢視後跌破 50 日均線、該賣出的日子（null＝還在持有）。
  final String? stoppedOn;
  const PickStatus(this.pick, this.gap50, this.stoppedOn);
}

class StrategyResult {
  final StrategyConfig cfg;
  final int startT, endT;
  static const names = ['穩健＋進攻', '穩健', '進攻', '0050', '大盤（含息）'];

  /// 從 1 開始的淨值，順序同 [names]。
  final List<Float64List> navs;
  final List<StPeriod> periods;
  final List<StYear> years;
  final int stops, marketSwitches;

  /// 最近一次正式檢視日、當時的進攻名單與大盤訊號；名單每一檔到今天的狀況。
  final String reviewDate;
  final double reviewGap;
  final List<PickStatus> picks;

  /// 今天大盤比 200 日均線高多少。
  final double marketGapNow;
  const StrategyResult({
    required this.cfg,
    required this.startT,
    required this.endT,
    required this.navs,
    required this.periods,
    required this.years,
    required this.stops,
    required this.marketSwitches,
    required this.reviewDate,
    required this.reviewGap,
    required this.picks,
    required this.marketGapNow,
  });

  bool get marketOn => reviewGap > 0;
  StPeriod get full => periods.first;
}

/// [picksBySample]：每個檢視日的進攻名單（評分時順便算好，見 runLtAnalysis）。
StrategyResult? runStrategy(
  LtData d,
  Map<int, List<TrendPick>> picksBySample, [
  StrategyConfig cfg = const StrategyConfig(),
]) {
  if (!d.hasTri || d.shares.isEmpty) return null;
  final samples = [
    for (var s = 0; s < d.samples.length; s++)
      if (!d.samples[s].live && d.samples[s].date.compareTo(cfg.startDate) >= 0 && picksBySample.containsKey(s)) s,
  ];
  if (samples.length < 2) return null;
  final t0 = d.samples[samples.first].t + 1;
  if (t0 >= d.nd) return null;
  final n = d.nd - t0;
  final execs = {for (final s in samples) d.samples[s].t + 1: s};
  final on = {for (final s in samples) s: marketGap(d, d.samples[s].t, cfg.marketMa) > 0};
  final etfCache = <int, Map<int, double>>{};
  Map<int, double> etf(int s) => etfCache[s] ??= etfWeights(capRanking(d, s), 50);

  var stops = 0;
  Float64List sim(Map<int, double> Function(int s) targets, {Set<int> Function(int s)? stoppable}) {
    final units = <int, double>{};
    var cash = 1.0;
    var canStop = <int>{};
    final nav = Float64List(n);
    for (var k = 0; k < n; k++) {
      final t = t0 + k;
      cash *= 1 + cfg.cashRate / 250;
      if (stoppable != null) {
        for (final si in units.keys.toList()) {
          if (!canStop.contains(si)) continue;
          final st = d.stocks[si];
          final px = st.trAt(t), m = trMa(st, t, cfg.stopMa);
          if (!px.isNaN && !m.isNaN && px < m) {
            cash += units[si]! * px * (1 - cfg.sellCost);
            units.remove(si);
            canStop.remove(si);
            stops++;
          }
        }
      }
      double val() => cash + units.entries.fold(0.0, (p, e) => p + e.value * d.stocks[e.key].trAt(t));
      final s = execs[t];
      if (s != null) {
        final w = targets(s);
        if (stoppable != null) canStop = {...stoppable(s)};
        final v = val();
        for (final e in units.entries.toList()) {
          final px = d.stocks[e.key].trAt(t);
          final have = e.value * px, tgt = (w[e.key] ?? 0) * v;
          if (have > tgt) {
            units[e.key] = tgt / px;
            cash += (have - tgt) * (1 - cfg.sellCost);
          }
        }
        for (final e in w.entries) {
          final px = d.stocks[e.key].trAt(t);
          if (px.isNaN || px <= 0) continue;
          final have = (units[e.key] ?? 0) * px, tgt = e.value * v;
          if (tgt > have) {
            final buy = math.min(tgt - have, cash / (1 + cfg.buyCost));
            if (buy <= 0) continue;
            units[e.key] = (units[e.key] ?? 0) + buy / px;
            cash -= buy * (1 + cfg.buyCost);
          }
        }
        units.removeWhere((_, u) => u <= 1e-12);
      }
      nav[k] = val();
    }
    return nav;
  }

  Map<int, double> trendW(int s) {
    final ps = picksBySample[s] ?? const [];
    final w = <int, double>{for (final p in ps) p.si: 1 / cfg.picks};
    final rest = 1 - ps.length / cfg.picks;
    if (rest > 1e-9) etf(s).forEach((k, v) => w[k] = (w[k] ?? 0) + rest * v);
    return w;
  }

  final etfNav = sim(etf);
  final stable = sim((s) => on[s]! ? etf(s) : const {});
  final aggr = sim(trendW, stoppable: (s) => {for (final p in picksBySample[s] ?? const <TrendPick>[]) p.si});
  final blend = Float64List(n);
  var x = 1 - cfg.aggressive, y = cfg.aggressive;
  blend[0] = 1;
  for (var k = 1; k < n; k++) {
    x *= stable[k] / stable[k - 1];
    y *= aggr[k] / aggr[k - 1];
    if (execs.containsKey(t0 + k)) {
      final tot = x + y;
      x = tot * (1 - cfg.aggressive);
      y = tot * cfg.aggressive;
    }
    blend[k] = x + y;
  }
  final b0 = _tri(d, t0);
  final bench = Float64List.fromList([for (var k = 0; k < n; k++) _tri(d, t0 + k) / b0]);
  final navs = [blend, stable, aggr, etfNav, bench];

  (double, double) stat(Float64List v, String from, String to) {
    final a = math.max(0, d.dateIndex(from) - t0), b = math.min(n - 1, d.dateIndex(to) - t0);
    if (b <= a) return (double.nan, double.nan);
    var peak = v[a], dd = 0.0;
    for (var k = a; k <= b; k++) {
      peak = math.max(peak, v[k]);
      dd = math.max(dd, 1 - v[k] / peak);
    }
    return (math.pow(v[b] / v[a], 250 / (b - a)) - 1.0, dd);
  }

  final periods = [
    for (final (label, from, to) in [
      ('全部期間', d.dates[t0], d.dates.last),
      ('2014–2019', '2014-01-01', '2019-12-31'),
      ('2020 以後', '2020-01-01', d.dates.last),
    ])
      StPeriod(label, from, to, [for (final v in navs) stat(v, from, to)]),
  ];
  final years = <StYear>[];
  for (var yr = int.parse(d.dates[t0].substring(0, 4)); yr <= int.parse(d.dates.last.substring(0, 4)); yr++) {
    final a = math.max(0, d.dateIndex('${yr - 1}-12-31') - t0), b = math.min(n - 1, d.dateIndex('$yr-12-31') - t0);
    if (b <= a) continue;
    years.add(StYear(yr, [for (final v in navs) v[b] / v[a] - 1], b - a < 200));
  }
  var switches = 0;
  for (var i = 1; i < samples.length; i++) {
    if (on[samples[i]] != on[samples[i - 1]]) switches++;
  }

  // 現況：最近一次正式檢視日的名單，每一檔到今天有沒有跌破 50 日均線
  final review = samples.last;
  final execT = d.samples[review].t + 1;
  final last = d.nd - 1;
  final picks = <PickStatus>[];
  for (final p in picksBySample[review] ?? const <TrendPick>[]) {
    final st = d.stocks[p.si];
    String? stopped;
    for (var t = execT; t <= last; t++) {
      final px = st.trAt(t), m = trMa(st, t, cfg.stopMa);
      if (!px.isNaN && !m.isNaN && px < m) {
        stopped = d.dates[t];
        break;
      }
    }
    final m = trMa(st, last, cfg.stopMa);
    picks.add(PickStatus(p, st.trAt(last) / m - 1, stopped));
  }
  return StrategyResult(
    cfg: cfg,
    startT: t0,
    endT: last,
    navs: navs,
    periods: periods,
    years: years,
    stops: stops,
    marketSwitches: switches,
    reviewDate: d.samples[review].date,
    reviewGap: marketGap(d, d.samples[review].t, cfg.marketMa),
    picks: picks,
    marketGapNow: marketGap(d, last, cfg.marketMa),
  );
}
