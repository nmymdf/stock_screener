import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/core/exposure.dart';
import 'package:stock_screener/core/factors.dart';
import 'package:stock_screener/core/lt_analysis.dart';
import 'package:stock_screener/core/lt_data.dart';
import 'package:stock_screener/core/portfolio.dart';
import 'package:stock_screener/core/research.dart';

import 'support/synthetic_pack.dart';

void main() {
  late Directory dir;
  late LtData data;
  late LtResult result;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('ltpack');
    writeSyntheticPack(dir);
    data = loadPackDir(dir.path);
    result = runLtAnalysis(data, cfg: const LtConfig(startDate: '2017-03-01'));
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  test('讀資料包：年檔＋最近 30 天接起來，沒有重複的日子', () {
    expect(data.stocks.length, 150);
    expect(data.dates.toSet().length, data.dates.length);
    expect(data.lastDate, startsWith('2020-12'));
    expect(data.samples.where((s) => !s.live).length, greaterThan(50));
    expect(data.revenue.cur, isNotEmpty);
    expect(data.intl.series.keys, contains('SOX'));
  });

  test('評分：百分位 0～1、名次連續、六大類都有分數', () {
    final live = result.live;
    expect(live.ranked.length, greaterThan(100));
    expect(live.ranked.first.rank, 1);
    expect(live.ranked.first.pct, 1);
    expect(live.ranked.last.pct, 0);
    for (final g in FactorGroup.values) {
      expect(live.ranked.where((x) => x.groups[g] != null).length, greaterThan(100), reason: g.label);
    }
  });

  test('回測：檔數、單一檔與產業上限、每月換股上限、成本', () {
    final sim = result.sim;
    expect(sim.holdings.length, lessThanOrEqualTo(15));
    expect(sim.holdings.length, greaterThanOrEqualTo(8));
    for (final w in sim.holdings.values) {
      expect(w.$1, lessThanOrEqualTo(0.2 + 1e-6));
    }
    final ind = <String, int>{};
    for (final si in sim.holdings.keys) {
      final k = industryKey(data.stocks[si].code);
      ind[k] = (ind[k] ?? 0) + 1;
    }
    expect(ind.values.every((n) => n <= const LtConfig().maxPerIndustry), isTrue);
    for (final r in sim.rebalances.skip(1)) {
      final buys = r.trades.where((t) => t.buy && t.code.isNotEmpty).length;
      expect(buys, lessThanOrEqualTo(5), reason: r.date);
    }
    expect(sim.stats.positions, greaterThan(0));
    expect(sim.stats.turnover, greaterThan(0));
    expect(sim.nav.first, 1);
    expect(sim.stats.yearRows, isNotEmpty);
  });

  test('至少抱 3 個月：沒有破壞理由的持股，不會在 63 個交易日內賣掉', () {
    for (final e in result.sim.episodes) {
      if (e.open || e.days >= 63) continue;
      // 提早賣出的只能是「長期理由破壞」或停止交易
      final r = result.sim.rebalances.firstWhere((r) => r.execDate == e.exitDate);
      final t = r.trades.firstWhere((t) => !t.buy && t.code == e.code);
      expect(t.reason, anyOf(contains('破壞'), contains('停止交易'), contains('20%')), reason: '${e.code} ${e.days} 天');
    }
  });

  test('權重：分數高、波動低的配比較多，單一檔 15%、產業 30% 上限', () {
    final w = targetWeights({
      1: (90, 0.15, 'A'),
      2: (90, 0.15, 'A'),
      3: (90, 0.15, 'A'),
      4: (60, 0.40, 'B'),
      5: (60, 0.40, 'C'),
      6: (60, 0.40, 'D'),
      7: (60, 0.40, 'E'),
      8: (60, 0.40, 'F'),
      9: (90, 0.15, 'G'),
    }, const LtConfig());
    expect(w.values.every((x) => x <= 0.15 + 1e-9), isTrue);
    // 同一產業 3 檔加起來被壓在 30%
    expect(w[1]! + w[2]! + w[3]!, closeTo(0.30, 1e-9));
    // 不受產業限制時，分數高、波動低的配得比較多
    expect(w[9]!, greaterThan(w[4]!));
    expect(w.values.reduce((a, b) => a + b), closeTo(1, 1e-9));
  });

  test('曝險：三種模式、國際指標有讀到', () {
    final e = ExposureEngine(data);
    final t = data.nd - 1;
    final none = e.at(t, 0.6, mode: ExposureMode.none);
    expect(none.level, 1);
    final local = e.at(t, 0.1, mode: ExposureMode.local);
    expect(local.localScore, lessThanOrEqualTo(2));
    expect(e.intlAt(data.dates[t]).length, 5);
  });

  test('汰弱留強：最弱的先換、最多換 N 檔、候選要明顯更強，上櫃／ETF 不評分', () {
    final live = result.live;
    final weakest = live.ranked.reversed.take(5).toList();
    final strong = live.ranked.first;
    final holdings = [
      for (final x in weakest) HoldingInput(x.code, '', 100000, '2019-01-01'),
      HoldingInput(strong.code, '', 100000, '2019-01-01'),
      const HoldingInput('6488', '環球晶', 50000, '2019-01-01'),
      const HoldingInput('0050', '元大台灣50', 50000, '2019-01-01'),
    ];
    final adv = swapAdvice(holdings, live, data, maxSwaps: 2);
    expect(adv.replaceCount, 2);
    final rep = adv.rows.where((r) => r.action == SwapAction.replace).toList();
    for (final r in rep) {
      for (final c in r.candidates) {
        expect(c.pct, greaterThanOrEqualTo(r.score!.pct + 0.25));
      }
    }
    expect(adv.rows.firstWhere((r) => r.holding.code == strong.code).action, SwapAction.keep);
    expect(adv.rows.firstWhere((r) => r.holding.code == '6488').action, SwapAction.notRated);
    expect(adv.rows.firstWhere((r) => r.holding.code == '0050').action, SwapAction.notRated);
    expect(adv.rows.where((r) => r.reasons.any((x) => x.contains('換股已達'))).length, 3);
  });

  test('因子研究與文字報告', () {
    expect(result.research.rows.first.name, '總分');
    expect(result.research.periods, greaterThan(20));
    final text = runPackResearch(dir.path);
    expect(text, contains('年化報酬'));
    expect(text, contains('因子研究'));
    expect(text, contains('理想組合'));
  });

  test('分數走勢：每個檢視日的百分位', () {
    final code = result.live.ranked.first.code;
    final h = result.pctHistory(code);
    expect(h, isNotEmpty);
    expect(h.last.$2, 1);
  });
}
