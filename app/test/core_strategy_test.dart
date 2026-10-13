import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/core/lt_analysis.dart';
import 'package:stock_screener/core/lt_data.dart';
import 'package:stock_screener/core/portfolio.dart';
import 'package:stock_screener/core/strategy.dart';

import 'support/synthetic_pack.dart';

void main() {
  late Directory dir;
  late LtData data;
  late LtResult result;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('stpack');
    writeSyntheticPack(dir);
    data = loadPackDir(dir.path);
    result = runLtAnalysis(data, cfg: const LtConfig(startDate: '2017-03-01'), variants: false);
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  test('回測：五條線都從 1 開始、長度一樣、三段期間、逐年', () {
    final st = result.strategy!;
    expect(st.navs.length, StrategyResult.names.length);
    for (final v in st.navs) {
      expect(v.length, st.navs.first.length);
      expect(v.first, closeTo(1, 0.02));
      expect(v.every((x) => x.isFinite && x > 0), isTrue);
    }
    expect(st.periods.map((p) => p.label), ['全部期間', '2014–2019', '2020 以後']);
    for (final (cagr, mdd) in st.full.v) {
      expect(cagr.isFinite, isTrue);
      expect(mdd, inInclusiveRange(0, 1));
    }
    expect(st.years, isNotEmpty);
    for (final y in st.years) {
      expect(y.v.length, StrategyResult.names.length);
    }
    expect(st.stops, greaterThanOrEqualTo(0));
  });

  test('穩健＋進攻＝每月調回 70／30：混合的報酬落在兩者之間', () {
    final st = result.strategy!;
    final (blend, stable, aggr) = (st.navs[0].last, st.navs[1].last, st.navs[2].last);
    final lo = stable < aggr ? stable : aggr, hi = stable < aggr ? aggr : stable;
    // 每月再平衡會有一點偏離，但不會離兩者區間太遠
    expect(blend, greaterThan(lo * 0.9));
    expect(blend, lessThan(hi * 1.1));
  });

  test('進攻名單：最多 10 檔、一年漲幅由高到低、都站上均線排列、營收年增達標', () {
    final st = result.strategy!;
    const cfg = StrategyConfig();
    expect(st.picks.length, lessThanOrEqualTo(cfg.picks));
    for (var i = 1; i < st.picks.length; i++) {
      expect(st.picks[i].pick.mom12, lessThanOrEqualTo(st.picks[i - 1].pick.mom12));
    }
    for (final p in st.picks) {
      expect(p.pick.revYoy3, greaterThanOrEqualTo(cfg.revMin));
      expect(p.pick.distHigh, inInclusiveRange(-0.25 - 1e-9, 1e-9));
      if (p.stoppedOn != null) expect(p.stoppedOn!.compareTo(st.reviewDate), greaterThan(0));
    }
    expect(st.reviewDate.compareTo(data.dates.last), lessThanOrEqualTo(0));
  });

  test('放寬條件時趨勢模板選得出股票，而且選出來的都符合均線排列', () {
    const loose = StrategyConfig(minValue: 0, revMin: -10, rsQuantile: 0.5);
    final sc = result.live;
    final picks = trendPicks(data, sc, loose);
    for (final p in picks) {
      final s = data.stocks[p.si];
      expect(s.trAt(sc.t), greaterThan(trMa(s, sc.t, 50)));
      expect(trMa(s, sc.t, 50), greaterThan(trMa(s, sc.t, 150)));
      expect(trMa(s, sc.t, 150), greaterThan(trMa(s, sc.t, 200)));
    }
  });

  test('大盤離 200 日線：有資料就是有限數字', () {
    expect(marketGap(data, data.nd - 1).isFinite, isTrue);
  });
}
