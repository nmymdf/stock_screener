/// 每日分析流程（規格書 §17 的第 3～7 步）：
/// 市場分數 → 產業分數 → 股票池與流動性否決 → 各模組分數 → 策略訊號與交易計畫
/// → 一票否決 → 依總分排序產生推薦清單。
///
/// 全部是純函式，吃的是本機存好的日 K，跑在背景 isolate，不卡畫面。
library;

import 'dart:math' as math;

import '../../data/stock_catalog.dart';
import '../../data/stock_industry.dart';
import '../../models/daily_bar.dart';
import '../ta.dart';
import 'industry_engine.dart';
import 'market_engine.dart';
import 'scoring.dart';
import 'signals.dart';

class AnalysisInput {
  final List<String> dates; // 有資料的交易日（舊 → 新）
  final Map<String, List<DailyBar>> series; // 已還原權息
  final Map<String, double> taiex;
  const AnalysisInput(this.dates, this.series, this.taiex);
}

class HitResult {
  final SignalHit hit;
  final TradePlan plan;
  final List<String> vetoes;
  const HitResult(this.hit, this.plan, this.vetoes);
  bool get passed => vetoes.isEmpty;
}

class StockReport {
  final String code;
  final String name;
  final String market; // 上市／上櫃
  final SecurityType type;
  final String? industry;
  final IndustryClass? industryClass;
  final double close;
  final double changePct;
  final int volumeLots;
  final double avgValue20;
  final double? rsPct;
  final int? rsRank;
  final List<ModuleScore> modules;
  final double total;
  final List<HitResult> hits;
  final List<String> vetoes; // 個股層級的一票否決
  final List<String> warnings;
  final List<String> positives;

  const StockReport({
    required this.code,
    required this.name,
    required this.market,
    required this.type,
    required this.industry,
    required this.industryClass,
    required this.close,
    required this.changePct,
    required this.volumeLots,
    required this.avgValue20,
    required this.rsPct,
    required this.rsRank,
    required this.modules,
    required this.total,
    required this.hits,
    required this.vetoes,
    required this.warnings,
    required this.positives,
  });

  HitResult? get primary {
    for (final h in hits) {
      if (h.passed) return h;
    }
    return null;
  }

  bool get recommended => vetoes.isEmpty && primary != null;

  /// 被否決時列出所有原因（個股層級＋每個訊號的）。
  List<String> get allVetoes => [
    ...vetoes,
    for (final h in hits)
      for (final v in h.vetoes) '${h.hit.strategy.code}：$v',
  ];

  ModuleScore module(String key) => modules.firstWhere((m) => m.key == key);
}

class Funnel {
  final int traded, liquid, withSignal, recommended;
  const Funnel(this.traded, this.liquid, this.withSignal, this.recommended);
}

class AnalysisResult {
  final String? latestDate;
  final int dayCount;
  final List<MarketDay> market;
  final List<IndustryReport> industries;
  final List<StockReport> stocks; // 今天有交易的全部股票
  final Funnel funnel;

  const AnalysisResult({
    required this.latestDate,
    required this.dayCount,
    required this.market,
    required this.industries,
    required this.stocks,
    required this.funnel,
  });

  static const empty = AnalysisResult(
    latestDate: null,
    dayCount: 0,
    market: [],
    industries: [],
    stocks: [],
    funnel: Funnel(0, 0, 0, 0),
  );

  MarketDay? get today => market.isEmpty ? null : market.last;

  List<StockReport> get recommendations {
    final r = stocks.where((s) => s.recommended).toList()..sort((a, b) => b.total.compareTo(a.total));
    return r;
  }

  /// 有訊號但被否決的（用來說明「為什麼沒推薦」）。
  List<StockReport> get rejected {
    final r = stocks.where((s) => s.hits.isNotEmpty && !s.recommended).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return r;
  }

  IndustryReport? industry(String? name) {
    if (name == null) return null;
    for (final i in industries) {
      if (i.name == name) return i;
    }
    return null;
  }

  StockReport? stock(String code) {
    for (final s in stocks) {
      if (s.code == code) return s;
    }
    return null;
  }
}

