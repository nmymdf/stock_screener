/// 短中長交叉分析（最終版規格 §02 交叉矩陣、§03 持有期間評估、§04 價量持續性）。
///
/// 每檔股票每天算出短期、中期、長期三個分數，各自有自己的失效條件；
/// 再依三個分數是否同向，判斷「這是哪一種機會」，並估計「最合理的持有區間
/// D1～D3 ＋ 信心度 ＋ 什麼情況會延長或縮短」。
///
/// 還沒有基本面資料，所以長期分數只看技術面（年線、一年相對強弱、波動穩定度），
/// 持有期間上限是 D3；D4／D5 要等營收、財報資料接上之後才會開放。
library;

import 'dart:math' as math;

import '../ta.dart';
import 'industry_engine.dart';
import 'market_engine.dart';
import 'scoring.dart';
import 'signals.dart';

String _f(double v) => v >= 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(2);

// ───────── 價量五種狀態（§04）─────────

enum PvState { distribution, churn, breakout, healthyUp, contraction, neutral }

extension PvStateInfo on PvState {
  String get label => switch (this) {
    PvState.distribution => '下跌放量',
    PvState.churn => '爆量不漲',
    PvState.breakout => '突破確認',
    PvState.healthyUp => '健康上升',
    PvState.contraction => '縮量整理',
    PvState.neutral => '量價平淡',
  };

  String get meaning => switch (this) {
    PvState.distribution => '下跌時量放大，賣方主導，風險上升',
    PvState.churn => '量很大但價格沒有漲，可能是換手，也可能是高檔出貨，要看接下來幾天',
    PvState.breakout => '創關鍵新高且量明顯放大，接下來要看能不能守住突破區',
    PvState.healthyUp => '上漲放量、回檔縮量，趨勢延續的品質較好',
    PvState.contraction => '量縮、波動收斂，可能在等待突破，也可能失去關注',
    PvState.neutral => '沒有明顯的量價訊號',
  };

  /// 給短期分數用的 0～100。
  double get shortScore => switch (this) {
    PvState.breakout => 100,
    PvState.healthyUp => 90,
    PvState.contraction => 60,
    PvState.neutral => 50,
    PvState.churn => 25,
    PvState.distribution => 0,
  };

  bool get bad => this == PvState.distribution || this == PvState.churn;
}

class PvReading {
  final PvState state;
  final String detail;

  /// 價量持續性 0～100（中長期的量價：累積還是分配）。
  final double persistence;
  final List<ScoreItem> persistenceItems;

  /// 最近 5 天內有突破時的突破品質（§04 突破品質評分）。
  final double? breakoutQuality;
  final List<ScoreItem> breakoutItems;

  const PvReading(
    this.state,
    this.detail,
    this.persistence,
    this.persistenceItems, {
    this.breakoutQuality,
    this.breakoutItems = const [],
  });

  /// 突破品質最後一項：大盤與產業是否同步走強（全市場算完才知道）。
  PvReading withContext(Regime? regime, IndustryClass? industryClass) {
    if (breakoutQuality == null) return this;
    final align =
        (regime == Regime.strongBull || regime == Regime.bull) &&
        (industryClass == IndustryClass.leading || industryClass == IndustryClass.improving);
    final items = [...breakoutItems, ScoreItem('大盤與產業同步走強（不是逆勢孤立突破）', align ? 10 : 0, 10)];
    return PvReading(state, detail, persistence, persistenceItems, breakoutQuality: _norm(items), breakoutItems: items);
  }
}

double _norm(List<ScoreItem> items) {
  final max = items.fold(0.0, (a, b) => a + b.max);
  return max == 0 ? 50 : items.fold(0.0, (a, b) => a + b.points) / max * 100;
}

