/// 進場訊號（規格書 §9 多種進場模式）與交易計畫（§11、§12、§14）。
///
/// 推薦清單和回測都呼叫這裡同一組函式，所以「回測驗證的邏輯」就是「推薦
/// 用的邏輯」，不會出現兩套各說各話。
library;

import 'dart:math' as math;

import '../../data/stock_industry.dart';
import '../ta.dart';

enum Strategy { breakout, pullback, continuation, meanReversion }

extension StrategyInfo on Strategy {
  String get code => switch (this) {
    Strategy.breakout => 'A',
    Strategy.pullback => 'B',
    Strategy.continuation => 'C',
    Strategy.meanReversion => 'D',
  };

  String get label => switch (this) {
    Strategy.breakout => 'A 突破型',
    Strategy.pullback => 'B 回檔型',
    Strategy.continuation => 'C 趨勢延續型',
    Strategy.meanReversion => 'D 均值回歸型',
  };

  String get idea => switch (this) {
    Strategy.breakout => '趨勢向上的強勢股，經過一段整理後放量突破區間上緣。',
    Strategy.pullback => '強勢股正常回檔到 20／50 日均線附近、量縮、RSI 回落後重新轉強。',
    Strategy.continuation => '已經漲了一段，高檔形成平台（旗型）後再次突破。',
    Strategy.meanReversion => '只在震盪盤使用：超跌後停止破底、重新轉強，目標是回到均值（20 日線）。',
  };

  /// 相對強度（全市場百分位）門檻。
  double get minRsPct => switch (this) {
    Strategy.breakout => 0.70,
    Strategy.pullback => 0.70,
    Strategy.continuation => 0.80,
    Strategy.meanReversion => 0,
  };

  /// 趨勢分數門檻（D 不看趨勢）。
  double get minTrend => this == Strategy.meanReversion ? 0 : 60;

  /// 最低報酬風險比：規格書 §19 建議 2.0；均值回歸的目標是 20 日線，距離
  /// 天生較近，放寬到 1.5（畫面上會說明）。
  double get minRR => this == Strategy.meanReversion ? 1.5 : 2.0;
}

/// 同一檔股票同時符合多種訊號時的優先順序。
const kStrategyPriority = [Strategy.continuation, Strategy.breakout, Strategy.pullback, Strategy.meanReversion];

class SignalHit {
  final Strategy strategy;
  final String headline;
  final List<String> details;
  final double structuralStop;
  final String stopBasis;
  final double? meanTarget; // 只有 D 有
  const SignalHit(this.strategy, this.headline, this.details, this.structuralStop, this.stopBasis, {this.meanTarget});
}

String _f(double v) => v >= 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(2);
String _pc(double v) => '${v.toStringAsFixed(1)}%';

/// A 突破型：整理後放量突破 20 日高點。
SignalHit? detectBreakout(StockSeries s, int i) {
  if (i < 61) return null;
  final c = s.close[i], atr = s.atr[i], e50 = s.ema50[i];
  if (!ok(atr) || !ok(e50) || atr <= 0) return null;
  final hh20 = maxIn(s.high, i - 20, i - 1), ll20 = minIn(s.low, i - 20, i - 1);
  if (!(c > hh20)) return null;
  final depth = hh20 / ll20 - 1;
  if (depth > 0.25) return null;
  final avgV = s.avgVolBefore(i, 20);
  final vr = avgV > 0 ? s.vol[i] / avgV : 0.0;
  if (vr < 1.5) return null;
  if (!(c > e50 && e50 >= s.ema50[i - 10])) return null;
  if (ok(s.ema200[i]) && c <= s.ema200[i]) return null;
  final range = s.high[i] - s.low[i];
  if (range > 0 && (c - s.low[i]) / range < 0.5) return null;

  final details = <String>[
    '突破前 20 天在 ${_f(ll20)}～${_f(hh20)} 整理（區間振幅 ${_pc(depth * 100)}）',
    '今天收盤 ${_f(c)} 站上 20 日高點 ${_f(hh20)}，收在當天振幅上半部（突破有站穩）',
    '成交量 ${s.vol[i].round()} 張，是前 20 日均量的 ${vr.toStringAsFixed(1)} 倍（放量突破）',
    '收盤在 50 日均線之上且均線上揚${ok(s.ema200[i]) ? '，也在 200 日均線之上' : ''}',
  ];
  for (final w in [250, 120, 60]) {
    if (i > w && c > maxIn(s.high, i - w, i - 1)) {
      details.add('同時創 $w 日新高${w == 250 ? '（約 52 週新高）' : ''}');
      break;
    }
  }
  var compressed = false;
  for (var k = i - 5; k < i; k++) {
    final p = s.percentileOf(s.bbw, k, 120);
    if (ok(p) && p <= 0.25) compressed = true;
  }
  if (compressed) details.add('突破前布林帶寬處於近期低分位——波動壓縮後的突破，通常比較有延續性');

  final stop = hh20 - 0.5 * atr;
  return SignalHit(
    Strategy.breakout,
    '整理 20 天後放量 ${vr.toStringAsFixed(1)} 倍突破 20 日高點 ${_f(hh20)}',
    details,
    stop,
    '跌回突破點 ${_f(hh20)} 下方 0.5 ATR（代表突破失敗）',
  );
}

