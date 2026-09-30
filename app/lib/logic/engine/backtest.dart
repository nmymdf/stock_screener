/// 回測（規格書 §15）：用本機的日 K，把「推薦清單用的同一組訊號、否決和
/// 交易計畫」套到過去每一天，模擬隔天進場、停損、2R 先出一半、保本、
/// 移動停利、時間停損，扣掉手續費、證交稅和滑價。
///
/// 避免偏誤的做法：
/// - 訊號用第 t 天收盤後的資料，隔天（t+1）開盤才進場——不偷看未來。
/// - 每天的全市場名單就是那天真的有交易的股票（包含之後下市的），沒有
///   存活者偏差。
/// - 參數是固定的預設值，沒有拿這段資料去最佳化；另外列出前段／後段、
///   壓力測試、Monte Carlo 最大回撤，看結果是不是穩定。
///
/// 這是「逐筆訊號」的統計（每筆固定承擔 1R 風險），不是投資組合模擬——
/// 沒有同時持股上限和資金限制，也還沒有產業、基本面、籌碼分數。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../data/stock_industry.dart';
import '../ta.dart';
import 'analysis.dart';
import 'market_engine.dart';
import 'scoring.dart';
import 'signals.dart';

class BacktestConfig {
  final Set<Strategy> strategies;
  final double slippagePct; // 單邊滑價（%）
  final double feeMultiplier; // 手續費倍數（壓力測試用）
  final int entryDelay; // 0 = 隔天開盤進場；1 = 再晚一天（壓力測試用）
  final int timeStopDays;

  const BacktestConfig({
    this.strategies = const {Strategy.breakout, Strategy.pullback, Strategy.continuation, Strategy.meanReversion},
    this.slippagePct = 0.1,
    this.feeMultiplier = 1,
    this.entryDelay = 0,
    this.timeStopDays = 10,
  });

  /// §15.2 Stress Test：滑價 ×2、交易成本提高、進出場延遲一根 Bar。
  BacktestConfig get stressed => BacktestConfig(
    strategies: strategies,
    slippagePct: slippagePct * 2,
    feeMultiplier: feeMultiplier * 1.5,
    entryDelay: entryDelay + 1,
    timeStopDays: timeStopDays,
  );
}

class BtTrade {
  final String code;
  final Strategy strategy;
  final String signalDate, entryDate, exitDate;
  final double entry, stop, target, exit;
  final double r; // 以初始風險為單位的損益（扣成本後）
  final double retPct;
  final int days;
  final String exitReason;
  final bool openAtEnd;

  const BtTrade({
    required this.code,
    required this.strategy,
    required this.signalDate,
    required this.entryDate,
    required this.exitDate,
    required this.entry,
    required this.stop,
    required this.target,
    required this.exit,
    required this.r,
    required this.retPct,
    required this.days,
    required this.exitReason,
    required this.openAtEnd,
  });
}

class BtStats {
  final int n;
  final double winRate, avgR, avgWinR, avgLossR, profitFactor, totalR, maxDdR, avgRetPct, avgDays;
  final int maxConsecLoss;

  const BtStats({
    required this.n,
    required this.winRate,
    required this.avgR,
    required this.avgWinR,
    required this.avgLossR,
    required this.profitFactor,
    required this.totalR,
    required this.maxDdR,
    required this.avgRetPct,
    required this.avgDays,
    required this.maxConsecLoss,
  });

  /// 平均盈虧比 = 平均獲利 R ÷ 平均虧損 R。
  double get payoff => avgLossR == 0 ? double.infinity : avgWinR / avgLossR.abs();

