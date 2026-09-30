import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/logic/technical_screen.dart';
import 'package:stock_screener/models/daily_bar.dart';

List<DailyBar> series(List<double> closes, {int vol = 1000, int? lastVol}) => [
      for (var i = 0; i < closes.length; i++)
        DailyBar(
          date: 'd${i.toString().padLeft(3, '0')}',
          open: closes[i],
          high: closes[i],
          low: closes[i],
          close: closes[i],
          volumeLots: i == closes.length - 1 && lastVol != null ? lastVol : vol,
        ),
    ];

final rising = [for (var i = 0; i < 70; i++) 100.0 + i];
final falling = [for (var i = 0; i < 70; i++) 200.0 - i];

void main() {
  test('多頭排列只留下一路往上的股票', () {
    final out = runScreen({'UP': series(rising), 'DOWN': series(falling)},
        const ScreenCriteria(bullishAlignment: true));
    expect(out.results.map((r) => r.code), ['UP']);
    expect(out.results.single.reasons.first, contains('多頭排列'));
  });

  test('資料天數不夠判斷條件的股票會被略過並計數', () {
    final out = runScreen({'NEW': series(rising.sublist(0, 30))}, const ScreenCriteria(aboveMa60: true));
    expect(out.results, isEmpty);
    expect(out.skippedShortHistory, 1);
  });

  test('均量下限過濾掉冷門股', () {
    final out = runScreen(
      {'HOT': series(rising, vol: 2000), 'COLD': series(rising, vol: 50)},
      const ScreenCriteria(minAvgVolLots: 500),
    );
    expect(out.results.map((r) => r.code), ['HOT']);
  });

  test('帶量突破：創 20 日新高而且量比 ≥ 1.5', () {
    final out = runScreen({
      'BREAK_VOL': series(rising, lastVol: 3000),
      'BREAK_NOVOL': series(rising),
      'NO_BREAK': series(falling, lastVol: 3000),
    }, const ScreenCriteria(breakoutDays: 20, minVolRatio: 1.5));
    expect(out.results.map((r) => r.code), ['BREAK_VOL']);
    expect(out.results.single.reasons.any((r) => r.contains('量比 3.0')), true);
  });

  test('RSI 上限：一路跌的 RSI 低、一路漲的被排除', () {
    final out = runScreen({'UP': series(rising), 'DOWN': series(falling)}, const ScreenCriteria(rsiMax: 30));
    expect(out.results.map((r) => r.code), ['DOWN']);
  });

  test('依今日漲幅由大到小排序', () {
    final a = [...List.filled(30, 100.0), 101.0];
    final b = [...List.filled(30, 100.0), 105.0];
    final out = runScreen({'A': series(a), 'B': series(b)}, const ScreenCriteria(minChangePct: 0.01));
    expect(out.results.map((r) => r.code), ['B', 'A']);
  });

  test('條件存檔再讀回來要一模一樣', () {
    const c = ScreenCriteria(
      aboveMa20: true,
      goldenCrossWithin: 3,
      rsiMin: 40,
      rsiMax: 60,
      minVolRatio: 1.5,
      breakoutDays: 20,
      minAvgVolLots: 1000,
      maxPrice: 100,
      sort: ScreenSort.volRatio,
    );
    expect(ScreenCriteria.fromJson(c.toJson()).toJson(), c.toJson());
  });

  test('copyWith 可以把條件改回不限（null），沒傳的欄位不變', () {
    const c = ScreenCriteria(rsiMax: 30, breakoutDays: 20);
    final d = c.copyWith(rsiMax: null);
    expect(d.rsiMax, isNull);
    expect(d.breakoutDays, 20);
  });

  test('每個預設條件都能跑，不會出錯', () {
    final data = {'UP': series(rising, lastVol: 5000), 'DOWN': series(falling)};
    for (final p in kScreenPresets) {
      expect(() => runScreen(data, p.criteria), returnsNormally, reason: p.name);
    }
  });
}
