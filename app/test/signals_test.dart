import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/data/stock_industry.dart';
import 'package:stock_screener/logic/engine/signals.dart';
import 'package:stock_screener/logic/ta.dart';

import 'support/synthetic.dart';

void main() {
  test('A 突破型：長期上漲、窄幅整理後放量突破會被抓到', () {
    final s = StockSeries('X', breakoutStock(tradingDays(300)));
    final hit = detectBreakout(s, s.length - 1);
    expect(hit, isNotNull);
    expect(hit!.strategy, Strategy.breakout);
    expect(hit.structuralStop, lessThan(s.close.last));
    // 前一天（還沒突破）不會觸發
    expect(detectBreakout(s, s.length - 2), isNull);
  });

  test('交易計畫：停損在進場價下方、目標 2R、價格都對齊 tick', () {
    final s = StockSeries('X', breakoutStock(tradingDays(300)));
    final i = s.length - 1;
    final plan = buildPlan(s, i, detectBreakout(s, i)!, SecurityType.stock);
    expect(plan.stop, lessThan(plan.entry));
    expect(plan.target, greaterThanOrEqualTo(plan.entry + 2 * plan.risk - 0.5));
    // 100～500 元的股票 tick 是 0.5
    expect((plan.stop / 0.5) % 1, closeTo(0, 1e-9));
    expect((plan.target / 0.5) % 1, closeTo(0, 1e-9));
    expect(plan.maxEntry, greaterThan(plan.entry));
  });

  test('tick size：股票與 ETF 不同', () {
    expect(tickSize(9.5, SecurityType.stock), 0.01);
    expect(tickSize(45, SecurityType.stock), 0.05);
    expect(tickSize(88, SecurityType.stock), 0.1);
    expect(tickSize(300, SecurityType.stock), 0.5);
    expect(tickSize(800, SecurityType.stock), 1);
    expect(tickSize(1200, SecurityType.stock), 5);
    expect(tickSize(45, SecurityType.etf), 0.01);
    expect(tickSize(180, SecurityType.etf), 0.05);
    expect(roundDownTick(123.7, SecurityType.stock), 123.5);
    expect(roundUpTick(123.2, SecurityType.stock), 123.5);
    expect(roundDownTick(1012, SecurityType.stock), 1010);
  });
}