/// 第 i 天的價量狀態、價量持續性、突破品質。
PvReading priceVolume(StockSeries s, int i) {
  if (i < 21) return const PvReading(PvState.neutral, '資料不足', 50, []);
  final avg = s.avgVolBefore(i, 20);
  final vr = avg > 0 ? s.vol[i] / avg : 1.0;
  final chg = s.changePct(i);
  final range = s.high[i] - s.low[i];
  final pos = range > 0 ? (s.close[i] - s.low[i]) / range : 0.5;
  final atr = ok(s.atr[i]) ? s.atr[i] : s.close[i] * 0.02;

  var downVol5 = 0.0, upVol5 = 0.0;
  for (var j = i - 4; j <= i; j++) {
    if (s.close[j] < s.close[j - 1]) downVol5 += s.vol[j];
    if (s.close[j] > s.close[j - 1]) upVol5 += s.vol[j];
  }
  var up20 = 0.0, down20 = 0.0;
  for (var j = i - 19; j <= i; j++) {
    if (s.close[j] > s.close[j - 1]) up20 += s.vol[j];
    if (s.close[j] < s.close[j - 1]) down20 += s.vol[j];
  }
  final hh20 = maxIn(s.high, i - 20, i - 1);
  final recent5 = avgIn(s.vol, i - 4, i);
  final width10 = maxIn(s.high, i - 9, i) - minIn(s.low, i - 9, i);

  PvState state;
  String detail;
  if ((chg <= -2 && vr >= 1.5) || (s.roc(i, 5) <= -4 && downVol5 > 1.5 * upVol5 && downVol5 > 0)) {
    state = PvState.distribution;
    detail = chg <= -2 && vr >= 1.5
        ? '今天跌 ${chg.toStringAsFixed(1)}%，量是均量的 ${vr.toStringAsFixed(1)} 倍'
        : '近 5 天跌 ${s.roc(i, 5).abs().toStringAsFixed(1)}%，下跌日的量是上漲日的 ${upVol5 == 0 ? '多' : (downVol5 / upVol5).toStringAsFixed(1)} 倍';
  } else if (vr >= 2.5 && (chg.abs() < 1.5 || pos < 0.4)) {
    state = PvState.churn;
    detail =
        '量是均量的 ${vr.toStringAsFixed(1)} 倍，但只${chg >= 0 ? '漲' : '跌'} ${chg.abs().toStringAsFixed(1)}%'
        '${pos < 0.4 ? '，收在當天低檔（上影線長）' : ''}';
  } else if (s.close[i] > hh20 && vr >= 1.5 && pos >= 0.5) {
    state = PvState.breakout;
    detail = '收盤 ${_f(s.close[i])} 站上 20 日高點 ${_f(hh20)}，量 ${vr.toStringAsFixed(1)} 倍';
  } else if (up20 > down20 * 1.15 && ok(s.ema20[i]) && s.close[i] > s.ema20[i] && s.roc(i, 20) > 0) {
    state = PvState.healthyUp;
    detail = '近 20 天上漲日的量是下跌日的 ${down20 == 0 ? '多' : (up20 / down20).toStringAsFixed(1)} 倍，收在 20 日線之上';
  } else if (recent5 < avg * 0.75 && width10 < 3 * atr) {
    state = PvState.contraction;
    detail =
        '近 5 日均量只有 20 日均量的 ${(recent5 / avg * 100).toStringAsFixed(0)}%，10 天振幅 ${(width10 / atr).toStringAsFixed(1)} ATR';
  } else {
    state = PvState.neutral;
    detail = '量比 ${vr.toStringAsFixed(1)} 倍，沒有明顯的量價訊號';
  }

  // 價量持續性（中長期）
  final items = <ScoreItem>[];
  if (i >= 61) {
    var up60 = 0.0, down60 = 0.0;
    for (var j = i - 59; j <= i; j++) {
      if (s.close[j] > s.close[j - 1]) up60 += s.vol[j];
      if (s.close[j] < s.close[j - 1]) down60 += s.vol[j];
    }
    final ratio = down60 == 0 ? 9.9 : up60 / down60;
    items.add(ScoreItem('近 60 天上漲日量 ÷ 下跌日量 = ${ratio.toStringAsFixed(2)}（≥ 1.1 代表資金累積）', ratio >= 1.1 ? 35 : 0, 35));
    items.add(ScoreItem('OBV 比 60 天前高（資金持續流入）', s.obv[i] > s.obv[i - 60] ? 25 : 0, 25));
  }
  var distDays = 0;
  for (var j = i - 19; j <= i; j++) {
    final a = s.avgVolBefore(j, 20);
    if (a > 0 && s.vol[j] >= 1.5 * a && s.changePct(j) <= -2) distDays++;
  }
  items.add(ScoreItem('近 20 天「下跌放量」$distDays 天（≤ 1 天）', distDays <= 1 ? 25 : 0, 25));
  items.add(ScoreItem('近 20 天上漲日量 > 下跌日量', up20 > down20 ? 15 : 0, 15));
  final persistence = _norm(items);

  // 突破品質：最近 5 天內有突破 20 日高點
  int? bk;
  for (var j = i; j >= i - 4 && j > 20; j--) {
    if (s.close[j] > maxIn(s.high, j - 20, j - 1)) {
      bk = j;
    }
  }
  double? quality;
  final bItems = <ScoreItem>[];
  if (bk != null) {
    final j = bk;
    final level = maxIn(s.high, j - 20, j - 1);
    var lv = 20;
    for (final w in [250, 120, 60]) {
      if (j > w && s.close[j] > maxIn(s.high, j - w, j - 1)) {
        lv = w;
        break;
      }
    }
    bItems.add(ScoreItem('突破的級別：$lv 日新高（越長期越有結構意義）', lv >= 120 ? 25 : (lv >= 60 ? 15 : 8), 25));
    final a = s.avgVolBefore(j, 20);
    final bvr = a > 0 ? s.vol[j] / a : 0.0;
    bItems.add(ScoreItem('突破當天量 ${bvr.toStringAsFixed(1)} 倍（≥ 2 倍最好）', bvr >= 2 ? 20 : (bvr >= 1.5 ? 12 : 0), 20));
    final r = s.high[j] - s.low[j];
    final p = r > 0 ? (s.close[j] - s.low[j]) / r : 0.5;
    bItems.add(
      ScoreItem('突破當天收在 ${(p * 100).toStringAsFixed(0)}% 位置（收在高檔優於沖高回落）', p >= 0.7 ? 15 : (p >= 0.5 ? 8 : 0), 15),
    );
    final held = i > j ? minIn(s.close, j + 1, i) >= level : true;
    bItems.add(
      ScoreItem(
        i > j ? '突破後 ${i - j} 天都守住突破價 ${_f(level)}' : '今天剛突破，還要看後續 1～5 天能不能守住',
        held && i > j ? 20 : (held ? 10 : 0),
        20,
      ),
    );
    final ext = ok(s.ema20[i]) ? (s.close[i] - s.ema20[i]) / atr : 0.0;
    bItems.add(ScoreItem('離 20 日線 ${ext.toStringAsFixed(1)} ATR（≤ 2.5 不算追高）', ext <= 2.5 ? 10 : 0, 10));
    quality = _norm(bItems);
  }

  return PvReading(state, detail, persistence, items, breakoutQuality: quality, breakoutItems: bItems);
}

