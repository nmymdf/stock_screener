/// 還原權息（規格書 §14「除權息：技術分析歷史資料應使用一致的調整方法，避免
/// 假跌幅造成指標失真」）。
///
/// 原理：交易所公布的「漲跌價差」是跟當天參考價比。平常參考價 = 前一天收盤，
/// 所以「收盤 − 前一天收盤」會剛好等於漲跌價差；除權息那天參考價比前一天收盤
/// 低（扣掉股利），兩者就對不起來。用 參考價 ÷ 前一天收盤 當還原因子，把那天
/// 以前的所有價格等比例往下調，均線、報酬率、新高這些指標就不會被除息的假跌幅
/// 誤導。最新一天的價格不變（是「向前還原」）。
library;

import '../models/daily_bar.dart';

/// 這根 K 棒相對前一天收盤有沒有除權息（或減資等）事件；有的話回傳還原因子。
double? corporateActionFactor(double prevClose, DailyBar bar) {
  final chg = bar.change;
  if (chg == null || prevClose <= 0) return null;
  // 收盤 − 前一天收盤 等於 漲跌價差 → 參考價就是前一天收盤，沒有事件
  if ((bar.close - prevClose - chg).abs() < 0.006) return null;
  final ref = bar.close - chg;
  if (ref <= 0) return null;
  final f = ref / prevClose;
  // 太離譜的比例多半是資料錯誤，寧可不還原
  if (f < 0.5 || f > 2 || (f - 1).abs() < 0.001) return null;
  return f;
}

/// 回傳還原後的新序列（舊 → 新）。沒有任何事件時直接回傳原本的 list。
List<DailyBar> adjustForCorporateActions(List<DailyBar> bars) {
  if (bars.length < 2) return bars;
  final cum = List<double>.filled(bars.length, 1.0);
  var f = 1.0;
  var any = false;
  for (var i = bars.length - 1; i >= 1; i--) {
    final e = corporateActionFactor(bars[i - 1].close, bars[i]);
    if (e != null) {
      f *= e;
      any = true;
    }
    cum[i - 1] = f;
  }
  if (!any) return bars;
  return [for (var i = 0; i < bars.length; i++) cum[i] == 1.0 ? bars[i] : bars[i].scaled(cum[i])];
}
