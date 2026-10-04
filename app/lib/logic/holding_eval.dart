/// 我的持股：每天收盤後判斷每一檔要「續抱、注意、加碼、先賣一半、出場、停損」，
/// 並且從買進那天起，每個交易日留下一筆紀錄（規格書 §12、最終版 §14、§15）。
///
/// 做法是從買進那天開始，一天一天往後模擬規則：停損只會往上調、不會往下；
/// 漲到 +1R 拉到成本（保本）；短線到 2R 先賣一半、之後移動停利；
/// 波段 +1R 之後就用移動停利；長期看季線、年線。所以不管哪天打開 App，
/// 算出來的停損價和每日紀錄都一樣，不會因為漏開幾天就亂掉。
///
/// 每天另外檢查「買進理由還成立嗎」（健康度）、持有週期有沒有升級或降級——
/// 讓你在跌破停損之前就先知道。
///
/// 價格比較一律用「還原權息」的序列；顯示價格和損益用實際成交價。
library;

import 'dart:math' as math;

import '../data/stock_industry.dart';
import '../models/daily_bar.dart';
import '../models/holding.dart';
import 'engine/horizon.dart';
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

/// 每天的「持續建議」。
enum DailyAction { stopLoss, exit, overdue, sellHalf, addOn, caution, hold, pending, closed }

extension DailyActionInfo on DailyAction {
  String get label => switch (this) {
    DailyAction.stopLoss => '停損出場',
    DailyAction.exit => '出場',
    DailyAction.overdue => '應已出場・未處理',
    DailyAction.sellHalf => '先賣一半',
    DailyAction.addOn => '可以加碼',
    DailyAction.caution => '續抱但注意',
    DailyAction.hold => '續抱',
    DailyAction.pending => '等收盤資料',
    DailyAction.closed => '已結案',
  };

  bool get needsAction =>
      this == DailyAction.stopLoss ||
      this == DailyAction.exit ||
      this == DailyAction.overdue ||
      this == DailyAction.sellHalf;
}

/// 每天建議的文字：長期持有用「健康／觀察／轉弱／考慮減碼」，其他用短中線的說法。
String actionText(DailyAction a, HoldStyle style) {
  if (style != HoldStyle.long) return a.label;
  return switch (a) {
    DailyAction.hold => '健康',
    DailyAction.caution => '觀察',
    DailyAction.exit => '轉弱',
    DailyAction.sellHalf || DailyAction.stopLoss || DailyAction.overdue => '考慮減碼',
    _ => a.label,
  };
}

/// 證交所的交易成本：手續費 0.1425%（最低 20 元）、證交稅股票 0.3%、ETF 0.1%。
double buyFee(double amount) => amount <= 0 ? 0 : math.max(20, amount * 0.001425);

/// 這筆買進的手續費：有實際數字（stock_acc）用實際的，沒有就用費率估算。
double lotBuyFee(BuyLot b) => b.fee ?? buyFee(b.price * b.shares);

/// 這筆賣出的手續費＋證交稅。
double lotSellCost(SellLot s, SecurityType t) =>
    s.fee != null || s.tax != null ? (s.fee ?? 0) + (s.tax ?? 0) : sellCost(s.price * s.shares, t);

double sellCost(double amount, SecurityType t) => amount <= 0
    ? 0
    : math.max(20, amount * 0.001425) +
          amount * (t == SecurityType.stock || t == SecurityType.preferred ? 0.003 : 0.001);

/// 買進理由的一項檢查。
class ThesisCheck {
  final String key;
  final String label;
  final bool ok;
  final String detail;
  final double weight;
  const ThesisCheck(this.key, this.label, this.ok, this.detail, this.weight);
}

/// 每日追蹤紀錄的一筆。
class DayRecord {
  final String date;
  final double close; // 實際價
  final double? changePct;
  final int shares;
  final double pnlPct; // 相對成本（含除權息還原）
  final double r;
  final double stop; // 實際價
  final double? prevStop;
  final DailyAction action;
  final String reason;
  final List<String> events;
  final int health;
  final int duration;
  final int okCount, checkCount;

  const DayRecord({
    required this.date,
    required this.close,
    required this.changePct,
    required this.shares,
    required this.pnlPct,
    required this.r,
    required this.stop,
    required this.prevStop,
    required this.action,
    required this.reason,
    required this.events,
    required this.health,
    required this.duration,
    required this.okCount,
    required this.checkCount,
  });

  bool get stopRaised => prevStop != null && stop > prevStop! + 1e-9;
}

class ScenarioLine {
  final String when;
  final String action;
  final DailyAction kind;
  const ScenarioLine(this.when, this.action, this.kind);
}

enum AddOnStatus { done, ready, waiting, blocked }

class AddOnLevel {
  final String title;
  final double? price;
  final String condition;
  final AddOnStatus status;
  const AddOnLevel(this.title, this.price, this.condition, this.status);
}

/// 出場訊號 vs 你實際的處理（紀律）。
enum DisciplineStatus { onTime, late, pending, early }

class DisciplineEvent {
  final String signalDate;
  final String signal;
  final DisciplineStatus status;
  final String? actionDate;
  final int? delayDays;
  final double? delayCost; // 正數＝因為晚處理多賠（或少賺）的金額
  const DisciplineEvent(this.signalDate, this.signal, this.status, {this.actionDate, this.delayDays, this.delayCost});
}

class HoldingSummary {
  final int days;
  final double maxGainPct, maxLossPct, drawdownFromPeakPct;
  final int stopRaises, upgrades, downgrades;
  final int healthAtEntry, healthNow;
  final int durationAtEntry, durationNow;
  final List<String> lines;
  const HoldingSummary({
    required this.days,
    required this.maxGainPct,
    required this.maxLossPct,
    required this.drawdownFromPeakPct,
    required this.stopRaises,
    required this.upgrades,
    required this.downgrades,
    required this.healthAtEntry,
    required this.healthNow,
    required this.durationAtEntry,
    required this.durationNow,
    required this.lines,
  });
}

class HoldingEval {
  final HoldState state;
  final DailyAction action;
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
  final String? addOn; // 今天可以加碼的理由
  final List<double?> stopPath; // 跟 [pathDates] 對齊，畫圖用
  final List<String> pathDates;

  // 每日追蹤
  final List<DayRecord> log;
  final List<ThesisCheck> thesisNow;
  final List<ThesisCheck> thesisAtEntry;
  final int? health;
  final int? durationNow;
  final String? durationWhy;
  final List<ScenarioLine> scenario;
  final List<AddOnLevel> addOnPlan;
  final List<String> addOnRules;
  final HoldingSummary? summary;
  final List<DisciplineEvent> discipline;
  final String? styleAdvice; // 持有週期跟持有方式不一致時的建議

  /// 在現價之下、碰到就會改變建議的價位（給持股頁「要盯的價位」只列很接近的）。
  final List<WatchLevel> watchLevels;

