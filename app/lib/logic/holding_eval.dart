/// 我的持股：每天收盤後判斷每一檔要「保留、注意、建議出場、停損」（規格書 §12）。
///
/// 做法是從買進那天開始，一天一天往後模擬規則：停損只會往上調、不會往下；
/// 漲到 +1R 拉到成本（保本）；短線到 2R 先賣一半、之後移動停利；
/// 波段 +1R 之後就用移動停利；長期看季線、年線。所以不管哪天打開 App，
/// 算出來的停損價都一樣，不會因為漏開幾天就亂掉。
///
/// 價格比較一律用「還原權息」的序列；顯示損益用實際成交價。
library;

import 'dart:math' as math;

import '../data/stock_industry.dart';
import '../models/daily_bar.dart';
import '../models/holding.dart';
import 'engine/industry_engine.dart';
import 'engine/market_engine.dart';
import 'ta.dart';

enum HoldState { hold, watch, exit, stopLoss, unknown }

extension HoldStateInfo on HoldState {
  String get label => switch (this) {
    HoldState.hold => '保留',
    HoldState.watch => '注意',
    HoldState.exit => '建議出場',
    HoldState.stopLoss => '停損',
    HoldState.unknown => '資料不足',
  };

  /// 排序用：越需要處理的越前面。
  int get urgency => switch (this) {
    HoldState.stopLoss => 0,
    HoldState.exit => 1,
    HoldState.watch => 2,
    HoldState.hold => 3,
    HoldState.unknown => 4,
  };
}

/// 證交所的交易成本：手續費 0.1425%（最低 20 元）、證交稅股票 0.3%、ETF 0.1%。
double buyFee(double amount) => amount <= 0 ? 0 : math.max(20, amount * 0.001425);
double sellCost(double amount, SecurityType t) => amount <= 0
    ? 0
    : math.max(20, amount * 0.001425) +
          amount * (t == SecurityType.stock || t == SecurityType.preferred ? 0.003 : 0.001);

class HoldingEval {
  final HoldState state;
  final String headline;
  final List<String> reasons;
  final List<String> notes;
  final String? asOf;
  final double? lastClose;
  final double? changePct;
  final double avgCost; // 實際成本（每股）
  final int shares;
  final double? marketValue;
  final double? unrealized; // 扣掉預估賣出成本
  final double? unrealizedPct;
  final double realized;
  final double? initialStop;
  final double? stop;
  final double? target;
  final double? risk; // 每股 1R
  final double? rNow;
  final double? distToStopPct;
  final String? triggerDate;
  final bool halfDone;
  final String? addOn; // 可以加碼的理由
  final List<double?> stopPath; // 跟 [pathDates] 對齊，畫圖用
  final List<String> pathDates;

  const HoldingEval({
    required this.state,
    required this.headline,
    this.reasons = const [],
    this.notes = const [],
    this.asOf,
    this.lastClose,
    this.changePct,
    required this.avgCost,
    required this.shares,
    this.marketValue,
    this.unrealized,
    this.unrealizedPct,
    this.realized = 0,
    this.initialStop,
    this.stop,
    this.target,
    this.risk,
    this.rNow,
    this.distToStopPct,
    this.triggerDate,
    this.halfDone = false,
    this.addOn,
    this.stopPath = const [],
    this.pathDates = const [],
  });
}

/// 已實現損益：每次賣出以當時的平均成本計算，扣手續費和證交稅。
double realizedPnl(Holding h, SecurityType type) {
  final cost = h.avgCost;
  final bought = h.boughtShares;
  final totalBuyFee = h.buys.fold(0.0, (a, b) => a + buyFee(b.price * b.shares));
  var sum = 0.0;
  for (final s in h.sells) {
    final amt = s.price * s.shares;
    final feeShare = bought == 0 ? 0 : totalBuyFee * s.shares / bought;
    sum += amt - sellCost(amt, type) - cost * s.shares - feeShare;
  }
  return sum;
}

