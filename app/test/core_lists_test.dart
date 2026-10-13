import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/core/factors.dart';
import 'package:stock_screener/core/lists.dart';
import 'package:stock_screener/core/lt_analysis.dart';
import 'package:stock_screener/core/lt_data.dart';
import 'package:stock_screener/core/portfolio.dart';
import 'package:stock_screener/core/strategy.dart';
import 'package:stock_screener/data/stock_industry.dart';

import 'support/synthetic_pack.dart';

void main() {
  late Directory dir;
  late LtData data;
  late LtResult result;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('listpack');
    writeSyntheticPack(dir);
    data = loadPackDir(dir.path);
    result = runLtAnalysis(data, cfg: const LtConfig(startDate: '2017-03-01'), variants: false);
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  test('兩份名單都有：最多 10 檔、同產業最多 2 檔、不重複', () {
    expect(result.lists.keys, PickList.values);
    for (final lr in result.lists.values) {
      expect(lr.now.length, lessThanOrEqualTo(kListSize));
      expect(lr.now.map((x) => x.si).toSet().length, lr.now.length);
      final cnt = <String, int>{};
      for (final x in lr.now) {
        final ind = industryOf(x.code) ?? '其他';
        cnt[ind] = (cnt[ind] ?? 0) + 1;
      }
      expect(cnt.values.every((c) => c <= kPerIndustry), isTrue);
    }
  });

  test('穩健存股：5 年都配息、殖利率 3% 以上、年線沒下彎、照殖利率排', () {
    final l = result.lists[PickList.income]!.now;
    for (final x in l) {
      expect(x.raw.divYears, greaterThanOrEqualTo(5));
      expect(x.raw.yld, greaterThanOrEqualTo(3));
      expect(x.flags.contains(LtFlag.downtrend), isFalse);
    }
    for (var i = 1; i < l.length; i++) {
      expect(l[i].raw.yld, lessThanOrEqualTo(l[i - 1].raw.yld));
    }
  });

  test('強勢成長：放寬成交門檻時選得出股票，都符合多頭排列、營收門檻', () {
    final sc = result.live;
    final tp = trendPicks(data, sc, const StrategyConfig(minValue: 0, revMin: -10, rsQuantile: 0.5, picks: 999));
    for (final p in tp) {
      final s = data.stocks[p.si];
      expect(s.trAt(sc.t), greaterThan(trMa(s, sc.t, 50)));
    }
    for (final x in result.lists[PickList.strong]!.now) {
      expect(x.raw.revYoy3, greaterThanOrEqualTo(0.2));
    }
  });

  test('成績表：3／6／12 個月 × 三段期間，比例在 0～1 之間', () {
    for (final lr in result.lists.values) {
      for (final s in lr.stats) {
        expect(kStatMonths, contains(s.months));
        expect(kStatPeriods, contains(s.period));
        expect(s.n, greaterThan(0));
        expect(s.upRate, inInclusiveRange(0, 1));
        expect(s.beatEtf, inInclusiveRange(0, 1));
        expect(s.worst, lessThanOrEqualTo(s.avg + 1e-12));
      }
    }
  });

  test('持股健檢：上市股票有三種結果之一和六個面向；上櫃、ETF 回傳 null', () {
    var seen = 0;
    for (final x in result.live.ranked.take(40)) {
      final h = healthOf(data, result.live, x.code, result.lists)!;
      expect(h.dims.map((d) => d.name), ['趨勢', '營收', '獲利', '價格', '法人', '波動']);
      for (final d in h.dims) {
        expect(d.grade, inInclusiveRange(-1, 2));
      }
      if (x.broken) expect(h.health, Health.broken);
      if (!x.broken && !h.gap200.isNaN && h.gap200 < 0) expect(h.health, Health.belowYear);
      if (h.health == Health.ok) expect(h.gap200, greaterThanOrEqualTo(0));
      for (final k in h.inLists) {
        expect(result.lists[k]!.contains(x.si), isTrue);
      }
      seen++;
    }
    expect(seen, greaterThan(0));
    expect(healthOf(data, result.live, '0050', result.lists), isNull);
    expect(coreEtfCodes.contains('0050'), isTrue);
  });
}
