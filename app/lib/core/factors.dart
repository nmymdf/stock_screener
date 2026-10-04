/// 長期因子：每個月檢視日，對每檔上市普通股算六大類因子，換成全市場百分位，再加權成總分。
///
/// 一律只用「那一天已經知道」的資料：股價用當天以前的總報酬指數；本益比、殖利率用當天公布的；
/// 月營收用當時已經公布的月份（回測時保守假設每月 11 日以後才知道上個月營收）；
/// 除權息只算已經除息的。最新一天（現在）則用手上所有已公布的資料。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'lt_data.dart';
import 'pack.dart';

enum FactorGroup { momentum, revenue, quality, value, flow, stability }

extension FactorGroupInfo on FactorGroup {
  String get label => switch (this) {
    FactorGroup.momentum => '動能趨勢',
    FactorGroup.revenue => '營收成長',
    FactorGroup.quality => '獲利品質',
    FactorGroup.value => '價值股利',
    FactorGroup.flow => '法人籌碼',
    FactorGroup.stability => '穩定度',
  };

  /// 平衡型（成長＋股利）的權重：事先決定、不拿回測結果去調，避免「對過去量身訂做」。
  double get weight => switch (this) {
    FactorGroup.momentum => 0.20,
    FactorGroup.revenue => 0.20,
    FactorGroup.quality => 0.20,
    FactorGroup.value => 0.20,
    FactorGroup.flow => 0.10,
    FactorGroup.stability => 0.10,
  };

  String get explain => switch (this) {
    FactorGroup.momentum => '近 12 個月（扣掉最近 1 個月）與近 6 個月的含息報酬、站上年線的程度與年線方向',
    FactorGroup.revenue => '近 3 個月營收年增率、近 12 個月有幾個月成長、近 12 個月累計年增、成長有沒有加速',
    FactorGroup.quality => '股東權益報酬率（ROE）的高低與穩定度、每股盈餘一年來的成長',
    FactorGroup.value => '本益比在自己過去 5 年的位置、盈餘殖利率、現金殖利率（排除殖利率陷阱）、近 5 年配息年數',
    FactorGroup.flow => '外資、投信近 60 個交易日買賣超佔成交量的比例',
    FactorGroup.stability => '近一年的波動度與最大跌幅（越小越好）',
  };
}

enum LtFlag { overheat, downtrend, revenueDrop, loss, yieldTrap, epsDrop, illiquid }

extension LtFlagInfo on LtFlag {
  String get label => switch (this) {
    LtFlag.overheat => '短期過熱',
    LtFlag.downtrend => '年線下彎',
    LtFlag.revenueDrop => '營收衰退',
    LtFlag.loss => '虧損',
    LtFlag.yieldTrap => '殖利率陷阱',
    LtFlag.epsDrop => '獲利大減',
    LtFlag.illiquid => '成交量太小',
  };

  String get explain => switch (this) {
    LtFlag.overheat => '一個月漲超過 30% 或股價高出年線 30% 以上：不追高，等回穩再買',
    LtFlag.downtrend => '股價在年線之下、年線也往下：長期趨勢轉弱',
    LtFlag.revenueDrop => '近 3 個月營收比去年少 10% 以上，而且一年中大多數月份衰退',
    LtFlag.loss => '近四季每股盈餘是負的（沒有本益比）',
    LtFlag.yieldTrap => '殖利率很高但配的比賺的多，或獲利大減：高殖利率可能撐不住',
    LtFlag.epsDrop => '每股盈餘比一年前少 30% 以上',
    LtFlag.illiquid => '近 60 日平均每天成交不到 5,000 萬或股價低於 10 元：不列入新買名單',
  };
}

