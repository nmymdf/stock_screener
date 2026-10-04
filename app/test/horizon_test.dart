import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/logic/engine/analysis.dart';
import 'package:stock_screener/logic/engine/backtest.dart';
import 'package:stock_screener/logic/engine/horizon.dart';
import 'package:stock_screener/logic/engine/industry_engine.dart';
import 'package:stock_screener/logic/engine/market_engine.dart';
import 'package:stock_screener/logic/engine/signals.dart';
import 'package:stock_screener/logic/ta.dart';
import 'package:stock_screener/models/daily_bar.dart';
import 'package:stock_screener/ui/screens/compare_screen.dart';

import 'support/synthetic.dart';

HorizonScore hs(String key, double? score) => HorizonScore(key, key, '', score, const [], '', '失效：$key');

void main() {
  final dates = tradingDays(300);
  final series = syntheticMarket(dates, stocks: 200, bias: 0.3);
  series['2330'] = breakoutStock(dates);
  final result = runAnalysis(AnalysisInput(dates, series, const {}));

  test('交叉矩陣：三週期同強是共振；只有短線強是純戰術；長中強短弱是等進場點', () {
    expect(classifyOpportunity(Level.strong, Level.strong, Level.strong), Opportunity.resonance);
    expect(classifyOpportunity(Level.strong, Level.strong, Level.weak), Opportunity.swing);
    expect(classifyOpportunity(Level.strong, Level.weak, Level.weak), Opportunity.tactical);
    expect(classifyOpportunity(Level.weak, Level.strong, Level.strong), Opportunity.waitEntry);
    expect(classifyOpportunity(Level.weak, Level.weak, Level.strong), Opportunity.watchlist);
    expect(classifyOpportunity(Level.weak, Level.strong, Level.weak), Opportunity.themeSwing);
    expect(classifyOpportunity(Level.weak, Level.weak, Level.weak), Opportunity.avoid);
    expect(classifyOpportunity(Level.neutral, Level.neutral, Level.neutral), Opportunity.neutral);
    // 長期資料不足（none）不能當成長期強
    expect(classifyOpportunity(Level.strong, Level.strong, Level.none), Opportunity.swing);
  });

  test('每檔股票都有三週期分數、機會類型、持有期間；長期至少要 200 天資料', () {
    for (final s in result.stocks) {
      for (final h in [s.short, s.medium]) {
        if (h.score != null) expect(h.score, inInclusiveRange(0, 100));
        expect(h.invalidation, isNotEmpty);
      }
      expect(s.long.score == null || s.long.score! <= 100, true);
      if (s.duration.cls != null) expect(s.duration.cls, inInclusiveRange(1, 3));
      expect(s.duration.whyNotHigher, isNotEmpty);
    }
    final short = runAnalysis(
      AnalysisInput(dates.sublist(0, 150), {for (final e in series.entries) e.key: e.value.sublist(0, 150)}, const {}),
    );
    expect(short.stocks.every((s) => s.long.score == null), true);
  });

  test('持有期間：證據都強才給 D3；市場弱勢、均值回歸、信心低會往下調，而且寫出原因', () {
    const facts = DurationFacts(80, 100, 95, 300);
    const pv = PvReading(PvState.healthyUp, '', 80, []);
    const rs = RsWindows(0.9, 0.9, 0.9, 0.9);
    DurationEstimate est({Regime? regime, Strategy? st, IndustryClass? ic}) => estimateDuration(
      facts: facts,
      short: hs('short', 80),
      medium: hs('medium', 80),
      long: hs('long', 80),
      pv: pv,
      rs: rs,
      strategy: st,
      industryScore: 80,
      industryClass: ic ?? IndustryClass.leading,
      marketScore: 75,
      regime: regime ?? Regime.bull,
    );
    final best = est();
    expect(best.cls, 3);
    expect(best.confidence, Confidence.high);
    expect(best.whyNotHigher, contains('D4'));
    expect(best.hardInvalidation, '失效：long');

    final weak = est(regime: Regime.weak);
    expect(weak.cls, 1);
    expect(weak.capped.join(), contains('弱勢'));

    final mr = est(st: Strategy.meanReversion);
    expect(mr.cls, 1);
    expect(mr.capped.join(), contains('均值回歸'));

    final range = est(regime: Regime.range);
    expect(range.cls, 2);

    final lagging = est(ic: IndustryClass.lagging);
    expect(lagging.cls, 2);

    // 證據不足：短中長都弱、沒有訊號 → 不建議持有
    final none = estimateDuration(
      facts: const DurationFacts(20, 100, 95, 300),
      short: hs('short', 30),
      medium: hs('medium', 30),
      long: hs('long', 30),
      pv: const PvReading(PvState.distribution, '', 20, []),
      rs: const RsWindows(0.2, 0.2, 0.2, 0.2),
    );
    expect(none.cls, isNull);
    expect(none.confidence, Confidence.low);
  });

  test('價量：下跌放量、爆量不漲、突破確認都認得出來', () {
    final d = tradingDays(80);
    List<DailyBar> flat() => [for (var i = 0; i < 79; i++) bar(d[i], 100, h: 101, l: 99, v: 1000)];
    final dump = StockSeries('x', [...flat(), bar(d[79], 96, o: 100, h: 100.5, l: 95.5, v: 3000)]);
    expect(priceVolume(dump, 79).state, PvState.distribution);
    final churn = StockSeries('x', [...flat(), bar(d[79], 100.3, o: 100, h: 103, l: 99.5, v: 4000)]);
    expect(priceVolume(churn, 79).state, PvState.churn);
    final brk = StockSeries('x', [...flat(), bar(d[79], 104, o: 100.5, h: 104.3, l: 100.2, v: 2500)]);
    final r = priceVolume(brk, 79);
    expect(r.state, PvState.breakout);
    expect(r.breakoutQuality, isNotNull);
  });

  test('觀察池：沒有通過的訊號、流動性合格、中長期條件好的才會進來', () {
    for (final s in result.watchlist) {
      expect(s.recommended, false);
      expect(s.liquid, true);
      expect(s.triggers, isNotEmpty);
    }
  });

  test('歷史統計：跟回測同一套條件，樣本太少時改用所有市場狀態', () {
    final cal = result.calibration;
    final bt = runBacktest(AnalysisInput(dates, series, const {}), const BacktestConfig());
    final closed = bt.trades.where((t) => !t.openAtEnd).length;
    final total = Strategy.values.fold(0, (a, s) => a + (cal.stats['${s.code}|*']?.n ?? 0));
    expect(total, closed);
    for (final st in cal.stats.values) {
      expect(st.winRate, inInclusiveRange(0, 1));
      for (final c in st.cone) {
        expect(c.p25, lessThanOrEqualTo(c.p50));
        expect(c.p50, lessThanOrEqualTo(c.p75));
      }
    }
    // 回測的每筆交易都知道訊號那天的市場狀態
    expect(bt.trades.every((t) => t.regime != null), true);
    expect(bt.byRegime.values.fold(0, (a, s) => a + s.n), bt.trades.length);

    const few = CalStat(title: 'x', n: 3, wins: 1, hitTarget: 0, hitStop: 1, avgR: 0, avgDays: 5, cone: []);
    const many = CalStat(title: 'all', n: 40, wins: 20, hitTarget: 10, hitStop: 10, avgR: 0.3, avgDays: 8, cone: []);
    const c = Calibration({'A|bull': few, 'A|*': many});
    expect(c.lookup(Strategy.breakout, Regime.bull)!.title, 'all');
    expect(many.reliable, true);
  });

  test('回測期間：只統計開始日之後的訊號', () {
    final start = dates[200];
    final bt = runBacktest(AnalysisInput(dates, series, const {}), BacktestConfig(startDate: start));
    expect(bt.fromDate, start);
    expect(bt.trades.every((t) => t.signalDate.compareTo(start) >= 0), true);
    final all = runBacktest(AnalysisInput(dates, series, const {}), const BacktestConfig());
    expect(bt.trades.length, lessThanOrEqualTo(all.trades.length));
  });

  test('比較頁的輸入：代號、名稱、混合分隔符號都認得，認不得的列出來', () {
    final unknown = <String>[];
    final codes = parseStockInput('2330, 2317、聯發科 xyz不存在', unknown: unknown);
    expect(codes.take(2), ['2330', '2317']);
    expect(codes.length, 3);
    expect(unknown, ['xyz不存在']);
  });
}