/// B 回檔型：強勢股回到 EMA20／50、量縮、RSI 回落後重新轉強。
SignalHit? detectPullback(StockSeries s, int i) {
  if (i < 66) return null;
  final c = s.close[i], atr = s.atr[i];
  final e20 = s.ema20[i], e50 = s.ema50[i];
  if (!ok(atr) || !ok(e20) || !ok(e50) || !ok(s.rsi[i]) || atr <= 0) return null;
  if (!(e20 > e50 && e50 > s.ema50[i - 10] && c > e50)) return null;
  // 強勢股：近 20 天內出現過 60 日最高收盤
  if (maxIn(s.close, i - 20, i) < maxIn(s.close, i - 60, i) * 0.99) return null;
  final peak = maxIn(s.high, i - 15, i - 1);
  final low5 = minIn(s.low, i - 5, i);
  if (peak - low5 < 1.5 * atr) return null;
  String? touched;
  for (var j = i - 5; j <= i; j++) {
    if (ok(s.ema20[j]) && s.low[j] <= s.ema20[j] + 0.3 * s.atr[j]) touched ??= '20 日線';
    if (ok(s.ema50[j]) && s.low[j] <= s.ema50[j] + 0.3 * s.atr[j]) touched = '50 日線';
  }
  if (touched == null) return null;
  final pbVol = avgIn(s.vol, i - 5, i - 1);
  final baseVol = s.avgVolBefore(i - 5, 20);
  if (!(baseVol > 0 && pbVol <= 0.85 * baseVol)) return null;
  final rsiMin = minIn(s.rsi, i - 6, i - 1);
  if (!(rsiMin >= 35 && rsiMin <= 52 && s.rsi[i] > 50)) return null;
  if (!(c > s.high[i - 1] && c > e20)) return null;

  return SignalHit(
    Strategy.pullback,
    '強勢股回檔到$touched、量縮後重新轉強（RSI ${rsiMin.toStringAsFixed(0)} → ${s.rsi[i].toStringAsFixed(0)}）',
    [
      '近 20 天內創過 60 日新高，是強勢股的正常回檔，不是趨勢反轉',
      '從高點 ${_f(peak)} 回檔到 ${_f(low5)}（${((peak - low5) / atr).toStringAsFixed(1)} ATR），低點碰到$touched',
      '回檔期間平均量 ${pbVol.round()} 張，只有之前均量的 ${(pbVol / baseVol * 100).toStringAsFixed(0)}%（量縮＝賣壓不大）',
      'RSI 回落到 ${rsiMin.toStringAsFixed(0)} 後站回 50 以上（${s.rsi[i].toStringAsFixed(0)}），今天收盤突破昨天高點',
      '20 日線 > 50 日線，且 50 日線仍在上揚',
    ],
    low5 - 0.2 * atr,
    '回檔低點 ${_f(low5)} 下方 0.2 ATR（跌破代表回檔變成轉弱）',
  );
}

/// C 趨勢延續型：已有一段漲勢，平台整理後再次突破。
SignalHit? detectContinuation(StockSeries s, int i) {
  if (i < 72) return null;
  final c = s.close[i], atr = s.atr[i], atrPrev = s.atr[i - 1];
  if (!ok(atr) || !ok(atrPrev) || !ok(s.ema50[i - 1]) || atr <= 0) return null;
  final leg = s.close[i - 10] / minIn(s.low, i - 70, i - 10) - 1;
  if (leg < 0.2) return null;
  final pHigh = maxIn(s.high, i - 10, i - 1), pLow = minIn(s.low, i - 10, i - 1);
  final tight = (pHigh - pLow) <= 3.5 * atrPrev || pHigh / pLow - 1 <= 0.12;
  if (!tight) return null;
  if (pLow < s.ema50[i - 1] * 0.99) return null;
  if (!(c > pHigh)) return null;
  final avgV = s.avgVolBefore(i, 20);
  final vr = avgV > 0 ? s.vol[i] / avgV : 0.0;
  if (vr < 1.3) return null;

  return SignalHit(
    Strategy.continuation,
    '前段已漲 ${_pc(leg * 100)}，高檔整理 10 天後再次突破平台 ${_f(pHigh)}',
    [
      '前段漲勢：從低點上漲 ${_pc(leg * 100)}，趨勢已經成形',
      '最近 10 天在 ${_f(pLow)}～${_f(pHigh)} 窄幅整理（旗型／平台），低點守在 50 日線之上',
      '今天收盤 ${_f(c)} 突破平台上緣，量是均量的 ${vr.toStringAsFixed(1)} 倍',
    ],
    pLow - 0.2 * atr,
    '平台低點 ${_f(pLow)} 下方 0.2 ATR（跌破代表平台失敗）',
  );
}

