/// 個股評分（規格書 §7、§8、§10.1）：每個模組 0～100 分，每一分都列出是
/// 哪個條件給的，畫面上可以逐項展開看「為什麼是這個分數」。
library;

import '../ta.dart';

class ScoreItem {
  final String label;
  final double points;
  final double max;
  const ScoreItem(this.label, this.points, this.max);
  bool get hit => points >= max && max > 0;
}

class ModuleScore {
  final String key;
  final String name;
  final double weight; // 總分權重（§10.1）
  final double? score; // 0～100；null = 沒有資料，不列入總分
  final List<ScoreItem> items;
  final String summary;
  const ModuleScore(this.key, this.name, this.weight, this.score, this.items, this.summary);
}

/// 把逐項得分換算成 0～100；可用的滿分太少（資料不足）回傳 null。
double? _norm(List<ScoreItem> items, {double minMax = 30}) {
  final max = items.fold(0.0, (a, b) => a + b.max);
  if (max < minMax) return null;
  return items.fold(0.0, (a, b) => a + b.points) / max * 100;
}

String _f(double v) => v >= 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(2);

/// 趨勢（§7.1）：收盤相對 EMA20/50/100/200、均線排列、斜率、ADX+DI、MACD。
ModuleScore trendModule(StockSeries s, int i) {
  final c = s.close[i];
  final items = <ScoreItem>[];
  void add(bool? cond, double max, String label) {
    if (cond == null) return;
    items.add(ScoreItem(label, cond ? max : 0, max));
  }

  double? v(double x) => ok(x) ? x : null;
  final e20 = v(s.ema20[i]), e50 = v(s.ema50[i]), e100 = v(s.ema100[i]), e200 = v(s.ema200[i]);
  add(e20 == null ? null : c > e20, 15, '收盤在 EMA20 之上${e20 == null ? '' : '（${_f(e20)}）'}');
  add(e50 == null ? null : c > e50, 15, '收盤在 EMA50 之上${e50 == null ? '' : '（${_f(e50)}）'}');
  add(e100 == null ? null : c > e100, 10, '收盤在 EMA100 之上');
  add(e200 == null ? null : c > e200, 15, '收盤在 EMA200 之上（長期多頭）');
  add(e20 == null || e50 == null || e100 == null ? null : e20 > e50 && e50 > e100, 15, '均線多頭排列 EMA20 > 50 > 100');
  add(e50 == null || i < 10 || !ok(s.ema50[i - 10]) ? null : e50 > s.ema50[i - 10], 10, 'EMA50 上揚（跟 10 天前比）');
  final adx = s.adx.adx[i], dip = s.adx.diPlus[i], dim = s.adx.diMinus[i];
  if (ok(adx) && ok(dip) && ok(dim)) {
    add(adx >= 20 && dip > dim, 10, 'ADX ${adx.toStringAsFixed(0)} ≥ 20 且 +DI > −DI（有方向的上升趨勢）');
    add(adx >= 25 && dip > dim, 5, 'ADX ≥ 25（趨勢夠強）');
  }
  final m = s.macd.macd[i], sig = s.macd.signal[i];
  if (ok(m) && ok(sig)) add(m > sig && m > 0, 5, 'MACD 在訊號線之上且在零軸之上');
  final score = _norm(items, minMax: 40);
  return ModuleScore(
    'trend',
    '趨勢',
    15,
    score,
    items,
    score == null
        ? '資料不足'
        : score >= 70
        ? '趨勢明確向上'
        : (score >= 50 ? '趨勢偏多但不夠完整' : '趨勢偏弱'),
  );
}