  const HoldingEval({
    required this.state,
    this.action = DailyAction.pending,
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
    this.log = const [],
    this.thesisNow = const [],
    this.thesisAtEntry = const [],
    this.health,
    this.durationNow,
    this.durationWhy,
    this.scenario = const [],
    this.addOnPlan = const [],
    this.addOnRules = const [],
    this.summary,
    this.discipline = const [],
    this.styleAdvice,
    this.watchLevels = const [],
  });

  /// 現價離最近的關鍵價位還有多少（%）；沒有就回傳 null。
  WatchLevel? get nearestLevel {
    if (lastClose == null || watchLevels.isEmpty) return null;
    final l = [...watchLevels]..sort((a, b) => b.price.compareTo(a.price));
    return l.first;
  }

  double? get distToLevelPct {
    final l = nearestLevel;
    return l == null || lastClose == null ? null : (lastClose! - l.price) / lastClose! * 100;
  }
}

class WatchLevel {
  final double price;
  final String what;
  final DailyAction kind;
  const WatchLevel(this.price, this.what, this.kind);
}

/// 已實現損益：每次賣出以當時的平均成本計算，扣手續費和證交稅。
double realizedPnl(Holding h, SecurityType type) {
  final cost = h.avgCost;
  final bought = h.boughtShares;
  final totalBuyFee = h.buys.fold(0.0, (a, b) => a + lotBuyFee(b));
  var sum = 0.0;
  for (final s in h.sells) {
    final amt = s.price * s.shares;
    final feeShare = bought == 0 ? 0 : totalBuyFee * s.shares / bought;
    sum += amt - lotSellCost(s, type) - cost * s.shares - feeShare;
  }
  return sum;
}