String _f(double v) => v >= 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(2);
String _p(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

HoldingEval evaluateHolding(
  Holding h, {
  required List<DailyBar> adjusted,
  required List<DailyBar> raw,
  Regime? regime,
  String? industry,
  IndustryClass? industryClass,
  String? newSignal, // 今天通過否決的新訊號名稱（用來判斷可不可以加碼）
}) {
  final type = securityTypeOf(h.code);
  final realized = realizedPnl(h, type);
  final shares = h.shares;
  final cost = h.avgCost;
  if (h.buys.isEmpty) {
    return HoldingEval(state: HoldState.unknown, headline: '沒有買進紀錄', avgCost: 0, shares: 0, realized: realized);
  }
  if (adjusted.isEmpty) {
    return HoldingEval(
      state: HoldState.unknown,
      headline: '本機沒有這檔的行情資料',
      notes: const ['先到「工具 → 資料管理」抓歷史資料'],
      avgCost: cost,
      shares: shares,
      realized: realized,
    );
  }

  final s = StockSeries(h.code, adjusted);
  final n = s.length;
  final buyDate = h.firstBuyDate;
  var e = adjusted.indexWhere((b) => b.date.compareTo(buyDate) >= 0);
  final notes = <String>[];
  // 今天才買、收盤資料還沒進來：先用最新一天的資料算出起始停損和目標，
  // 收盤資料更新後才開始逐日判斷。
  final pending = e < 0;
  if (pending) e = n - 1;
  if (adjusted.first.date.compareTo(buyDate) > 0) {
    notes.add('買進日 $buyDate 早於本機資料的第一天（${adjusted.first.date}），從那天開始計算');
  }

  // 還原權息因子：買進那天「還原價 ÷ 實際價」。之後有除權息，成本跟著等比例下修，
  // 停損才不會被除息的假跌幅觸發。
  final rawEntry = raw.firstWhere((b) => b.date == adjusted[e].date, orElse: () => adjusted[e]);
  final f = rawEntry.close == 0 ? 1.0 : adjusted[e].close / rawEntry.close;
  final c = cost * f; // 還原後成本
  if ((f - 1).abs() > 0.001) notes.add('買進後有除權息，比較停損時成本以還原後的 ${_f(c)} 計算');

  double atrAt(int i) {
    for (var k = i; k < n; k++) {
      if (ok(s.atr[k])) return s.atr[k];
    }
    for (var k = i; k >= 0; k--) {
      if (ok(s.atr[k])) return s.atr[k];
    }
    return c * 0.03;
  }

  final atrE = atrAt(e);
  double stop0;
  double? target;
  String stopBasis;
  switch (h.style) {
    case HoldStyle.short:
      stop0 = h.planStop != null ? h.planStop! * f : c - 2 * atrE;
      stopBasis = h.planStop != null ? '推薦時的停損' : '進場價 − 2 ATR';
    case HoldStyle.swing:
      stop0 = h.planStop != null ? h.planStop! * f : c - 2.5 * atrE;
      stopBasis = h.planStop != null ? '推薦時的停損' : '進場價 − 2.5 ATR';
    case HoldStyle.long:
      stop0 = c * 0.85;
      stopBasis = '虧損 15%';
    case HoldStyle.custom:
      stop0 = h.manualStop ?? c * 0.92;
      stopBasis = h.manualStop != null ? '你設定的停損' : '沒有設定停損，先用虧損 8%';
      target = h.manualTarget;
  }
  if (h.style != HoldStyle.custom && h.manualStop != null && h.manualStop! > stop0) {
    stop0 = h.manualStop!;
    stopBasis = '你調高的停損';
  }
  var risk = c - stop0;
  if (risk <= 0) {
    risk = 2 * atrE;
    stop0 = c - risk;
    stopBasis = '$stopBasis（設定在成本之上不合理，改用進場價 − 2 ATR）';
  }
  if (h.style == HoldStyle.short) target = h.planTarget != null ? h.planTarget! * f : c + 2 * risk;

  var stop = stop0;
  var breakeven = false;
  String? targetHitDate;
  String? triggerDate;
  HoldState? triggered;
  String? triggerReason;
  var maxHigh = 0.0;
  var maxClose = 0.0;
  final path = <double?>[];
  final pathDates = <String>[];
  var below60 = 0;

  for (var j = e; j < n && !pending; j++) {
    final close = s.close[j];
    // 1. 收盤跌破「前一天為止」的停損
    if (close < stop) {
      triggerDate = s.bars[j].date;
      final inLoss = stop < c * 0.999;
      triggered = inLoss ? HoldState.stopLoss : HoldState.exit;
      triggerReason = inLoss
          ? '$triggerDate 收盤 ${_f(close)} 跌破停損 ${_f(stop)}'
          : (breakeven && (targetHitDate != null || h.style == HoldStyle.swing) && stop > c * 1.001
                ? '$triggerDate 收盤 ${_f(close)} 跌破移動停利 ${_f(stop)}，獲利了結'
                : '$triggerDate 收盤 ${_f(close)} 跌破保本停損 ${_f(stop)}');
      path.add(stop);
      pathDates.add(s.bars[j].date);
      break;
    }
    maxHigh = math.max(maxHigh, s.high[j]);
    maxClose = math.max(maxClose, close);

    // 2. 目標價
    if (target != null && targetHitDate == null && s.high[j] >= target) {
      targetHitDate = s.bars[j].date;
      if (h.style == HoldStyle.custom) {
        triggerDate = targetHitDate;
        triggered = HoldState.exit;
        triggerReason = '$targetHitDate 最高 ${_f(s.high[j])} 碰到你設定的目標價 ${_f(target)}，可以獲利了結';
        path.add(stop);
        pathDates.add(s.bars[j].date);
        break;
      }
    }

    // 3. 長期：收盤連續 3 天在季線之下、季線往下彎
    if (h.style == HoldStyle.long && ok(s.sma60[j])) {
      below60 = close < s.sma60[j] ? below60 + 1 : 0;
      final falling = j >= 5 && ok(s.sma60[j - 5]) && s.sma60[j] < s.sma60[j - 5];
      if (below60 >= 3 && falling) {
        triggerDate = s.bars[j].date;
        triggered = close < c ? HoldState.stopLoss : HoldState.exit;
        triggerReason = '$triggerDate 收盤已連續 3 天在季線（${_f(s.sma60[j])}）之下，而且季線往下彎，長期趨勢轉弱';
        path.add(stop);
        pathDates.add(s.bars[j].date);
        break;
      }
    }

    // 4. 短線時間停損：10 個交易日還沒有 +1R
    if (h.style == HoldStyle.short && targetHitDate == null && j - e + 1 >= 10 && maxClose < c + risk) {
      triggerDate = s.bars[j].date;
      triggered = HoldState.exit;
      triggerReason = '買進後 ${j - e + 1} 個交易日還沒漲到 +1R（${_f(c + risk)}），表現不如預期（時間停損）';
      path.add(stop);
      pathDates.add(s.bars[j].date);
      break;
    }

    // 5. 收盤後更新停損（只會往上）
    if (h.style == HoldStyle.short || h.style == HoldStyle.swing) {
      if (close >= c + risk) {
        breakeven = true;
        stop = math.max(stop, c);
      }
      final trailingOn = h.style == HoldStyle.short ? targetHitDate != null : breakeven;
      if (trailingOn) stop = math.max(stop, maxHigh - 3 * atrAt(j));
    }
    path.add(stop);
    pathDates.add(s.bars[j].date);
  }

  final last = s.bars[n - 1];
  final lastClose = last.close; // 還原序列最新一天 = 實際價
  final rawLast = raw.isEmpty ? lastClose : raw.last.close;
  final value = rawLast * shares;
  final costBasis =
      cost * shares +
      h.buys.fold(0.0, (a, b) => a + buyFee(b.price * b.shares)) * (h.boughtShares == 0 ? 0 : shares / h.boughtShares);
  final unrealized = shares > 0 ? value - sellCost(value, type) - costBasis : 0.0;
  final rNow = (lastClose - c) / risk;
  final dist = (lastClose - stop) / lastClose * 100;
  final changePct = n >= 2 && s.close[n - 2] != 0 ? (lastClose / s.close[n - 2] - 1) * 100 : null;

  final halfDone = targetHitDate != null && h.lastSellDate != null && h.lastSellDate!.compareTo(targetHitDate) >= 0;
  final reasons = <String>[];
  HoldState state;
  String headline;

  if (pending) {
    state = HoldState.unknown;
    headline = '買進日 $buyDate 之後還沒有收盤資料，收盤資料進來後開始每天判斷';
    reasons.add('先照規則訂好起始停損 ${_f(stop0)}${target != null ? '、目標 ${_f(target)}' : ''}');
  } else if (triggered != null) {
    state = triggered;
    headline = triggerReason!;
    final soldAfter = h.lastSellDate != null && h.lastSellDate!.compareTo(triggerDate!) >= 0;
    reasons.add(soldAfter ? '你已經在 ${h.lastSellDate} 記錄賣出部分持股，剩下的也建議處理' : '還沒有記錄賣出——依規則應該出場');
    if (state == HoldState.stopLoss) reasons.add('停損是為了讓單筆損失維持在可控範圍，不要因為「已經跌很多」而改成攤平或凹單');
  } else if (h.style == HoldStyle.short && targetHitDate != null && !halfDone) {
    state = HoldState.exit;
    headline = '$targetHitDate 漲到目標 ${_f(target!)}（2R），建議先賣一半';
    reasons.add('剩下的一半繼續抱，用移動停利 ${_f(stop)}（最高價 − 3 ATR）保護獲利');
  } else {
    final watch = <String>[];
    final atr = atrAt(n - 1);
    if (lastClose - stop < math.max(0.5 * atr, lastClose * 0.02)) {
      watch.add('收盤 ${_f(lastClose)} 離停損 ${_f(stop)} 只剩 ${dist.toStringAsFixed(1)}%');
    }
    if (regime == Regime.bear || regime == Regime.weak) {
      watch.add('市場處於「${regime!.label}」，建議降低整體持股（總曝險 ${regime.exposure}）');
    }
    if (industryClass == IndustryClass.weakening || industryClass == IndustryClass.lagging) {
      watch.add('所屬「$industry」產業目前${industryClass!.label}');
    }
    if (ok(s.rsi[n - 1]) && s.rsi[n - 1] > 80) watch.add('RSI ${s.rsi[n - 1].toStringAsFixed(0)} 過熱，短線可能拉回');
    if (h.style == HoldStyle.long) {
      if (ok(s.sma60[n - 1]) && lastClose < s.sma60[n - 1]) watch.add('收盤在季線（${_f(s.sma60[n - 1])}）之下 $below60 天');
      if (ok(s.sma240[n - 1]) && lastClose < s.sma240[n - 1]) watch.add('收盤跌破年線（${_f(s.sma240[n - 1])}）');
    }
    if (watch.isNotEmpty) {
      state = HoldState.watch;
      headline = watch.first;
      reasons.addAll(watch.skip(1));
    } else {
      state = HoldState.hold;
      headline =
          '續抱：目前 ${_p((lastClose / c - 1) * 100)}（${rNow >= 0 ? '+' : ''}${rNow.toStringAsFixed(1)}R），'
          '停損 ${_f(stop)}（距離 ${dist.toStringAsFixed(1)}%）';
    }
    if (breakeven) reasons.add('已經漲到 +1R，停損已拉到成本以上——這筆最差也是打平');
    if (halfDone) reasons.add('已在目標價附近賣出一半，剩下用移動停利 ${_f(stop)} 抱住');
  }

  String? addOn;
  if ((state == HoldState.hold || state == HoldState.watch) && newSignal != null && rNow >= 1 && shares > 0) {
    addOn = '今天出現「$newSignal」訊號，而且這檔已經賺 ${rNow.toStringAsFixed(1)}R——符合「只加贏家」，可以考慮加碼';
  }

  notes.insert(0, '停損起點：${_f(stop0)}（$stopBasis）；1R = 每股 ${_f(risk)}');

  return HoldingEval(
    state: state,
    headline: headline,
    reasons: reasons,
    notes: notes,
    asOf: last.date,
    lastClose: rawLast,
    changePct: changePct,
    avgCost: cost,
    shares: shares,
    marketValue: value,
    unrealized: unrealized,
    unrealizedPct: costBasis == 0 ? null : unrealized / costBasis * 100,
    realized: realized,
    initialStop: stop0,
    stop: stop,
    target: target,
    risk: risk,
    rNow: rNow,
    distToStopPct: dist,
    triggerDate: triggerDate,
    halfDone: halfDone,
    addOn: addOn,
    stopPath: path,
    pathDates: pathDates,
  );
}

/// 加碼前檢查（規格書 §12.3：只加贏家、禁止向下攤平）。回傳警告文字，沒問題回傳 null。
String? averageDownWarning(Holding h, double price, {double? lastClose}) {
  if (h.shares <= 0) return null;
  final cost = h.avgCost;
  final losing = lastClose != null && lastClose < cost;
  if (price < cost || losing) {
    final pct = ((lastClose ?? price) / cost - 1) * 100;
    return '這檔目前${losing ? '虧損 ${pct.toStringAsFixed(1)}%' : '的加碼價 ${_f(price)} 低於平均成本 ${_f(cost)}'}。'
        '規則是「只加贏家、禁止向下攤平」：虧損時加碼會讓單筆風險變大，一旦繼續下跌損失會加倍。';
  }
  return null;
}

class TradeRecordStats {
  final int closed, wins;
  final double realized, avgWin, avgLoss;
  const TradeRecordStats(this.closed, this.wins, this.realized, this.avgWin, this.avgLoss);
  double get winRate => closed == 0 ? 0 : wins / closed;
}

/// 已經全部賣出的持股，算成你自己的交易績效。
TradeRecordStats tradeStats(List<Holding> holdings) {
  var closed = 0, wins = 0;
  var total = 0.0, sumW = 0.0, sumL = 0.0;
  for (final h in holdings) {
    final r = realizedPnl(h, securityTypeOf(h.code));
    total += r;
    if (!h.closed) continue;
    closed++;
    if (r > 0) {
      wins++;
      sumW += r;
    } else {
      sumL += r;
    }
  }
  return TradeRecordStats(
    closed,
    wins,
    total,
    wins == 0 ? 0 : sumW / wins,
    closed - wins == 0 ? 0 : sumL / (closed - wins),
  );
}