/// 某檔股票在某個檢視日的原始數值（沒有資料是 NaN）。
class LtRaw {
  double close = kNaN, val60 = kNaN;
  double mom12 = kNaN, mom6 = kNaN, ret21 = kNaN, dist200 = kNaN, slope200 = kNaN;
  double revYoy3 = kNaN, revPos12 = kNaN, rev12 = kNaN, revAccel = kNaN;
  bool revNewHigh = false;
  int revMonth = -1; // 用到的最後一個月（月份索引）
  double roe = kNaN, roeStab = kNaN, epsGrowth = kNaN;
  double pe = kNaN, pb = kNaN, pePct = kNaN, ey = kNaN, yld = kNaN, payout = kNaN, divYears = kNaN;
  double fi = kNaN, it = kNaN;
  double vol = kNaN, mdd = kNaN;
}

class LtScore {
  final int si;
  final String code;
  final LtRaw raw;
  final Map<FactorGroup, double> groups; // 0～100
  final double composite; // 0～100（含扣分）
  final Set<LtFlag> flags;

  /// 可以新買進（流動性、股價夠）。
  final bool investable;

  /// 全部有分數的股票裡的百分位（1 = 最好）、名次。
  double pct = 0;
  int rank = 0;

  LtScore(this.si, this.code, this.raw, this.groups, this.composite, this.flags, this.investable);

  /// 從精簡紀錄還原（只有回測需要的欄位，原始數值只剩波動度）。
  factory LtScore.fromBook(ScoreBook b, int s, int si, String code) {
    final j = b.at(s, si);
    final groups = <FactorGroup, double>{};
    for (final g in FactorGroup.values) {
      final v = b.groups[j * 6 + g.index];
      if (!v.isNaN) groups[g] = v;
    }
    final flags = <LtFlag>{
      for (final f in LtFlag.values)
        if (b.flags[j] & (1 << f.index) != 0) f,
    };
    return LtScore(si, code, LtRaw()..vol = b.vol[j], groups, b.composite[j], flags, !flags.contains(LtFlag.illiquid))
      ..pct = b.pct[j]
      ..rank = b.rank[j];
  }

  /// 長期理由已經不成立：趨勢轉弱又營收衰退、虧損又趨勢轉弱、或總分掉到全市場後 15%。
  bool get broken =>
      (flags.contains(LtFlag.downtrend) && flags.contains(LtFlag.revenueDrop)) ||
      (flags.contains(LtFlag.loss) && flags.contains(LtFlag.downtrend)) ||
      pct < 0.15;

  double? group(FactorGroup g) => groups[g];
}

/// 一個檢視日的全市場評分。
class SampleScores {
  final int sampleIdx;
  final LtSample sample;
  final List<LtScore> ranked; // 總分由高到低
  final Map<int, LtScore> bySi;

  /// 有分數的股票裡，站上年線（總報酬指數 > 200 日均）的比例。
  final double breadth;

  SampleScores(this.sampleIdx, this.sample, this.ranked, this.breadth) : bySi = {for (final s in ranked) s.si: s};

  LtScore? of(int si) => bySi[si];
  int get t => sample.t;
  String get date => sample.date;
}

/// 所有檢視日的評分，精簡存放（每檔每次幾個數字），回測、因子研究、分數走勢用。
class ScoreBook {
  final int ns, nst;
  final Float32List composite, pct, vol, groups;
  final Int32List rank;
  final Uint8List flags;

  /// 每個檢視日依總分由高到低的股票位置。
  final List<Int32List> order;
  final Float64List breadth;

  ScoreBook(this.ns, this.nst)
    : composite = Float32List(ns * nst)..fillRange(0, ns * nst, kNaN),
      pct = Float32List(ns * nst)..fillRange(0, ns * nst, kNaN),
      vol = Float32List(ns * nst)..fillRange(0, ns * nst, kNaN),
      groups = Float32List(ns * nst * 6)..fillRange(0, ns * nst * 6, kNaN),
      rank = Int32List(ns * nst),
      flags = Uint8List(ns * nst),
      order = List<Int32List>.filled(ns, Int32List(0)),
      breadth = Float64List(ns)..fillRange(0, ns, kNaN);