/// 動能（§7.2）：RSI 用「順勢」解讀（50 以上是多頭區），不採用「30 以下必買」。
ModuleScore momentumModule(StockSeries s, int i) {
  final items = <ScoreItem>[];
  final r = s.rsi[i];
  if (ok(r)) {
    final pts = r >= 50 && r <= 75
        ? 30.0
        : (r > 75 && r <= 85 ? 20.0 : (r >= 40 && r < 50 ? 10.0 : (r > 85 ? 10.0 : 0.0)));
    items.add(ScoreItem('RSI ${r.toStringAsFixed(0)}（50～75 是健康的多頭區）', pts, 30));
  }
  final r20 = s.roc(i, 20), r60 = s.roc(i, 60), r5 = s.roc(i, 5);
  if (ok(r20)) items.add(ScoreItem('20 日報酬 ${r20.toStringAsFixed(1)}% > 0', r20 > 0 ? 20 : 0, 20));
  if (ok(r60)) items.add(ScoreItem('60 日報酬 ${r60.toStringAsFixed(1)}% > 0', r60 > 0 ? 20 : 0, 20));
  if (ok(r5)) items.add(ScoreItem('5 日報酬 ${r5.toStringAsFixed(1)}% > 0', r5 > 0 ? 5 : 0, 5));
  final h = s.macd.hist[i];
  if (ok(h) && i >= 3 && ok(s.macd.hist[i - 3])) {
    items.add(ScoreItem('MACD 柱體比 3 天前擴大', h > s.macd.hist[i - 3] ? 15 : 0, 15));
  }
  final k = s.kd.k[i], d = s.kd.d[i];
  if (ok(k) && ok(d)) {
    items.add(ScoreItem('KD：K ${k.toStringAsFixed(0)} > D ${d.toStringAsFixed(0)}（短線輔助，高檔鈍化不當賣訊）', k > d ? 10 : 0, 10));
  }
  final score = _norm(items);
  return ModuleScore(
    'momentum',
    '動能',
    10,
    score,
    items,
    score == null
        ? '資料不足'
        : score >= 70
        ? '動能強'
        : (score >= 45 ? '動能普通' : '動能弱'),
  );
}

/// 量價（§7.3）：上漲日量 vs 下跌日量、OBV、突破放量、回檔量縮。
ModuleScore volumeModule(StockSeries s, int i) {
  final items = <ScoreItem>[];
  if (i >= 21) {
    var up = 0.0, down = 0.0;
    for (var j = i - 19; j <= i; j++) {
      if (s.close[j] > s.close[j - 1]) up += s.vol[j];
      if (s.close[j] < s.close[j - 1]) down += s.vol[j];
    }
    items.add(
      ScoreItem('近 20 天上漲日的量 > 下跌日的量（${down == 0 ? '—' : (up / down).toStringAsFixed(1)} 倍）', up > down ? 30 : 0, 30),
    );
    items.add(ScoreItem('OBV 比 20 天前高（資金淨流入）', s.obv[i] > s.obv[i - 20] ? 25 : 0, 25));
    final avg = s.avgVolBefore(i, 20);
    final vr = avg > 0 ? s.vol[i] / avg : 0.0;
    final upDay = s.close[i] > s.close[i - 1];
    items.add(ScoreItem('今天量比 ${vr.toStringAsFixed(1)} 倍且收漲（價漲量增）', upDay && vr >= 1.5 ? 25 : 0, 25));
    final recent = avgIn(s.vol, i - 4, i);
    items.add(
      ScoreItem(
        '近 5 日量縮（< 20 日均量）且守在 EMA20 上（回檔量縮）',
        recent < avg && ok(s.ema20[i]) && s.close[i] > s.ema20[i] && !(upDay && vr >= 1.5) ? 20 : 0,
        20,
      ),
    );
  }
  final score = _norm(items);
  return ModuleScore(
    'volume',
    '量價',
    10,
    score,
    items,
    score == null
        ? '資料不足'
        : score >= 60
        ? '量價配合'
        : '量價普通',
  );
}

