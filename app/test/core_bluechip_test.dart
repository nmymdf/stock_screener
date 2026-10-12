import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/core/bluechip.dart';
import 'package:stock_screener/core/lt_analysis.dart';
import 'package:stock_screener/core/lt_data.dart';
import 'package:stock_screener/core/pack.dart';
import 'package:stock_screener/core/portfolio.dart';

import 'support/synthetic_pack.dart';

void main() {
  late Directory dir;
  late LtData data;
  late LtResult result;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('bcpack');
    writeSyntheticPack(dir);
    data = loadPackDir(dir.path);
    result = runLtAnalysis(data, cfg: const LtConfig(startDate: '2017-03-01'), variants: false);
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  test('發行股數：用當天已經知道的最新一份（當月取樣日還沒到就用上個月）', () {
    const sh = SharesData({
      '2024-04': ('2024-04-11', {'2330': 100}),
      '2024-05': ('2024-05-13', {'2330': 200}),
    });
    expect(sh.at('2024-05-10')!['2330'], 100);
    expect(sh.at('2024-05-13')!['2330'], 200);
    expect(sh.at('2024-04-01'), isNull);
    expect(data.shares.isEmpty, isFalse);
  });

  test('組合：市值前 30 大去掉地雷，單一檔（含 0050 裡的）不超過 40%，沒有不到 1.5% 的零碎部位', () {
    final bc = result.bluechip!;
    final p = bc.current!;
    const cfg = BcConfig();
    expect(p.stocks, isNotEmpty);
    final sum = p.stocks.fold(0.0, (a, x) => a + x.weight) + p.etfWeight;
    expect(sum, closeTo(1, 1e-9));
    for (final st in p.stocks) {
      expect(st.weight, greaterThanOrEqualTo(cfg.minWeight - 1e-9));
      expect(st.capRank, lessThanOrEqualTo(cfg.universe));
    }
    for (final e in p.exposure.values) {
      expect(e, lessThanOrEqualTo(cfg.maxWeight + 1e-9));
    }
    expect(p.exposure.values.fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
    // 地雷不會在組合裡，而且都有理由
    final held = {for (final s in p.stocks) s.si};
    for (final m in p.landmines) {
      expect(held.contains(m.si), isFalse);
      expect(m.reasons, isNotEmpty);
      expect(m.capRank, lessThanOrEqualTo(cfg.universe));
    }
    // 比重由大到小
    for (var i = 1; i < p.stocks.length; i++) {
      expect(p.stocks[i].weight, lessThanOrEqualTo(p.stocks[i - 1].weight + 1e-12));
    }
  });

  test('回測：從 1 開始、三段期間、逐年、地雷成績單、上次檢視', () {
    final bc = result.bluechip!;
    expect(bc.nav.first, closeTo(1, 0.01));
    expect(bc.bench.first, 1);
    expect(bc.periods.map((p) => p.label), ['全部期間', '2014–2019', '2020 以後']);
    expect(bc.years, isNotEmpty);
    expect(bc.turnover, greaterThan(0));
    expect(bc.previous, isNotNull);
    expect(bc.previous!.date.compareTo(bc.current!.date), lessThan(0));
    for (final m in bc.mines) {
      expect(m.mines, greaterThan(0));
    }
  });

  test('依我的持股調整：組合裡的續抱、有地雷的換掉（換成組合裡沒有的）、0050 算組合、上櫃不判斷', () {
    final bc = result.bluechip!;
    final p = bc.current!;
    final live = result.live;
    final inPick = data.stocks[p.stocks.first.si].code;
    // 找一檔有地雷的（不在前 30 大也可以）
    final mine = live.ranked.lastWhere((x) => landmineReasonsOf(x).isNotEmpty);
    final holdings = [
      HoldingInput(inPick, '', 100000, '2020-01-01'),
      HoldingInput(mine.code, '', 100000, '2020-01-01'),
      const HoldingInput('0050', '元大台灣50', 100000, '2020-01-01'),
      const HoldingInput('6488', '環球晶', 50000, '2020-01-01'),
    ];
    final adv = bcSwapAdvice(holdings, p, data, live, maxSwaps: 2);
    SwapRow row(String c) => adv.rows.firstWhere((r) => r.holding.code == c);
    expect(row(inPick).action, SwapAction.keep);
    expect(row(mine.code).action, SwapAction.replace);
    expect(row(mine.code).candidates.map((c) => c.code), isNot(contains(inPick)));
    expect(row(mine.code).candidates.every((c) => p.of(c.si) != null), isTrue);
    expect(row('0050').action, SwapAction.core);
    expect(row('6488').action, SwapAction.notRated);
  });
}