  int at(int s, int si) => s * nst + si;
  bool scored(int s, int si) => !composite[at(s, si)].isNaN;
  int count(int s) => order[s].length;

  void put(SampleScores sc) {
    final s = sc.sampleIdx;
    for (final x in sc.ranked) {
      final j = at(s, x.si);
      composite[j] = x.composite;
      pct[j] = x.pct;
      rank[j] = x.rank;
      vol[j] = x.raw.vol;
      var f = 0;
      for (final fl in x.flags) {
        f |= 1 << fl.index;
      }
      flags[j] = f;
      for (final g in FactorGroup.values) {
        final v = x.groups[g];
        if (v != null) groups[j * 6 + g.index] = v;
      }
    }
    order[s] = Int32List.fromList([for (final x in sc.ranked) x.si]);
    breadth[s] = sc.breadth;
  }

  /// 還原某個檢視日的評分（給回測用）。
  SampleScores sample(LtData data, int s) => SampleScores(s, data.samples[s], [
    for (final si in order[s]) LtScore.fromBook(this, s, si, data.stocks[si].code),
  ], breadth[s]);
}

/// 每檔股票在每個檢視日的價格統計（一次掃過整條序列算好，不用每個檢視日重算）。
class PriceStats {
  final int ns, nst;
  final Float32List tr, mom12, mom6, ret21, dist200, slope200, vol, mdd;

  /// 那天（含前 5 天內）有成交。
  final Uint8List traded;
  PriceStats._(this.ns, this.nst)
    : tr = _nan(ns * nst),
      mom12 = _nan(ns * nst),
      mom6 = _nan(ns * nst),
      ret21 = _nan(ns * nst),
      dist200 = _nan(ns * nst),
      slope200 = _nan(ns * nst),
      vol = _nan(ns * nst),
      mdd = _nan(ns * nst),
      traded = Uint8List(ns * nst);

  static Float32List _nan(int n) => Float32List(n)..fillRange(0, n, kNaN);

  int at(int sampleIdx, int si) => sampleIdx * nst + si;