// ───────── 三週期分數（§02）─────────

class HorizonScore {
  final String key; // short / medium / long
  final String name;
  final String span;
  final double? score;
  final List<ScoreItem> items;
  final String summary;
  final String invalidation; // 這個週期自己的失效條件

  const HorizonScore(this.key, this.name, this.span, this.score, this.items, this.summary, this.invalidation);

  Level get level => levelOf(score);

  /// 加上需要全市場資料才算得出來的項目（產業、市場），重新計分。
  HorizonScore extend(List<ScoreItem> extra) {
    if (extra.isEmpty) return this;
    final all = [...items, ...extra];
    final max = all.fold(0.0, (a, b) => a + b.max);
    final sc = max < 40 ? null : all.fold(0.0, (a, b) => a + b.points) / max * 100;
    return HorizonScore(key, name, span, sc, all, _summary(key, sc), invalidation);
  }
}

String _summary(String key, double? score) {
  if (score == null) return key == 'long' ? '至少要 200 個交易日的資料才能判斷長期結構' : '資料不足';
  final strong = score >= 65, weak = score < 45;
  return switch (key) {
    'short' => strong ? '短線量價與動能強' : (weak ? '短線偏弱或位置不佳' : '短線普通'),
    'medium' => strong ? '中期趨勢、相對強度、產業同向' : (weak ? '中期結構偏弱' : '中期普通'),
    _ => strong ? '長期結構完整、一年相對強勢' : (weak ? '長期結構偏弱' : '長期普通'),
  };
}

enum Level { strong, neutral, weak, none }

Level levelOf(double? v) => v == null ? Level.none : (v >= 65 ? Level.strong : (v < 45 ? Level.weak : Level.neutral));

extension LevelInfo on Level {
  String get label => switch (this) {
    Level.strong => '強',
    Level.neutral => '中性',
    Level.weak => '弱',
    Level.none => '資料不足',
  };
}

/// 全市場在各個期間的報酬百分位（0～1），也就是各期間的相對強度。
class RsWindows {
  final double? p20, p60, p120, p250;
  const RsWindows(this.p20, this.p60, this.p120, this.p250);

  List<(int, double)> get available => [
    if (p20 != null) (20, p20!),
    if (p60 != null) (60, p60!),
    if (p120 != null) (120, p120!),
    if (p250 != null) (250, p250!),
  ];
}

String _top(double p) => '前 ${((1 - p) * 100).clamp(1, 100).toStringAsFixed(0)}%';

HorizonScore shortHorizon(
  StockSeries s,
  int i,
  ModuleScore momentum,
  ModuleScore breakout,
  PvReading pv,
  RsWindows rs,
) {
  final items = <ScoreItem>[];
  if (momentum.score != null) {
    items.add(ScoreItem('動能 ${momentum.score!.toStringAsFixed(0)} 分（RSI、MACD、KD、短期報酬）', momentum.score! * 0.25, 25));
  }
  items.add(ScoreItem('量價狀態：${pv.state.label}（${pv.detail}）', pv.state.shortScore * 0.25, 25));
  if (rs.p20 != null) items.add(ScoreItem('20 日相對強度全市場${_top(rs.p20!)}', rs.p20! * 20, 20));
  if (breakout.score != null) items.add(ScoreItem('位置：${breakout.summary}', breakout.score! * 0.15, 15));
  final atr = s.atr[i];
  if (ok(atr) && atr > 0 && ok(s.ema20[i])) {
    final ext = (s.close[i] - s.ema20[i]) / atr;
    final pts = ext < 0 ? 4.5 : (ext <= 2 ? 15.0 : (ext <= 3 ? 9.0 : 3.0));
    items.add(
      ScoreItem(ext < 0 ? '收盤在 20 日線之下（短線偏弱）' : '離 20 日線 ${ext.toStringAsFixed(1)} ATR（≤ 2 最好；太遠是追高）', pts, 15),
    );
  }
  final max = items.fold(0.0, (a, b) => a + b.max);
  final score = max < 40 ? null : items.fold(0.0, (a, b) => a + b.points) / max * 100;
  final low5 = minIn(s.low, i - 4, i);
  final inval = ok(s.ema20[i]) && s.close[i] > s.ema20[i]
      ? '收盤跌破 20 日線 ${_f(s.ema20[i])}，或跌破近 5 日低點 ${_f(low5)}；突破後 5 天內沒有延續也算失效'
      : '收盤跌破近 5 日低點 ${_f(low5)}';
  return HorizonScore('short', '短期', '3～10 交易日', score, items, _summary('short', score), inval);
}

