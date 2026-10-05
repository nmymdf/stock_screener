/// 長期組合：怎麼挑、怎麼配權重、什麼時候換股，以及照這套規則跑過去十幾年的回測。
///
/// 規則（事先決定，不拿回測結果去調）：
/// - 每月檢視日（11 日以後第一個交易日）收盤後決定，隔天收盤成交。
/// - 新買進：全市場總分前 10%、流動性夠、沒有短期過熱、沒有虧損、長期理由成立。
/// - 續抱：總分還在前 30% 就不動；至少抱 3 個月，除非長期理由破壞。
/// - 每月最多換 [LtConfig.maxChanges] 檔；換上去的要比換下來的明顯強（百分位高 20 以上）。
/// - 權重：分數越高、波動越低的配越多；單一檔最多 15%、單一產業最多 30%。
/// - 市場曝險（可選）：環境轉差時股票部位降到 75% 或 50%，按比例減碼，不換股。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../data/stock_industry.dart' show industryOf;
import 'exposure.dart';
import 'factors.dart';
import 'lt_data.dart';

class LtConfig {
  final int size;
  final double maxWeight;
  final double maxIndustry;
  final int maxChanges;
  final double buyPct;
  final double holdPct;
  final int minHoldDays;
  final ExposureMode exposure;

  /// 買進成本：手續費 0.1425% ＋ 滑價 0.1%；賣出再加證交稅 0.3%。
  final double buyCost, sellCost;
  final String startDate;

  /// 短期過熱的不買。
  final bool skipOverheat;

  /// 等權（否則分數 ÷ 波動度）。
  final bool equalWeight;

  /// 新買進的最低流動性：近 60 日平均每天成交值（百萬元）。
  final double minValue;

  /// 大盤核心比例：這部分放市值型 ETF（0050／006208），用加權報酬指數扣 0.3% 年費模擬；
  /// 其餘才是選股。每月檢視日調回目標比例。
  final double coreWeight;

  /// 只從成交值最大的 N 檔裡挑（0 = 不限）；這時「新買」改成這 N 檔裡總分前 [universeBuyFrac]。
  final int universeTop;
  final double universeBuyFrac;

  const LtConfig({
    this.coreWeight = 0,
    this.universeTop = 0,
    this.universeBuyFrac = 0.2,
    this.skipOverheat = true,
    this.equalWeight = false,
    this.minValue = 50,
    this.size = 15,
    this.maxWeight = 0.15,
    this.maxIndustry = 0.30,
    this.maxChanges = 5,
    this.buyPct = 0.90,
    this.holdPct = 0.70,
    this.minHoldDays = 63,
    this.exposure = ExposureMode.local,
    this.buyCost = 0.002425,
    this.sellCost = 0.005425,
    this.startDate = '2014-01-01',
  });

  LtConfig copyWith({
    int? size,
    int? maxChanges,
    ExposureMode? exposure,
    String? startDate,
    double? buyPct,
    double? holdPct,
    int? minHoldDays,
    bool? skipOverheat,
    bool? equalWeight,
    double? minValue,
    double? maxWeight,
    int? universeTop,
    double? universeBuyFrac,
    double? coreWeight,
  }) => LtConfig(
    coreWeight: coreWeight ?? this.coreWeight,
    universeTop: universeTop ?? this.universeTop,
    universeBuyFrac: universeBuyFrac ?? this.universeBuyFrac,
    size: size ?? this.size,
    maxWeight: maxWeight ?? this.maxWeight,
    maxIndustry: maxIndustry,
    maxChanges: maxChanges ?? this.maxChanges,
    buyPct: buyPct ?? this.buyPct,
    holdPct: holdPct ?? this.holdPct,
    minHoldDays: minHoldDays ?? this.minHoldDays,
    exposure: exposure ?? this.exposure,
    buyCost: buyCost,
    sellCost: sellCost,
    startDate: startDate ?? this.startDate,
    skipOverheat: skipOverheat ?? this.skipOverheat,
    equalWeight: equalWeight ?? this.equalWeight,
    minValue: minValue ?? this.minValue,
  );

  /// 單一產業最多幾檔（檔數上限，權重另外再限制）。
  int get maxPerIndustry => math.max(1, (maxIndustry * size + 1e-9).floor());
}

/// 產業（沒有分類的已下市股票各自算一類，不會被誤擋）。
String industryKey(String code) => industryOf(code) ?? '其他:$code';

