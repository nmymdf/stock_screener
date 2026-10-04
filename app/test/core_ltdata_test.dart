import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/core/lt_data.dart';
import 'package:stock_screener/core/pack.dart';
import 'package:stock_screener/core/sources.dart';

/// 造一年的原始資料：2330 每天漲 1 元，2024-03-14 除息 4 元；1101 中間停牌三天。
PackYear _rawYear() {
  final py = PackYear(2024, names: {'2330': '台積電', '1101': '台泥'});
  var d = DateTime.utc(2024, 1, 2);
  var p2330 = 500.0, p1101 = 30.0;
  var k = 0;
  while (d.year == 2024 && k < 120) {
    if (d.weekday <= 5) {
      final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final exDiv = date == '2024-03-14';
      final prev2330 = p2330;
      p2330 = exDiv ? p2330 - 4 + 1 : p2330 + 1; // 除息當天：參考價 = 前收 − 4，再漲 1
      final chg2330 = exDiv ? 1.0 : p2330 - prev2330;
      final twse = <String, List<num>>{
        '2330': [p2330 - 1, p2330 + 2, p2330 - 2, p2330, 20000 + k, chg2330],
      };
      final suspended = k >= 40 && k < 43;
      if (!suspended) {
        final prev1101 = p1101;
        p1101 = p1101 * 1.002;
        twse['1101'] = [p1101, p1101, p1101, packNum(p1101), 5000, packNum(p1101 - prev1101)];
      }
      twse['0050'] = [150, 151, 149, 150, 9000, 0]; // ETF：長期資料不收
      py.days[date] = PackDay(
        date: date,
        taiex: 17000 + k.toDouble(),
        tri: 35000 + 2.0 * k,
        twse: twse,
        tpex: {
          '6488': [100, 101, 99, 100, 300, 0],
        },
        val: {
          '2330': [20 + k / 100, 5.0, 2.0],
          '1101': [15, 1.2, 4.5],
        },
        inst: {
          '2330': [1000, k.isEven ? 10 : 0, 5],
        },
      );
      k++;
    }
    d = d.add(const Duration(days: 1));
  }
  return py;
}

void main() {
  test('長期資料檔和完整的每日資料建出一樣的總報酬指數、快照', () {
    final raw = _rawYear();
    final viaLt = LtDataBuilder()..addLtYear(jsonDecode(jsonEncode(ltYearJson(raw))) as Map<String, dynamic>);
    final viaDays = LtDataBuilder();
    for (final d in raw.sortedDays) {
      viaDays.addDay(d);
    }
    final a = viaLt.build(), b = viaDays.build();
    expect(a.dates, b.dates);
    expect(a.stocks.map((s) => s.code).toList(), ['2330', '1101']); // ETF、上櫃不收
    for (final code in ['2330', '1101']) {
      final x = a.stock(code)!, y = b.stock(code)!;
      expect(x.start, y.start);
      expect(x.tr.length, y.tr.length);
      for (var i = 0; i < x.tr.length; i++) {
        if (x.tr[i].isNaN) {
          expect(y.tr[i].isNaN, isTrue);
        } else {
          expect(x.tr[i], closeTo(y.tr[i], 1e-3));
        }
      }
    }
    expect(a.samples.length, b.samples.length);
    final sa = a.samples[1], sb = b.samples[1];
    expect(sa.date, sb.date);
    final i = a.index['2330']!;
    expect(sa.pe[i], closeTo(sb.pe[i], 1e-6));
    expect(sa.fi60[i], sb.fi60[i]);
    expect(sa.it60[i], sb.it60[i]);
    expect(sa.val60[i], closeTo(sb.val60[i], 1e-3));
  });

  test('總報酬指數：除息那天不算跌，含息報酬 = 價差 + 股利', () {
    final raw = _rawYear();
    final b = LtDataBuilder();
    for (final d in raw.sortedDays) {
      b.addDay(d);
    }
    final data = b.build();
    final s = data.stock('2330')!;
    final t = data.dateIndex('2024-03-14');
    // 前一天收盤 p，除息日收盤 p − 3：總報酬 = (p − 3) / (p − 4)
    final prevClose = raw.days['2024-03-13']!.twse['2330']!.close;
    final r = s.trAt(t) / s.trAt(t - 1);
    expect(r, closeTo((prevClose - 3) / (prevClose - 4), 1e-6));
    expect(b.eventsFromChange, 1);
  });

  test('有證交所除權息事件時用它的參考價', () {
    final raw = _rawYear();
    final prevClose = raw.days['2024-03-13']!.twse['2330']!.close;
    final div = DividendData({
      '2330': [DivEvent('2024-03-14', prevClose, prevClose - 4, 4, '息')],
    });
    final b = LtDataBuilder(dividends: div)..addLtYear(ltYearJson(raw));
    final data = b.build();
    final s = data.stock('2330')!;
    final t = data.dateIndex('2024-03-14');
    expect(s.trAt(t) / s.trAt(t - 1), closeTo((prevClose - 3) / (prevClose - 4), 1e-6));
    expect(b.eventsFromTwse, 1);
    expect(b.eventsFromChange, 0);
  });

  test('停牌的日子是 NaN，trAt 往前找最近一次成交；60 日成交值把停牌日算 0', () {
    final b = LtDataBuilder();
    for (final d in _rawYear().sortedDays) {
      b.addDay(d);
    }
    final data = b.build();
    final s = data.stock('1101')!;
    expect(s.tradedAt(41), isFalse);
    expect(s.trAt(41), s.trAt(39));
    expect(s.tradedAt(43), isTrue);
    // 檢視日：每月 11 日以後第一個交易日
    expect(data.samples.first.date, '2024-01-11');
    expect(data.samples.last.live, isTrue);
  });

  test('檢視日：每個月 11 日以後第一個交易日', () {
    expect(sampleDayIndexes(['2024-01-10', '2024-01-11', '2024-01-12', '2024-02-13', '2024-02-14']), [1, 3]);
  });

  test('bars 檔可以還原成每日行情（上市＋上櫃）', () {
    final j = barsYearJson(_rawYear());
    final days = j['days'] as List;
    expect(days, isNotEmpty);
    final first = days.first as Map<String, dynamic>;
    expect((first['bars'] as Map).keys, containsAll(['2330', '6488', '0050']));
  });
}
