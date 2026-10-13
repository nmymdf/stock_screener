/// 大型股避雷組合（v3 的做法，現在只用在「市值排行」分頁和研究對照）：照市值持有台股最大的公司，只把有「地雷」的拿掉。
///
/// 為什麼這樣做（真實資料檢驗過，規則事先定好、沒有回頭調參數）：
/// - 全市場評分「挑贏家」：2014–2026 每月名單抱 3～6 個月，贏大盤的次數約一半，大型股裡挑反而輸。
/// - 評分「排除地雷」有用：市值前 30／50／100 大去掉地雷，2014–2019、2020–2026 兩段都比不去掉的好。
/// - 單一檔（台積電）最多 40%（連 0050 裡的一起算）；不到 3% 的小部位改放 0050，不買零碎部位。
/// - 實際比重跟目標差不到 1/4 就不調，減少交易。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'factors.dart';
import 'lt_data.dart';
import 'portfolio.dart' show ltStressPeriods;

class BcConfig {
  /// 從市值前幾大裡挑。
  final int universe;

  /// 單一檔最多（直接持有＋0050 裡的）。
  final double maxWeight;

  /// 直接持有的最低比重，不到的不另外買（列為參考，透過 0050 持有）。
  final double minWeight;

  /// 實際比重跟目標差不到這個比例就不調。
  final double band;

  /// 0050 用市值前幾大模擬。
  final int etfSize;
  final double buyCost, sellCost;
  final String startDate;
  const BcConfig({
    this.universe = 30,
    this.maxWeight = 0.40,
    this.minWeight = 0.03,
    this.band = 0.25,
    this.etfSize = 50,
    this.buyCost = 0.002425,
    this.sellCost = 0.005425,
    this.startDate = '2014-01-01',
  });
}

/// 大型股的地雷：虧損、年線下彎又營收衰退、殖利率陷阱、成交量太小、總分在全市場後 20%。
/// 沒評分的（上市未滿一年）不判斷。
List<String> landmineReasons(ScoreBook book, int s, int si) {
  if (!book.scored(s, si)) return const [];
  final j = book.at(s, si);
  bool f(LtFlag x) => book.flags[j] & (1 << x.index) != 0;
  return [
    if (f(LtFlag.loss)) '虧損',
    if (f(LtFlag.downtrend) && f(LtFlag.revenueDrop)) '年線下彎又營收衰退',
    if (f(LtFlag.yieldTrap)) '殖利率陷阱（配的比賺的多）',
    if (f(LtFlag.illiquid)) '成交量太小',
    if (book.pct[j] < 0.2) '總分在全市場後 20%（第 ${book.rank[j]} 名）',
  ];
}

/// 同 [landmineReasons]，用某一天的完整評分（例如最新一天）。
List<String> landmineReasonsOf(LtScore x) => [
  if (x.flags.contains(LtFlag.loss)) '虧損',
  if (x.flags.contains(LtFlag.downtrend) && x.flags.contains(LtFlag.revenueDrop)) '年線下彎又營收衰退',
  if (x.flags.contains(LtFlag.yieldTrap)) '殖利率陷阱（配的比賺的多）',
  if (x.flags.contains(LtFlag.illiquid)) '成交量太小',
  if (x.pct < 0.2) '總分在全市場後 20%（第 ${x.rank} 名）',
];

/// 第 [s] 個檢視日的市值排名：(股票, 市值)，由大到小。沒有股數資料回傳空的。
List<(int, double)> capRanking(LtData d, int s) {
  final sm = d.samples[s];
  final shares = d.shares.at(sm.date);
  if (shares == null) return const [];
  final out = <(int, double)>[];
  for (final e in shares.entries) {
    final si = d.index[e.key];
    if (si == null) continue;
    final c = sm.close[si];
    if (c.isNaN || c <= 0 || !d.stocks[si].tradedAt(sm.t)) continue;
    out.add((si, e.value * c));
  }
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}

Map<int, double> _capWeights(Iterable<(int, double)> l) {
  final tot = l.fold(0.0, (p, x) => p + x.$2);
  return {for (final x in l) x.$1: x.$2 / tot};
}

/// 單一檔超過 [cap] 的部分按比例分給其他檔。
Map<int, double> _capped(Map<int, double> w0, double cap) {
  final w = {...w0};
  for (var it = 0; it < 20; it++) {
    var excess = 0.0;
    for (final k in w.keys.toList()) {
      if (w[k]! > cap) {
        excess += w[k]! - cap;
        w[k] = cap;
      }
    }
    if (excess < 1e-9) break;
    final open = [
      for (final k in w.keys)
        if (w[k]! < cap - 1e-9) k,
    ];
    final tot = open.fold(0.0, (p, k) => p + w[k]!);
    if (tot <= 0) break;
    for (final k in open) {
      w[k] = w[k]! + excess * w[k]! / tot;
    }
  }
  return w;
}