/// 目標權重：分數 ÷ 波動度，再套單一檔、單一產業上限（多的部分分給還沒到上限的）。
Map<int, double> targetWeights(Map<int, (double score, double vol, String industry)> picks, LtConfig cfg) {
  if (picks.isEmpty) return {};
  final raw = <int, double>{
    for (final e in picks.entries)
      e.key: math.max(0.05, e.value.$1 / 100) / math.max(e.value.$2.isNaN ? 0.35 : e.value.$2, 0.15),
  };
  final total = raw.values.reduce((a, b) => a + b);
  final w = {for (final e in raw.entries) e.key: e.value / total};
  for (var iter = 0; iter < 50; iter++) {
    var excess = 0.0;
    final capped = <int>{};
    for (final e in w.entries.toList()) {
      if (e.value > cfg.maxWeight) {
        excess += e.value - cfg.maxWeight;
        w[e.key] = cfg.maxWeight;
      }
      if (w[e.key]! >= cfg.maxWeight - 1e-9) capped.add(e.key);
    }
    final ind = <String, double>{};
    for (final e in w.entries) {
      final k = picks[e.key]!.$3;
      ind[k] = (ind[k] ?? 0) + e.value;
    }
    final fullInd = <String>{};
    for (final e in ind.entries) {
      if (e.value > cfg.maxIndustry + 1e-9) {
        final f = cfg.maxIndustry / e.value;
        for (final k in w.keys.toList()) {
          if (picks[k]!.$3 == e.key) {
            excess += w[k]! * (1 - f);
            w[k] = w[k]! * f;
          }
        }
      }
      if ((ind[e.key]! >= cfg.maxIndustry - 1e-9)) fullInd.add(e.key);
    }
    if (excess < 1e-9) break;
    final open = [
      for (final k in w.keys)
        if (!capped.contains(k) && !fullInd.contains(picks[k]!.$3)) k,
    ];
    if (open.isEmpty) break; // 放不下的就留現金
    final rs = open.fold(0.0, (a, k) => a + raw[k]!);
    for (final k in open) {
      w[k] = w[k]! + excess * raw[k]! / rs;
    }
  }
  return w;
}

class LtTrade {
  final String date;
  final String code;
  final bool buy;
  final double weight; // 佔總資產
  final String reason;
  const LtTrade(this.date, this.code, this.buy, this.weight, this.reason);
}

class LtEpisode {
  final String code;
  final int entryT, exitT;
  final String entryDate, exitDate;

  /// 含息、扣成本的報酬；同期間比較基準的報酬。
  final double ret, benchRet;
  final bool open;
  const LtEpisode(
    this.code,
    this.entryT,
    this.exitT,
    this.entryDate,
    this.exitDate,
    this.ret,
    this.benchRet,
    this.open,
  );
  bool get win => ret > 0;
  bool get beat => ret > benchRet;
  int get days => exitT - entryT;
}

class LtRebalance {
  final String date; // 決定的那天（檢視日）
  final String execDate;
  final double exposure;
  final List<LtTrade> trades;
  final List<String> holdings; // 調整後持有
  const LtRebalance(this.date, this.execDate, this.exposure, this.trades, this.holdings);
}

/// 某次檢視的決定。
class LtDecision {
  final int t;
  final Map<int, String> sells; // 賣出 → 理由
  final List<(int, String)> buys; // 買進 → 理由
  final Map<int, double> target; // 調整後全部持股的目標權重
  final ExposureState exposure;
  const LtDecision(this.t, this.sells, this.buys, this.target, this.exposure);
}

class _Pos {
  double units;
  final int entryT;
  final double entryTr;
  _Pos(this.units, this.entryT, this.entryTr);
}

class YearRow {
  final int year;
  final double ret, bench;

  /// 這一年有幾個交易日在回測期間內（不滿一年的是第一年或今年）。
  final int days;
  const YearRow(this.year, this.ret, this.bench, this.days);
  bool get beat => ret > bench;
  bool get partial => days < 230;
}

class StressRow {
  final String label, from, to;
  final double ret, bench;
  const StressRow(this.label, this.from, this.to, this.ret, this.bench);
}

class PerfStats {
  final String from, to;
  final double years;
  final double totalRet, cagr, vol, sharpe, mdd;
  final double benchTotal, benchCagr, benchMdd;
  final double eqwCagr;
  final double monthlyWin;
  final List<YearRow> yearRows;
  final double posWin, posBeat, avgHoldDays;
  final int positions;
  final double turnover;
  final double avgExposure;
  final double firstHalfExcess, secondHalfExcess;
  final List<StressRow> stress;

