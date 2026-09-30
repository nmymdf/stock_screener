import 'dart:math' as math;

import 'package:stock_screener/data/history_store.dart' show ymd;
import 'package:stock_screener/data/stock_industry.dart';
import 'package:stock_screener/models/daily_bar.dart';

/// 產生 [days] 個交易日（週一～週五）的日期。
List<String> tradingDays(int days, {DateTime? start}) {
  final out = <String>[];
  var d = start ?? DateTime.utc(2025, 6, 2);
  while (out.length < days) {
    if (d.weekday <= 5) out.add(ymd(d));
    d = d.add(const Duration(days: 1));
  }
  return out;
}

DailyBar bar(String date, double c, {double? o, double? h, double? l, int v = 2000, double? change}) => DailyBar(
  date: date,
  open: o ?? c,
  high: h ?? math.max(c, o ?? c) * 1.005,
  low: l ?? math.min(c, o ?? c) * 0.995,
  close: c,
  volumeLots: v,
  change: change,
);

/// 一檔「長期上漲 → 窄幅整理 → 最後一天放量突破」的股票（策略 A 的教科書範例）。
List<DailyBar> breakoutStock(List<String> dates) {
  final n = dates.length;
  final out = <DailyBar>[];
  final rnd = math.Random(7);
  for (var i = 0; i < n - 1; i++) {
    final base = i < n - 41 ? 50 + 50 * i / (n - 41) : 100.0;
    final c = base * (1 + (rnd.nextDouble() - 0.5) * 0.01);
    out.add(bar(dates[i], c, v: i < n - 41 ? 2000 : 1500));
  }
  out.add(bar(dates[n - 1], 106, o: 100.5, h: 106.5, l: 100, v: 6000));
  return out;
}

/// 用一般股票的代號（有產業別）產生隨機漫步的全市場資料。
Map<String, List<DailyBar>> syntheticMarket(List<String> dates, {int stocks = 150, int seed = 1, double bias = 0.45}) {
  final rnd = math.Random(seed);
  final codes = kIndustryIndexByCode.keys.take(stocks).toList();
  final out = <String, List<DailyBar>>{};
  for (final code in codes) {
    final drift = (rnd.nextDouble() - bias) * 0.003;
    var c = 20 + rnd.nextDouble() * 200;
    final bars = <DailyBar>[];
    for (final d in dates) {
      final o = c;
      c = c * (1 + drift + (rnd.nextDouble() - 0.5) * 0.04);
      final h = math.max(o, c) * (1 + rnd.nextDouble() * 0.01);
      final l = math.min(o, c) * (1 - rnd.nextDouble() * 0.01);
      bars.add(DailyBar(date: d, open: o, high: h, low: l, close: c, volumeLots: 800 + rnd.nextInt(4000)));
    }
    out[code] = bars;
  }
  return out;
}

/// 陡升 → 20 天窄幅整理 → 第 [breakAt] 天放量突破 → 之後每天漲 1.5%。
List<DailyBar> breakoutThenRally(List<String> dates, int breakAt) {
  final rnd = math.Random(3);
  final out = <DailyBar>[];
  final baseStart = breakAt - 20;
  for (var i = 0; i < dates.length; i++) {
    if (i < baseStart) {
      final c = 30 + 70 * i / baseStart;
      out.add(bar(dates[i], c, h: c * 1.01, l: c * 0.99));
    } else if (i < breakAt) {
      final c = 100 * (1 + (rnd.nextDouble() - 0.5) * 0.02);
      out.add(bar(dates[i], c, h: c * 1.01, l: c * 0.99, v: 1500));
    } else if (i == breakAt) {
      out.add(bar(dates[i], 104, o: 101, h: 104.5, l: 100.8, v: 5000));
    } else {
      final prev = out.last.close;
      final c = prev * 1.015;
      out.add(bar(dates[i], c, o: prev, h: c * 1.005, l: prev * 0.998, v: 3000));
    }
  }
  return out;
}
