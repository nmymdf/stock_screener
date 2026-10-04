/// 持股的股利收入（估算）：每次除權息前一天收盤時持有的股數 × 每股權值＋息值。
///
/// 上市股票用證交所公布的除權息；上櫃、ETF 用每日行情的參考價推算（前一天收盤 − 參考價）。
library;

import '../core/sources.dart';
import '../models/daily_bar.dart';
import '../models/holding.dart';

class DividendItem {
  final String date;
  final int shares;
  final double perShare;
  final bool cash;
  const DividendItem(this.date, this.shares, this.perShare, this.cash);
  double get amount => shares * perShare;
}

/// 從每日行情推算除權息：交易所的漲跌價差是跟參考價比，參考價比前一天收盤低就是除權息。
List<DivEvent> derivedDividends(List<DailyBar> raw) {
  final out = <DivEvent>[];
  for (var i = 1; i < raw.length; i++) {
    final b = raw[i], prev = raw[i - 1].close;
    final chg = b.change;
    if (chg == null || prev <= 0) continue;
    if ((b.close - prev - chg).abs() < 0.006) continue;
    final ref = b.close - chg;
    final f = ref / prev;
    if (ref <= 0 || f < 0.5 || f >= 0.999) continue; // 參考價比較高的（減資等）不算股利
    out.add(DivEvent(b.date, prev, ref, double.parse((prev - ref).toStringAsFixed(4)), '息'));
  }
  return out;
}

/// 這筆持股（從第一次買進到現在、或到賣光）領到的股利。
List<DividendItem> dividendIncome(Holding h, List<DivEvent> events) {
  if (h.buys.isEmpty) return const [];
  final first = h.firstBuyDate;
  final out = <DividendItem>[];
  for (final e in events) {
    if (e.date.compareTo(first) <= 0) continue;
    // 除息日前一天收盤持有的才領得到：除息日當天以前（不含）的買賣
    final shares =
        h.buys.where((b) => b.date.compareTo(e.date) < 0).fold<int>(0, (a, b) => a + b.shares) -
        h.sells.where((s) => s.date.compareTo(e.date) < 0).fold<int>(0, (a, b) => a + b.shares);
    if (shares <= 0) continue;
    out.add(DividendItem(e.date, shares, e.value, e.cash));
  }
  return out;
}