class BcStock {
  final int si;
  final int capRank;

  /// 直接持有的比重。
  final double weight;
  const BcStock(this.si, this.capRank, this.weight);
}

class BcLandmine {
  final int si;
  final int capRank;
  final List<String> reasons;
  const BcLandmine(this.si, this.capRank, this.reasons);
}

/// 某一天的組合。
/// 組合裡比重太小、不另外買的公司（透過 0050 間接持有）。
class BcRef {
  final int si;
  final int capRank;

  /// 照市值該有的比重（不到最低比重）。
  final double capWeight;

  /// 透過 0050 間接持有的比重。
  final double viaEtf;
  const BcRef(this.si, this.capRank, this.capWeight, this.viaEtf);
}

class BcPick {
  final int sample;
  final String date;

  /// 直接買的股票（比重由大到小）。
  final List<BcStock> stocks;

  /// 沒有地雷、但比重不到最低比重的（列為參考，透過 0050 持有）。
  final List<BcRef> references;

  /// 放 0050 的比例。
  final double etfWeight;

  /// 市值前 N 大裡因為地雷被排除的。
  final List<BcLandmine> landmines;

  /// 每一檔實際的比重（直接持有＋0050 裡的），回測用。
  final Map<int, double> exposure;
  const BcPick(this.sample, this.date, this.stocks, this.references, this.etfWeight, this.landmines, this.exposure);

  BcStock? of(int si) => stocks.where((x) => x.si == si).firstOrNull;
  BcRef? refOf(int si) => references.where((x) => x.si == si).firstOrNull;

  /// 組合裡的公司（直接買的＋參考的），沒有地雷。
  bool contains(int si) => of(si) != null || refOf(si) != null;
}

/// 0050 的成分（市值前 [n] 大、市值加權）。
Map<int, double> etfWeights(List<(int, double)> rank, int n) => _capWeights(rank.take(n));

BcPick? bcPick(LtData d, ScoreBook book, int s, [BcConfig cfg = const BcConfig()]) {
  final rank = capRanking(d, s);
  if (rank.length < cfg.etfSize) return null;
  final top = rank.take(cfg.universe).toList();
  final mines = <BcLandmine>[];
  final ok = <(int, double)>[];
  for (var i = 0; i < top.length; i++) {
    final r = landmineReasons(book, s, top[i].$1);
    if (r.isEmpty) {
      ok.add(top[i]);
    } else {
      mines.add(BcLandmine(top[i].$1, i + 1, r));
    }
  }
  final j = _capped(_capWeights(ok), cfg.maxWeight);
  final keep = {
    for (final e in j.entries)
      if (e.value >= cfg.minWeight) e.key: e.value,
  };
  final double etf = 1 - keep.values.fold(0.0, (p, v) => p + v);
  final c50 = etfWeights(rank, cfg.etfSize);
  // 連 0050 裡的一起算，單一檔不超過上限；多出來的按比例給其他直接持有的
  var freed = 0.0;
  for (final k in keep.keys.toList()) {
    final viaEtf = etf * (c50[k] ?? 0);
    if (keep[k]! + viaEtf > cfg.maxWeight) {
      final nk = math.max(0.0, cfg.maxWeight - viaEtf);
      freed += keep[k]! - nk;
      keep[k] = nk;
    }
  }
  final others = [
    for (final k in keep.keys)
      if (keep[k]! + etf * (c50[k] ?? 0) < cfg.maxWeight - 1e-9) k,
  ];
  final ot = others.fold(0.0, (p, k) => p + keep[k]!);
  if (ot > 0) {
    for (final k in others) {
      keep[k] = keep[k]! + freed * keep[k]! / ot;
    }
  }
  final exposure = <int, double>{...keep};
  c50.forEach((k, v) => exposure[k] = (exposure[k] ?? 0) + etf * v);
  final rankOf = {for (var i = 0; i < rank.length; i++) rank[i].$1: i + 1};
  final stocks = [for (final e in keep.entries) BcStock(e.key, rankOf[e.key]!, e.value)]
    ..sort((a, b) => b.weight.compareTo(a.weight));
  final refs = [
    for (final e in j.entries)
      if (!keep.containsKey(e.key)) BcRef(e.key, rankOf[e.key]!, e.value, etf * (c50[e.key] ?? 0)),
  ]..sort((a, b) => a.capRank.compareTo(b.capRank));
  return BcPick(s, d.samples[s].date, stocks, refs, etf, mines, exposure);
}

/// 某一段期間的成績。
class BcPeriod {
  final String label, from, to;
  final double cagr, mdd, etfCagr, etfMdd, benchCagr, benchMdd;
  const BcPeriod(
    this.label,
    this.from,
    this.to,
    this.cagr,
    this.mdd,
    this.etfCagr,
    this.etfMdd,
    this.benchCagr,
    this.benchMdd,
  );
}