  const PerfStats({
    required this.from,
    required this.to,
    required this.years,
    required this.totalRet,
    required this.cagr,
    required this.vol,
    required this.sharpe,
    required this.mdd,
    required this.benchTotal,
    required this.benchCagr,
    required this.benchMdd,
    required this.eqwCagr,
    required this.monthlyWin,
    required this.yearRows,
    required this.posWin,
    required this.posBeat,
    required this.avgHoldDays,
    required this.positions,
    required this.turnover,
    required this.avgExposure,
    required this.firstHalfExcess,
    required this.secondHalfExcess,
    required this.stress,
  });

  double get excessCagr => cagr - benchCagr;
  double get yearlyWin => yearRows.isEmpty ? 0 : yearRows.where((y) => y.beat).length / yearRows.length;
}

class SimResult {
  final LtConfig cfg;
  final int startT, endT;
  final Float64List nav, bench, eqw;
  final bool benchIsTri;
  final List<LtRebalance> rebalances;
  final List<LtEpisode> episodes;

  /// 目前持股：位置 → (權重, 買進日)。
  final Map<int, (double, String)> holdings;
  final double cashWeight;

  /// 最後一個檢視日已經決定、還沒成交的調整（今天就是檢視日的時候）。
  final LtDecision? pending;
  final PerfStats stats;

  const SimResult({
    required this.cfg,
    required this.startT,
    required this.endT,
    required this.nav,
    required this.bench,
    required this.eqw,
    required this.benchIsTri,
    required this.rebalances,
    required this.episodes,
    required this.holdings,
    required this.cashWeight,
    required this.pending,
    required this.stats,
  });
}

/// 跑回測。[book] 是每個檢視日的評分（位置和 data.samples 一樣）。
class PortfolioSim {
  final LtData data;
  final ScoreBook book;
  final ExposureEngine exposure;
  final LtConfig cfg;

  PortfolioSim(this.data, this.book, this.exposure, this.cfg);

  final Map<int, _Pos> _pos = {};
  double _cash = 1;

  double _value(int t) {
    var v = _cash;
    for (final e in _pos.entries) {
      final p = data.stocks[e.key].trAt(t);
      if (!p.isNaN) v += e.value.units * p;
    }
    return v;
  }

  /// 第一個可以開始的檢視日：日期到了、而且有足夠多股票有分數。
  int get startSample {
    for (var s = 0; s < data.samples.length; s++) {
      final sm = data.samples[s];
      if (sm.live) continue;
      if (sm.date.compareTo(cfg.startDate) >= 0 && book.count(s) >= math.min(300, data.stocks.length ~/ 3)) return s;
    }
    return -1;
  }

