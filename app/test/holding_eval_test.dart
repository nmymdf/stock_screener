import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/data/stock_industry.dart';
import 'package:stock_screener/logic/engine/market_engine.dart';
import 'package:stock_screener/logic/holding_eval.dart';
import 'package:stock_screener/models/daily_bar.dart';
import 'package:stock_screener/models/holding.dart';

import 'support/synthetic.dart';

/// 每天振幅 ±1% 的日 K（ATR 大約是價格的 2%）。
List<DailyBar> barsOf(List<String> dates, List<num> closes) => [
  for (var i = 0; i < closes.length; i++)
    DailyBar(
      date: dates[i],
      open: closes[i].toDouble(),
      high: closes[i] * 1.01,
      low: closes[i] * 0.99,
      close: closes[i].toDouble(),
      volumeLots: 2000,
    ),
];

Holding holding(
  String date,
  double price,
  HoldStyle style, {
  int shares = 1000,
  List<SellLot> sells = const [],
  double? manualStop,
  double? manualTarget,
}) => Holding(
  id: 'x',
  code: '2330',
  style: style,
  buys: [BuyLot(date, price, shares)],
  sells: sells,
  manualStop: manualStop,
  manualTarget: manualTarget,
);

HoldingEval eval(Holding h, List<DailyBar> bars, {Regime? regime, String? newSignal}) =>
    evaluateHolding(h, adjusted: bars, raw: bars, regime: regime, newSignal: newSignal);

