/// 造一份假的資料包（隨機漫步的股價、營收、除權息、國際指標），測試整條長期分析流程用。
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:stock_screener/core/pack.dart';
import 'package:stock_screener/core/sources.dart';
import 'package:stock_screener/data/stock_industry.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 寫進 [dir]：lt-YYYY、recent、revenue、dividends、intl。回傳用到的股票代號。
List<String> writeSyntheticPack(
  Directory dir, {
  int stocks = 150,
  int fromYear = 2016,
  int toYear = 2020,
  int seed = 42,
}) {
  final rnd = math.Random(seed);
  double gauss() {
    final u = 1 - rnd.nextDouble(), v = rnd.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  final codes = [
    for (final c in kIndustryIndexByCode.keys)
      if (isCommonStockCode(c)) c,
  ].take(stocks).toList();
  final drift = [for (final _ in codes) (0.06 + 0.12 * gauss()) / 250];
  final vol = [for (final _ in codes) (0.15 + 0.35 * rnd.nextDouble()) / math.sqrt(250)];
  final price = [for (final _ in codes) 20 + 180 * rnd.nextDouble()];
  final growth = [for (var i = 0; i < codes.length; i++) drift[i] * 250 * 2 + 0.05 * gauss()];
  final rev = RevenueData('${fromYear - 1}-01');
  final div = DividendData();
  final years = <int, PackYear>{};
  final revBase = [for (final _ in codes) 1e5 + 1e6 * rnd.nextDouble()];
  final revHist = <String, Map<int, double>>{};
  var taiex = 9000.0, tri = 15000.0;
  final intl = <String, (List<String>, List<double>)>{
    for (final k in ['SOX', 'NASDAQ', 'VIX', 'USDTWD', 'US10Y']) k: (<String>[], <double>[]),
  };
  final intlLevel = {'SOX': 800.0, 'NASDAQ': 5000.0, 'VIX': 15.0, 'USDTWD': 31.0, 'US10Y': 2.0};
  var lastMonth = -1;
  for (var d = DateTime.utc(fromYear, 1, 1); d.year <= toYear; d = d.add(const Duration(days: 1))) {
    if (d.weekday > 5) continue;
    final date = _ymd(d);
    // 國際指標（美國當地日期）
    for (final e in intl.entries) {
      final k = e.key;
      final step = k == 'VIX'
          ? 0.05 * gauss() * intlLevel[k]!
          : (k == 'US10Y' ? 0.02 * gauss() : intlLevel[k]! * 0.012 * gauss());
      intlLevel[k] = math.max(0.5, intlLevel[k]! + step + (k == 'VIX' ? (15 - intlLevel[k]!) * 0.05 : 0));
      e.value.$1.add(date);
      e.value.$2.add(packNum(intlLevel[k]!, 4).toDouble());
    }
    final market = 0.0004 + 0.01 * gauss();
    taiex *= 1 + market;
    tri *= 1 + market + 0.04 / 250;
    final twse = <String, List<num>>{};
    final val = <String, List<num?>>{};
    final inst = <String, List<int>>{};
    for (var i = 0; i < codes.length; i++) {
      final prev = price[i];
      var p = prev * math.exp(drift[i] + vol[i] * gauss() + market * 0.8);
      double? chg = p - prev;
      // 每年 7 月第一個交易日除息 3%
      if (d.month == 7 && d.day <= 7 && d.weekday == DateTime.monday) {
        final cash = prev * 0.03;
        final ref = prev - cash;
        p = ref * math.exp(vol[i] * gauss());
        chg = p - ref;
        div.merge({
          codes[i]: [DivEvent(date, packNum(prev).toDouble(), packNum(ref).toDouble(), packNum(cash).toDouble(), '息')],
        });
      }
      price[i] = p;
      final lots = (2000 + 20000 * rnd.nextDouble()).round();
      twse[codes[i]] = [packNum(p * 0.99), packNum(p * 1.01), packNum(p * 0.98), packNum(p), lots, packNum(chg)];
      final pe = 10 + 20 * rnd.nextDouble();
      val[codes[i]] = [packNum(pe), packNum(1 + 3 * rnd.nextDouble()), packNum(1 + 5 * rnd.nextDouble())];
      inst[codes[i]] = [(gauss() * 500 + drift[i] * 250 * 2000).round(), (gauss() * 50).round(), 0];
    }
    final py = years[d.year] ??= PackYear(d.year);
    py.days[date] = PackDay(date: date, taiex: taiex, tri: tri, twse: twse, val: val, inst: inst);
    // 月營收：每月第一個交易日寫入上個月
    final mi = d.year * 12 + d.month - 1;
    if (mi != lastMonth) {
      lastMonth = mi;
      final m = mi - 1;
      final month = <String, (double, double?)>{};
      for (var i = 0; i < codes.length; i++) {
        final h = revHist[codes[i]] ??= {};
        for (var k = m - 13; k <= m; k++) {
          h.putIfAbsent(k, () => revBase[i] * math.pow(1 + growth[i], (k - mi) / 12) * (1 + 0.08 * gauss()));
        }
        month[codes[i]] = (h[m]!, h[m - 12]);
      }
      rev.addMonth(RevenueData.monthOf(m), month);
    }
  }
  for (final py in years.values) {
    File('${dir.path}/lt-${py.year}.json.gz').writeAsBytesSync(encodeGz(ltYearJson(py)));
  }
  final last = years[toYear]!.sortedDays;
  File(
    '${dir.path}/recent.json.gz',
  ).writeAsBytesSync(encodeGz(RecentPack(last.sublist(last.length - 30), {for (final c in codes) c: '測試$c'}).toJson()));
  File('${dir.path}/revenue.json.gz').writeAsBytesSync(encodeGz(rev.toJson()));
  File('${dir.path}/dividends.json.gz').writeAsBytesSync(encodeGz(div.toJson()));
  File('${dir.path}/intl.json.gz').writeAsBytesSync(
    encodeGz(
      IntlData({for (final e in intl.entries) e.key: IntlSeries(e.key, 'test', 1, e.value.$1, e.value.$2)}).toJson(),
    ),
  );
  return codes;
}