  static BtStats of(List<BtTrade> trades) {
    final t = [...trades]..sort((a, b) => a.exitDate.compareTo(b.exitDate));
    final n = t.length;
    if (n == 0) {
      return const BtStats(
        n: 0,
        winRate: 0,
        avgR: 0,
        avgWinR: 0,
        avgLossR: 0,
        profitFactor: 0,
        totalR: 0,
        maxDdR: 0,
        avgRetPct: 0,
        avgDays: 0,
        maxConsecLoss: 0,
      );
    }
    var wins = 0, streak = 0, maxStreak = 0;
    var sumW = 0.0, sumL = 0.0, sumR = 0.0, sumRet = 0.0, sumDays = 0.0;
    for (final x in t) {
      sumR += x.r;
      sumRet += x.retPct;
      sumDays += x.days;
      if (x.r > 0) {
        wins++;
        sumW += x.r;
        streak = 0;
      } else {
        sumL += x.r;
        streak++;
        maxStreak = math.max(maxStreak, streak);
      }
    }
    final losses = n - wins;
    return BtStats(
      n: n,
      winRate: wins / n,
      avgR: sumR / n,
      avgWinR: wins == 0 ? 0 : sumW / wins,
      avgLossR: losses == 0 ? 0 : sumL / losses,
      profitFactor: sumL == 0 ? (sumW > 0 ? double.infinity : 0) : sumW / -sumL,
      totalR: sumR,
      maxDdR: maxDrawdown([for (final x in t) x.r]),
      avgRetPct: sumRet / n,
      avgDays: sumDays / n,
      maxConsecLoss: maxStreak,
    );
  }
}

/// 依序累加 R 的最大回撤（以 R 為單位）。
double maxDrawdown(List<double> rs) {
  var cum = 0.0, peak = 0.0, dd = 0.0;
  for (final r in rs) {
    cum += r;
    peak = math.max(peak, cum);
    dd = math.max(dd, peak - cum);
  }
  return dd;
}

class BacktestResult {
  final BacktestConfig config;
  final List<BtTrade> trades;
  final BtStats overall;
  final Map<Strategy, BtStats> byStrategy;
  final String? splitDate;
  final BtStats firstPart, secondPart;
  final BtStats stressed;
  final double mcDdMedian, mcDd95;
  final List<(String, double)> equity; // (出場日, 累積 R)
  final int signals, skippedChase, skippedGap;
  final String? fromDate, toDate;

  const BacktestResult({
    required this.config,
    required this.trades,
    required this.overall,
    required this.byStrategy,
    required this.splitDate,
    required this.firstPart,
    required this.secondPart,
    required this.stressed,
    required this.mcDdMedian,
    required this.mcDd95,
    required this.equity,
    required this.signals,
    required this.skippedChase,
    required this.skippedGap,
    required this.fromDate,
    required this.toDate,
  });
}

class _Sim {
  final List<BtTrade> trades = [];
  int signals = 0, skippedChase = 0, skippedGap = 0;
}

const _warmup = 60;