  static PriceStats compute(LtData data) {
    final ns = data.samples.length, nst = data.stocks.length;
    final ps = PriceStats._(ns, nst);
    final sampleTs = [for (final s in data.samples) s.t];
    for (var si = 0; si < nst; si++) {
      final st = data.stocks[si];
      final len = st.tr.length;
      if (len < 30) continue;
      // 沒成交的日子沿用前一天，算均線、報酬才連續
      final cf = Float64List(len);
      var last = kNaN;
      for (var k = 0; k < len; k++) {
        final v = st.tr[k];
        if (!v.isNaN) last = v;
        cf[k] = last;
      }
      final sma = Float64List(len)..fillRange(0, len, kNaN);
      var sum = 0.0;
      for (var k = 0; k < len; k++) {
        sum += cf[k];
        if (k >= 200) sum -= cf[k - 200];
        if (k >= 199) sma[k] = sum / 200;
      }
      final r = Float64List(len);
      for (var k = 1; k < len; k++) {
        r[k] = cf[k] > 0 && cf[k - 1] > 0 ? math.log(cf[k] / cf[k - 1]) : 0;
      }
      var s1 = 0.0, s2 = 0.0;
      var nextSample = 0;
      for (var k = 0; k < len; k++) {
        s1 += r[k];
        s2 += r[k] * r[k];
        if (k >= 250) {
          s1 -= r[k - 250];
          s2 -= r[k - 250] * r[k - 250];
        }
        final t = st.start + k;
        while (nextSample < ns && sampleTs[nextSample] < t) {
          nextSample++;
        }
        if (nextSample >= ns || sampleTs[nextSample] != t) continue;
        // 檢視日 t
        final j = ps.at(nextSample, si);
        ps.tr[j] = cf[k];
        var tradedRecently = false;
        for (var b = 0; b < 5 && k - b >= 0; b++) {
          if (!st.tr[k - b].isNaN) {
            tradedRecently = true;
            break;
          }
        }
        ps.traded[j] = tradedRecently ? 1 : 0;
        if (k >= 21) ps.ret21[j] = cf[k] / cf[k - 21] - 1;
        if (k >= 126) ps.mom6[j] = cf[k] / cf[k - 126] - 1;
        if (k >= 252) ps.mom12[j] = cf[k - 21] / cf[k - 252] - 1;
        if (!sma[k].isNaN) ps.dist200[j] = cf[k] / sma[k] - 1;
        if (k >= 219 && !sma[k - 20].isNaN) ps.slope200[j] = sma[k] / sma[k - 20] - 1;
        if (k >= 250) {
          final n = 250.0;
          final variance = math.max(0.0, s2 / n - (s1 / n) * (s1 / n));
          ps.vol[j] = math.sqrt(variance * 250);
          var peak = cf[k - 249], dd = 0.0;
          for (var q = k - 249; q <= k; q++) {
            if (cf[q] > peak) peak = cf[q];
            final x = 1 - cf[q] / peak;
            if (x > dd) dd = x;
          }
          ps.mdd[j] = dd;
        }
      }
      // 最新一天（live）如果不是當天成交的也要有值：上面的迴圈只處理到最後一個有資料的 k
      final liveIdx = ns - 1;
      final lt = sampleTs[liveIdx];
      if (lt >= st.start + len && ps.tr[ps.at(liveIdx, si)].isNaN && len > 0) {
        final k = len - 1;
        final j = ps.at(liveIdx, si);
        ps.tr[j] = cf[k];
        ps.traded[j] = lt - (st.start + k) < 5 ? 1 : 0;
        if (k >= 21) ps.ret21[j] = cf[k] / cf[k - 21] - 1;
        if (k >= 126) ps.mom6[j] = cf[k] / cf[k - 126] - 1;
        if (k >= 252) ps.mom12[j] = cf[k - 21] / cf[k - 252] - 1;
        if (!sma[k].isNaN) ps.dist200[j] = cf[k] / sma[k] - 1;
        if (k >= 219 && !sma[k - 20].isNaN) ps.slope200[j] = sma[k] / sma[k - 20] - 1;
      }
    }
    return ps;
  }
}