HorizonScore mediumHorizon(StockSeries s, int i, ModuleScore trend, PvReading pv, RsWindows rs) {
  final items = <ScoreItem>[];
  if (trend.score != null) {
    items.add(ScoreItem('日線趨勢 ${trend.score!.toStringAsFixed(0)} 分（均線排列、ADX、MACD）', trend.score! * 0.30, 30));
  }
  final rsMid = rs.p60 == null ? null : (rs.p120 == null ? rs.p60! : rs.p60! * 0.6 + rs.p120! * 0.4);
  if (rsMid != null) {
    items.add(ScoreItem('60／120 日相對強度：${_top(rs.p60!)}${rs.p120 == null ? '' : '／${_top(rs.p120!)}'}', rsMid * 25, 25));
  }
  items.add(ScoreItem('資金累積（價量持續性 ${pv.persistence.toStringAsFixed(0)} 分）', pv.persistence * 0.15, 15));
  final max = items.fold(0.0, (a, b) => a + b.max);
  final score = max < 40 ? null : items.fold(0.0, (a, b) => a + b.points) / max * 100;
  final e50 = s.ema50[i];
  return HorizonScore(
    'medium',
    '中期',
    '2～8 週',
    score,
    items,
    _summary('medium', score),
    ok(e50) ? '收盤跌破 50 日線 ${_f(e50)} 且 50 日線走平或下彎；或 60 日相對強度掉出前 50%；或出現連續下跌放量' : '資料不足，暫以 20 日線為準',
  );
}

/// 長期（技術面）：至少要 200 天資料，不然回傳 null 分數。
HorizonScore longHorizon(StockSeries s, int i, RsWindows rs) {
  final items = <ScoreItem>[];
  const name = '長期（技術面）';
  if (i < 200 || !ok(s.ema200[i])) {
    return HorizonScore('long', name, '2～6 個月以上', null, items, '至少要 200 個交易日的資料才能判斷長期結構', '—');
  }
  final c = s.close[i];
  final y = ok(s.sma240[i]) ? s.sma240[i] : s.ema200[i];
  final yName = ok(s.sma240[i]) ? '年線（240 日）' : '200 日均線';
  final yPrev = ok(s.sma240[i]) ? (i >= 20 && ok(s.sma240[i - 20]) ? s.sma240[i - 20] : double.nan) : s.ema200[i - 20];
  final rising = ok(yPrev) && y > yPrev;
  items.add(ScoreItem('收盤在$yName ${_f(y)} 之上${rising ? '，而且$yName上揚' : ''}', c > y ? (rising ? 25 : 15) : 0, 25));
  final aligned = ok(s.sma60[i]) && s.sma60[i] > y && s.ema50[i] > s.ema200[i];
  items.add(ScoreItem('季線 > 年線、50 日線 > 200 日線（長期多頭排列）', aligned ? 15 : 0, 15));
  final rsLong = rs.p250 ?? rs.p120;
  if (rsLong != null) {
    items.add(ScoreItem('${rs.p250 != null ? 250 : 120} 日相對強度全市場${_top(rsLong)}', rsLong * 25, 25));
  }
  final look = math.min(250, i);
  final top = maxIn(s.high, i - look, i);
  final dist = (top - c) / top;
  items.add(
    ScoreItem(
      '離 $look 日高點 ${(dist * 100).toStringAsFixed(1)}%（15% 以內）',
      dist <= 0.15 ? 15 : (dist <= 0.25 ? 7 : 0),
      15,
    ),
  );
  var peak = 0.0, mdd = 0.0;
  for (var j = i - look; j <= i; j++) {
    peak = math.max(peak, s.close[j]);
    mdd = math.max(mdd, 1 - s.close[j] / peak);
  }
  items.add(ScoreItem('一年內最大回檔 ${(mdd * 100).toStringAsFixed(0)}%（≤ 35% 算穩定）', mdd <= 0.35 ? 10 : 0, 10));
  final atrPct = ok(s.atr[i]) ? s.atr[i] / c * 100 : double.nan;
  if (ok(atrPct)) {
    items.add(ScoreItem('每日波動 ATR ${atrPct.toStringAsFixed(1)}%（≤ 3.5% 算穩定）', atrPct <= 3.5 ? 10 : 0, 10));
  }
  final score = _norm(items);
  return HorizonScore(
    'long',
    name,
    '2～6 個月以上',
    score,
    items,
    _summary('long', score),
    '收盤跌破$yName ${_f(y)} 且$yName下彎；或一年相對強度落到後半段',
  );
}