BacktestResult runBacktest(AnalysisInput input, BacktestConfig cfg) {
  final dates = input.dates;
  final nd = dates.length;

  // 第一輪：市場分數＋每天每檔的 RS 原始值
  final rsRawBy = <String, Float32List>{};
  final market = computeMarket(
    input,
    onSeries: (s, idx) {
      final arr = Float32List(nd)..fillRange(0, nd, double.nan);
      for (var i = 0; i < s.length; i++) {
        arr[idx[i]] = rsRaw(s, i);
      }
      rsRawBy[s.code] = arr;
    },
  );
  final mScore = [for (final m in market) m.score];

  // 每天的 RS 百分位
  final rsPct = {for (final c in rsRawBy.keys) c: Float32List(nd)..fillRange(0, nd, double.nan)};
  for (var d = 0; d < nd; d++) {
    final vals = <(String, double)>[];
    rsRawBy.forEach((c, a) {
      if (ok(a[d])) vals.add((c, a[d]));
    });
    if (vals.length < 2) continue;
    vals.sort((a, b) => a.$2.compareTo(b.$2));
    for (var k = 0; k < vals.length; k++) {
      rsPct[vals[k].$1]![d] = k / (vals.length - 1);
    }
  }

  // 第二輪：逐檔模擬（基本設定和壓力測試一起跑，指標只算一次）
  final dIdx = {for (var k = 0; k < nd; k++) dates[k]: k};
  final base = _Sim(), stress = _Sim();
  final stressCfg = cfg.stressed;
  for (final e in input.series.entries) {
    if (e.value.length < _warmup + 5) continue;
    final s = StockSeries(e.key, e.value);
    final idx = [for (final b in e.value) dIdx[b.date]!];
    final type = securityTypeOf(e.key);
    _simulate(s, idx, rsPct[e.key]!, mScore, cfg, type, base);
    _simulate(s, idx, rsPct[e.key]!, mScore, stressCfg, type, stress);
  }

  final trades = base.trades..sort((a, b) => a.exitDate.compareTo(b.exitDate));
  final byStrategy = <Strategy, BtStats>{
    for (final st in cfg.strategies) st: BtStats.of(trades.where((t) => t.strategy == st).toList()),
  };

  // 前段 70%／後段 30%（依日期切）
  final first = dates.length > _warmup
      ? dates[_warmup + ((nd - _warmup) * 0.7).floor().clamp(0, nd - _warmup - 1)]
      : null;
  final a = first == null ? <BtTrade>[] : trades.where((t) => t.entryDate.compareTo(first) < 0).toList();
  final b = first == null ? <BtTrade>[] : trades.where((t) => t.entryDate.compareTo(first) >= 0).toList();

  // Monte Carlo：打亂交易順序 1000 次，看最大回撤的分布
  final rs = [for (final t in trades) t.r];
  final dds = <double>[];
  final rnd = math.Random(42);
  for (var k = 0; k < (rs.isEmpty ? 0 : 1000); k++) {
    final x = [...rs]..shuffle(rnd);
    dds.add(maxDrawdown(x));
  }
  dds.sort();

  final equity = <(String, double)>[];
  var cum = 0.0;
  for (final t in trades) {
    cum += t.r;
    if (equity.isNotEmpty && equity.last.$1 == t.exitDate) {
      equity[equity.length - 1] = (t.exitDate, cum);
    } else {
      equity.add((t.exitDate, cum));
    }
  }

  return BacktestResult(
    config: cfg,
    trades: trades,
    overall: BtStats.of(trades),
    byStrategy: byStrategy,
    splitDate: first,
    firstPart: BtStats.of(a),
    secondPart: BtStats.of(b),
    stressed: BtStats.of(stress.trades),
    mcDdMedian: dds.isEmpty ? 0 : dds[dds.length ~/ 2],
    mcDd95: dds.isEmpty ? 0 : dds[(dds.length * 0.95).floor().clamp(0, dds.length - 1)],
    equity: equity,
    signals: base.signals,
    skippedChase: base.skippedChase,
    skippedGap: base.skippedGap,
    fromDate: nd > _warmup ? dates[_warmup] : null,
    toDate: nd == 0 ? null : dates.last,
  );
}