/// D 均值回歸型：超跌 → 停止破底 → 重新轉強，目標回到 20 日線。
SignalHit? detectMeanReversion(StockSeries s, int i) {
  if (i < 30) return null;
  final c = s.close[i], atr = s.atr[i], mid = s.sma20[i];
  if (!ok(atr) || !ok(mid) || atr <= 0) return null;
  var oversold = false;
  String why = '';
  final rsiMin = minIn(s.rsi, i - 8, i - 1);
  if (ok(rsiMin) && rsiMin <= 32) {
    oversold = true;
    why = 'RSI 最低到 ${rsiMin.toStringAsFixed(0)}';
  }
  for (var j = i - 8; j < i && !oversold; j++) {
    if (ok(s.sma20[j]) && ok(s.bbw[j]) && s.close[j] < s.sma20[j] * (1 - s.bbw[j] / 2)) {
      oversold = true;
      why = '收盤跌破布林下軌';
    }
  }
  if (!oversold) return null;
  final low10 = minIn(s.low, i - 9, i);
  if (minIn(s.low, i - 1, i) <= minIn(s.low, i - 9, i - 2)) return null; // 最近兩天還在破底
  if (!(c > s.high[i - 1] && c > s.open[i])) return null;
  if (ok(s.ema200[i]) && c < s.ema200[i] * 0.9) return null; // 長期空頭的股票不接
  if (mid <= c) return null; // 已經回到均值上方，沒有空間

  return SignalHit(
    Strategy.meanReversion,
    '超跌（$why）後止跌轉強，目標回到 20 日線 ${_f(mid)}',
    [
      '最近 8 天超跌：$why',
      '最近兩天沒有再破底（低點 ${_f(low10)} 守住），今天收紅且突破昨天高點——等到止跌、轉強才進場，不是「跌很多就買」',
      '目標是回到 20 日均線 ${_f(mid)}（均值），不期待趨勢反轉',
    ],
    low10 - 0.2 * atr,
    '近 10 日最低點 ${_f(low10)} 下方 0.2 ATR（再破底就認錯）',
    meanTarget: mid,
  );
}

List<SignalHit> detectAll(StockSeries s, int i) => [
  for (final f in [detectContinuation, detectBreakout, detectPullback, detectMeanReversion]) ?f(s, i),
];

// ───────── 台股 tick size（§14）─────────

double tickSize(double price, SecurityType t) {
  if (t == SecurityType.etf || t == SecurityType.etn) return price < 50 ? 0.01 : 0.05;
  if (price < 10) return 0.01;
  if (price < 50) return 0.05;
  if (price < 100) return 0.1;
  if (price < 500) return 0.5;
  if (price < 1000) return 1;
  return 5;
}

double roundDownTick(double p, SecurityType t) {
  final k = tickSize(p, t);
  return double.parse(((p / k + 1e-9).floor() * k).toStringAsFixed(2));
}

double roundUpTick(double p, SecurityType t) {
  final k = tickSize(p, t);
  return double.parse(((p / k - 1e-9).ceil() * k).toStringAsFixed(2));
}

// ───────── 交易計畫 ─────────

class TradePlan {
  final Strategy strategy;
  final double entry; // 參考進場價（今天收盤）
  final double maxEntry; // 可接受的最高買價（避免追價，§13）
  final double stop;
  final String stopBasis;
  final double target;
  final String targetBasis;
  final double? resistance; // 上方最近的前高壓力
  final double rr; // 報酬風險比
  final double atr;
  final double trailing; // 目前的移動停利參考（Chandelier：22 日最高 − 3 ATR）
  final int timeStopDays;
  final List<String> vetoes;