/// 中期分數要再加上產業和市場（全市場算完才知道）。
List<ScoreItem> mediumContext({double? industryScore, String? industryLabel, double? marketScore}) => [
  if (industryScore != null)
    ScoreItem('產業動能：${industryLabel ?? ''} ${industryScore.toStringAsFixed(0)} 分', industryScore * 0.20, 20),
  if (marketScore != null) ScoreItem('市場環境 ${marketScore.toStringAsFixed(0)} 分', marketScore * 0.10, 10),
];

// ───────── 交叉矩陣：機會類型（§02）─────────

enum Opportunity { resonance, swing, longTurning, tactical, waitEntry, watchlist, themeSwing, neutral, avoid }

extension OpportunityInfo on Opportunity {
  String get label => switch (this) {
    Opportunity.resonance => '三週期共振',
    Opportunity.swing => '波段機會',
    Opportunity.longTurning => '長線股短線轉強',
    Opportunity.tactical => '純短線戰術',
    Opportunity.waitEntry => '中長期佳・等進場點',
    Opportunity.watchlist => '好股票・時機未到',
    Opportunity.themeSwing => '題材／週期波段',
    Opportunity.neutral => '證據不足',
    Opportunity.avoid => '三週期都弱',
  };

  String get strategy => switch (this) {
    Opportunity.resonance => '短中長同向，品質最高：可以提高優先順序，持有期間可往中長期延伸；仍依停損與總曝險控制。',
    Opportunity.swing => '以短中期操作為主，長期條件還不夠：獲利用移動停利保護，不要自動變成長抱。',
    Opportunity.longTurning => '長期結構好、短線剛轉強，但中期還沒確認：先當短線進場，中期轉強再考慮延長。',
    Opportunity.tactical => '只有短線強：小部位、停損要快、時間停損要嚴格，賺了就走，套住不能改成長抱。',
    Opportunity.waitEntry => '中長期佳但短線位置不好：等回檔到支撐量縮再轉強，或突破確認後再買，不要猜底。',
    Opportunity.watchlist => '長期體質好，但趨勢還不配合：放進觀察池，不急著買。',
    Opportunity.themeSwing => '中期強、長期弱：比較像題材或景氣波段，重視產業和價格結構，不要延伸成長期投資。',
    Opportunity.neutral => '證據不足或互相矛盾：不交易，保留資金。',
    Opportunity.avoid => '短中長都弱：避開。',
  };

  /// 排序用：越前面越值得看。
  int get rank => index;

  bool get tradable =>
      this == Opportunity.resonance ||
      this == Opportunity.swing ||
      this == Opportunity.longTurning ||
      this == Opportunity.tactical ||
      this == Opportunity.themeSwing;
}

Opportunity classifyOpportunity(Level s, Level m, Level l) {
  final ls = l == Level.strong;
  final lw = l == Level.weak || l == Level.none;
  if (s == Level.strong && m == Level.strong) return ls ? Opportunity.resonance : Opportunity.swing;
  if (s == Level.strong && ls) return Opportunity.longTurning;
  if (s == Level.strong) return Opportunity.tactical;
  if (m == Level.strong && ls) return Opportunity.waitEntry;
  if (ls) return Opportunity.watchlist;
  if (m == Level.strong && lw) return Opportunity.themeSwing;
  if (m == Level.strong) return Opportunity.waitEntry;
  if (s == Level.weak && m == Level.weak && lw) return Opportunity.avoid;
  return Opportunity.neutral;
}

// ───────── 持有期間 D0～D5（§03）─────────

const kDurationRange = {0: '當日～3 日', 1: '3～10 交易日', 2: '2～8 週', 3: '2～6 個月', 4: '6～24 個月', 5: '2 年以上'};

String durationLabel(int d) => 'D$d（${kDurationRange[d]}）';

enum Confidence { high, medium, low }

extension ConfidenceInfo on Confidence {
  String get label => switch (this) {
    Confidence.high => '高',
    Confidence.medium => '中',
    Confidence.low => '低',
  };

  String get meaning => switch (this) {
    Confidence.high => '多組獨立證據（趨勢、相對強度、量價、產業、市場）同向，而且資料完整',
    Confidence.medium => '方向大致一致，但有 1 組證據矛盾或資料不夠長',
    Confidence.low => '主要靠單一訊號，或證據互相矛盾；持有期間上限自動縮短',
  };
}