/// 百分位：值由小到大排，最小 0、最大 1，同分取平均名次。
Map<int, double> pctRanks(List<(int, double)> xs) {
  final l = [
    for (final x in xs)
      if (!x.$2.isNaN) x,
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  final out = <int, double>{};
  if (l.isEmpty) return out;
  if (l.length == 1) return {l.first.$1: 0.5};
  var i = 0;
  while (i < l.length) {
    var j = i;
    while (j + 1 < l.length && l[j + 1].$2 == l[i].$2) {
      j++;
    }
    final p = (i + j) / 2 / (l.length - 1);
    for (var k = i; k <= j; k++) {
      out[l[k].$1] = p;
    }
    i = j + 1;
  }
  return out;
}

double _clip(double x, double lo, double hi) => x.isNaN ? x : (x < lo ? lo : (x > hi ? hi : x));

/// 依日期決定回測時「看得到」的最後一個營收月份：每月 11 日以後才算知道上個月的營收。
int availableRevenueMonth(String date) {
  final y = int.parse(date.substring(0, 4)), m = int.parse(date.substring(5, 7));
  final d = int.parse(date.substring(8, 10));
  final cur = y * 12 + m - 1;
  return d >= 11 ? cur - 1 : cur - 2;
}

class FactorEngine {
  final LtData data;
  final PriceStats stats;

  /// 代號 → 現金股利的除息日（由舊到新）。
  final Map<String, List<String>> _cashDiv;

  FactorEngine(this.data)
    : stats = PriceStats.compute(data),
      _cashDiv = {
        for (final e in data.dividends.byCode.entries)
          e.key: [
            for (final x in e.value)
              if (x.cash) x.date,
          ],
      };

  bool get _hasDividends => data.dividends.byCode.isNotEmpty;

  /// 第 [sampleIdx] 個檢視日的全市場評分。最後一個（最新一天）用所有已公布的營收。
  SampleScores score(int sampleIdx) {
    final s = data.samples[sampleIdx];
    final live = sampleIdx == data.samples.length - 1;
    final raws = <int, LtRaw>{};
    for (var si = 0; si < data.stocks.length; si++) {
      final r = _raw(sampleIdx, si, live);
      if (r != null) raws[si] = r;
    }
    // 各子因子的百分位
    Map<int, double> rank(double Function(LtRaw) f) => pctRanks([for (final e in raws.entries) (e.key, f(e.value))]);
    final medYld = _median([
      for (final r in raws.values)
        if (!r.yld.isNaN) r.yld,
    ]);
    final sub = <FactorGroup, List<Map<int, double>>>{
      FactorGroup.momentum: [
        rank((r) => r.mom12),
        rank((r) => r.mom6),
        rank((r) => r.slope200),
        rank((r) => _clip(r.dist200, -1, 0.3)),
      ],
      FactorGroup.revenue: [
        rank((r) => _clip(r.revYoy3, -0.8, 2)),
        rank((r) => r.revPos12),
        rank((r) => _clip(r.rev12, -0.8, 2)),
        rank((r) => _clip(r.revAccel, -1, 1)),
      ],
      FactorGroup.quality: [
        rank((r) => r.roe.isNaN && !r.pb.isNaN ? -1 : _clip(r.roe, -1, 1)),
        rank((r) => r.roeStab),
        rank((r) => _clip(r.epsGrowth, -1, 1)),
      ],
      FactorGroup.value: [
        rank((r) => r.pePct.isNaN ? kNaN : -r.pePct),
        rank((r) => r.ey),
        rank((r) => _isTrap(r) ? medYld : r.yld),
        rank((r) => r.divYears),
      ],
      FactorGroup.flow: [rank((r) => r.fi), rank((r) => r.it)],
      FactorGroup.stability: [rank((r) => r.vol.isNaN ? kNaN : -r.vol), rank((r) => r.mdd.isNaN ? kNaN : -r.mdd)],
    };
    final scores = <LtScore>[];
    var above = 0, withTrend = 0;
    for (final e in raws.entries) {
      final si = e.key, r = e.value;
      final groups = <FactorGroup, double>{};
      for (final g in FactorGroup.values) {
        final vals = [
          for (final m in sub[g]!)
            if (m[si] != null) m[si]!,
        ];
        final need = g == FactorGroup.revenue ? 2 : 1;
        if (vals.length >= need) groups[g] = vals.reduce((a, b) => a + b) / vals.length * 100;
      }
      if (!r.dist200.isNaN) {
        withTrend++;
        if (r.dist200 > 0) above++;
      }
      if (!groups.containsKey(FactorGroup.momentum) ||
          !groups.containsKey(FactorGroup.stability) ||
          groups.length < 4) {
        continue;
      }
      var wsum = 0.0, sum = 0.0;
      for (final g in groups.entries) {
        wsum += g.key.weight;
        sum += g.key.weight * g.value;
      }
      final flags = _flags(r);
      var composite = sum / wsum;
      if (flags.contains(LtFlag.overheat)) composite -= 8;
      if (flags.contains(LtFlag.loss)) composite -= 5;
      final investable = r.val60 >= 50 && r.close >= 10;
      if (!investable) flags.add(LtFlag.illiquid);
      scores.add(LtScore(si, data.stocks[si].code, r, groups, composite, flags, investable));
    }
    scores.sort((a, b) => b.composite.compareTo(a.composite));
    for (var k = 0; k < scores.length; k++) {
      scores[k].rank = k + 1;
      scores[k].pct = scores.length < 2 ? 0.5 : 1 - k / (scores.length - 1);
    }
    return SampleScores(sampleIdx, s, scores, withTrend == 0 ? kNaN : above / withTrend);
  }

  static bool _isTrap(LtRaw r) =>
      r.yld > 0 && ((!r.payout.isNaN && r.payout > 1.0) || (r.yld > 7 && !r.epsGrowth.isNaN && r.epsGrowth < -0.2));

  Set<LtFlag> _flags(LtRaw r) => {
    if ((!r.ret21.isNaN && r.ret21 > 0.30) || (!r.dist200.isNaN && r.dist200 > 0.30)) LtFlag.overheat,
    if (!r.dist200.isNaN && r.dist200 < 0 && !r.slope200.isNaN && r.slope200 < 0) LtFlag.downtrend,
    if (!r.revYoy3.isNaN && r.revYoy3 < -0.10 && (r.revPos12.isNaN || r.revPos12 <= 4 / 12)) LtFlag.revenueDrop,
    if (r.pe.isNaN && !r.pb.isNaN) LtFlag.loss,
    if (_isTrap(r)) LtFlag.yieldTrap,
    if (!r.epsGrowth.isNaN && r.epsGrowth < -0.3) LtFlag.epsDrop,
  };

  LtRaw? _raw(int sampleIdx, int si, bool live) {
    final s = data.samples[sampleIdx];
    final st = data.stocks[si];
    final j = stats.at(sampleIdx, si);
    if (stats.traded[j] == 0) return null;
    // 至少一年多的歷史才看得出長期趨勢
    if (s.t - st.start < 260) return null;
    final close = s.close[si];
    if (close.isNaN || close <= 0) return null;
    final r = LtRaw()
      ..close = close
      ..val60 = s.val60[si]
      ..mom12 = stats.mom12[j]
      ..mom6 = stats.mom6[j]
      ..ret21 = stats.ret21[j]
      ..dist200 = stats.dist200[j]
      ..slope200 = stats.slope200[j]
      ..vol = stats.vol[j]
      ..mdd = stats.mdd[j];
    _revenue(r, st.code, s.date, live);
    // 品質、價值：本益比、淨值比、殖利率
    final pe = s.pe[si], pb = s.pb[si], yld = s.yld[si];
    r.pe = pe > 0 ? pe : kNaN;
    r.pb = pb > 0 ? pb : kNaN;
    r.yld = yld.isNaN ? kNaN : yld;
    if (!r.pe.isNaN) {
      r.ey = 1 / r.pe;
      if (!r.pb.isNaN) r.roe = r.pb / r.pe;
      if (!r.yld.isNaN) r.payout = r.yld / 100 * r.pe;
    } else if (!r.pb.isNaN) {
      r.ey = 0; // 虧損：盈餘殖利率當 0
    }
    // ROE 穩定度、本益比歷史位置、EPS 成長：看過去的檢視日
    final roes = <double>[], pes = <double>[];
    for (var k = math.max(0, sampleIdx - 60); k < sampleIdx; k++) {
      final o = data.samples[k];
      final ope = o.pe[si], opb = o.pb[si];
      if (ope > 0) pes.add(ope);
      if (k >= sampleIdx - 35 && ope > 0 && opb > 0) roes.add(opb / ope);
    }
    if (!r.roe.isNaN) roes.add(r.roe);
    if (roes.length >= 12) {
      final m = roes.reduce((a, b) => a + b) / roes.length;
      final sd = math.sqrt(roes.fold(0.0, (a, x) => a + (x - m) * (x - m)) / roes.length);
      r.roeStab = m - sd;
    }
    if (!r.pe.isNaN && pes.length >= 24) {
      r.pePct = pes.where((x) => x < r.pe).length / pes.length;
    }
    final back = sampleIdx - 12;
    if (back >= 0) {
      final o = data.samples[back];
      final ope = o.pe[si], oclose = o.close[si], opb = o.pb[si];
      final epsNow = r.pe.isNaN ? kNaN : close / r.pe;
      final epsOld = ope > 0 && oclose > 0 ? oclose / ope : kNaN;
      if (!epsNow.isNaN && !epsOld.isNaN) {
        r.epsGrowth = epsNow / epsOld - 1;
      } else if (epsNow.isNaN && !r.pb.isNaN && !epsOld.isNaN) {
        r.epsGrowth = -1; // 由盈轉虧
      } else if (!epsNow.isNaN && epsOld.isNaN && opb > 0) {
        r.epsGrowth = 1; // 由虧轉盈
      }
    }
    // 配息年數（近 5 年）
    if (_hasDividends) {
      final ds = _cashDiv[st.code] ?? const <String>[];
      final y = int.parse(s.date.substring(0, 4));
      final from = '${y - 5}${s.date.substring(4)}';
      final years = <String>{
        for (final d in ds)
          if (d.compareTo(from) > 0 && d.compareTo(s.date) <= 0) d.substring(0, 4),
      };
      r.divYears = math.min(5, years.length).toDouble();
    }
    // 法人
    final vol60 = s.vol60[si];
    if (vol60 > 0) {
      r.fi = s.fi60[si] / vol60;
      r.it = s.it60[si] / vol60;
    }
    return r;
  }

  void _revenue(LtRaw r, String code, String date, bool live) {
    final rev = data.revenue;
    var last = live ? (rev.lastIdxOf(code) ?? -1) : availableRevenueMonth(date);
    if (live) last = math.min(last, availableRevenueMonth(date) + 1);
    // 公司晚公布的話往前找，最多 2 個月
    var l = last;
    while (l > last - 3 && rev.at(code, l) == null) {
      l--;
    }
    if (rev.at(code, l) == null) return;
    r.revMonth = l;
    double yoy(int end, int w, {int minPairs = -1}) {
      var c = 0.0, p = 0.0, n = 0;
      for (var k = end - w + 1; k <= end; k++) {
        final a = rev.at(code, k), b = rev.lastYearAt(code, k);
        if (a == null || b == null || b <= 0) {
          if (minPairs < 0) return kNaN;
          continue;
        }
        c += a;
        p += b;
        n++;
      }
      if (n == 0 || (minPairs >= 0 && n < minPairs) || p <= 0) return kNaN;
      return c / p - 1;
    }

    r.revYoy3 = yoy(l, 3);
    r.rev12 = yoy(l, 12, minPairs: 10);
    final prev3 = yoy(l - 3, 3);
    if (!r.revYoy3.isNaN && !prev3.isNaN) r.revAccel = r.revYoy3 - prev3;
    var pos = 0, n = 0;
    for (var k = l - 11; k <= l; k++) {
      final a = rev.at(code, k), b = rev.lastYearAt(code, k);
      if (a == null || b == null || b <= 0) continue;
      n++;
      if (a > b) pos++;
    }
    if (n >= 8) r.revPos12 = pos / n;
    double? sum3(int end) {
      var s = 0.0;
      for (var k = end - 2; k <= end; k++) {
        final a = rev.at(code, k);
        if (a == null) return null;
        s += a;
      }
      return s;
    }

    final now = sum3(l);
    if (now != null) {
      var best = 0.0;
      var seen = 0;
      for (var k = l - 35; k <= l - 3; k++) {
        final x = sum3(k);
        if (x == null) continue;
        seen++;
        if (x > best) best = x;
      }
      r.revNewHigh = seen >= 12 && now >= best;
    }
  }

  static double _median(List<double> xs) {
    if (xs.isEmpty) return kNaN;
    final l = [...xs]..sort();
    return l[l.length ~/ 2];
  }
}

/// 營收月份索引 → yyyy-MM。
String revenueMonthLabel(int idx) => RevenueData.monthOf(idx);