  const TradePlan({
    required this.strategy,
    required this.entry,
    required this.maxEntry,
    required this.stop,
    required this.stopBasis,
    required this.target,
    required this.targetBasis,
    required this.resistance,
    required this.rr,
    required this.atr,
    required this.trailing,
    required this.timeStopDays,
    required this.vetoes,
  });

  double get risk => entry - stop;
  double get riskPct => risk / entry * 100;
}

TradePlan buildPlan(StockSeries s, int i, SignalHit hit, SecurityType type) {
  final entry = s.close[i];
  final atr = s.atr[i];
  final vetoes = <String>[];
  var stop = hit.structuralStop;
  var stopBasis = hit.stopBasis;
  // 結構停損太近（不到 1 ATR）容易被正常波動洗掉，放寬到 1 ATR
  if (entry - stop < atr) {
    stop = entry - atr;
    stopBasis = '$stopBasis；距離不到 1 ATR，放寬到進場價 − 1 ATR';
  }
  stop = roundDownTick(stop, type);
  final risk = entry - stop;
  // §12.1 最大停損上限：合理技術停損過寬就不做
  if (risk > 3 * atr || risk / entry > 0.10) {
    vetoes.add(
      '合理停損 ${_f(stop)} 離進場價 ${(risk / atr).toStringAsFixed(1)} ATR／${_pc(risk / entry * 100)}，'
      '停損過寬（上限 3 ATR 或 10%），寧可不做',
    );
  }

  final double target;
  final String targetBasis;
  if (hit.meanTarget != null) {
    target = roundDownTick(hit.meanTarget!, type);
    targetBasis = '回到 20 日均線（均值），到了就全部出場';
  } else {
    target = roundUpTick(entry + 2 * risk, type);
    targetBasis = '2R（進場價 + 2 倍風險）：先出一半，剩下的用移動停利抱住';
  }

  // 上方壓力：過去一年（最多 250 天）的最高價，在進場價之上才算
  double? resistance;
  if (i >= 20) {
    final hh = maxIn(s.high, math.max(0, i - 250), i - 1);
    if (hh > entry * 1.005) resistance = hh;
  }
  final reachable = resistance == null ? target : math.min(target, resistance);
  final rr = risk > 0 ? (reachable - entry) / risk : 0.0;
  if (risk > 0 && rr < hit.strategy.minRR) {
    vetoes.add(
      resistance != null && resistance < target
          ? '上方 ${_f(resistance)} 有前高壓力，到壓力的報酬風險比只有 ${rr.toStringAsFixed(1)}（要求 ≥ ${hit.strategy.minRR}）'
          : '報酬風險比只有 ${rr.toStringAsFixed(1)}（要求 ≥ ${hit.strategy.minRR}）',
    );
  }

  final hh22 = maxIn(s.high, math.max(0, i - 21), i);
  return TradePlan(
    strategy: hit.strategy,
    entry: entry,
    maxEntry: roundDownTick(entry + 0.5 * atr, type),
    stop: stop,
    stopBasis: stopBasis,
    target: target,
    targetBasis: targetBasis,
    resistance: resistance,
    rr: rr,
    atr: atr,
    trailing: roundDownTick(hh22 - 3 * atr, type),
    timeStopDays: 10,
    vetoes: vetoes,
  );
}

/// 流動性否決（§4：流動性必須做成硬性 Veto）。
const kMinAvgValue = 3e7; // 20 日平均成交值 3,000 萬
const kMinAvgVolLots = 300.0;

String? liquidityVeto(StockSeries s, int i) {
  if (i < 20) return '歷史資料不到 20 天，無法判斷流動性';
  final v = s.avgValueBefore(i + 1, 20);
  final vol = s.avgVolBefore(i + 1, 20);
  if (v < kMinAvgValue || vol < kMinAvgVolLots) {
    return '流動性不足：20 日平均成交值 ${(v / 1e4).round()} 萬元／${vol.round()} 張'
        '（門檻 ${(kMinAvgValue / 1e4).round()} 萬元、${kMinAvgVolLots.round()} 張）';
  }
  return null;
}

/// 全市場相對強度的原始值：20／60／120／250 日報酬的加權（§7.2 RS Ranking）。
double rsRaw(StockSeries s, int i) {
  const ws = {20: 0.2, 60: 0.4, 120: 0.2, 250: 0.2};
  var sum = 0.0, w = 0.0;
  for (final e in ws.entries) {
    final r = s.roc(i, e.key);
    if (ok(r)) {
      sum += r * e.value;
      w += e.value;
    }
  }
  return w < 0.6 ? double.nan : sum / w;
}