String _f(double v) => v >= 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(2);
String _p(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';
String _r(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}R';

/// 每天檢查「買進理由還成立嗎」：價格結構、趨勢、相對大盤強弱、量價、動能、市場、離停損的緩衝。
List<ThesisCheck> thesisChecks(
  StockSeries s,
  int j,
  HoldStyle style, {
  required double stop,
  Regime? regime,
  double? rel20,
  double? rel60,
  PvReading? pv,
}) {
  final c = s.close[j];
  final out = <ThesisCheck>[];
  final long = style == HoldStyle.long;
  if (long && ok(s.sma60[j])) {
    out.add(ThesisCheck('structure', '守住季線', c > s.sma60[j], '收盤 ${_f(c)}／季線 ${_f(s.sma60[j])}', 20));
  } else if (ok(s.ema20[j])) {
    out.add(ThesisCheck('structure', '守住 20 日線', c > s.ema20[j], '收盤 ${_f(c)}／20 日線 ${_f(s.ema20[j])}', 20));
  }
  if (long && ok(s.sma240[j])) {
    out.add(ThesisCheck('trend', '長期趨勢向上', c > s.sma240[j], '收盤在年線 ${_f(s.sma240[j])} 之上', 20));
  } else if (ok(s.ema20[j]) && ok(s.ema50[j]) && j >= 10 && ok(s.ema50[j - 10])) {
    final okT = s.ema20[j] > s.ema50[j] && s.ema50[j] > s.ema50[j - 10];
    out.add(ThesisCheck('trend', '趨勢向上', okT, '20 日線 > 50 日線，且 50 日線上揚', 20));
  }
  final useRel = long || style == HoldStyle.swing ? rel60 : rel20;
  final n = long || style == HoldStyle.swing ? 60 : 20;
  if (useRel != null) {
    out.add(
      ThesisCheck(
        'rs',
        '贏過大盤',
        useRel > 0,
        '$n 日報酬比加權指數${useRel >= 0 ? '多' : '少'} ${useRel.abs().toStringAsFixed(1)}%',
        15,
      ),
    );
  } else if (ok(s.roc(j, n))) {
    out.add(ThesisCheck('rs', '$n 日報酬為正', s.roc(j, n) > 0, '$n 日報酬 ${_p(s.roc(j, n))}（沒有大盤資料）', 15));
  }
  final reading = pv ?? priceVolume(s, j);
  out.add(
    ThesisCheck(
      'pv',
      '量價沒有出貨跡象',
      !reading.state.bad && reading.persistence >= 40,
      '${reading.state.label}：${reading.detail}',
      15,
    ),
  );
  if (ok(s.rsi[j])) {
    final th = long ? 45 : 50;
    out.add(ThesisCheck('momentum', '動能還在', s.rsi[j] >= th, 'RSI ${s.rsi[j].toStringAsFixed(0)}（≥ $th）', 10));
  }
  if (regime != null) {
    final okM = regime != Regime.weak && regime != Regime.bear;
    out.add(ThesisCheck('market', '市場不是弱勢', okM, '市場「${regime.label}」', 10));
  }
  final atr = ok(s.atr[j]) ? s.atr[j] : c * 0.02;
  out.add(
    ThesisCheck('buffer', '離停損還有緩衝', c - stop >= atr, '離停損 ${((c - stop) / atr).toStringAsFixed(1)} ATR（≥ 1 ATR）', 10),
  );
  return out;
}

int healthOf(List<ThesisCheck> checks) {
  final w = checks.fold(0.0, (a, b) => a + b.weight);
  if (w == 0) return 50;
  return (checks.where((c) => c.ok).fold(0.0, (a, b) => a + b.weight) / w * 100).round();
}

HoldingEval evaluateHolding(
  Holding h, {
  required List<DailyBar> adjusted,
  required List<DailyBar> raw,
  Regime? regime,
  String? industry,
  IndustryClass? industryClass,
  String? newSignal, // 今天通過否決的新訊號名稱（用來判斷可不可以加碼）
  Map<String, Regime>? regimeByDate,
  Map<String, double>? taiex,
  double drawdownLimit = 0.25, // 長期：從持有期間高點回落多少算「考慮減碼」
}) {
  final type = securityTypeOf(h.code);
  final longMode = h.style == HoldStyle.long;
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
  // 已經持有一段時間才加進來追蹤：從追蹤起點那天才開始用規則判斷，不倒推過去的走勢。
  final buyIdx = e;
  var takeover = false;
  if (!pending && h.takenOver) {
    final k = adjusted.lastIndexWhere((b) => b.date.compareTo(h.trackSince!) <= 0);
    if (k > e) {
      e = k;
      takeover = true;
      notes.add('接手追蹤：從 ${adjusted[e].date} 開始判斷（之前的走勢不算），損益仍以實際成本計算');
    }
  }
  // 全部賣掉的持股，紀錄只到最後一次賣出那天。
  var end = n - 1;
  if (h.closed && h.lastSellDate != null) {
    final k = adjusted.lastIndexWhere((b) => b.date.compareTo(h.lastSellDate!) <= 0);
    if (k >= e) end = k;
  }

  final rawByDate = {for (final b in raw) b.date: b};
  double factorAt(int j) {
    final r = rawByDate[adjusted[j].date];
    return r == null || r.close == 0 ? 1.0 : adjusted[j].close / r.close;
  }

  // 還原權息因子：買進那天「還原價 ÷ 實際價」。之後有除權息，成本跟著等比例下修，
  // 停損才不會被除息的假跌幅觸發。
  final f = factorAt(buyIdx);
  final c = cost * f; // 還原後成本
  // 規則的基準價：一般是成本；接手追蹤時是開始追蹤那天的收盤（停損、R 都從這裡算）
  final ref = takeover ? s.close[e] : c;
  final from = takeover ? '接手當天收盤' : '進場價';
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
  final usePlan = h.planStop != null && !takeover;
  switch (h.style) {
    case HoldStyle.short:
      stop0 = usePlan ? h.planStop! * f : ref - 2 * atrE;
      stopBasis = usePlan ? '推薦時的停損' : '$from − 2 ATR';
    case HoldStyle.swing:
      stop0 = usePlan ? h.planStop! * f : ref - 2.5 * atrE;
      stopBasis = usePlan ? '推薦時的停損' : '$from − 2.5 ATR';
    case HoldStyle.long:
      stop0 = s.close[e] * (1 - drawdownLimit);
      stopBasis = '持有期間最高收盤回落 ${(drawdownLimit * 100).round()}%（會隨新高往上調）';
    case HoldStyle.custom:
      stop0 = h.manualStop ?? ref * 0.92;
      stopBasis = h.manualStop != null ? '你設定的停損' : '沒有設定停損，先用$from − 8%';
      target = h.manualTarget;
  }
  if (h.style != HoldStyle.custom && h.manualStop != null && h.manualStop! > stop0) {
    stop0 = h.manualStop!;
    stopBasis = '你調高的停損';
  }
  var risk = ref - stop0;
  if (risk <= 0) {
    risk = 2 * atrE;
    stop0 = ref - risk;
    stopBasis = '$stopBasis（設定在$from之上不合理，改用$from − 2 ATR）';
  }
  if (h.style == HoldStyle.short) target = h.planTarget != null && !takeover ? h.planTarget! * f : ref + 2 * risk;

  double? relAt(int j, int k) {
    if (taiex == null || j - k < 0) return null;
    final a = taiex[s.bars[j].date], b = taiex[s.bars[j - k].date];
    final r = s.roc(j, k);
    if (a == null || b == null || b == 0 || !ok(r)) return null;
    return r - (a / b - 1) * 100;
  }

  final noAdd = h.strategy == 'D';
  var stop = stop0;
  var breakeven = false;
  String? targetHitDate;
  String? triggerDate;
  var triggerIdx = -1;
  HoldState? triggered;
  String? triggerReason;
  var maxHigh = 0.0;
  var maxClose = 0.0;
  var minClose = double.infinity;
  final path = <double?>[];
  final pathDates = <String>[];
  var below60 = 0;
  final log = <DayRecord>[];
  List<ThesisCheck> checksNow = const [];
  List<ThesisCheck> checksEntry = const [];
  var durConfirmed = h.duration ?? 0;
  var durCandidate = 0, durStreak = 0;
  var durWhy = '';
  var upgrades = 0, downgrades = 0;
  var lowHealthDays = 0;
  String? reduceSince;
  var lastAddIdx = -100;
  var addsDone = 0;
  Regime? prevRegime;
  var prevHealth = -1;
  var stopRaises = 0;
  var belowY = 0;
  var belowYFalling = false;
  String? prevLongLabel;

  for (var j = e; j <= end && !pending; j++) {
    final close = s.close[j];
    final date = s.bars[j].date;
    final fj = factorAt(j);
    final stopBefore = stop;
    final events = <String>[];
    final rDay = (close - ref) / risk;
    final dayRegime = regimeByDate?[date] ?? (j == n - 1 ? regime : null);
    final sharesDay = h.sharesAt(date);
    for (final b in h.buys) {
      if (b.date == date) events.add('你記錄買進 ${_f(b.price)} × ${b.shares} 股');
    }
    for (final x in h.sells) {
      if (x.date == date) events.add('你記錄賣出 ${_f(x.price)} × ${x.shares} 股${x.reason == null ? '' : '（${x.reason}）'}');
    }
    if (j > e && h.buys.any((b) => b.date == date)) {
      addsDone = h.buys.where((b) => b.date.compareTo(date) <= 0).length - 1;
      lastAddIdx = j;
    }

    var justTriggered = false;
    // 長期：年線（不夠一年資料就退而用 200 日線、半年線、季線）
    double yv = double.nan;
    var yName = '年線';
    for (final (nm, v, back) in [
      ('年線', s.sma240, 20),
      ('200 日線', s.ema200, 20),
      ('半年線', s.sma120, 10),
      ('季線', s.sma60, 5),
    ]) {
      if (ok(v[j])) {
        yv = v[j];
        yName = nm;
        if (j >= back && ok(v[j - back])) belowYFalling = v[j] < v[j - back];
        break;
      }
    }
    if (longMode) {
      if (close > maxClose * 1.01 && j > e + 2) events.add('創持有期間新高（收盤 ${_f(close / fj)}）');
      maxHigh = math.max(maxHigh, s.high[j]);
      maxClose = math.max(maxClose, close);
      stop = math.max(stop, maxClose * (1 - drawdownLimit));
      belowY = ok(yv) && close < yv ? belowY + 1 : 0;
      if (belowY == 1) events.add('收盤跌破$yName ${_f(yv / fj)}');
      path.add(stop);
      pathDates.add(date);
    }
    if (!longMode && triggered == null) {
      // 1. 收盤跌破「前一天為止」的停損
      if (close < stop) {
        triggerDate = date;
        final inLoss = stop < c * 0.999;
        triggered = inLoss ? HoldState.stopLoss : HoldState.exit;
        triggerReason = inLoss
            ? '$triggerDate 收盤 ${_f(close)} 跌破停損 ${_f(stop)}'
            : (breakeven && (targetHitDate != null || h.style == HoldStyle.swing) && stop > c * 1.001
                  ? '$triggerDate 收盤 ${_f(close)} 跌破移動停利 ${_f(stop)}，獲利了結'
                  : '$triggerDate 收盤 ${_f(close)} 跌破保本停損 ${_f(stop)}');
        justTriggered = true;
      }
      if (triggered == null) {
        maxHigh = math.max(maxHigh, s.high[j]);
        if (close > maxClose * 1.01 && j > e + 2) events.add('創買進後新高（收盤 ${_f(close / fj)}）');
        maxClose = math.max(maxClose, close);

        // 2. 目標價
        if (target != null && targetHitDate == null && s.high[j] >= target) {
          targetHitDate = date;
          events.add('最高 ${_f(s.high[j] / fj)} 碰到目標 ${_f(target / fj)}');
          if (h.style == HoldStyle.custom) {
            triggerDate = targetHitDate;
            triggered = HoldState.exit;
            triggerReason = '$targetHitDate 最高 ${_f(s.high[j])} 碰到你設定的目標價 ${_f(target)}，可以獲利了結';
            justTriggered = true;
          }
        }
      }

      // 3. 長期：收盤連續 3 天在季線之下、季線往下彎
      if (triggered == null && h.style == HoldStyle.long && ok(s.sma60[j])) {
        below60 = close < s.sma60[j] ? below60 + 1 : 0;
        final falling = j >= 5 && ok(s.sma60[j - 5]) && s.sma60[j] < s.sma60[j - 5];
        if (below60 >= 3 && falling) {
          triggerDate = date;
          triggered = close < c ? HoldState.stopLoss : HoldState.exit;
          triggerReason = '$triggerDate 收盤已連續 3 天在季線（${_f(s.sma60[j])}）之下，而且季線往下彎，長期趨勢轉弱';
          justTriggered = true;
        }
      }

      // 4. 短線時間停損：10 個交易日還沒有 +1R
      if (triggered == null &&
          h.style == HoldStyle.short &&
          targetHitDate == null &&
          j - e + 1 >= 10 &&
          maxClose < ref + risk) {
        triggerDate = date;
        triggered = HoldState.exit;
        triggerReason = '${takeover ? '開始追蹤' : '買進'}後 ${j - e + 1} 個交易日還沒漲到 +1R（${_f(ref + risk)}），表現不如預期（時間停損）';
        justTriggered = true;
      }

      // 5. 收盤後更新停損（只會往上）
      if (triggered == null && (h.style == HoldStyle.short || h.style == HoldStyle.swing)) {
        if (close >= ref + risk) {
          if (!breakeven) {
            events.add(
              takeover
                  ? '漲到 +1R（${_f((ref + risk) / fj)}），停損拉到接手當天的價位 ${_f(ref / fj)}'
                  : '漲到 +1R（${_f((ref + risk) / fj)}），停損拉到成本——這筆最差也是打平',
            );
          }
          breakeven = true;
          stop = math.max(stop, ref);
        }
        final trailingOn = h.style == HoldStyle.short ? targetHitDate != null : breakeven;
        if (trailingOn) stop = math.max(stop, maxHigh - 3 * atrAt(j));
      }
      path.add(stop);
      pathDates.add(date);
      if (justTriggered) {
        triggerIdx = j;
        events.add(triggerReason!);
      }
    }
    minClose = math.min(minClose, close);
    if (!longMode && stop > stopBefore + 1e-9) {
      stopRaises++;
      if (!events.any((x) => x.contains('停損拉到成本'))) {
        events.add('停損上調 ${_f(stopBefore / fj)} → ${_f(stop / fj)}（移動停利：最高價 − 3 ATR）');
      }
    }
    for (var m = 2; m <= 5; m++) {
      if (!longMode && rDay >= m && (j == e || (s.close[j - 1] - ref) / risk < m)) events.add('獲利達到 +${m}R');
    }

    // 每日檢查：買進理由、量價、持有週期、市場
    final pv = priceVolume(s, j);
    final rel20 = relAt(j, 20), rel60 = relAt(j, 60);
    final checks = thesisChecks(s, j, h.style, stop: stop, regime: dayRegime, rel20: rel20, rel60: rel60, pv: pv);
    final health = healthOf(checks);
    if (j == e) checksEntry = checks;
    checksNow = checks;
    if (prevHealth >= 0 && prevHealth - health >= 20) events.add('健康度 $prevHealth → $health（買進理由有幾項失效）');
    prevHealth = health;
    if (ok(s.ema20[j]) && j > e && ok(s.ema20[j - 1])) {
      if (close < s.ema20[j] && s.close[j - 1] >= s.ema20[j - 1]) events.add('收盤跌破 20 日線 ${_f(s.ema20[j] / fj)}');
      if (close > s.ema20[j] && s.close[j - 1] <= s.ema20[j - 1]) events.add('重新站上 20 日線 ${_f(s.ema20[j] / fj)}');
    }
    if (ok(s.ema50[j]) && j > e && ok(s.ema50[j - 1]) && close < s.ema50[j] && s.close[j - 1] >= s.ema50[j - 1]) {
      events.add('收盤跌破 50 日線 ${_f(s.ema50[j] / fj)}（中期結構轉弱）');
    }
    if (pv.state == PvState.distribution || pv.state == PvState.churn || pv.state == PvState.breakout) {
      events.add('量價「${pv.state.label}」：${pv.detail}');
    }
    if (dayRegime != null && prevRegime != null && dayRegime != prevRegime) {
      events.add('市場由「${prevRegime.label}」轉為「${dayRegime.label}」');
    }
    prevRegime = dayRegime ?? prevRegime;

    final (cand, why) = stockOnlyDuration(s, j, regime: dayRegime, rel20: rel20, rel60: rel60);
    if (durConfirmed == 0) {
      durConfirmed = cand;
      durWhy = why;
    } else if (cand != durConfirmed) {
      durStreak = cand == durCandidate ? durStreak + 1 : 1;
      durCandidate = cand;
      if (durStreak >= 2) {
        if (cand > durConfirmed) {
          // 升級只在已經獲利 +1R 以上時才算數（虧損的短線不能改成長抱）
          if (rDay >= 1) {
            events.add('持有週期升級 D$durConfirmed → D$cand：$why');
            upgrades++;
            durConfirmed = cand;
            durWhy = why;
          }
        } else {
          events.add('持有週期降級 D$durConfirmed → D$cand：$why');
          downgrades++;
          durConfirmed = cand;
          durWhy = why;
        }
        durStreak = 0;
      }
    } else {
      durStreak = 0;
      durWhy = why;
    }

    // 今天的持續建議
    final isLast = j == end;
    final halfByNow =
        targetHitDate != null &&
        h.sells.any((x) => x.date.compareTo(targetHitDate!) >= 0 && x.date.compareTo(date) <= 0);
    lowHealthDays = health < 40 ? lowHealthDays + 1 : 0;
    if (lowHealthDays == 2 && reduceSince == null) reduceSince = date;
    if (health >= 55) reduceSince = null;
    final reducedAfterWarn =
        reduceSince != null && h.sells.any((x) => x.date.compareTo(reduceSince!) >= 0 && x.date.compareTo(date) <= 0);

    DailyAction action;
    String reason;
    final atr = atrAt(j);
    if (sharesDay <= 0 && j > e) {
      action = DailyAction.closed;
      reason = '已全部賣出';
    } else if (longMode) {
      final dd = maxClose <= 0 ? 0.0 : 1 - close / maxClose;
      final watch = <String>[];
      if (ok(yv) && close < yv) {
        watch.add('收盤在$yName ${_f(yv / fj)} 之下（第 $belowY 天）${belowYFalling ? '，$yName往下彎' : ''}');
      }
      if (dd >= drawdownLimit * 0.5) watch.add('從持有期間高點 ${_f(maxClose / fj)} 回落 ${(dd * 100).toStringAsFixed(1)}%');
      if (health < 60) watch.add('健康度 $health：${checks.where((x) => !x.ok).map((x) => x.label).join('、')} 不成立');
      if (dayRegime == Regime.bear || dayRegime == Regime.weak) watch.add('市場處於「${dayRegime!.label}」');
      if (isLast && (industryClass == IndustryClass.weakening || industryClass == IndustryClass.lagging)) {
        watch.add('所屬「$industry」產業目前${industryClass!.label}');
      }
      if (pv.state == PvState.distribution) watch.add('量價「下跌放量」：${pv.detail}');
      if (dd >= drawdownLimit) {
        action = DailyAction.sellHalf;
        reason =
            '從持有期間高點 ${_f(maxClose / fj)} 回落 ${(dd * 100).toStringAsFixed(1)}%，超過你設定的 ${(drawdownLimit * 100).round()}%：'
            '考慮減碼，或重新確認長期持有的理由';
      } else if (belowY >= 3 && belowYFalling) {
        action = DailyAction.exit;
        reason = '收盤連續 $belowY 天在$yName ${_f(yv / fj)} 之下，而且$yName往下彎：長期趨勢轉弱';
      } else if (watch.isNotEmpty) {
        action = DailyAction.caution;
        reason = watch.join('；');
      } else {
        action = DailyAction.hold;
        reason =
            '健康：${_p((close / c - 1) * 100)}，${ok(yv) ? '在$yName ${_f(yv / fj)} 之上 ${((close / yv - 1) * 100).toStringAsFixed(1)}%，' : ''}'
            '離持有期間高點 −${(dd * 100).toStringAsFixed(1)}%，買進理由 ${checks.where((x) => x.ok).length}／${checks.length} 項成立';
      }
      if (newSignal != null && isLast && action == DailyAction.hold && close > c && health >= 70 && !noAdd) {
        action = DailyAction.addOn;
        reason = '今天出現「$newSignal」訊號，這檔健康、而且是賺錢的——長期持有可以考慮分批加碼（比上一次少）';
      }
      final label = actionText(action, HoldStyle.long);
      if (prevLongLabel != null && label != prevLongLabel) events.add('狀態：$prevLongLabel → $label');
      prevLongLabel = label;
    } else if (triggered != null && j > triggerIdx) {
      action = DailyAction.overdue;
      reason = '依規則應該在 $triggerDate 出場，已經第 ${j - triggerIdx} 個交易日沒有處理（$triggerReason）';
    } else if (triggered != null) {
      action = triggered == HoldState.stopLoss ? DailyAction.stopLoss : DailyAction.exit;
      reason = triggerReason!;
    } else if (h.style == HoldStyle.short && targetHitDate != null && !halfByNow) {
      action = DailyAction.sellHalf;
      reason = '$targetHitDate 漲到目標 ${_f(target! / fj)}（2R），先賣一半，剩下用移動停利 ${_f(stop / fj)} 抱住';
    } else if (reduceSince != null && !reducedAfterWarn) {
      action = DailyAction.sellHalf;
      final broken = checks.where((x) => !x.ok).map((x) => x.label).join('、');
      reason = '買進理由大多已經失效（健康度 $health：$broken 不成立），股價還沒跌破停損前先減碼一半，剩下用停損 ${_f(stop / fj)} 保護';
    } else {
      final watch = <String>[];
      if (close - stop < math.max(0.5 * atr, close * 0.02)) {
        watch.add('收盤 ${_f(close / fj)} 離停損 ${_f(stop / fj)} 只剩 ${((close - stop) / close * 100).toStringAsFixed(1)}%');
      }
      if (dayRegime == Regime.bear || dayRegime == Regime.weak) {
        watch.add('市場處於「${dayRegime!.label}」，建議降低整體持股（總曝險 ${dayRegime.exposure}）');
      }
      if (isLast && (industryClass == IndustryClass.weakening || industryClass == IndustryClass.lagging)) {
        watch.add('所屬「$industry」產業目前${industryClass!.label}');
      }
      if (ok(s.rsi[j]) && s.rsi[j] > 80) watch.add('RSI ${s.rsi[j].toStringAsFixed(0)} 過熱，短線可能拉回');
      if (h.style == HoldStyle.long) {
        if (ok(s.sma60[j]) && close < s.sma60[j]) watch.add('收盤在季線（${_f(s.sma60[j] / fj)}）之下 $below60 天');
        if (ok(s.sma240[j]) && close < s.sma240[j]) watch.add('收盤跌破年線（${_f(s.sma240[j] / fj)}）');
      }
      if (pv.state.bad) watch.add('量價「${pv.state.label}」：${pv.detail}');
      if (health < 60) {
        watch.add('健康度 $health：${checks.where((x) => !x.ok).map((x) => x.label).join('、')} 不成立');
      }
      final styleD = h.style.durationClass;
      if (styleD != null && durConfirmed < styleD) {
        watch.add('持有週期降到 D$durConfirmed（${kDurationRange[durConfirmed]}），比${h.style.label}的預期短：提高停利敏感度');
      }
      final canAdd =
          !noAdd &&
          sharesDay > 0 &&
          rDay >= 1 &&
          health >= 70 &&
          !pv.state.bad &&
          addsDone < 3 &&
          j - lastAddIdx >= 5 &&
          watch.isEmpty;
      final breakoutAdd =
          canAdd &&
          j >= 11 &&
          close > maxIn(s.high, j - 10, j - 1) &&
          (pv.state == PvState.breakout || pv.state == PvState.healthyUp);
      final signalAdd = canAdd && isLast && newSignal != null;
      if (watch.isNotEmpty) {
        action = DailyAction.caution;
        reason = watch.join('；');
      } else if (breakoutAdd || signalAdd) {
        action = DailyAction.addOn;
        lastAddIdx = j;
        reason = signalAdd
            ? '今天出現「$newSignal」訊號，這筆已經 ${_r(rDay)}、健康度 $health——符合「只加贏家」，可以加碼（比上一次少）'
            : '已經 ${_r(rDay)}、整理後再創 10 日新高（${pv.state.label}），健康度 $health——符合「只加贏家」，可以加碼（比上一次少）';
      } else {
        action = DailyAction.hold;
        reason =
            '續抱：目前 ${_p((close / c - 1) * 100)}（${_r(rDay)}），停損 ${_f(stop / fj)}'
            '（距離 ${((close - stop) / close * 100).toStringAsFixed(1)}%），'
            '買進理由 ${checks.where((x) => x.ok).length}／${checks.length} 項仍成立';
      }
    }

    log.add(
      DayRecord(
        date: date,
        close: close / fj,
        changePct: j > 0 && s.close[j - 1] != 0 ? (close / s.close[j - 1] - 1) * 100 : null,
        shares: sharesDay,
        pnlPct: (close / c - 1) * 100,
        r: rDay,
        stop: stop / fj,
        prevStop: j == e ? null : stopBefore / fj,
        action: action,
        reason: reason,
        events: events,
        health: health,
        duration: durConfirmed,
        okCount: checks.where((x) => x.ok).length,
        checkCount: checks.length,
      ),
    );
  }

  final last = s.bars[n - 1];
  final lastClose = last.close; // 還原序列最新一天 = 實際價
  final rawLast = raw.isEmpty ? lastClose : raw.last.close;
  final value = rawLast * shares;
  final costBasis =
      cost * shares +
      h.buys.fold(0.0, (a, b) => a + lotBuyFee(b)) * (h.boughtShares == 0 ? 0 : shares / h.boughtShares);
  final unrealized = shares > 0 ? value - sellCost(value, type) - costBasis : 0.0;
  final rNow = (lastClose - c) / risk;
  final dist = (lastClose - stop) / lastClose * 100;
  final changePct = n >= 2 && s.close[n - 2] != 0 ? (lastClose / s.close[n - 2] - 1) * 100 : null;

  final halfDone = targetHitDate != null && h.lastSellDate != null && h.lastSellDate!.compareTo(targetHitDate) >= 0;
  final reasons = <String>[];
  HoldState state;
  DailyAction action;
  String headline;
  final today = log.isEmpty ? null : log.last;

  if (pending) {
    state = HoldState.unknown;
    action = DailyAction.pending;
    headline = '買進日 $buyDate 之後還沒有收盤資料，收盤資料進來後開始每天判斷';
    reasons.add('先照規則訂好起始停損 ${_f(stop0)}${target != null ? '、目標 ${_f(target)}' : ''}');
  } else if (h.closed) {
    state = triggered ?? HoldState.hold;
    action = DailyAction.closed;
    headline = '已全部賣出（${h.firstBuyDate} → ${h.lastSellDate}）';
  } else if (triggered != null) {
    state = triggered;
    action = today?.action ?? DailyAction.exit;
    headline = triggerReason!;
    final soldAfter = h.lastSellDate != null && h.lastSellDate!.compareTo(triggerDate!) >= 0;
    reasons.add(soldAfter ? '你已經在 ${h.lastSellDate} 記錄賣出部分持股，剩下的也建議處理' : '還沒有記錄賣出——依規則應該出場');
    if (action == DailyAction.overdue) reasons.add('已經第 ${(n - 1) - triggerIdx} 個交易日沒有處理');
    if (state == HoldState.stopLoss) reasons.add('停損是為了讓單筆損失維持在可控範圍，不要因為「已經跌很多」而改成攤平或凹單');
  } else {
    action = today?.action ?? DailyAction.hold;
    headline = today?.reason ?? '續抱';
    state = switch (action) {
      DailyAction.sellHalf || DailyAction.exit => HoldState.exit,
      DailyAction.caution => HoldState.watch,
      _ => HoldState.hold,
    };
    if (action == DailyAction.caution) {
      final parts = headline.split('；');
      headline = parts.first;
      reasons.addAll(parts.skip(1));
    }
    if (action == DailyAction.sellHalf && h.style == HoldStyle.short && targetHitDate != null && !halfDone) {
      headline = '$targetHitDate 漲到目標 ${_f(target!)}（2R），建議先賣一半';
      reasons.add('剩下的一半繼續抱，用移動停利 ${_f(stop)}（最高價 − 3 ATR）保護獲利');
    }
    if (breakeven) reasons.add('已經漲到 +1R，停損已拉到成本以上——這筆最差也是打平');
    if (halfDone) reasons.add('已在目標價附近賣出一半，剩下用移動停利 ${_f(stop)} 抱住');
  }

  String? addOn;
  if (action == DailyAction.addOn) addOn = today!.reason;
  if (addOn == null &&
      (state == HoldState.hold || state == HoldState.watch) &&
      newSignal != null &&
      rNow >= 1 &&
      shares > 0 &&
      !noAdd) {
    addOn = '今天出現「$newSignal」訊號，而且這檔已經賺 ${rNow.toStringAsFixed(1)}R——符合「只加贏家」，可以考慮加碼';
  }

  notes.insert(
    0,
    longMode
        ? '防守價：${_f(stop)}（$stopBasis）'
        : '停損起點：${_f(stop0 / factorAt(e))}（$stopBasis）；1R = 每股 ${_f(risk / factorAt(e))}',
  );

  // 明日劇本、加碼時機
  final scenario = <ScenarioLine>[];
  final addPlan = <AddOnLevel>[];
  final addRules = <String>[];
  String? styleAdvice;
  final levels = <WatchLevel>[];
  if (!pending && !h.closed && shares > 0) {
    if (longMode) {
      final i = n - 1;
      double yv = double.nan;
      var yName = '年線';
      for (final (nm, v) in [('年線', s.sma240), ('200 日線', s.ema200), ('半年線', s.sma120), ('季線', s.sma60)]) {
        if (ok(v[i])) {
          yv = v[i];
          yName = nm;
          break;
        }
      }
      final guard = maxClose * (1 - drawdownLimit);
      if (ok(yv) && yv < lastClose) levels.add(WatchLevel(yv, '跌破$yName → 觀察', DailyAction.caution));
      levels.add(WatchLevel(guard, '回落 ${(drawdownLimit * 100).round()}% → 考慮減碼', DailyAction.sellHalf));
      if (ok(yv) && yv < lastClose) {
        scenario.add(
          ScenarioLine('收盤 < ${_f(yv)}（$yName）', '觀察：跌破$yName；連續 3 天而且$yName往下彎就是「轉弱」', DailyAction.caution),
        );
      } else if (ok(yv)) {
        scenario.add(ScenarioLine('收盤 ≥ ${_f(yv)}（$yName）', '守在$yName之上，長期趨勢沒有轉弱', DailyAction.hold));
      }
      scenario.add(
        ScenarioLine(
          '收盤 < ${_f(guard)}',
          '考慮減碼：從持有期間高點 ${_f(maxClose)} 回落超過 ${(drawdownLimit * 100).round()}%',
          DailyAction.sellHalf,
        ),
      );
      addRules.addAll([
        '長期持有的加碼：只在「健康」狀態、而且這筆是賺錢的時候，分批、每次比上一次少。',
        if (ok(yv)) '比較好的加碼位置：回到$yName（${_f(yv)}）附近不破、再轉強；或是創持有期間新高（${_f(maxClose)}）之後。',
        '虧損中不加碼（禁止向下攤平）。',
      ]);
    } else {
      final atr = atrAt(n - 1);
      final e20 = s.ema20[n - 1];
      final addPrice = math.max(ref + risk, maxHigh);
      if (triggered != null) {
        scenario.add(
          ScenarioLine(
            '明天開盤',
            '依規則應該出場：$triggerReason',
            triggered == HoldState.stopLoss ? DailyAction.stopLoss : DailyAction.exit,
          ),
        );
      } else {
        final inLoss = stop < c * 0.999;
        levels.add(
          WatchLevel(
            stop,
            inLoss ? '跌破停損 → 停損出場' : (stop > c * 1.001 ? '跌破移動停利 → 出場' : '跌破保本 → 出場'),
            inLoss ? DailyAction.stopLoss : DailyAction.exit,
          ),
        );
        scenario.add(
          ScenarioLine(
            '收盤 < ${_f(stop)}',
            inLoss ? '停損出場（不攤平、不凹單）' : (stop > c * 1.001 ? '移動停利出場，獲利了結' : '保本出場'),
            inLoss ? DailyAction.stopLoss : DailyAction.exit,
          ),
        );
        var warn = stop + 0.5 * atr;
        if (ok(e20) && e20 > warn && e20 < lastClose) warn = e20;
        final low = math.min(warn, lastClose);
        if (warn < lastClose) {
          scenario.add(ScenarioLine('${_f(stop)} ～ ${_f(warn)}', '警戒區：不加碼，準備出場', DailyAction.caution));
        }
        final canAddLater = !noAdd && rNow >= 0;
        scenario.add(
          ScenarioLine(canAddLater ? '${_f(low)} ～ ${_f(addPrice)}' : '收盤 ≥ ${_f(low)}', '續抱', DailyAction.hold),
        );
        if (h.style == HoldStyle.short && target != null && targetHitDate == null) {
          scenario.add(ScenarioLine('最高碰到 ${_f(target)}', '到 2R 目標：先賣一半，剩下移動停利', DailyAction.sellHalf));
        }
        if (!breakeven && (h.style == HoldStyle.short || h.style == HoldStyle.swing)) {
          scenario.add(
            ScenarioLine(
              '收盤 ≥ ${_f(ref + risk)}',
              takeover ? '漲到 +1R：停損拉到接手當天的價位 ${_f(ref)}' : '漲到 +1R：停損拉到成本 ${_f(c)}（之後最差打平）',
              DailyAction.hold,
            ),
          );
        }
        if (canAddLater) {
          scenario.add(ScenarioLine('收盤 ≥ ${_f(addPrice)} 且量 ≥ 5 日均量', '加碼條件成立（只加贏家，比上一次少）', DailyAction.addOn));
        }
      }

      // 加碼時機
      if (noAdd) {
        addRules.add('均值回歸型的目標就是 20 日線、空間有限，不加碼；到目標全部出場。');
      } else {
        final blocked = rNow < 0 ? AddOnStatus.blocked : null;
        addPlan.add(
          AddOnLevel(
            '① +1R 之後',
            ref + risk,
            '收盤站上 ${_f(ref + risk)}（+1R）、停損已拉到成本，這時加碼才不會讓整筆變成虧錢的風險',
            blocked ?? (breakeven || rNow >= 1 ? AddOnStatus.done : AddOnStatus.waiting),
          ),
        );
        if (h.strategy == 'B' || h.style == HoldStyle.short) {
          addPlan.add(
            AddOnLevel(
              '② 回測 20 日線不破',
              ok(e20) ? e20 : null,
              '拉回 20 日線${ok(e20) ? ' ${_f(e20)}' : ''} 附近量縮，再收盤站上前一天高點（回檔買點）',
              blocked ??
                  (rNow >= 1 && ok(e20) && (lastClose - e20).abs() <= 0.5 * atr
                      ? AddOnStatus.ready
                      : AddOnStatus.waiting),
            ),
          );
        } else {
          addPlan.add(
            AddOnLevel(
              '② 整理後再突破',
              maxHigh,
              '買進後高點 ${_f(maxHigh)}：回檔整理後，放量收盤站上這個價（突破加碼）',
              blocked ?? (rNow >= 1 && lastClose >= maxHigh * 0.995 ? AddOnStatus.ready : AddOnStatus.waiting),
            ),
          );
        }
        addRules.addAll([
          '只加贏家：虧損中禁止加碼（禁止向下攤平）。${rNow < 0 ? '目前虧損 ${_r(rNow)}，先不要加。' : ''}',
          '每次加碼比上一次少：第一次 ≤ 原始股數的一半，第二次 ≤ 四分之一（金字塔）。',
          '加碼後整筆的停損至少拉到新的平均成本，總風險不超過原本的 1R。',
          if (h.buys.length > 1) '你已經加碼 ${h.buys.length - 1} 次。',
        ]);
      }
    }
    // 持有週期跟持有方式
    final styleD = h.style.durationClass;
    if (styleD != null && durConfirmed > styleD && rNow >= 1) {
      styleAdvice =
          '目前證據支持 D$durConfirmed（${kDurationRange[durConfirmed]}），比「${h.style.label}」長：可以考慮改成較長的持有方式，'
          '但停損至少維持在 ${_f(stop)}，不能放寬。';
    } else if (styleD != null && durConfirmed > 0 && durConfirmed < styleD) {
      styleAdvice = '持有理由的時間尺度縮短到 D$durConfirmed（${kDurationRange[durConfirmed]}）：提高停利敏感度，獲利不要回吐太多。';
    }
  }

  // 紀律：出場訊號 vs 你實際的處理
  final discipline = <DisciplineEvent>[];
  final idxOf = {for (var j = 0; j < n; j++) s.bars[j].date: j};
  void judge(String date, String signal, int idx) {
    final sell = h.sells.where((x) => x.date.compareTo(date) >= 0).toList()..sort((a, b) => a.date.compareTo(b.date));
    if (sell.isEmpty) {
      discipline.add(DisciplineEvent(date, signal, DisciplineStatus.pending, delayDays: (n - 1) - idx));
      return;
    }
    final sj = idxOf[sell.first.date] ?? adjusted.lastIndexWhere((b) => b.date.compareTo(sell.first.date) <= 0);
    final delay = sj - idx;
    final refClose = rawByDate[date]?.close ?? s.close[idx];
    discipline.add(
      DisciplineEvent(
        date,
        signal,
        delay <= 1 ? DisciplineStatus.onTime : DisciplineStatus.late,
        actionDate: sell.first.date,
        delayDays: delay,
        delayCost: (refClose - sell.first.price) * sell.first.shares,
      ),
    );
  }

  if (triggerDate != null && triggerIdx >= 0) judge(triggerDate, triggerReason ?? '出場訊號', triggerIdx);
  if (h.style == HoldStyle.short && targetHitDate != null && idxOf[targetHitDate] != null) {
    judge(targetHitDate, '到 2R 目標先賣一半', idxOf[targetHitDate]!);
  }
  if (h.closed && triggerDate == null && h.lastSellDate != null) {
    discipline.add(
      DisciplineEvent(h.lastSellDate!, '沒有出場訊號，你自己先賣出', DisciplineStatus.early, actionDate: h.lastSellDate),
    );
  }

  // 摘要
  HoldingSummary? summary;
  if (log.isNotEmpty) {
    final peak = maxClose == 0 ? s.close[end] : maxClose;
    final lines = <String>[];
    final days = log.length;
    final entryD = log.first.duration;
    final nowD = log.last.duration;
    final healthE = log.first.health, healthN = log.last.health;
    if (h.closed) {
      final rr = risk / f * h.boughtShares;
      lines.add(
        '持有 $days 個交易日（${h.firstBuyDate} → ${h.lastSellDate}），已實現 ${realized >= 0 ? '+' : ''}${realized.round()} 元'
        '${rr > 0 ? '（約 ${_r(realized / rr)}）' : ''}',
      );
      final why = h.sells.map((x) => x.reason ?? '').where((x) => x.isNotEmpty).toSet().join('、');
      if (why.isNotEmpty) lines.add('出場原因：$why');
      if (h.duration != null) {
        final range = switch (h.duration!) {
          1 => (3, 10),
          2 => (10, 40),
          _ => (40, 125),
        };
        final verdict = days < range.$1 ? '比預估短' : (days > range.$2 ? '比預估長' : '在預估範圍內');
        lines.add('買進時預估 ${durationLabel(h.duration!)}，實際持有 $days 個交易日 → $verdict');
      }
    } else {
      lines.add('已持有 $days 個交易日，目前 ${_p(log.last.pnlPct)}（${_r(log.last.r)}）');
    }
    lines.add(
      '期間最高 ${_p((peak / c - 1) * 100)}、最低 ${_p((minClose / c - 1) * 100)}；'
      '${longMode ? '目前防守價 ${_f(stop)}' : '停損上調 $stopRaises 次${breakeven ? '，已保本' : ''}'}',
    );
    if (!h.closed && peak > c && lastClose < peak) {
      lines.add('從高點回落 ${((1 - lastClose / peak) * 100).toStringAsFixed(1)}%');
    }
    lines.add('健康度：買進時 $healthE → 現在 $healthN；持有週期 D$entryD → D$nowD（升級 $upgrades 次、降級 $downgrades 次）');
    for (final d in discipline) {
      lines.add(switch (d.status) {
        DisciplineStatus.onTime => '紀律：${d.signalDate} 的出場訊號，你在 ${d.actionDate} 準時處理',
        DisciplineStatus.late =>
          '紀律：${d.signalDate} 的出場訊號，你晚了 ${d.delayDays} 個交易日才處理'
              '${(d.delayCost ?? 0) > 0 ? '，多賠（少賺）約 ${d.delayCost!.round()} 元' : '（這次晚賣反而賣得比較好，但不要養成習慣）'}',
        DisciplineStatus.pending => '紀律：${d.signalDate} 的出場訊號，已經 ${d.delayDays} 個交易日還沒處理',
        DisciplineStatus.early => '紀律：沒有出場訊號前就自己先賣出',
      });
    }
    var peakPct = -1e9, dd = 0.0;
    for (final x in log) {
      peakPct = math.max(peakPct, x.pnlPct);
      dd = math.max(dd, peakPct - x.pnlPct);
    }
    summary = HoldingSummary(
      days: days,
      maxGainPct: (peak / c - 1) * 100,
      maxLossPct: (minClose / c - 1) * 100,
      drawdownFromPeakPct: dd,
      stopRaises: stopRaises,
      upgrades: upgrades,
      downgrades: downgrades,
      healthAtEntry: healthE,
      healthNow: healthN,
      durationAtEntry: entryD,
      durationNow: nowD,
      lines: lines,
    );
  }

  return HoldingEval(
    state: state,
    action: action,
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
    log: log,
    thesisNow: checksNow,
    thesisAtEntry: checksEntry,
    health: today?.health,
    durationNow: log.isEmpty ? null : durConfirmed,
    durationWhy: log.isEmpty ? null : durWhy,
    scenario: scenario,
    addOnPlan: addPlan,
    addOnRules: addRules,
    summary: summary,
    discipline: discipline,
    styleAdvice: styleAdvice,
    watchLevels: levels,
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

/// 改成更長的持有方式前檢查（最終版 §02：不能把短線虧損改成長期投資）。
/// 回傳 (是否擋下, 說明)；沒問題回傳 null。
(bool, String)? styleUpgradeCheck(Holding h, HoldStyle to, HoldingEval e) {
  final from = h.style.durationClass, next = to.durationClass;
  if (from == null || next == null || next <= from || h.closed) return null;
  final r = e.rNow ?? 0;
  if (r < 0) {
    return (
      true,
      '這筆目前虧損 ${_r(r)}，不能從「${h.style.label}」改成「${to.label}」：'
          '虧損時改成更長的持有方式，等於把停損放寬、把短線套牢改叫長期投資。要改，請先等它回到獲利。',
    );
  }
  if (r < 1) {
    return (false, '還沒有獲利 +1R，延長持有期間的證據不足。可以改，但停損不會往下放寬。');
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

class DisciplineStats {
  final int onTime, late, pending, early;
  final double lateCost;
  final double avgDelay;
  const DisciplineStats(this.onTime, this.late, this.pending, this.early, this.lateCost, this.avgDelay);

  int get judged => onTime + late;
  double get rate => judged == 0 ? 1 : onTime / judged;
  bool get isEmpty => onTime + late + pending + early == 0;
}

/// 你的紀律：出場訊號出現後，準時處理的比例、晚處理平均晚幾天、多賠多少。
DisciplineStats disciplineStats(Iterable<HoldingEval> evals) {
  var onTime = 0, late = 0, pending = 0, early = 0;
  var cost = 0.0, delay = 0;
  for (final e in evals) {
    for (final d in e.discipline) {
      switch (d.status) {
        case DisciplineStatus.onTime:
          onTime++;
        case DisciplineStatus.late:
          late++;
          cost += math.max(0, d.delayCost ?? 0);
          delay += d.delayDays ?? 0;
        case DisciplineStatus.pending:
          pending++;
        case DisciplineStatus.early:
          early++;
      }
    }
  }
  return DisciplineStats(onTime, late, pending, early, cost, late == 0 ? 0 : delay / late);
}

/// 週報：這一週（最近 5 個交易日）持股的變化。
class WeeklyReport {
  final String from, to;
  final double change; // 這週市值變化（元）
  final List<String> worse, better, up, down;
  const WeeklyReport(this.from, this.to, this.change, this.worse, this.better, this.up, this.down);
  bool get quiet => worse.isEmpty && better.isEmpty;
}

WeeklyReport? weeklyReport(List<(Holding, HoldingEval)> open, String Function(Holding) name) {
  String? from, to;
  var change = 0.0;
  final worse = <String>[], better = <String>[];
  final moves = <(String, double)>[];
  for (final (h, e) in open) {
    final log = e.log;
    if (log.length < 2) continue;
    final now = log.last, prev = log[log.length > 5 ? log.length - 6 : 0];
    from = from == null || prev.date.compareTo(from) < 0 ? prev.date : from;
    to = to == null || now.date.compareTo(to) > 0 ? now.date : to;
    change += now.shares * (now.close - prev.close);
    final a = actionText(prev.action, h.style), b = actionText(now.action, h.style);
    if (now.action.index < prev.action.index) {
      worse.add('${name(h)}：$a → $b（${now.reason.split('；').first}）');
    } else if (now.action.index > prev.action.index) {
      better.add('${name(h)}：$a → $b');
    }
    if (prev.close > 0) moves.add((name(h), (now.close / prev.close - 1) * 100));
  }
  if (from == null) return null;
  moves.sort((a, b) => b.$2.compareTo(a.$2));
  String fmt((String, double) m) => '${m.$1} ${m.$2 >= 0 ? '+' : ''}${m.$2.toStringAsFixed(1)}%';
  return WeeklyReport(
    from,
    to!,
    change,
    worse,
    better,
    [
      for (final m in moves.take(3))
        if (m.$2 > 0) fmt(m),
    ],
    [
      for (final m in moves.reversed.take(3))
        if (m.$2 < 0) fmt(m),
    ],
  );
}