class _Partial {
  final String code;
  final SecurityType type;
  final int bars;
  final double close, changePct, avgValue20;
  final int volumeLots;
  final List<ModuleScore> tech;
  final List<(SignalHit, TradePlan)> hits;
  final String? liquidity;
  final List<String> warnings;
  final double rsRaw;
  final double roc20, roc60, roc120, roc250;
  const _Partial(
    this.code,
    this.type,
    this.bars,
    this.close,
    this.changePct,
    this.avgValue20,
    this.volumeLots,
    this.tech,
    this.hits,
    this.liquidity,
    this.warnings,
    this.rsRaw,
    this.roc20,
    this.roc60,
    this.roc120,
    this.roc250,
  );
}

/// 成交值前 [n] 名的一般股票（大型股），給市場廣度比較大型／中小型用。
Set<String> largeCaps(Map<String, List<DailyBar>> series, {int n = 150}) {
  final vals = <(String, double)>[];
  for (final e in series.entries) {
    if (securityTypeOf(e.key) != SecurityType.stock || e.value.isEmpty) continue;
    final bars = e.value;
    var v = 0.0;
    final from = math.max(0, bars.length - 20);
    for (var i = from; i < bars.length; i++) {
      v += bars[i].close * bars[i].volumeLots;
    }
    vals.add((e.key, v));
  }
  vals.sort((a, b) => b.$2.compareTo(a.$2));
  return {for (final x in vals.take(n)) x.$1};
}

/// 市場廣度（給分析和回測共用）。
List<MarketDay> computeMarket(AnalysisInput input, {void Function(StockSeries s, List<int> idx)? onSeries}) {
  final dIdx = {for (var k = 0; k < input.dates.length; k++) input.dates[k]: k};
  final large = largeCaps(input.series);
  final builder = BreadthBuilder(input.dates);
  for (final e in input.series.entries) {
    if (e.value.length < 2) continue;
    final s = StockSeries(e.key, e.value);
    final idx = [for (final b in e.value) dIdx[b.date]!];
    if (securityTypeOf(e.key) == SecurityType.stock) {
      builder.add(s, idx, large: large.contains(e.key), tpex: kBuiltinStocksByCode[e.key]?.market == '上櫃');
    }
    onSeries?.call(s, idx);
  }
  return scoreMarket(builder.build(input.taiex));
}

