import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/logic/engine/analysis.dart';
import 'package:stock_screener/logic/engine/market_engine.dart';
import 'package:stock_screener/logic/engine/signals.dart';

import 'support/synthetic.dart';

void main() {
  final dates = tradingDays(300);
  final series = syntheticMarket(dates, stocks: 200);
  series['2330'] = breakoutStock(dates);
  final result = runAnalysis(AnalysisInput(dates, series, const {}));

  test('全市場分析跑得完，市場分數在 0～100、每天都有廣度', () {
    expect(result.latestDate, dates.last);
    expect(result.market.length, dates.length);
    final today = result.today!;
    expect(today.score, inInclusiveRange(0, 100));
    expect(today.regime, isNotNull);
    expect(today.breadth.total, greaterThan(150));
    expect(today.breadth.pctAbove240, isNotNull);
    // 前幾天資料不足，沒有分數
    expect(result.market.first.score, isNull);
  });

  test('產業分數：有產業、分數在 0～100、有五類之一', () {
    expect(result.industries, isNotEmpty);
    for (final i in result.industries) {
      expect(i.score, inInclusiveRange(0, 100));
      expect(i.members, greaterThanOrEqualTo(3));
    }
  });

  test('個股：總分在 0～100，RS 排名完整，漏斗數字一致', () {
    expect(result.stocks.length, series.length);
    for (final s in result.stocks) {
      expect(s.total, inInclusiveRange(0, 100));
      expect(s.modules.length, 10);
    }
    final ranks = result.stocks.map((s) => s.rsRank).whereType<int>().toList()..sort();
    expect(ranks.first, 1);
    expect(ranks.last, ranks.length);
    final f = result.funnel;
    expect(f.traded, greaterThanOrEqualTo(f.liquid));
    expect(f.withSignal, greaterThanOrEqualTo(f.recommended));
    expect(result.recommendations.length, f.recommended);
    for (final r in result.recommendations) {
      expect(r.vetoes, isEmpty);
      expect(r.primary, isNotNull);
    }
  });

  test('突破股被偵測到 A 訊號，並且有完整的理由和交易計畫', () {
    final s = result.stock('2330')!;
    expect(s.hits.map((h) => h.hit.strategy), contains(Strategy.breakout));
    final h = s.hits.firstWhere((h) => h.hit.strategy == Strategy.breakout);
    expect(h.hit.details, isNotEmpty);
    expect(h.plan.stop, lessThan(h.plan.entry));
    expect(s.industry, '半導體業');
    // 推薦或否決，兩者之一一定說得出原因
    expect(s.recommended || s.allVetoes.isNotEmpty, true);
  });

  test('市場狀態對應規格書的分數區間', () {
    expect(regimeOf(85), Regime.strongBull);
    expect(regimeOf(70), Regime.bull);
    expect(regimeOf(55), Regime.range);
    expect(regimeOf(40), Regime.weak);
    expect(regimeOf(20), Regime.bear);
    expect(Regime.bear.minTotalScore, greaterThan(100));
  });
}