class Evidence {
  final String name;
  final double weight; // 規格書 §03 的建議權重
  final double? score; // null = 還沒有資料
  final String detail;
  const Evidence(this.name, this.weight, this.score, this.detail);

  bool get supports => score != null && score! >= 60;
  bool get contradicts => score != null && score! < 40;
}

class DurationEstimate {
  final int? cls; // 1～3；null = 不建議持有（沒有可以持有的理由）
  final Confidence confidence;
  final double durationScore;
  final List<Evidence> evidence;
  final List<String> why;
  final List<String> capped; // 為什麼被往下調
  final String whyNotHigher;
  final List<String> upgradeIf;
  final List<String> downgradeIf;
  final String hardInvalidation;

  const DurationEstimate({
    required this.cls,
    required this.confidence,
    required this.durationScore,
    required this.evidence,
    required this.why,
    required this.capped,
    required this.whyNotHigher,
    required this.upgradeIf,
    required this.downgradeIf,
    required this.hardInvalidation,
  });

  String get label => cls == null ? '不建議持有' : durationLabel(cls!);
}

/// 中長期趨勢的持續性 0～100：均線長期排列、50 日線斜率、年線。
double trendPersistenceOf(StockSeries s, int i) {
  final items = <ScoreItem>[];
  void add(bool? c, double w) {
    if (c != null) items.add(ScoreItem('', c ? w : 0, w));
  }

  bool? v(bool Function() f, List<double> need) => need.every(ok) ? f() : null;
  add(v(() => s.close[i] > s.ema50[i], [s.ema50[i]]), 20);
  add(v(() => s.ema20[i] > s.ema50[i], [s.ema20[i], s.ema50[i]]), 15);
  add(i >= 20 ? v(() => s.ema50[i] > s.ema50[i - 20], [s.ema50[i], s.ema50[i - 20]]) : null, 20);
  add(v(() => s.ema50[i] > s.ema100[i], [s.ema50[i], s.ema100[i]]), 15);
  add(v(() => s.close[i] > s.ema200[i], [s.ema200[i]]), 15);
  add(i >= 20 ? v(() => s.sma60[i] > s.sma60[i - 20], [s.sma60[i], s.sma60[i - 20]]) : null, 15);
  final max = items.fold(0.0, (a, b) => a + b.max);
  return max == 0 ? 50 : items.fold(0.0, (a, b) => a + b.points) / max * 100;
}

double regimeScore(Regime? r) => switch (r) {
  Regime.strongBull => 85,
  Regime.bull => 70,
  Regime.range => 50,
  Regime.weak => 35,
  Regime.bear => 15,
  null => 50,
};

/// 估計持有期間需要的個股數值（在分析的單檔迴圈裡先算好，之後不用再留整條序列）。
class DurationFacts {
  final double trendPersistence, ema20, ema50;
  final int bars;
  const DurationFacts(this.trendPersistence, this.ema20, this.ema50, this.bars);
  factory DurationFacts.of(StockSeries s, int i) =>
      DurationFacts(trendPersistenceOf(s, i), s.ema20[i], s.ema50[i], s.length);
}