AnalysisResult runAnalysis(AnalysisInput input) {
  if (input.dates.isEmpty) return AnalysisResult.empty;
  final latest = input.dates.last;
  final partials = <_Partial>[];
  final indNow = <String, (String, IndustryInput)>{};
  final indPrev = <String, (String, IndustryInput)>{};

  final market = computeMarket(
    input,
    onSeries: (s, idx) {
      if (s.bars.last.date != latest) return; // 今天沒交易（停牌、下市）
      final i = s.length - 1;
      final code = s.code;
      final type = securityTypeOf(code);
      final industry = industryOf(code);
      if (industry != null) {
        final a = IndustryInput.at(s, i);
        if (a != null) indNow[code] = (industry, a);
        if (i >= 10) {
          final b = IndustryInput.at(s, i - 10);
          if (b != null) indPrev[code] = (industry, b);
        }
      }
      final tech = [
        trendModule(s, i),
        momentumModule(s, i),
        volumeModule(s, i),
        breakoutModule(s, i),
        volatilityModule(s, i),
      ];
      final hits = [for (final h in detectAll(s, i)) (h, buildPlan(s, i, h, type))];
      partials.add(
        _Partial(
          code,
          type,
          s.length,
          s.close[i],
          s.changePct(i),
          s.avgValueBefore(i + 1, math.min(20, i + 1)),
          s.bars[i].volumeLots,
          tech,
          hits,
          liquidityVeto(s, i),
          _warnings(s, i),
          rsRaw(s, i),
          s.roc(i, 20),
          s.roc(i, 60),
          s.roc(i, 120),
          s.roc(i, 250),
        ),
      );
    },
  );

  final today = market.last;
  final regime = today.regime;

  // RS 全市場排名
  final rsList = partials.where((p) => ok(p.rsRaw)).toList()..sort((a, b) => b.rsRaw.compareTo(a.rsRaw));
  final rsRank = <String, int>{};
  for (var k = 0; k < rsList.length; k++) {
    rsRank[rsList[k].code] = k + 1;
  }
  final rsTotal = rsList.length;

  final stockRoc20 = [
    for (final p in partials)
      if (p.type == SecurityType.stock && ok(p.roc20)) p.roc20,
  ]..sort();
  final medRoc20 = stockRoc20.isEmpty ? 0.0 : stockRoc20[stockRoc20.length ~/ 2];
  final industries = buildIndustries(indNow, indPrev, medRoc20);
  final indByName = {for (final r in industries) r.name: r};

  final stocks = <StockReport>[];
  var liquid = 0, withSignal = 0;
  for (final p in partials) {
    final rank = rsRank[p.code];
    final pct = rank == null || rsTotal < 2 ? null : 1 - (rank - 1) / (rsTotal - 1);
    final industry = industryOf(p.code);
    final ind = indByName[industry];
    final modules = [
      kFundamentalPending,
      kChipPending,
      p.tech[0], // 趨勢
      _rsModule(p, pct, rank, rsTotal),
      p.tech[1], // 動能
      p.tech[2], // 量價
      p.tech[3], // 突破
      p.tech[4], // 波動
      marketModule(today.score, regime?.label ?? '資料不足'),
      industryModule(industry, ind?.score, ind?.cls.label),
    ];
    final total = totalScore(modules);
    final trend = p.tech[0].score ?? 0;

    final vetoes = <String>[];
    if (p.liquidity != null) vetoes.add(p.liquidity!);
    if (p.bars < 60) vetoes.add('本機只有 ${p.bars} 天歷史資料（至少要 60 天才能判斷），先補抓更多資料');
    if (regime == Regime.bear) vetoes.add('市場處於「空頭／極端風險」（Market Score ${today.score!.toStringAsFixed(0)}），停止一般多單');
    final minTotal = regime?.minTotalScore ?? 60;
    if (regime != Regime.bear && total < minTotal) {
      vetoes.add('總分 ${total.toStringAsFixed(0)} 未達目前市場（${regime?.label ?? '—'}）的推薦門檻 ${minTotal.toStringAsFixed(0)}');
    }
    if (p.liquidity == null) liquid++;

    final hitResults = <HitResult>[];
    for (final (hit, plan) in p.hits) {
      final hv = [...plan.vetoes];
      final st = hit.strategy;
      if (st == Strategy.meanReversion && regime != Regime.range) {
        hv.add('均值回歸型只在「震盪」盤使用，目前市場是「${regime?.label ?? '資料不足'}」');
      }
      if (pct != null && pct < st.minRsPct) {
        hv.add('相對強度只排前 ${((1 - pct) * 100).toStringAsFixed(0)}%，${st.label}要求前 ${((1 - st.minRsPct) * 100).round()}%');
      } else if (pct == null && st.minRsPct > 0) {
        hv.add('資料不足，算不出相對強度排名');
      }
      if (trend < st.minTrend) hv.add('趨勢分數 ${trend.toStringAsFixed(0)} 低於 ${st.minTrend.round()}');
      hitResults.add(HitResult(hit, plan, hv));
    }
    if (hitResults.isNotEmpty) withSignal++;

    final warnings = [...p.warnings];
    if (ind != null && (ind.cls == IndustryClass.weakening || ind.cls == IndustryClass.lagging)) {
      warnings.add('所屬「$industry」產業目前${ind.cls.label}（產業分數 ${ind.score.toStringAsFixed(0)}）');
    }
    if (regime == Regime.range || regime == Regime.weak) {
      warnings.add('市場「${regime!.label}」，建議總曝險只有 ${regime.exposure}');
    }

    stocks.add(
      StockReport(
        code: p.code,
        name: kBuiltinStocksByCode[p.code]?.name ?? '',
        market: kBuiltinStocksByCode[p.code]?.market ?? '',
        type: p.type,
        industry: industry,
        industryClass: ind?.cls,
        close: p.close,
        changePct: p.changePct,
        volumeLots: p.volumeLots,
        avgValue20: p.avgValue20,
        rsPct: pct,
        rsRank: rank,
        modules: modules,
        total: total,
        hits: hitResults,
        vetoes: vetoes,
        warnings: warnings,
        positives: _positives(modules, pct, rank, rsTotal, industry, ind, today),
      ),
    );
  }
  final rec = stocks.where((s) => s.recommended).length;
  return AnalysisResult(
    latestDate: latest,
    dayCount: input.dates.length,
    market: market,
    industries: industries,
    stocks: stocks,
    funnel: Funnel(stocks.length, liquid, withSignal, rec),
  );
}

