import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/logic/engine/analysis.dart';
import 'package:stock_screener/logic/engine/backtest.dart';
import 'package:stock_screener/logic/engine/signals.dart';

import 'support/synthetic.dart';

void main() {
  final dates = tradingDays(300);
  final series = syntheticMarket(dates, stocks: 200, bias: 0.3);
  const breakAt = 250;
  series['2330'] = breakoutThenRally(dates, breakAt);
  final result = runBacktest(AnalysisInput(dates, series, const {}), const BacktestConfig());

  test('放量突破後大漲的股票：隔天開盤進場、先在 2R 出一半、整體賺錢', () {
    final t = result.trades.where((t) => t.code == '2330' && t.signalDate == dates[breakAt]).toList();
    expect(t, hasLength(1), reason: '應該在突破那天產生訊號');
    final trade = t.single;
    expect(trade.strategy, Strategy.breakout);
    expect(trade.entryDate, dates[breakAt + 1]);
    expect(trade.r, greaterThan(1));
    expect(trade.exitReason, contains('2R 先出一半'));
  });

  test('統計數字自洽', () {
    final s = result.overall;
    expect(s.n, result.trades.length);
    expect(s.winRate, inInclusiveRange(0, 1));
    if (result.equity.isNotEmpty) expect(result.equity.last.$2, closeTo(s.totalR, 1e-9));
    expect(result.mcDd95, greaterThanOrEqualTo(result.mcDdMedian));
    final sumByStrategy = result.byStrategy.values.fold(0, (a, b) => a + b.n);
    expect(sumByStrategy, s.n);
    expect(result.firstPart.n + result.secondPart.n, s.n);
  });

  test('R 倍數合理：開盤跌到停損附近的訊號不進場，不會出現誇張的 R', () {
    for (final t in result.trades) {
      expect(t.r.abs(), lessThan(40), reason: '${t.code} ${t.entryDate} R=${t.r}');
      expect(t.entry - t.stop, greaterThan(0));
    }
  });

  test('不偷看未來：每筆交易都是訊號日之後才進場', () {
    for (final t in result.trades) {
      expect(t.entryDate.compareTo(t.signalDate), greaterThan(0));
      expect(t.exitDate.compareTo(t.entryDate), greaterThanOrEqualTo(0));
    }
  });

  test('最大回撤：依序累加 R', () {
    expect(maxDrawdown([1, -1, -1, 2, -3]), 3);
    expect(maxDrawdown([1, 2, 3]), 0);
  });

  test('壓力測試（滑價×2、成本×1.5、晚一天進場）平均 R 不會比基本設定好很多', () {
    // 同一段資料，條件變差，結果不應該反而大幅變好
    expect(result.stressed.avgR, lessThanOrEqualTo(result.overall.avgR + 0.5));
  });
}