class BcYear {
  final int year;
  final double ret, etf, bench;
  final bool partial;
  const BcYear(this.year, this.ret, this.etf, this.bench, this.partial);
}

class BcStress {
  final String label, from, to;
  final double ret, etf, bench;
  const BcStress(this.label, this.from, this.to, this.ret, this.etf, this.bench);
}

/// 地雷成績單：每個檢視日被排除的地雷，之後 6 個月跟沒地雷的大型股比。
class BcMineRow {
  final String date;
  final int mines;
  final double mineRet, okRet;
  const BcMineRow(this.date, this.mines, this.mineRet, this.okRet);
}

class BcResult {
  final BcConfig cfg;
  final int startT, endT;

  /// 從 1 開始的淨值：組合、0050（市值前 50 大模擬）、加權報酬指數。
  final Float64List nav, etf, bench;
  final List<BcPeriod> periods;
  final List<BcYear> years;
  final List<BcStress> stress;
  final List<BcMineRow> mines;
  final double turnover, etfTurnover, vol;

  /// 最新一天的組合、上次正式檢視日的組合（看這個月要調什麼）。
  final BcPick? current, previous;
  const BcResult({
    required this.cfg,
    required this.startT,
    required this.endT,
    required this.nav,
    required this.etf,
    required this.bench,
    required this.periods,
    required this.years,
    required this.stress,
    required this.mines,
    required this.turnover,
    required this.etfTurnover,
    required this.vol,
    required this.current,
    required this.previous,
  });

  BcPeriod get full => periods.first;

  /// 地雷之後 6 個月比沒地雷的少賺的比例。
  double get mineLagRate => mines.isEmpty ? double.nan : mines.where((m) => m.mineRet < m.okRet).length / mines.length;
  double get mineAvgGap =>
      mines.isEmpty ? double.nan : mines.fold(0.0, (p, m) => p + m.mineRet - m.okRet) / mines.length;
}