  /// 在檢視日 [sc] 依目前持股做決定。[initial] = 第一次建倉（不受每月換股上限）。
  LtDecision decide(ScoreSource sc, {Map<int, int>? entryT}) {
    final t = sc.t;
    final exp = exposure.at(t, sc.breadth, mode: cfg.exposure);
    final held = (entryT ?? {for (final e in _pos.entries) e.key: e.value.entryT});
    final initial = held.isEmpty;
    final sells = <int, String>{};
    final weak = <LtScore>[];
    final keep = <int>[];
    for (final e in held.entries) {
      final si = e.key;
      final x = sc.of(si);
      final st = data.stocks[si];
      if (x == null) {
        if (t - st.lastTradedBy(t) > 20) {
          sells[si] = '停止交易超過一個月（可能下市或全額交割）';
        } else {
          keep.add(si);
        }
        continue;
      }
      if (x.broken) {
        sells[si] = _brokenReason(x);
        continue;
      }
      if (t - e.value >= cfg.minHoldDays && x.pct < cfg.holdPct) {
        weak.add(x);
      } else {
        keep.add(si);
      }
    }
    final indCount = <String, int>{};
    void addInd(int si, int d) {
      final k = industryKey(data.stocks[si].code);
      indCount[k] = (indCount[k] ?? 0) + d;
    }

    for (final si in keep) {
      addInd(si, 1);
    }
    for (final w in weak) {
      addInd(w.si, 1);
    }
    final taken = <int>{...held.keys};
    // 依名次往下看，到不在前 10%（或大型股範圍的前 20%）就停（不用看完全部）
    final candidates = <LtScore>[];
    final uni = cfg.universeTop > 0 ? sc.topLiquid(cfg.universeTop) : null;
    final uniLimit = uni == null ? 0 : (uni.length * cfg.universeBuyFrac).ceil();
    var uniSeen = 0;
    for (final c in sc.rankedIter) {
      if (uni != null) {
        if (!uni.contains(c.si)) continue;
        if (++uniSeen > uniLimit) break;
      } else if (c.pct < cfg.buyPct) {
        break;
      }
      if (c.investable &&
          (c.raw.val60.isNaN || c.raw.val60 >= cfg.minValue) &&
          !c.broken &&
          !(cfg.skipOverheat && c.flags.contains(LtFlag.overheat)) &&
          !c.flags.contains(LtFlag.loss) &&
          !taken.contains(c.si)) {
        candidates.add(c);
      }
    }
    final buys = <(int, String)>[];
    var changes = 0;
    bool indOk(LtScore c) => (indCount[industryKey(c.code)] ?? 0) < cfg.maxPerIndustry;
    var open = cfg.size - keep.length - weak.length;
    for (final c in candidates) {
      if (open <= 0 || (!initial && changes >= cfg.maxChanges)) break;
      if (!indOk(c)) continue;
      buys.add((c.si, initial ? '建立組合：總分第 ${c.rank} 名' : '補上空出的位置：總分第 ${c.rank} 名'));
      taken.add(c.si);
      addInd(c.si, 1);
      open--;
      changes++;
    }
    weak.sort((a, b) => a.pct.compareTo(b.pct));
    final keptWeak = <int>[];
    for (final w in weak) {
      if (changes >= cfg.maxChanges) {
        keptWeak.add(w.si);
        continue;
      }
      addInd(w.si, -1);
      LtScore? pick;
      for (final c in candidates) {
        if (taken.contains(c.si) || c.pct < w.pct + 0.2 || !indOk(c)) continue;
        pick = c;
        break;
      }
      if (pick == null) {
        addInd(w.si, 1);
        keptWeak.add(w.si);
        continue;
      }
      sells[w.si] = '總分掉到第 ${w.rank} 名（不在前 30%），換成更強的 ${pick.code}';
      buys.add((pick.si, '換掉轉弱的 ${w.code}：總分第 ${pick.rank} 名'));
      taken.add(pick.si);
      addInd(pick.si, 1);
      changes++;
    }
    final finalSet = [...keep, ...keptWeak, for (final b in buys) b.$1];
    final picks = <int, (double, double, String)>{};
    for (final si in finalSet) {
      final x = sc.of(si);
      picks[si] = cfg.equalWeight
          ? (50, 0.3, industryKey(data.stocks[si].code))
          : (x?.composite ?? 50, x?.raw.vol ?? double.nan, industryKey(data.stocks[si].code));
    }
    return LtDecision(t, sells, buys, targetWeights(picks, cfg), exp);
  }

  static String _brokenReason(LtScore x) {
    final f = x.flags;
    if (f.contains(LtFlag.downtrend) && f.contains(LtFlag.revenueDrop)) return '長期理由破壞：年線下彎而且營收衰退';
    if (f.contains(LtFlag.loss) && f.contains(LtFlag.downtrend)) return '長期理由破壞：虧損而且年線下彎';
    return '長期理由破壞：總分掉到全市場後 15%（第 ${x.rank} 名）';
  }

  double _turnoverValue = 0;
  final List<double> _blend = [];
  final List<LtEpisode> _episodes = [];
  final List<double> _exposures = [];

  double _bench(int t) {
    final tri = data.tri[t];
    return tri.isNaN ? data.taiex[t] : tri;
  }

  void _closeEpisode(int si, int t, {bool open = false}) {
    final p = _pos[si]!;
    final px = data.stocks[si].trAt(t);
    final ret = px / p.entryTr * (1 - cfg.sellCost) / (1 + cfg.buyCost) - 1;
    final b0 = _bench(p.entryT), b1 = _bench(t);
    _episodes.add(
      LtEpisode(
        data.stocks[si].code,
        p.entryT,
        t,
        data.dates[p.entryT],
        data.dates[t],
        ret,
        b0.isNaN || b1.isNaN ? 0 : b1 / b0 - 1,
        open,
      ),
    );
  }

