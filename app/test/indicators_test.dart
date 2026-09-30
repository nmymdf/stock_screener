import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/logic/indicators.dart';
import 'package:stock_screener/models/daily_bar.dart';

List<DailyBar> bars(List<double> closes, {List<int>? vols}) => [
  for (var i = 0; i < closes.length; i++)
    DailyBar(
      date: '2026-01-${(i + 1).toString().padLeft(2, '0')}',
      open: closes[i],
      high: closes[i],
      low: closes[i],
      close: closes[i],
      volumeLots: vols?[i] ?? 1000,
    ),
];

void main() {
  test('sma 算最後 N 筆的平均，資料不夠回傳 null', () {
    expect(sma([1, 2, 3, 4, 5], 3), 4);
    expect(sma([1, 2, 3, 4, 5], 3, endOffset: 1), 3);
    expect(sma([1, 2], 3), isNull);
  });

  test('RSI：一路上漲是 100，一路下跌是 0，資料不夠回傳 null', () {
    final up = [for (var i = 0; i < 20; i++) 100.0 + i];
    final down = [for (var i = 0; i < 20; i++) 100.0 - i];
    expect(rsi(up), 100);
    expect(rsi(down), closeTo(0, 1e-9));
    expect(rsi(up.sublist(0, 14)), isNull);
  });

  test('RSI 跟 Wilder 公式手算的結果一致', () {
    // 前 14 天漲跌交替（+1, -1），平均漲 = 平均跌 = 0.5 → RSI 50
    final closes = <double>[100];
    for (var i = 0; i < 14; i++) {
      closes.add(closes.last + (i.isEven ? 1 : -1));
    }
    expect(rsi(closes), closeTo(50, 1e-9));
    // 再漲 1：avgGain = (0.5*13+1)/14, avgLoss = 0.5*13/14
    closes.add(closes.last + 1);
    const g = (0.5 * 13 + 1) / 14, l = 0.5 * 13 / 14;
    expect(rsi(closes), closeTo(100 - 100 / (1 + g / l), 1e-9));
  });

  test('量比是今天跟「前 N 天（不含今天）」平均比', () {
    final v = [for (var i = 0; i < 20; i++) 100.0, 300.0];
    expect(ratioToPriorAverage(v, 20), 3);
  });

  test('創 N 日新高：要嚴格大於前 N 天的最高', () {
    expect(isBreakout([10, 12, 11, 13], 3), true);
    expect(isBreakout([10, 13, 11, 13], 3), false);
    expect(isBreakout([10, 13], 3), false); // 資料不夠
  });

  test('黃金交叉：5 日線由下往上穿過 20 日線', () {
    // 先跌 25 天讓 5 日線在 20 日線下面，最後兩天急漲讓 5 日線翻上去
    final closes = [for (var i = 0; i < 25; i++) 100.0 - i, 110.0, 125.0];
    final ago = goldenCrossDaysAgo(closes, within: 3);
    expect(ago, isNotNull);
    // 一路跌就不會有交叉
    expect(goldenCrossDaysAgo([for (var i = 0; i < 30; i++) 100.0 - i]), isNull);
  });

  test('IndicatorSnapshot 算出漲跌幅、均線、量比', () {
    final closes = [for (var i = 0; i < 61; i++) 100.0 + i];
    final vols = [for (var i = 0; i < 61; i++) i == 60 ? 2000 : 1000];
    final ind = IndicatorSnapshot.compute('TEST', bars(closes, vols: vols))!;
    expect(ind.close, 160);
    expect(ind.changePct, closeTo(1 / 159 * 100, 1e-9));
    expect(ind.ma5, 158);
    expect(ind.ma60, closeTo(130.5, 1e-9));
    expect(ind.volRatio, 2);
    expect(ind.avgVol20, 1000);
    expect(ind.return20Pct, closeTo(20 / 140 * 100, 1e-9));
  });
}