void _simulate(
  StockSeries s,
  List<int> idx,
  Float32List rsPct,
  List<double?> mScore,
  BacktestConfig cfg,
  SecurityType type,
  _Sim out,
) {
  final n = s.length;
  final slip = cfg.slippagePct / 100;
  final fee = 0.001425 * cfg.feeMultiplier;
  final tax = type == SecurityType.stock || type == SecurityType.preferred ? 0.003 : 0.001;
  var i = _warmup;
  while (i < n - 1 - cfg.entryDelay) {
    final d = idx[i];
    final ms = mScore[d];
    if (ms == null) {
      i++;
      continue;
    }
    final regime = regimeOf(ms);
    if (regime == Regime.bear || liquidityVeto(s, i) != null) {
      i++;
      continue;
    }
    final hits = detectAll(s, i).where((h) => cfg.strategies.contains(h.strategy)).toList();
    if (hits.isEmpty) {
      i++;
      continue;
    }
    final trend = trendModule(s, i).score ?? 0;
    final pct = rsPct[d];
    TradePlan? plan;
    for (final h in hits) {
      final st = h.strategy;
      if (st == Strategy.meanReversion && regime != Regime.range) continue;
      if (st.minRsPct > 0 && (!ok(pct) || pct < st.minRsPct)) continue;
      if (trend < st.minTrend) continue;
      final p = buildPlan(s, i, h, type);
      if (p.vetoes.isEmpty) {
        plan = p;
        break;
      }
    }
    if (plan == null) {
      i++;
      continue;
    }
    out.signals++;
    final eb = i + 1 + cfg.entryDelay;
    final open = s.open[eb];
    // §13 避免追價：開盤超過可接受價就取消；開盤就漲停也買不到
    final prevClose = s.close[eb - 1];
    if (open > plan.maxEntry || open >= prevClose * 1.095) {
      out.skippedChase++;
      i++;
      continue;
    }
    final entryPx = open * (1 + slip);
    final r0 = entryPx - plan.stop;
    // 開盤就跌到停損附近（剩不到一半的原始風險）：訊號已經失效，不進場。
    // 不這樣做的話，風險距離很小，一點點獲利就會變成誇張的 R 倍數。
    if (r0 < 0.5 * plan.risk) {
      out.skippedGap++;
      i++;
      continue;
    }

    var stop = plan.stop;
    var half = false, be = false;
    double? firstExit;
    double exitPx = 0;
    var exitJ = n - 1;
    var reason = '資料結束（未平倉，以最後收盤計）';
    var openAtEnd = true;
    for (var j = eb; j < n; j++) {
      final locked = s.isLimitDown(j) && s.high[j] == s.low[j]; // §14 跌停鎖死賣不掉
      if (!locked) {
        double? px;
        if (j > eb && s.open[j] <= stop) {
          px = s.open[j];
        } else if (s.low[j] <= stop) {
          px = stop;
        }
        if (px != null) {
          exitPx = px;
          exitJ = j;
          reason = half ? '移動停利' : (be ? '保本停損' : (px < stop ? '停損（跳空開低）' : '停損'));
          openAtEnd = false;
          break;
        }
      }
      if (!half && s.high[j] >= plan.target) {
        if (plan.strategy == Strategy.meanReversion) {
          exitPx = math.max(plan.target, s.open[j]);
          exitJ = j;
          reason = '到達目標（回到均值）';
          openAtEnd = false;
          break;
        }
        half = true;
        firstExit = math.max(plan.target, j > eb ? s.open[j] : plan.target);
        stop = math.max(stop, entryPx);
      }
      if (!be && s.close[j] >= entryPx + r0) {
        be = true;
        stop = math.max(stop, entryPx); // §12.2 Break-even
      }
      if (half && ok(s.atr[j])) {
        stop = math.max(stop, maxIn(s.high, math.max(eb, j - 21), j) - 3 * s.atr[j]); // Chandelier Exit
      }
      if (!half && j - eb + 1 >= cfg.timeStopDays && maxIn(s.close, eb, j) < entryPx + r0) {
        exitPx = s.close[j];
        exitJ = j;
        reason = '時間停損（${cfg.timeStopDays} 天沒有 +1R）';
        openAtEnd = false;
        break;
      }
      if (j == n - 1) exitPx = s.close[j];
    }

    double net(double px) => px * (1 - slip) * (1 - fee - tax);
    final proceeds = firstExit == null ? net(exitPx) : 0.5 * net(firstExit) + 0.5 * net(exitPx);
    final pnl = proceeds - entryPx * (1 + fee);
    out.trades.add(
      BtTrade(
        code: s.code,
        strategy: plan.strategy,
        signalDate: s.bars[i].date,
        entryDate: s.bars[eb].date,
        exitDate: s.bars[exitJ].date,
        entry: entryPx,
        stop: plan.stop,
        target: plan.target,
        exit: firstExit == null ? exitPx : (firstExit + exitPx) / 2,
        r: pnl / r0,
        retPct: pnl / entryPx * 100,
        days: exitJ - eb + 1,
        exitReason: firstExit == null ? reason : '2R 先出一半＋$reason',
        openAtEnd: openAtEnd,
      ),
    );
    i = exitJ + 1; // 同一檔不重複持有
  }
}