/// 相對強度（§7.2）：全市場 RS 排名的百分位。
ModuleScore _rsModule(_Partial p, double? pct, int? rank, int total) {
  final items = <ScoreItem>[
    if (pct != null)
      ScoreItem('全市場排名第 $rank／$total（前 ${((1 - pct) * 100).clamp(0.1, 100).toStringAsFixed(1)}%）', pct * 100, 100),
    for (final (n, r) in [(20, p.roc20), (60, p.roc60), (120, p.roc120), (250, p.roc250)])
      if (ok(r)) ScoreItem('$n 日報酬 ${r >= 0 ? '+' : ''}${r.toStringAsFixed(1)}%', 0, 0),
  ];
  return ModuleScore(
    'rs',
    '相對強度 RS',
    10,
    pct == null ? null : pct * 100,
    items,
    pct == null
        ? '資料不足'
        : pct >= 0.9
        ? '全市場前 10% 強勢股'
        : (pct >= 0.7 ? '前 30% 強勢' : '相對強度普通或偏弱'),
  );
}

List<String> _warnings(StockSeries s, int i) {
  final w = <String>[];
  final atr = s.atr[i];
  if (ok(atr) && atr > 0 && ok(s.ema20[i])) {
    final ext = (s.close[i] - s.ema20[i]) / atr;
    if (ext > 3) w.add('距 20 日線 ${ext.toStringAsFixed(1)} ATR，乖離過大，追價風險高（可等回檔）');
  }
  if (ok(s.rsi[i]) && s.rsi[i] > 80) w.add('RSI ${s.rsi[i].toStringAsFixed(0)} 過熱');
  if (s.isLimitUp(i)) w.add('今天收漲停：明天可能買不到或跳空開高，開盤超過「可接受最高買價」就不要追');
  if (i >= 20) {
    final avg = s.avgVolBefore(i, 20);
    if (avg > 0 && s.vol[i] / avg >= 3 && s.close[i] < s.open[i]) {
      w.add('爆量（${(s.vol[i] / avg).toStringAsFixed(1)} 倍）收黑，可能是高檔出貨');
    }
  }
  return w;
}

List<String> _positives(
  List<ModuleScore> modules,
  double? pct,
  int? rank,
  int total,
  String? industry,
  IndustryReport? ind,
  MarketDay today,
) {
  final out = <String>[];
  if (pct != null && pct >= 0.7) {
    out.add('相對強度全市場第 $rank 名（前 ${((1 - pct) * 100).clamp(0.1, 100).toStringAsFixed(1)}%），比大多數股票強');
  }
  if (ind != null && (ind.cls == IndustryClass.leading || ind.cls == IndustryClass.improving)) {
    out.add(
      '所屬「$industry」是${ind.cls.label}產業（產業分數 ${ind.score.toStringAsFixed(0)}'
      '${ind.delta == null ? '' : '，10 天內 ${ind.delta! >= 0 ? '+' : ''}${ind.delta!.toStringAsFixed(0)}'}）',
    );
  }
  for (final key in ['trend', 'volume', 'volatility']) {
    final m = modules.firstWhere((m) => m.key == key);
    if ((m.score ?? 0) >= 60) {
      final hits = m.items.where((x) => x.hit).map((x) => x.label).take(3).join('、');
      if (hits.isNotEmpty) out.add('${m.name} ${m.score!.toStringAsFixed(0)} 分：$hits');
    }
  }
  final r = today.regime;
  if (r == Regime.strongBull || r == Regime.bull) out.add('市場「${r!.label}」，環境支持做多');
  return out;
}