  LtRebalance _execute(LtDecision d, int t) {
    final trades = <LtTrade>[];
    final nav0 = _value(t);
    for (final e in d.sells.entries) {
      final si = e.key;
      final p = _pos[si];
      if (p == null) continue;
      final px = data.stocks[si].trAt(t);
      final v = p.units * px;
      _cash += v * (1 - cfg.sellCost);
      _turnoverValue += v;
      _closeEpisode(si, t);
      _pos.remove(si);
      trades.add(LtTrade(data.dates[t], data.stocks[si].code, false, v / nav0, e.value));
    }
    final nav = _value(t);
    final targetEquity = d.exposure.level * nav;
    for (final (si, reason) in d.buys) {
      final px = data.stocks[si].trAt(t);
      if (px.isNaN || px <= 0) continue;
      final want = (d.target[si] ?? 0) * targetEquity;
      final spend = math.min(want, _cash / (1 + cfg.buyCost));
      if (spend <= nav * 0.005) continue;
      _cash -= spend * (1 + cfg.buyCost);
      _turnoverValue += spend;
      _pos[si] = _Pos(spend / px, t, px);
      trades.add(LtTrade(data.dates[t], data.stocks[si].code, true, spend / nav, reason));
    }
    // 單一檔漲到 20% 以上就調回 15%
    for (final e in _pos.entries) {
      final px = data.stocks[e.key].trAt(t);
      final v = e.value.units * px;
      if (v > nav * 0.20) {
        final cut = v - nav * cfg.maxWeight;
        e.value.units -= cut / px;
        _cash += cut * (1 - cfg.sellCost);
        _turnoverValue += cut;
        trades.add(LtTrade(data.dates[t], data.stocks[e.key].code, false, cut / nav, '漲到超過 20%，調回 15% 上限'));
      }
    }
    // 曝險：股票部位離目標超過 5% 才調整
    var equity = nav - _cash;
    if (equity > targetEquity + 0.05 * nav) {
      final f = (equity - targetEquity) / equity;
      for (final e in _pos.entries) {
        final px = data.stocks[e.key].trAt(t);
        final cut = e.value.units * px * f;
        e.value.units *= 1 - f;
        _cash += cut * (1 - cfg.sellCost);
        _turnoverValue += cut;
      }
      trades.add(
        LtTrade(data.dates[t], '', false, f * equity / nav, '市場轉弱：股票部位降到 ${(d.exposure.level * 100).round()}%'),
      );
    } else if (equity < targetEquity - 0.05 * nav && _cash > 0.01 * nav) {
      // 補到目標：先補離目標權重最遠的
      final deficits = <int, double>{};
      for (final e in _pos.entries) {
        final px = data.stocks[e.key].trAt(t);
        final cur = e.value.units * px;
        final tgt = (d.target[e.key] ?? cfg.maxWeight * 0.5) * targetEquity;
        if (tgt > cur) deficits[e.key] = tgt - cur;
      }
      final need = deficits.values.fold(0.0, (a, b) => a + b);
      final budget = math.min(math.min(_cash / (1 + cfg.buyCost), targetEquity - equity), need);
      if (need > 0 && budget > nav * 0.01) {
        for (final e in deficits.entries) {
          final px = data.stocks[e.key].trAt(t);
          final add = budget * e.value / need;
          _pos[e.key]!.units += add / px;
          _cash -= add * (1 + cfg.buyCost);
          _turnoverValue += add;
        }
        trades.add(LtTrade(data.dates[t], '', true, budget / nav, '股票部位補到 ${(d.exposure.level * 100).round()}%'));
      }
    }
    equity = _value(t) - _cash;
    _exposures.add(equity / _value(t));
    return LtRebalance(data.dates[d.t], data.dates[t], d.exposure.level, trades, [
      for (final si in _pos.keys) data.stocks[si].code,
    ]);
  }

