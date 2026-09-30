/// 「技術選股」的篩選邏輯：用本機存好的每日收盤行情算指標，再依使用者勾的
/// 條件篩選。純函式，不碰網路、不碰畫面，方便寫測試。
///
/// 重要：這是機械化的條件篩選，不是預測未來會不會賺錢，也不是投資建議——
/// 沒有任何指標組合能保證篩出來的股票之後會漲，只是幫忙從兩千多檔裡縮小範圍。
library;

import '../models/daily_bar.dart';
import 'indicators.dart';

enum ScreenSort { changePct, volRatio, return20, rsi }

const Object _keep = Object();

extension ScreenSortLabel on ScreenSort {
  String get label => switch (this) {
    ScreenSort.changePct => '今日漲幅',
    ScreenSort.volRatio => '量比',
    ScreenSort.return20 => '近 20 日漲幅',
    ScreenSort.rsi => 'RSI',
  };
}

/// 篩選條件。每個條件都是可選的（null / false = 不限制），勾選的條件之間是「而且」。
class ScreenCriteria {
  final bool aboveMa20; // 收盤站上月線
  final bool aboveMa60; // 收盤站上季線
  final bool bullishAlignment; // 多頭排列：收盤 > MA5 > MA20 > MA60
  final int? goldenCrossWithin; // 最近 N 天內 MA5 黃金交叉 MA20
  final double? rsiMin;
  final double? rsiMax;
  final double? minVolRatio; // 量比下限，例如 1.5 = 比前 20 日均量多 5 成
  final int? breakoutDays; // 收盤創 N 日新高
  final double? minChangePct; // 今日漲幅下限（%）
  final double? minAvgVolLots; // 20 日均量下限（張），過濾冷門股
  final double? minPrice;
  final double? maxPrice;
  final ScreenSort sort;

  const ScreenCriteria({
    this.aboveMa20 = false,
    this.aboveMa60 = false,
    this.bullishAlignment = false,
    this.goldenCrossWithin,
    this.rsiMin,
    this.rsiMax,
    this.minVolRatio,
    this.breakoutDays,
    this.minChangePct,
    this.minAvgVolLots = 500,
    this.minPrice,
    this.maxPrice,
    this.sort = ScreenSort.changePct,
  });

  /// 改其中幾個條件。可以是 null 的欄位要「改成不限」時傳 null 進來，
  /// 沒傳的欄位維持原值（用 [_keep] 區分「沒傳」和「傳 null」）。
  ScreenCriteria copyWith({
    bool? aboveMa20,
    bool? aboveMa60,
    bool? bullishAlignment,
    Object? goldenCrossWithin = _keep,
    Object? rsiMin = _keep,
    Object? rsiMax = _keep,
    Object? minVolRatio = _keep,
    Object? breakoutDays = _keep,
    Object? minChangePct = _keep,
    Object? minAvgVolLots = _keep,
    Object? minPrice = _keep,
    Object? maxPrice = _keep,
    ScreenSort? sort,
  }) {
    T? pick<T>(Object? v, T? old) => identical(v, _keep) ? old : v as T?;
    return ScreenCriteria(
      aboveMa20: aboveMa20 ?? this.aboveMa20,
      aboveMa60: aboveMa60 ?? this.aboveMa60,
      bullishAlignment: bullishAlignment ?? this.bullishAlignment,
      goldenCrossWithin: pick(goldenCrossWithin, this.goldenCrossWithin),
      rsiMin: pick(rsiMin, this.rsiMin),
      rsiMax: pick(rsiMax, this.rsiMax),
      minVolRatio: pick(minVolRatio, this.minVolRatio),
      breakoutDays: pick(breakoutDays, this.breakoutDays),
      minChangePct: pick(minChangePct, this.minChangePct),
      minAvgVolLots: pick(minAvgVolLots, this.minAvgVolLots),
      minPrice: pick(minPrice, this.minPrice),
      maxPrice: pick(maxPrice, this.maxPrice),
      sort: sort ?? this.sort,
    );
  }

