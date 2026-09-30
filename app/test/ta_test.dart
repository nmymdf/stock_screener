import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/logic/adjust.dart';
import 'package:stock_screener/logic/ta.dart';
import 'package:stock_screener/models/daily_bar.dart';

import 'support/synthetic.dart';

void main() {
  test('EMA：第一個值是前 n 筆的平均，之後用 2/(n+1) 平滑', () {
    final e = emaSeries([1, 2, 3, 4, 5, 6], 3);
    expect(e[1].isNaN, true);
    expect(e[2], 2);
    expect(e[3], closeTo(4 * 0.5 + 2 * 0.5, 1e-12));
  });

  test('ATR：每天振幅固定 2、沒有跳空時 ATR = 2', () {
    final c = List<double>.generate(30, (i) => 100);
    final h = [for (final x in c) x + 1];
    final l = [for (final x in c) x - 1];
    final a = atrSeries(h, l, c);
    expect(a[29], closeTo(2, 1e-9));
  });

  test('ADX：一路上漲 +DI 大於 −DI、ADX 很高', () {
    final c = [for (var i = 0; i < 80; i++) 100.0 + i];
    final h = [for (final x in c) x + 0.5];
    final l = [for (final x in c) x - 0.5];
    final a = adxSeries(h, l, c);
    expect(a.diPlus[79], greaterThan(a.diMinus[79]));
    expect(a.adx[79], greaterThan(50));
  });

  test('MACD：一路上漲時 MACD > 0', () {
    final c = [for (var i = 0; i < 60; i++) 100.0 + i];
    final m = macdSeries(c);
    expect(m.macd[59], greaterThan(0));
    expect(m.signal[59].isNaN, false);
  });

  test('RSI 序列最後一個值跟單點版本一致', () {
    final c = [for (var i = 0; i < 40; i++) 100.0 + (i % 3 == 0 ? -1.5 : 1.0) * i / 10];
    final r = rsiSeries(c);
    expect(r[13].isNaN, true);
    expect(r[39], inInclusiveRange(0, 100));
  });

  test('KD、布林帶寬、OBV 算得出來', () {
    final d = tradingDays(60);
    final s = StockSeries('X', breakoutStock(d));
    expect(s.kd.k[59], inInclusiveRange(0, 100));
    expect(s.bbw[59], greaterThan(0));
    expect(s.obv[59], isNot(0));
  });

  group('還原權息', () {
    test('除息那天參考價比前一天收盤低，之前的價格等比例下修', () {
      final bars = [
        const DailyBar(date: 'd1', open: 100, high: 101, low: 99, close: 100, volumeLots: 1, change: 0),
        // 除息 5 元：參考價 95，收 96（漲 1）
        const DailyBar(date: 'd2', open: 95, high: 96, low: 95, close: 96, volumeLots: 1, change: 1),
      ];
      final adj = adjustForCorporateActions(bars);
      expect(adj[0].close, closeTo(95, 1e-9));
      expect(adj[1].close, 96);
      // 還原後的漲跌幅 = 真實的 1/95，不是假的 -4%
      expect(adj[1].close / adj[0].close - 1, closeTo(1 / 95, 1e-9));
    });

    test('平常日子（收盤 − 前收 = 漲跌價差）不調整；沒有漲跌價差的舊資料也不調整', () {
      final bars = [
        const DailyBar(date: 'd1', open: 100, high: 101, low: 99, close: 100, volumeLots: 1),
        const DailyBar(date: 'd2', open: 100, high: 103, low: 99, close: 102, volumeLots: 1, change: 2),
        const DailyBar(date: 'd3', open: 102, high: 103, low: 90, close: 92, volumeLots: 1),
      ];
      expect(identical(adjustForCorporateActions(bars), bars), true);
    });

    test('不合理的因子（資料錯誤）不調整', () {
      expect(
        corporateActionFactor(
          100,
          const DailyBar(date: 'd', open: 1, high: 1, low: 1, close: 30, volumeLots: 1, change: 1),
        ),
        isNull,
      );
    });
  });
}