/// 突破（§8.1）：20／60／250 日新高、離 52 週高點的距離。
ModuleScore breakoutModule(StockSeries s, int i) {
  final items = <ScoreItem>[];
  final c = s.close[i];
  void hh(int w, double pts, String label) {
    if (i <= w) return;
    items.add(ScoreItem(label, c > maxIn(s.high, i - w, i - 1) ? pts : 0, pts));
  }

  hh(20, 30, '收盤創 20 日新高');
  hh(60, 25, '收盤創 60 日新高');
  hh(250, 30, '收盤創 250 日（52 週）新高');
  final look = i >= 250 ? 250 : (i >= 120 ? 120 : 0);
  if (look > 0) {
    final top = maxIn(s.high, i - look, i);
    final dist = (top - c) / top;
    items.add(ScoreItem('離 $look 日高點 ${(dist * 100).toStringAsFixed(1)}%（5% 以內）', dist <= 0.05 ? 15 : 0, 15));
  }
  final score = _norm(items);
  return ModuleScore(
    'breakout',
    '突破',
    5,
    score,
    items,
    score == null
        ? '資料不足'
        : score >= 50
        ? '位在新高附近'
        : '離高點還有距離',
  );
}

/// 波動壓縮與型態（§8.2、§8.3：型態只做加分）。
ModuleScore volatilityModule(StockSeries s, int i) {
  final items = <ScoreItem>[];
  final p = s.percentileOf(s.bbw, i, 120);
  if (ok(p)) {
    items.add(ScoreItem('布林帶寬在近 120 日 ${(p * 100).toStringAsFixed(0)}% 分位（≤ 25% 算壓縮）', p <= 0.25 ? 35 : 0, 35));
  }
  if (i >= 20 && ok(s.atr[i]) && ok(s.atr[i - 20])) {
    final a1 = s.atr[i] / s.close[i], a0 = s.atr[i - 20] / s.close[i - 20];
    items.add(
      ScoreItem(
        'ATR% 比 20 天前下降（${(a0 * 100).toStringAsFixed(1)}% → ${(a1 * 100).toStringAsFixed(1)}%）',
        a1 < a0 ? 25 : 0,
        25,
      ),
    );
  }
  if (i >= 7) {
    var nr7 = true;
    final r = s.high[i] - s.low[i];
    for (var j = i - 6; j < i; j++) {
      if (s.high[j] - s.low[j] <= r) nr7 = false;
    }
    items.add(ScoreItem('NR7：今天振幅是近 7 天最小', nr7 ? 20 : 0, 20));
    final inside = s.high[i] <= s.high[i - 1] && s.low[i] >= s.low[i - 1];
    items.add(ScoreItem('Inside Bar：今天高低都在昨天範圍內', inside ? 20 : 0, 20));
  }
  final score = _norm(items);
  return ModuleScore(
    'volatility',
    '波動／型態',
    5,
    score,
    items,
    score == null
        ? '資料不足'
        : score >= 50
        ? '波動收斂中，醞釀突破'
        : '沒有明顯壓縮',
  );
}

ModuleScore marketModule(double? score, String regimeLabel) => ModuleScore('market', '市場環境', 10, score, [
  if (score != null) ScoreItem('Market Score ${score.toStringAsFixed(0)}（$regimeLabel）', score, 100),
], score == null ? '資料不足' : regimeLabel);

ModuleScore industryModule(String? industry, double? score, String? cls) => ModuleScore('industry', '產業強弱', 10, score, [
  if (score != null) ScoreItem('$industry：產業分數 ${score.toStringAsFixed(0)}（$cls）', score, 100),
], industry == null ? 'ETF／ETN／特別股沒有產業分類，不列入' : (score == null ? '同產業樣本太少' : '$industry・$cls'));

const kFundamentalPending = ModuleScore('fundamental', '基本面', 15, null, [], '尚未接資料：需要月營收、財報（含實際公告日），之後版本再加入，目前不列入總分');
const kChipPending = ModuleScore('chip', '籌碼', 10, null, [], '尚未接資料：需要三大法人、融資融券，之後版本再加入，目前不列入總分');

/// 總分：可用模組依權重加權平均，沒資料的模組不列入（權重重新分配）。
double totalScore(List<ModuleScore> modules) {
  var s = 0.0, w = 0.0;
  for (final m in modules) {
    if (m.score == null) continue;
    s += m.score! * m.weight;
    w += m.weight;
  }
  return w == 0 ? 0 : s / w;
}