void main() {
  final dates = tradingDays(120);
  // 前 40 天在 100 附近，讓 ATR 穩定
  final base = [for (var i = 0; i < 40; i++) 100.0];

  test('短線：收盤跌破「進場價 − 2 ATR」就停損，並寫出哪一天、什麼價格', () {
    final closes = [...base, 99, 98, 97, 95, 94];
    final r = eval(holding(dates[39], 100, HoldStyle.short), barsOf(dates, closes));
    expect(r.state, HoldState.stopLoss);
    expect(r.stop, closeTo(96, 0.3)); // 100 − 2 × ATR(≈2)
    expect(r.triggerDate, dates[43]);
    expect(r.headline, contains('跌破停損'));
  });

  test('短線：漲到 2R 提醒先賣一半；記錄賣出後回到保留，停損在成本以上', () {
    // ATR ≈ 2 → 停損 96、1R = 4、2R 目標 108
    final up = [...base, 102.0, 104, 106, 107, 108, 109];
    final h = holding(dates[39], 100, HoldStyle.short);
    final r = eval(h, barsOf(dates, up));
    expect(r.state, HoldState.exit);
    expect(r.headline, contains('先賣一半'));
    final sold = h.copyWith(sells: [SellLot(dates[45], 105, 500)]);
    final r2 = eval(sold, barsOf(dates, up));
    expect(r2.halfDone, true);
    expect(r2.state, isNot(HoldState.exit));
    expect(r2.stop, greaterThanOrEqualTo(100));
  });

  test('短線：10 個交易日還沒 +1R 就時間停損', () {
    final flat = [...base, for (var i = 0; i < 12; i++) 100.5];
    final r = eval(holding(dates[39], 100, HoldStyle.short), barsOf(dates, flat));
    expect(r.state, HoldState.exit);
    expect(r.headline, contains('時間停損'));
  });

  test('波段：漲到 +1R 後拉回，停損已在成本以上，是「出場」不是「停損」', () {
    final closes = [...base, 102.0, 104, 106, 103, 101, 99.5];
    final r = eval(holding(dates[39], 100, HoldStyle.swing), barsOf(dates, closes));
    expect(r.state, HoldState.exit);
    expect(r.stop, greaterThanOrEqualTo(100));
    expect(r.headline, anyOf(contains('保本'), contains('移動停利')));
  });

  test('波段：一路上漲後回落超過 3 ATR，是移動停利、停損在成本之上', () {
    final closes = [...base, for (var i = 1; i <= 20; i++) 100.0 + i * 2, 125, 120, 115];
    final r = eval(holding(dates[39], 100, HoldStyle.swing), barsOf(dates, closes));
    expect(r.state, HoldState.exit);
    expect(r.headline, contains('移動停利'));
    expect(r.stop, greaterThan(100));
  });

  test('停損只會往上、不會往下', () {
    final closes = [...base, for (var i = 1; i <= 15; i++) 100.0 + (i.isEven ? i : -i * 0.2) + i];
    final r = eval(holding(dates[39], 100, HoldStyle.swing), barsOf(dates, closes));
    final path = r.stopPath.whereType<double>().toList();
    for (var i = 1; i < path.length; i++) {
      expect(path[i], greaterThanOrEqualTo(path[i - 1] - 1e-9));
    }
  });

  test('長期：收盤連續 3 天在季線下、季線往下彎才出場；中間只是注意', () {
    final rise = [for (var i = 0; i < 80; i++) 100.0 + i];
    final fall = [for (var i = 1; i <= 30; i++) 179.0 - i * 2.0];
    final r = eval(holding(dates[79], 179, HoldStyle.long), barsOf(dates, [...rise, ...fall]));
    expect(r.state, anyOf(HoldState.exit, HoldState.stopLoss));
    expect(r.headline, anyOf(contains('季線'), contains('跌破停損')));
  });

  test('自己設定：跌破你設的停損就停損、碰到目標就提醒獲利了結', () {
    final down = [...base, 98.0, 96, 94];
    expect(
      eval(holding(dates[39], 100, HoldStyle.custom, manualStop: 95), barsOf(dates, down)).state,
      HoldState.stopLoss,
    );
    final up = [...base, 103.0, 106, 109];
    final r = eval(holding(dates[39], 100, HoldStyle.custom, manualStop: 95, manualTarget: 108), barsOf(dates, up));
    expect(r.state, HoldState.exit);
    expect(r.headline, contains('目標價'));
  });

  test('市場轉弱時提醒注意', () {
    final closes = [...base, 101.0, 101.5];
    final r = eval(holding(dates[39], 100, HoldStyle.swing), barsOf(dates, closes), regime: Regime.weak);
    expect(r.state, HoldState.watch);
    expect(r.headline, contains('市場'));
  });

  test('只加贏家：賺 ≥ 1R 又出現新訊號才提示加碼；虧損時加碼要警告', () {
    final up = [...base, 102.0, 104, 105];
    final win = eval(holding(dates[39], 100, HoldStyle.swing), barsOf(dates, up), newSignal: 'A 突破型');
    expect(win.addOn, isNotNull);
    final h = holding(dates[39], 100, HoldStyle.swing);
    expect(averageDownWarning(h, 95, lastClose: 95), contains('禁止向下攤平'));
    expect(averageDownWarning(h, 105, lastClose: 105), isNull);
  });

  test('已實現損益扣手續費和證交稅', () {
    final h = holding('2026-01-02', 100, HoldStyle.swing, sells: [const SellLot('2026-01-10', 110, 1000)]);
    // 買 10 萬手續費 142.5；賣 11 萬手續費 156.75 + 證交稅 330
    expect(realizedPnl(h, SecurityType.stock), closeTo(110000 - 486.75 - 100000 - 142.5, 1e-6));
    expect(h.closed, true);
    final stats = tradeStats([h]);
    expect(stats.closed, 1);
    expect(stats.wins, 1);
  });

  test('除權息：成本跟著還原，不會被除息的假跌幅觸發停損', () {
    // 實際價：100 → 除息 5 元後 95（真實沒有虧）
    final rawCloses = [...base, 100.0, 100, 95, 95.5];
    final raw = barsOf(dates, rawCloses);
    // 還原後：除息日之前的價格乘 0.95
    final adj = [for (var i = 0; i < raw.length; i++) i < 42 ? raw[i].scaled(0.95) : raw[i]];
    final r = evaluateHolding(holding(dates[40], 100, HoldStyle.short), adjusted: adj, raw: raw);
    expect(r.state, isNot(HoldState.stopLoss));
    expect(r.notes.join(), contains('除權息'));
  });

  test('沒有資料、買進日之後還沒有資料，都會說明原因', () {
    expect(eval(holding(dates[0], 100, HoldStyle.swing), const []).state, HoldState.unknown);
    final r = eval(holding('2099-01-01', 100, HoldStyle.swing), barsOf(dates, base));
    expect(r.state, HoldState.unknown);
    expect(r.headline, contains('還沒有收盤資料'));
    // 就算還沒開始判斷，也要先給起始停損
    expect(r.stop, closeTo(95, 0.5));
  });

  test('持股存檔再讀回來一模一樣', () {
    final h = Holding(
      id: 'a',
      code: '2330',
      style: HoldStyle.short,
      buys: const [BuyLot('2026-01-02', 600, 1000)],
      sells: const [SellLot('2026-01-20', 650, 500, reason: '2R 先賣一半')],
      planStop: 580,
      planTarget: 640,
      strategy: 'A',
      reason: '突破',
    );
    expect(Holding.fromJson(h.toJson()).toJson(), h.toJson());
    expect(h.shares, 500);
    expect(h.avgCost, 600);
  });
}