DurationEstimate estimateDuration({
  required DurationFacts facts,
  required HorizonScore short,
  required HorizonScore medium,
  required HorizonScore long,
  required PvReading pv,
  required RsWindows rs,
  Strategy? strategy,
  double? industryScore,
  IndustryClass? industryClass,
  String? industry,
  double? marketScore,
  Regime? regime,
}) {
  final tp = facts.trendPersistence;
  final rsList = rs.available;
  final rsScore = rsList.isEmpty ? null : rsList.fold(0.0, (a, b) => a + b.$2) / rsList.length * 100;
  final rsLeading = rsList.where((x) => x.$2 >= 0.7).map((x) => x.$1).toList();
  final evidence = [
    const Evidence('公司品質持續性', 22, null, '需要 ROIC、自由現金流、負債資料（尚未接）'),
    Evidence(
      '產業週期持續性',
      18,
      industryScore,
      industryScore == null
          ? '沒有產業分類或樣本太少'
          : '$industry ${industryClass?.label ?? ''}（產業分數 ${industryScore.toStringAsFixed(0)}）',
    ),
    const Evidence('獲利動能', 15, null, '需要月營收、EPS、毛利率（尚未接）'),
    Evidence('中長期趨勢', 12, tp, '均線長期排列、50 日線斜率、季線方向：${tp.toStringAsFixed(0)} 分'),
    Evidence(
      '相對強弱持續性',
      10,
      rsScore,
      rsList.isEmpty
          ? '資料不足'
          : (rsLeading.isEmpty ? '20／60／120／250 日都沒有進前 30%' : '${rsLeading.join('／')} 日相對強度在全市場前 30%'),
    ),
    Evidence('價量持續性', 10, pv.persistence, '資金累積還是分配：${pv.persistence.toStringAsFixed(0)} 分'),
    Evidence('總體／資金環境', 8, marketScore ?? regimeScore(regime), '台股市場 ${regime?.label ?? '資料不足'}（國際資料尚未接）'),
    const Evidence('事件／治理風險', 5, null, '需要重大訊息、財報日程（尚未接）'),
  ];
  var sw = 0.0, ws = 0.0;
  for (final e in evidence) {
    if (e.score == null) continue;
    sw += e.score! * e.weight;
    ws += e.weight;
  }
  final dScore = ws == 0 ? 0.0 : sw / ws;
  final avail = evidence.where((e) => e.score != null).toList();
  final sup = avail.where((e) => e.supports).length;
  final con = avail.where((e) => e.contradicts).length;
  final longData = facts.bars >= 250;

  Confidence conf;
  if (sup >= 4 && con == 0 && longData) {
    conf = Confidence.high;
  } else if (sup >= 3 && con <= 1) {
    conf = Confidence.medium;
  } else {
    conf = Confidence.low;
  }

  final sv = short.score ?? 0, mv = medium.score ?? 0, lv = long.score;
  final why = <String>[];
  final capped = <String>[];
  int? cls;
  if (lv != null && lv >= 65 && mv >= 65 && tp >= 65 && (rsScore ?? 0) >= 65) {
    cls = 3;
    why.add('長期 ${lv.toStringAsFixed(0)}、中期 ${mv.toStringAsFixed(0)} 都強，趨勢持續性 ${tp.toStringAsFixed(0)}、多期間相對強度領先');
  } else if (mv >= 60 && tp >= 50) {
    cls = 2;
    why.add('中期分數 ${mv.toStringAsFixed(0)}、趨勢持續性 ${tp.toStringAsFixed(0)}：日線趨勢與相對強度支持持有數週');
  } else if (sv >= 55 || strategy != null) {
    cls = 1;
    why.add(strategy != null ? '主要由今天的「${strategy.label}」訊號支持，中期證據還不夠' : '短期分數 ${sv.toStringAsFixed(0)}：只有短線量價與動能支持');
  }
  for (final e in evidence) {
    if (e.supports) why.add('${e.name}：${e.detail}');
  }

  int cap(int? c, int max, String reason) {
    if (c != null && c > max) {
      capped.add(reason);
      return max;
    }
    return c ?? 0;
  }

  if (cls != null) {
    if (strategy == Strategy.meanReversion) cls = cap(cls, 1, '均值回歸型目標就是 20 日線，本質是短線');
    if (regime == Regime.weak || regime == Regime.bear) cls = cap(cls, 1, '市場「${regime!.label}」，只做短週期');
    if (regime == Regime.range) cls = cap(cls, 2, '市場「震盪」，持有期間先不超過 D2');
    if (industryClass == IndustryClass.weakening || industryClass == IndustryClass.lagging) {
      cls = cap(cls, math.max(1, cls - 1), '所屬產業${industryClass!.label}，持有期間縮短一級');
    }
    if (conf == Confidence.low) cls = cap(cls, math.max(1, cls - 1), '信心度低，持有期間上限縮短一級');
    if (pv.state == PvState.distribution) cls = cap(cls, 1, '今天出現「下跌放量」，先以短線看待');
  }

  // 為什麼不是更長、升級／降級條件
  String whyNot;
  final up = <String>[];
  final down = <String>[];
  final e50 = facts.ema50, e20 = facts.ema20;
  switch (cls) {
    case 3:
      whyNot = 'D4（6～24 個月）以上要有公司品質、獲利成長、現金流的證據；目前還沒有基本面資料，技術面最多只能支持到 D3。';
      up.add('之後接上營收、財報資料，品質與獲利同步改善，才可能升級到 D4');
      down.add('收盤跌破 50 日線${ok(e50) ? ' ${_f(e50)}' : ''}、或產業轉弱、或 120 日相對強度掉出前 50% → 降為 D2');
    case 2:
      final miss = <String>[
        if (lv == null) '長期資料不足 200 天',
        if (lv != null && lv < 65) '長期分數 ${lv.toStringAsFixed(0)} 未達 65',
        if (mv < 65) '中期分數 ${mv.toStringAsFixed(0)} 未達 65',
        if (tp < 65) '趨勢持續性 ${tp.toStringAsFixed(0)} 未達 65',
        if ((rsScore ?? 0) < 65) '多期間相對強度平均未達前 35%',
        ...capped,
      ];
      whyNot = '還不是 D3：${miss.isEmpty ? '條件接近，需要再觀察' : miss.join('；')}';
      up.add('長期分數 ≥ 65、50 日線持續上揚、120／250 日相對強度進前 30% → 可升級 D3');
      down.add('收盤跌破 50 日線${ok(e50) ? ' ${_f(e50)}' : ''}或 60 日相對強度掉出前 50% → 降為 D1');
    case 1:
      final miss = <String>[
        if (mv < 60) '中期分數 ${mv.toStringAsFixed(0)} 未達 60',
        if (tp < 50) '趨勢持續性 ${tp.toStringAsFixed(0)} 未達 50',
        ...capped,
      ];
      whyNot = '還不是 D2：${miss.isEmpty ? '受市場或訊號類型限制' : miss.join('；')}';
      up.add('站穩 50 日線${ok(e50) ? ' ${_f(e50)}' : ''}且 50 日線上揚、60 日相對強度進前 30%、中期分數 ≥ 60 → 可升級 D2');
      down.add('跌破停損，或買進後 5～10 天沒有延續（時間停損）→ 出場');
    default:
      whyNot = '短中長都沒有足夠的持有理由。';
  }
  if (cls != null) up.add('升級只在「已經獲利」時才算數：虧損的短線不能因為不想停損就改成長抱');
  if (ok(e20) && cls == 1) down.add('收盤跌破 20 日線 ${_f(e20)} → 短線理由轉弱');

  final hard = switch (cls) {
    3 => long.invalidation,
    2 => medium.invalidation,
    1 => short.invalidation,
    _ => '—',
  };

  return DurationEstimate(
    cls: cls,
    confidence: conf,
    durationScore: dScore,
    evidence: evidence,
    why: why,
    capped: capped,
    whyNotHigher: whyNot,
    upgradeIf: up,
    downgradeIf: down,
    hardInvalidation: hard,
  );
}