/// 從 [cfg.startDate] 起每月檢視、隔天收盤調整，扣交易成本；同時模擬 0050（市值前 50 大，每月調整）。
BcResult? runBlueChip(LtData d, ScoreBook book, [BcConfig cfg = const BcConfig()]) {
  if (d.shares.isEmpty || !d.hasTri) return null;
  final samples = [
    for (var s = 0; s < d.samples.length; s++)
      if (!d.samples[s].live && d.samples[s].date.compareTo(cfg.startDate) >= 0 && capRanking(d, s).length >= 50) s,
  ];
  if (samples.isEmpty) return null;
  final t0 = d.samples[samples.first].t + 1;
  if (t0 >= d.nd) return null;
  final n = d.nd - t0;
  final bench = Float64List(n);
  final b0 = d.tri[t0];
  for (var k = 0; k < n; k++) {
    final v = d.tri[t0 + k];
    bench[k] = v.isNaN ? (k > 0 ? bench[k - 1] : 1.0) : v / b0;
  }
  final exec = {for (final s in samples) d.samples[s].t + 1: s};

  (Float64List, double) simulate(Map<int, double> Function(int s) targets, double band) {
    final units = <int, double>{};
    var cash = 1.0, turnover = 0.0;
    final nav = Float64List(n);
    for (var k = 0; k < n; k++) {
      final t = t0 + k;
      double val() => cash + units.entries.fold(0.0, (p, e) => p + e.value * d.stocks[e.key].trAt(t));
      final s = exec[t];
      if (s != null) {
        final w = targets(s);
        if (w.isNotEmpty) {
          final v = val();
          bool skip(double have, double tgt) => band > 0 && tgt > 0 && have > 0 && (have - tgt).abs() <= band * tgt;
          for (final e in units.entries.toList()) {
            final px = d.stocks[e.key].trAt(t);
            final have = e.value * px;
            final tgt = (w[e.key] ?? 0) * v;
            if (skip(have, tgt) || have <= tgt) continue;
            final sell = have - tgt;
            units[e.key] = e.value - sell / px;
            cash += sell * (1 - cfg.sellCost);
            turnover += sell;
          }
          for (final e in w.entries) {
            final px = d.stocks[e.key].trAt(t);
            if (px.isNaN || px <= 0) continue;
            final have = (units[e.key] ?? 0) * px;
            final tgt = e.value * v;
            if (skip(have, tgt) || tgt <= have) continue;
            final buy = math.min(tgt - have, cash / (1 + cfg.buyCost));
            if (buy <= 0) continue;
            units[e.key] = (units[e.key] ?? 0) + buy / px;
            cash -= buy * (1 + cfg.buyCost);
            turnover += buy;
          }
          units.removeWhere((_, u) => u <= 1e-12);
        }
      }
      nav[k] = val();
    }
    return (nav, turnover / (n / 250));
  }

  final picks = <int, BcPick>{};
  final (nav, turnover) = simulate((s) {
    final p = bcPick(d, book, s, cfg);
    if (p == null) return const {};
    picks[s] = p;
    return p.exposure;
  }, cfg.band);
  final (etf, etfTurnover) = simulate((s) => etfWeights(capRanking(d, s), cfg.etfSize), 0);

  (double, double) stat(Float64List v, String from, String to) {
    final a = math.max(0, d.dateIndex(from) - t0), b = math.min(n - 1, d.dateIndex(to) - t0);
    if (b <= a) return (double.nan, double.nan);
    final yrs = (b - a) / 250.0;
    var peak = v[a], dd = 0.0;
    for (var k = a; k <= b; k++) {
      peak = math.max(peak, v[k]);
      dd = math.max(dd, 1 - v[k] / peak);
    }
    return (math.pow(v[b] / v[a], 1 / yrs) - 1.0, dd);
  }

  final periods = <BcPeriod>[];
  for (final (label, from, to) in [
    ('全部期間', d.dates[t0], d.dates.last),
    ('2014–2019', '2014-01-01', '2019-12-31'),
    ('2020 以後', '2020-01-01', d.dates.last),
  ]) {
    final (c, m) = stat(nav, from, to);
    final (ec, em) = stat(etf, from, to);
    final (bc, bm) = stat(bench, from, to);
    periods.add(BcPeriod(label, from, to, c, m, ec, em, bc, bm));
  }
  final years = <BcYear>[];
  for (var y = int.parse(d.dates[t0].substring(0, 4)); y <= int.parse(d.dates.last.substring(0, 4)); y++) {
    final a = math.max(0, d.dateIndex('${y - 1}-12-31') - t0), b = d.dateIndex('$y-12-31') - t0;
    if (b <= a) continue;
    double r(Float64List v) => v[b] / v[a] - 1;
    years.add(BcYear(y, r(nav), r(etf), r(bench), b - a < 200));
  }
  final stress = <BcStress>[];
  for (final (label, from, to) in ltStressPeriods) {
    final a = d.dateIndex(from) - t0, b = d.dateIndex(to) - t0;
    if (a < 0 || b <= a || b >= n) continue;
    stress.add(BcStress(label, from, to, nav[b] / nav[a] - 1, etf[b] / etf[a] - 1, bench[b] / bench[a] - 1));
  }
  // 地雷成績單（抱 6 個月）
  final mines = <BcMineRow>[];
  for (final s in samples) {
    final p = picks[s];
    if (p == null || p.landmines.isEmpty) continue;
    final ta = d.samples[s].t + 1, tb = ta + 126;
    if (tb >= d.nd) break;
    double fwd(int si) {
      final a = d.stocks[si].trAt(ta), b = d.stocks[si].trAt(tb);
      return a.isNaN || b.isNaN || a <= 0 ? double.nan : b / a - 1;
    }

    final mineIds = {for (final m in p.landmines) m.si};
    final rank = capRanking(d, s).take(cfg.universe);
    final mr = [for (final m in mineIds) fwd(m)].where((x) => !x.isNaN).toList();
    final orr = [
      for (final x in rank)
        if (!mineIds.contains(x.$1)) fwd(x.$1),
    ].where((x) => !x.isNaN).toList();
    if (mr.isEmpty || orr.isEmpty) continue;
    mines.add(
      BcMineRow(p.date, mr.length, mr.reduce((a, b) => a + b) / mr.length, orr.reduce((a, b) => a + b) / orr.length),
    );
  }
  var s1 = 0.0, s2 = 0.0;
  for (var k = 1; k < n; k++) {
    final r = nav[k] / nav[k - 1] - 1;
    s1 += r;
    s2 += r * r;
  }
  final mean = s1 / math.max(1, n - 1);
  final vol = math.sqrt(math.max(0, s2 / math.max(1, n - 1) - mean * mean) * 250);
  // 最新一天（今天不是檢視日也算一次）和上次正式檢視日
  final last = d.samples.length - 1;
  final current = bcPick(d, book, last, cfg);
  final prevS = d.samples[last].live ? samples.last : (samples.length >= 2 ? samples[samples.length - 2] : null);
  final previous = prevS == null ? null : (picks[prevS] ?? bcPick(d, book, prevS, cfg));
  return BcResult(
    cfg: cfg,
    startT: t0,
    endT: d.nd - 1,
    nav: nav,
    etf: etf,
    bench: bench,
    periods: periods,
    years: years,
    stress: stress,
    mines: mines,
    turnover: turnover,
    etfTurnover: etfTurnover,
    vol: vol,
    current: current,
    previous: previous,
  );
}
