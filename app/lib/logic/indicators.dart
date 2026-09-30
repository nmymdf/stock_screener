/// 技術指標：均線、RSI、量比、區間新高……全部是純函式，不碰網路、不碰畫面，
/// 方便寫測試。輸入的序列一律是「舊 → 新」排序，最後一筆是最新的交易日。
library;

import '../models/daily_bar.dart';

/// 最後 [n] 筆的簡單平均；資料不足 [n] 筆時回傳 null。
double? sma(List<double> values, int n, {int endOffset = 0}) {
  final end = values.length - endOffset;
  if (n <= 0 || end < n) return null;
  var sum = 0.0;
  for (var i = end - n; i < end; i++) {
    sum += values[i];
  }
  return sum / n;
}

/// Wilder 平滑法的 RSI（一般看盤軟體用的算法）。至少要 [period] + 1 筆收盤價。
double? rsi(List<double> closes, {int period = 14}) {
  if (closes.length < period + 1) return null;
  var gain = 0.0;
  var loss = 0.0;
  for (var i = 1; i <= period; i++) {
    final d = closes[i] - closes[i - 1];
    if (d > 0) {
      gain += d;
    } else {
      loss -= d;
    }
  }
  var avgGain = gain / period;
  var avgLoss = loss / period;
  for (var i = period + 1; i < closes.length; i++) {
    final d = closes[i] - closes[i - 1];
    avgGain = (avgGain * (period - 1) + (d > 0 ? d : 0)) / period;
    avgLoss = (avgLoss * (period - 1) + (d < 0 ? -d : 0)) / period;
  }
  if (avgLoss == 0) return avgGain == 0 ? 50 : 100;
  final rs = avgGain / avgLoss;
  return 100 - 100 / (1 + rs);
}

/// 最新一筆和「前 [n] 筆（不含最新一筆）」平均的比值，例如量比。
double? ratioToPriorAverage(List<double> values, int n) {
  final avg = sma(values, n, endOffset: 1);
  if (avg == null || avg == 0) return null;
  return values.last / avg;
}

/// 最新一筆是否大於前 [n] 筆（不含最新一筆）的最高值——「創 N 日新高」。
bool isBreakout(List<double> values, int n) {
  if (values.length < n + 1) return false;
  var prevMax = double.negativeInfinity;
  for (var i = values.length - 1 - n; i < values.length - 1; i++) {
    if (values[i] > prevMax) prevMax = values[i];
  }
  return values.last > prevMax;
}

/// 最近 [within] 天內，短均線是否由下往上穿過長均線（黃金交叉），
/// 而且到最新一天仍在長均線之上。回傳是幾天前交叉的（0 = 今天），沒有則 null。
int? goldenCrossDaysAgo(List<double> closes, {int fast = 5, int slow = 20, int within = 3}) {
  for (var ago = 0; ago < within; ago++) {
    final fNow = sma(closes, fast, endOffset: ago);
    final sNow = sma(closes, slow, endOffset: ago);
    final fPrev = sma(closes, fast, endOffset: ago + 1);
    final sPrev = sma(closes, slow, endOffset: ago + 1);
    if (fNow == null || sNow == null || fPrev == null || sPrev == null) return null;
    if (fPrev <= sPrev && fNow > sNow) {
      final fLast = sma(closes, fast)!;
      final sLast = sma(closes, slow)!;
      return fLast > sLast ? ago : null;
    }
  }
  return null;
}

/// 一檔股票最新一天的各項指標，篩選條件和個股頁都用這一份。
class IndicatorSnapshot {
  final String code;
  final String date;
  final int bars; // 有幾天的歷史資料
  final double close;
  final double? changePct; // 跟前一個交易日收盤比
  final int volumeLots;
  final double? ma5;
  final double? ma10;
  final double? ma20;
  final double? ma60;
  final double? rsi14;
  final double? avgVol20; // 前 20 日平均張數（不含今天）
  final double? volRatio; // 今天張數 ÷ 前 20 日平均
  final double? return20Pct; // 近 20 個交易日漲跌幅

  const IndicatorSnapshot({
    required this.code,
    required this.date,
    required this.bars,
    required this.close,
    required this.changePct,
    required this.volumeLots,
    required this.ma5,
    required this.ma10,
    required this.ma20,
    required this.ma60,
    required this.rsi14,
    required this.avgVol20,
    required this.volRatio,
    required this.return20Pct,
  });

  static IndicatorSnapshot? compute(String code, List<DailyBar> series) {
    if (series.isEmpty) return null;
    final closes = [for (final b in series) b.close];
    final vols = [for (final b in series) b.volumeLots.toDouble()];
    final last = series.last;
    final prev = series.length >= 2 ? series[series.length - 2].close : null;
    final base20 = series.length >= 21 ? series[series.length - 21].close : null;
    return IndicatorSnapshot(
      code: code,
      date: last.date,
      bars: series.length,
      close: last.close,
      changePct: prev == null || prev == 0 ? null : (last.close - prev) / prev * 100,
      volumeLots: last.volumeLots,
      ma5: sma(closes, 5),
      ma10: sma(closes, 10),
      ma20: sma(closes, 20),
      ma60: sma(closes, 60),
      rsi14: rsi(closes),
      avgVol20: sma(vols, 20, endOffset: 1),
      volRatio: ratioToPriorAverage(vols, 20),
      return20Pct: base20 == null || base20 == 0 ? null : (last.close - base20) / base20 * 100,
    );
  }
}