/// 進場觸發條件（觀察池用）：還沒有訊號的好股票，什麼情況會變成可以買。
List<String> entryTriggers(StockSeries s, int i) {
  final out = <String>[];
  if (i < 21) return out;
  final hh20 = maxIn(s.high, i - 20, i - 1);
  final hh = math.max(hh20, s.high[i]);
  final e20 = s.ema20[i], e50 = s.ema50[i];
  final atr = ok(s.atr[i]) ? s.atr[i] : s.close[i] * 0.02;
  out.add('突破：收盤放量（≥ 1.5 倍均量）站上 20 日高點 ${_f(hh)}');
  if (ok(e20) && s.close[i] > e20) {
    out.add('回檔：拉回 20 日線 ${_f(e20)}～${_f(e20 + 0.3 * atr)} 附近量縮，再收盤站上前一天高點');
  } else if (ok(e50) && s.close[i] > e50) {
    out.add('回檔：守住 50 日線 ${_f(e50)}，量縮後重新站回 20 日線${ok(e20) ? ' ${_f(e20)}' : ''}');
  } else if (ok(e20)) {
    out.add('先重新站回 20 日線 ${_f(e20)}，趨勢轉強後再看');
  }
  return out;
}

/// 單一股票、不需要全市場資料的持有週期估計（持股每日追蹤用）：
/// 趨勢持續性＋相對大盤強弱＋價量持續性＋市場狀態。
(int, String) stockOnlyDuration(StockSeries s, int j, {Regime? regime, double? rel20, double? rel60}) {
  final tp = trendPersistenceOf(s, j);
  final pv = priceVolume(s, j);
  final r20 = rel20 ?? s.roc(j, 20);
  final r60 = rel60 ?? s.roc(j, 60);
  final rsOk = (ok(r20) && r20 > 0 ? 1 : 0) + (ok(r60) && r60 > 0 ? 1 : 0);
  final longOk = ok(s.sma240[j]) ? s.close[j] > s.sma240[j] : (ok(s.ema200[j]) && s.close[j] > s.ema200[j]);
  final mkt = regime == null || regime == Regime.strongBull || regime == Regime.bull;
  final e50 = s.ema50[j];
  final e50Up = j >= 10 && ok(e50) && ok(s.ema50[j - 10]) && e50 > s.ema50[j - 10];
  if (tp >= 70 && rsOk == 2 && pv.persistence >= 55 && longOk && mkt && !pv.state.bad) {
    return (3, '趨勢持續性 ${tp.toStringAsFixed(0)}、20 和 60 日都贏大盤、長期均線之上、資金累積');
  }
  if (ok(e50) && s.close[j] > e50 && e50Up && tp >= 50 && rsOk >= 1 && regime != Regime.bear) {
    return (2, '收盤在 50 日線之上且 50 日線上揚，相對大盤${rsOk == 2 ? '持續' : '部分'}領先');
  }
  final why = <String>[
    if (!(ok(e50) && s.close[j] > e50)) '收盤在 50 日線之下',
    if (ok(e50) && !e50Up) '50 日線沒有上揚',
    if (rsOk == 0) '20、60 日都輸大盤',
    if (regime == Regime.weak || regime == Regime.bear) '市場${regime!.label}',
    if (pv.state.bad) '量價${pv.state.label}',
  ];
  return (1, why.isEmpty ? '中期證據不足' : why.join('、'));
}