  /// 至少要幾天的歷史資料才能判斷這組條件（例如季線要 60 天）。
  int get requiredBars {
    var need = 2;
    if (aboveMa20 || minAvgVolLots != null || minVolRatio != null) need = 21;
    if (goldenCrossWithin != null) need = 21 + goldenCrossWithin!;
    if (aboveMa60 || bullishAlignment) need = need < 60 ? 60 : need;
    if (rsiMin != null || rsiMax != null) need = need < 15 ? 15 : need;
    if (breakoutDays != null && breakoutDays! + 1 > need) need = breakoutDays! + 1;
    return need;
  }

  Map<String, dynamic> toJson() => {
    'aboveMa20': aboveMa20,
    'aboveMa60': aboveMa60,
    'bullishAlignment': bullishAlignment,
    'goldenCrossWithin': goldenCrossWithin,
    'rsiMin': rsiMin,
    'rsiMax': rsiMax,
    'minVolRatio': minVolRatio,
    'breakoutDays': breakoutDays,
    'minChangePct': minChangePct,
    'minAvgVolLots': minAvgVolLots,
    'minPrice': minPrice,
    'maxPrice': maxPrice,
    'sort': sort.name,
  };

  static ScreenCriteria fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    int? i(String k) => (j[k] as num?)?.round();
    return ScreenCriteria(
      aboveMa20: j['aboveMa20'] as bool? ?? false,
      aboveMa60: j['aboveMa60'] as bool? ?? false,
      bullishAlignment: j['bullishAlignment'] as bool? ?? false,
      goldenCrossWithin: i('goldenCrossWithin'),
      rsiMin: d('rsiMin'),
      rsiMax: d('rsiMax'),
      minVolRatio: d('minVolRatio'),
      breakoutDays: i('breakoutDays'),
      minChangePct: d('minChangePct'),
      minAvgVolLots: d('minAvgVolLots'),
      minPrice: d('minPrice'),
      maxPrice: d('maxPrice'),
      sort: ScreenSort.values.firstWhere((s) => s.name == j['sort'], orElse: () => ScreenSort.changePct),
    );
  }
}

/// 預設的幾組常見條件，一鍵套用後還可以再自己調整。
class ScreenPreset {
  final String name;
  final String description;
  final ScreenCriteria criteria;
  const ScreenPreset(this.name, this.description, this.criteria);
}

const List<ScreenPreset> kScreenPresets = [
  ScreenPreset(
    '多頭排列',
    '收盤 > 5 日線 > 20 日線 > 60 日線，中短期趨勢都往上',
    ScreenCriteria(bullishAlignment: true, sort: ScreenSort.return20),
  ),
  ScreenPreset(
    '帶量突破',
    '收盤創 20 日新高，而且成交量是前 20 日均量的 1.5 倍以上',
    ScreenCriteria(breakoutDays: 20, minVolRatio: 1.5, sort: ScreenSort.volRatio),
  ),
  ScreenPreset('黃金交叉', '最近 3 天內 5 日線由下往上穿過 20 日線', ScreenCriteria(goldenCrossWithin: 3, sort: ScreenSort.changePct)),
  ScreenPreset('RSI 超賣', 'RSI(14) 低於 30，短線跌深（跌深不代表會反彈，只是列出來）', ScreenCriteria(rsiMax: 30, sort: ScreenSort.rsi)),
  ScreenPreset(
    '量能爆發',
    '今天上漲，而且成交量是前 20 日均量的 2 倍以上',
    ScreenCriteria(minChangePct: 0.01, minVolRatio: 2, sort: ScreenSort.volRatio),
  ),
];

class ScreenResult {
  final IndicatorSnapshot ind;
  final List<String> reasons;

  const ScreenResult(this.ind, this.reasons);

  String get code => ind.code;
}

class ScreenOutcome {
  final List<ScreenResult> results;
  final int scanned; // 有歷史資料的股票數
  final int skippedShortHistory; // 資料天數不夠判斷條件而略過的股票數

  const ScreenOutcome(this.results, this.scanned, this.skippedShortHistory);
}

