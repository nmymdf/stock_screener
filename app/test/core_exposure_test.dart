import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/core/exposure.dart';
import 'package:stock_screener/core/lt_data.dart';
import 'package:stock_screener/core/pack.dart';
import 'package:stock_screener/core/sources.dart';

String _d(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// 300 個平日；加權指數前 250 天上漲、最後 50 天急跌。
LtData _data({required Map<String, IntlSeries> intl}) {
  final b = LtDataBuilder();
  var t = DateTime.utc(2024, 1, 1);
  var ix = 10000.0;
  for (var k = 0; k < 300; k++) {
    while (t.weekday > 5) {
      t = t.add(const Duration(days: 1));
    }
    ix *= k < 250 ? 1.002 : 0.985;
    b.addDay(
      PackDay(
        date: _d(t),
        taiex: ix,
        twse: {
          '2330': [ix / 20, 1000, 0],
        },
      ),
    );
    t = t.add(const Duration(days: 1));
  }
  return b.build(intl: IntlData(intl));
}

IntlSeries _series(String key, List<String> dates, double Function(int i) v, {int lag = 1}) =>
    IntlSeries(key, 'test', lag, dates, [for (var i = 0; i < dates.length; i++) v(i)]);

void main() {
  test('國際指標不偷看：台股某一天只用前一天以前的美國收盤', () {
    // 美國每天都有資料（含週末，簡化），VIX 在最後一天突然跳到 80
    final dates = <String>[];
    var t = DateTime.utc(2023, 1, 1);
    while (dates.length < 700) {
      dates.add(_d(t));
      t = t.add(const Duration(days: 1));
    }
    final last = dates.length - 1;
    final data = _data(intl: {'VIX': _series('VIX', dates, (i) => i == last ? 80 : 15)});
    final e = ExposureEngine(data);
    // 美國最後一天的資料，台股同一天還不能用
    final same = e.intlAt(dates[last]).firstWhere((x) => x.key == 'VIX');
    expect(same.value, 15);
    // 隔天就能用了
    final next = e
        .intlAt(_d(DateTime.parse(dates[last]).add(const Duration(days: 1))))
        .firstWhere((x) => x.key == 'VIX');
    expect(next.value, 80);
  });

  test('曝險：指數在年線上、年線往上、廣度好 → 100%；急跌後轉保守；國際風險多再降一級', () {
    final dates = <String>[];
    var t = DateTime.utc(2023, 1, 1);
    while (dates.length < 900) {
      dates.add(_d(t));
      t = t.add(const Duration(days: 1));
    }
    // 費半、Nasdaq 一路跌（在年線下、年線往下）、台幣貶值超過 3%
    final intl = {
      'SOX': _series('SOX', dates, (i) => 5000 - i * 3.0),
      'NASDAQ': _series('NASDAQ', dates, (i) => 20000 - i * 10.0),
      'USDTWD': _series('USDTWD', dates, (i) => 30 + i * 0.03),
    };
    final data = _data(intl: intl);
    final e = ExposureEngine(data);
    final up = e.at(249, 0.7, mode: ExposureMode.local);
    expect(up.localScore, 3);
    expect(up.level, 1.0);
    final none = e.at(299, 0.1, mode: ExposureMode.none);
    expect(none.level, 1.0);
    final down = e.at(299, 0.1, mode: ExposureMode.local);
    expect(down.taiexDist, lessThan(0));
    expect(down.level, 0.5);
    final withIntl = e.at(249, 0.7, mode: ExposureMode.localIntl);
    expect(withIntl.intlRisk, greaterThanOrEqualTo(3));
    expect(withIntl.level, 0.75); // 台股很好，但國際風險三項以上：降一級
    expect(withIntl.localLevel, 1.0);
    expect(withIntl.reasons, isNotEmpty);
  });
}