  SimResult run() {
    final s0 = startSample;
    final nd = data.nd;
    if (s0 < 0 || nd < 2) throw StateError('資料不足，無法回測（需要至少一年多的歷史資料）');
    final startT = data.samples[s0].t;
    final endT = nd - 1;
    final n = endT - startT + 1;
    final nav = Float64List(n), bench = Float64List(n), eqw = Float64List(n);
    final sampleAt = <int, int>{
      for (var s = s0; s < data.samples.length; s++)
        if (!data.samples[s].live) data.samples[s].t: s,
    };
    LtDecision? pending;
    final rebalances = <LtRebalance>[];
    // 等權比較：最近一個檢視日「可投資」的股票每天平均報酬
    var eqUniverse = <int>[];
    var eqv = 1.0;
    final b0 = _bench(startT);
    for (var t = startT; t <= endT; t++) {
      if (pending != null && t == pending.t + 1) {
        rebalances.add(_execute(pending, t));
        pending = null;
      }
      nav[t - startT] = _value(t);
      final b = _bench(t);
      bench[t - startT] = b0.isNaN || b.isNaN ? double.nan : b / b0;
      if (t > startT && eqUniverse.isNotEmpty) {
        var sum = 0.0, c = 0;
        for (final si in eqUniverse) {
          final st = data.stocks[si];
          final a = st.trAt(t), p = st.trAt(t - 1);
          if (a.isNaN || p.isNaN || p <= 0) continue;
          sum += a / p - 1;
          c++;
        }
        if (c > 0) eqv *= 1 + sum / c;
      }
      eqw[t - startT] = eqv;
      final si = sampleAt[t];
      if (si != null) {
        final sc = BookView(book, data, si);
        eqUniverse = sc.investable.toList();
        pending = decide(sc);
      }
    }
    final open = pending; // 今天就是檢視日：已經決定、明天才成交
    for (final si in _pos.keys.toList()) {
      _closeEpisode(si, endT, open: true);
    }
    // 大盤核心：選股部位和大盤每月檢視日調回目標比例
    if (cfg.coreWeight > 0) {
      final w = cfg.coreWeight;
      final execs = {for (final r in rebalances) data.dateIndex(r.execDate)};
      var core = w, sat = 1 - w;
      for (var k = 1; k < n; k++) {
        final t = startT + k;
        final rb = bench[k].isNaN || bench[k - 1].isNaN ? 0.0 : bench[k] / bench[k - 1] - 1;
        core *= 1 + rb - 0.003 / 250;
        sat *= nav[k - 1] > 0 ? nav[k] / nav[k - 1] : 1;
        final total = core + sat;
        if (execs.contains(t)) {
          core = total * w;
          sat = total * (1 - w);
        }
        _blend.add(total); // 迴圈還要用原本的選股淨值，最後才覆寫
      }
      for (var k = 1; k < n; k++) {
        nav[k] = _blend[k - 1];
      }
      nav[0] = 1;
    }
    final navEnd = _value(endT);
    final holdings = <int, (double, String)>{
      for (final e in _pos.entries)
        e.key: (e.value.units * data.stocks[e.key].trAt(endT) / navEnd, data.dates[e.value.entryT]),
    };
    return SimResult(
      cfg: cfg,
      startT: startT,
      endT: endT,
      nav: nav,
      bench: bench,
      eqw: eqw,
      benchIsTri: !data.tri[startT].isNaN,
      rebalances: rebalances,
      episodes: List.unmodifiable(_episodes),
      holdings: holdings,
      cashWeight: _cash / navEnd,
      pending: open,
      stats: _stats(startT, endT, nav, bench, eqw),
    );
  }

  static const _stressPeriods = [
    ('2015 中國股災', '2015-04-27', '2015-08-24'),
    ('2018 貿易戰', '2018-09-28', '2018-10-26'),
    ('2020 新冠疫情', '2020-01-20', '2020-03-19'),
    ('2022 升息空頭', '2022-01-05', '2022-10-25'),
    ('2024 日圓套利平倉', '2024-07-11', '2024-08-05'),
    ('2025 關稅衝擊', '2025-03-26', '2025-04-09'),
  ];