/// 對每一檔股票套用條件，回傳符合的股票和每一檔符合的理由。
ScreenOutcome runScreen(Map<String, List<DailyBar>> seriesByCode, ScreenCriteria c) {
  final out = <ScreenResult>[];
  var skipped = 0;
  final need = c.requiredBars;
  for (final e in seriesByCode.entries) {
    final series = e.value;
    if (series.length < need) {
      skipped++;
      continue;
    }
    final ind = IndicatorSnapshot.compute(e.key, series);
    if (ind == null) continue;
    final reasons = _match(ind, series, c);
    if (reasons != null) out.add(ScreenResult(ind, reasons));
  }

  double key(ScreenResult r) => switch (c.sort) {
    ScreenSort.changePct => r.ind.changePct ?? double.negativeInfinity,
    ScreenSort.volRatio => r.ind.volRatio ?? double.negativeInfinity,
    ScreenSort.return20 => r.ind.return20Pct ?? double.negativeInfinity,
    // RSI 由低排到高：超賣條件時最低的排最前面
    ScreenSort.rsi => -(r.ind.rsi14 ?? double.infinity),
  };
  out.sort((a, b) => key(b).compareTo(key(a)));
  return ScreenOutcome(out, seriesByCode.length, skipped);
}

/// 符合所有條件就回傳理由清單，任何一個不符合就回傳 null。
List<String>? _match(IndicatorSnapshot ind, List<DailyBar> series, ScreenCriteria c) {
  final reasons = <String>[];
  String n2(double v) => v.toStringAsFixed(2);

  if (c.minAvgVolLots != null) {
    final avg = ind.avgVol20;
    if (avg == null || avg < c.minAvgVolLots!) return null;
  }
  if (c.minPrice != null && ind.close < c.minPrice!) return null;
  if (c.maxPrice != null && ind.close > c.maxPrice!) return null;

  if (c.minChangePct != null) {
    final ch = ind.changePct;
    if (ch == null || ch < c.minChangePct!) return null;
    reasons.add('今日${ch >= 0 ? '上漲' : '下跌'} ${n2(ch.abs())}%');
  }
  if (c.aboveMa20) {
    if (ind.ma20 == null || ind.close <= ind.ma20!) return null;
    reasons.add('站上 20 日線（${n2(ind.ma20!)}）');
  }
  if (c.aboveMa60) {
    if (ind.ma60 == null || ind.close <= ind.ma60!) return null;
    reasons.add('站上 60 日線（${n2(ind.ma60!)}）');
  }
  if (c.bullishAlignment) {
    final m5 = ind.ma5, m20 = ind.ma20, m60 = ind.ma60;
    if (m5 == null || m20 == null || m60 == null) return null;
    if (!(ind.close > m5 && m5 > m20 && m20 > m60)) return null;
    reasons.add('多頭排列（收 > 5日 > 20日 > 60日線）');
  }
  if (c.goldenCrossWithin != null) {
    final closes = [for (final b in series) b.close];
    final ago = goldenCrossDaysAgo(closes, within: c.goldenCrossWithin!);
    if (ago == null) return null;
    reasons.add(ago == 0 ? '今天 5 日線黃金交叉 20 日線' : '$ago 天前 5 日線黃金交叉 20 日線');
  }
  if (c.rsiMin != null || c.rsiMax != null) {
    final r = ind.rsi14;
    if (r == null) return null;
    if (c.rsiMin != null && r < c.rsiMin!) return null;
    if (c.rsiMax != null && r > c.rsiMax!) return null;
    reasons.add('RSI(14) ${r.toStringAsFixed(1)}');
  }
  if (c.breakoutDays != null) {
    final closes = [for (final b in series) b.close];
    if (!isBreakout(closes, c.breakoutDays!)) return null;
    reasons.add('收盤創 ${c.breakoutDays} 日新高');
  }
  if (c.minVolRatio != null) {
    final vr = ind.volRatio;
    if (vr == null || vr < c.minVolRatio!) return null;
    reasons.add('量比 ${vr.toStringAsFixed(1)} 倍（${ind.volumeLots} 張）');
  }
  if (reasons.isEmpty) reasons.add('符合流動性/價格條件');
  return reasons;
}