  PerfStats _stats(int startT, int endT, Float64List nav, Float64List bench, Float64List eqw) {
    final n = nav.length;
    final years = math.max(1 / 250, (n - 1) / 250.0);
    double cagr(double total) => math.pow(math.max(1e-9, 1 + total), 1 / years) - 1;
    double mddOf(Float64List v) {
      var peak = v[0], dd = 0.0;
      for (final x in v) {
        if (x.isNaN) continue;
        if (x > peak) peak = x;
        dd = math.max(dd, 1 - x / peak);
      }
      return dd;
    }

    final total = nav[n - 1] / nav[0] - 1;
    final bTotal = bench[n - 1].isNaN ? 0.0 : bench[n - 1] / bench[0] - 1;
    var s1 = 0.0, s2 = 0.0;
    for (var k = 1; k < n; k++) {
      final r = nav[k] / nav[k - 1] - 1;
      s1 += r;
      s2 += r * r;
    }
    final mean = s1 / math.max(1, n - 1);
    final vol = math.sqrt(math.max(0, s2 / math.max(1, n - 1) - mean * mean) * 250);
    final c = cagr(total);
    // 月報酬勝率、年度
    final monthEnds = <int>[];
    final yearEnds = <int>[];
    for (var k = 0; k < n; k++) {
      final d = data.dates[startT + k];
      final nextD = k + 1 < n ? data.dates[startT + k + 1] : null;
      if (nextD == null || nextD.substring(0, 7) != d.substring(0, 7)) monthEnds.add(k);
      if (nextD == null || nextD.substring(0, 4) != d.substring(0, 4)) yearEnds.add(k);
    }
    var mw = 0, mt = 0;
    var prev = 0;
    for (final k in monthEnds) {
      if (k == 0) continue;
      final r = nav[k] / nav[prev] - 1, b = bench[k] / bench[prev] - 1;
      if (!b.isNaN) {
        mt++;
        if (r > b) mw++;
      }
      prev = k;
    }
    final rows = <YearRow>[];
    prev = 0;
    for (final k in yearEnds) {
      if (k == 0) continue;
      final y = int.parse(data.dates[startT + k].substring(0, 4));
      final span = k - prev;
      if (span >= 120) {
        rows.add(YearRow(y, nav[k] / nav[prev] - 1, bench[k] / bench[prev] - 1, span));
      }
      prev = k;
    }
    final closed = _episodes.where((e) => !e.open).toList();
    final half = n ~/ 2;
    double excess(int a, int b) {
      final yrs = math.max(1 / 250, (b - a) / 250.0);
      final p = math.pow(nav[b] / nav[a], 1 / yrs) - 1;
      final q = math.pow(bench[b] / bench[a], 1 / yrs) - 1;
      return (p - q).toDouble();
    }

    final stress = <StressRow>[];
    for (final (label, from, to) in _stressPeriods) {
      final a = data.dateIndex(from) - startT, b = data.dateIndex(to) - startT;
      if (a < 0 || b <= a || b >= n) continue;
      stress.add(StressRow(label, from, to, nav[b] / nav[a] - 1, bench[b] / bench[a] - 1));
    }
    final avgNav = nav.fold(0.0, (a, b) => a + b) / n;
    return PerfStats(
      from: data.dates[startT],
      to: data.dates[endT],
      years: years,
      totalRet: total,
      cagr: c,
      vol: vol,
      sharpe: vol > 0 ? (c - 0.01) / vol : 0,
      mdd: mddOf(nav),
      benchTotal: bTotal,
      benchCagr: cagr(bTotal),
      benchMdd: mddOf(bench),
      eqwCagr: cagr(eqw[n - 1] / eqw[0] - 1),
      monthlyWin: mt == 0 ? 0 : mw / mt,
      yearRows: rows,
      posWin: closed.isEmpty ? 0 : closed.where((e) => e.win).length / closed.length,
      posBeat: closed.isEmpty ? 0 : closed.where((e) => e.beat).length / closed.length,
      avgHoldDays: closed.isEmpty ? 0 : closed.fold(0, (a, e) => a + e.days) / closed.length,
      positions: closed.length,
      turnover: _turnoverValue / avgNav / years / 2,
      avgExposure: _exposures.isEmpty ? 1 : _exposures.reduce((a, b) => a + b) / _exposures.length,
      firstHalfExcess: half > 20 ? excess(0, half) : 0,
      secondHalfExcess: half > 20 ? excess(half, n - 1) : 0,
      stress: stress,
    );
  }
}

// ───────────────────────────── 汰弱留強（依手上持股） ─────────────────────────────

class HoldingInput {
  final String code;
  final String name;
  final double value; // 市值
  final String? since; // 第一次買進日
  const HoldingInput(this.code, this.name, this.value, this.since);
}

enum SwapAction { keep, watch, replace, notRated }

extension SwapActionInfo on SwapAction {
  String get label => switch (this) {
    SwapAction.keep => '續抱',
    SwapAction.watch => '觀察',
    SwapAction.replace => '建議汰換',
    SwapAction.notRated => '不在評分範圍',
  };
}

class SwapRow {
  final HoldingInput holding;
  final LtScore? score;
  final SwapAction action;
  final List<String> reasons;
  final double weight;
  final List<LtScore> candidates;
  const SwapRow(this.holding, this.score, this.action, this.reasons, this.weight, this.candidates);
}

class SwapAdvice {
  final List<SwapRow> rows;
  final List<String> notes;
  final int maxSwaps;
  const SwapAdvice(this.rows, this.notes, this.maxSwaps);
  int get replaceCount => rows.where((r) => r.action == SwapAction.replace).length;
}

/// 依手上的持股給汰弱留強建議：不全面換，一個月最多換 [maxSwaps] 檔，換上去的要明顯更強。
SwapAdvice swapAdvice(
  List<HoldingInput> holdings,
  SampleScores sc,
  LtData data, {
  int maxSwaps = 3,
  LtConfig cfg = const LtConfig(),
}) {
  final total = holdings.fold(0.0, (a, h) => a + h.value);
  final today = sc.date;
  int daysHeld(String? since) {
    if (since == null) return 9999;
    final a = DateTime.tryParse(since), b = DateTime.tryParse(today);
    return a == null || b == null ? 9999 : b.difference(a).inDays;
  }

  final rows = <SwapRow>[];
  final replace = <(int, LtScore, HoldingInput, List<String>, double)>[];
  final indWeight = <String, double>{};
  for (final h in holdings) {
    indWeight[industryKey(h.code)] = (indWeight[industryKey(h.code)] ?? 0) + (total > 0 ? h.value / total : 0);
  }
  final heldCodes = {for (final h in holdings) h.code};
  for (var i = 0; i < holdings.length; i++) {
    final h = holdings[i];
    final w = total > 0 ? h.value / total : 0.0;
    final si = data.index[h.code];
    final x = si == null ? null : sc.of(si);
    if (x == null) {
      final why = si == null
          ? (RegExp(r'^[1-9]\d{3}$').hasMatch(h.code) ? '上櫃或沒有上市資料，長期評分只涵蓋上市普通股' : 'ETF、特別股不做個股評分')
          : '資料不足（上市未滿一年或近期停止交易）';
      rows.add(SwapRow(h, null, SwapAction.notRated, [why], w, const []));
      continue;
    }
    final reasons = <String>[];
    final held = daysHeld(h.since);
    SwapAction action;
    if (x.broken) {
      action = SwapAction.replace;
      reasons.add(PortfolioSim._brokenReason(x));
    } else if (x.pct < 0.3 && held >= 90) {
      action = SwapAction.replace;
      reasons.add('總分第 ${x.rank} 名（全市場後 30%），持有已超過 3 個月');
    } else if (x.pct < 0.5 ||
        x.flags.contains(LtFlag.downtrend) ||
        x.flags.contains(LtFlag.revenueDrop) ||
        x.flags.contains(LtFlag.epsDrop)) {
      action = SwapAction.watch;
      reasons.add(
        x.pct < 0.3 && held < 90
            ? '總分偏低（第 ${x.rank} 名），但持有未滿 3 個月，先觀察'
            : '總分第 ${x.rank} 名（前 ${((1 - x.pct) * 100).toStringAsFixed(0)}%）',
      );
      for (final f in x.flags) {
        if (f == LtFlag.downtrend || f == LtFlag.revenueDrop || f == LtFlag.epsDrop) reasons.add(f.explain);
      }
    } else {
      action = SwapAction.keep;
      reasons.add('總分第 ${x.rank} 名（前 ${((1 - x.pct) * 100).toStringAsFixed(0)}%），長期理由還在');
    }
    if (w > cfg.maxWeight) reasons.add('佔持股 ${(w * 100).toStringAsFixed(0)}%，超過單一檔 15% 的上限，可考慮分批調節');
    if (action == SwapAction.replace) {
      replace.add((i, x, h, reasons, w));
      rows.add(SwapRow(h, x, action, reasons, w, const [])); // 先佔位，下面補候選
    } else {
      rows.add(SwapRow(h, x, action, reasons, w, const []));
    }
  }
  // 最弱的先換，一個月最多 maxSwaps 檔
  replace.sort((a, b) => a.$2.pct.compareTo(b.$2.pct));
  final used = <String>{};
  for (var k = 0; k < replace.length; k++) {
    final (i, x, h, reasons, w) = replace[k];
    final idx = rows.indexWhere((r) => identical(r.holding, h));
    if (k >= maxSwaps) {
      rows[idx] = SwapRow(h, x, SwapAction.watch, [...reasons, '本月換股已達 $maxSwaps 檔上限，下個月再處理'], w, const []);
      continue;
    }
    final myInd = industryKey(h.code);
    final cands = <LtScore>[];
    for (final c in sc.ranked) {
      if (cands.length >= 3) break;
      if (!c.investable ||
          c.pct < 0.85 ||
          c.broken ||
          c.flags.contains(LtFlag.overheat) ||
          c.flags.contains(LtFlag.loss) ||
          heldCodes.contains(c.code) ||
          c.pct < x.pct + 0.25) {
        continue;
      }
      final ci = industryKey(c.code);
      final after = (indWeight[ci] ?? 0) + w - (ci == myInd ? w : 0);
      if (after > cfg.maxIndustry + 1e-9) continue;
      if (cands.isEmpty && used.contains(c.code)) continue; // 第一推薦不重複
      cands.add(c);
    }
    if (cands.isNotEmpty) used.add(cands.first.code);
    rows[idx] = SwapRow(h, x, SwapAction.replace, reasons, w, cands);
  }
  final notes = <String>[];
  for (final e in indWeight.entries) {
    if (e.value > cfg.maxIndustry + 1e-9 && !e.key.startsWith('其他:')) {
      notes.add('「${e.key}」佔持股 ${(e.value * 100).toStringAsFixed(0)}%，超過單一產業 30% 的上限，新買進時避開這個產業');
    }
  }
  if (holdings.length < 8) notes.add('目前只有 ${holdings.length} 檔，長期組合建議 10～15 檔分散風險');
  return SwapAdvice(rows, notes, maxSwaps);
}
