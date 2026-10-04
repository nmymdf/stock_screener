import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/core/pack.dart';
import 'package:stock_screener/core/sources.dart';
import 'package:stock_screener/models/daily_bar.dart';

void main() {
  test('報酬指數：從報酬指數表找「發行量加權股價報酬指數」，不會跟價格指數搞混', () {
    final body = {
      'stat': 'OK',
      'tables': [
        {
          'title': '價格指數(臺灣證券交易所)',
          'fields': ['指數', '收盤指數', '漲跌(+/-)'],
          'data': [
            ['發行量加權股價指數', '23,000.12', '+'],
          ],
        },
        {
          'title': '報酬指數(臺灣證券交易所)',
          'fields': ['報酬指數', '收盤指數', '漲跌(+/-)'],
          'data': [
            ['發行量加權股價報酬指數', '45,678.90', '+'],
          ],
        },
      ],
    };
    expect(parseTaiexTotalReturn(body), closeTo(45678.90, 1e-6));
  });

  test('BWIBBU_d 新舊欄位都認，「-」是 null', () {
    final newer = parseBwibbu({
      'stat': 'OK',
      'fields': ['證券代號', '證券名稱', '收盤價', '殖利率(%)', '股利年度', '本益比', '股價淨值比', '財報年/季'],
      'data': [
        ['2330', '台積電', '1,000.00', '1.60', '113', '25.30', '7.10', '114/2'],
        ['2610', '華航', '20.00', '0.00', '113', '-', '1.20', '114/2'],
      ],
    });
    expect(newer['2330'], [25.30, 7.10, 1.60]);
    expect(newer['2610'], [null, 1.20, null]);
    final older = parseBwibbu({
      'stat': 'OK',
      'fields': ['證券代號', '證券名稱', '本益比', '殖利率(%)', '股價淨值比'],
      'data': [
        ['1101', '台泥', '12.5', '5.2', '1.1'],
      ],
    });
    expect(older['1101'], [12.5, 1.1, 5.2]);
  });

  test('T86：新版（外陸資＋外資自營商）和舊版（外資）都算出外資、投信、自營商張數', () {
    final newer = parseT86({
      'stat': 'OK',
      'fields': [
        '證券代號',
        '證券名稱',
        '外陸資買進股數(不含外資自營商)',
        '外陸資賣出股數(不含外資自營商)',
        '外陸資買賣超股數(不含外資自營商)',
        '外資自營商買進股數',
        '外資自營商賣出股數',
        '外資自營商買賣超股數',
        '投信買進股數',
        '投信賣出股數',
        '投信買賣超股數',
        '自營商買賣超股數',
        '自營商買進股數(自行買賣)',
        '三大法人買賣超股數',
      ],
      'data': [
        ['2330', '台積電', '1', '1', '5,000,000', '0', '0', '100,000', '0', '0', '-300,000', '20,000', '0', '0'],
      ],
    });
    expect(newer['2330'], [5100, -300, 20]);
    final older = parseT86({
      'stat': 'OK',
      'fields': ['證券代號', '證券名稱', '外資買進股數', '外資賣出股數', '外資買賣超股數', '投信買進股數', '投信賣出股數', '投信買賣超股數', '自營商買賣超股數'],
      'data': [
        ['2317', '鴻海', '0', '0', '-2,500,000', '0', '0', '1,000', '0'],
      ],
    });
    expect(older['2317'], [-2500, 1, 0]);
  });

  test('TWT49U：民國日期、權值＋息值、權／息', () {
    final ev = parseTwt49u({
      'stat': 'OK',
      'fields': ['資料日期', '股票代號', '股票名稱', '除權息前收盤價', '除權息參考價', '權值+息值', '權/息', '漲停價格'],
      'data': [
        ['113年06月13日', '2330', '台積電', '900.00', '896.00', '4.00', '息', '985'],
        ['113年07月18日', '1101', '台泥', '35.00', '33.00', '2.00', '權息', '36'],
      ],
    });
    expect(ev['2330']!.single.date, '2024-06-13');
    expect(ev['2330']!.single.value, 4.0);
    expect(ev['2330']!.single.cash, isTrue);
    expect(ev['1101']!.single.kind, '權息');
    expect(rocToIso('113/1/2'), '2024-01-02');
    expect(rocToIso('1130102'), '2024-01-02');
  });

  test('營收 HTML：Big5 的中文用 latin1 讀也不影響代號和數字', () {
    // 模擬 Big5 位元組（0xA5 0x78 = 「台」），用 latin1 解碼
    final big5ish = latin1.decode([0xA5, 0x78, 0xBF, 0x6E]);
    final html =
        '<table><tr><th>公司代號</th><th>名稱</th></tr>'
        '<tr align=right><td align=center>1101</td><td align=left>$big5ish</td>'
        '<td nowrap>  9,961,416</td><td nowrap>10,000,000</td><td nowrap>8,500,000</td><td>-0.38</td><td>17.19</td></tr>'
        '<tr><td>合計</td><td></td><td>1</td><td>1</td><td>1</td></tr></table>';
    final r = parseRevenueHtml(html);
    expect(r.keys, ['1101']);
    expect(r['1101'], (9961416.0, 8500000.0));
  });

  test('營收 CSV 和 OpenAPI', () {
    final csv =
        '﻿出表日期,資料年月,公司代號,公司名稱,產業別,營業收入-當月營收,營業收入-上月營收,營業收入-去年當月營收\n'
        '113/10/11,113/9,2330,台積電,半導體業,"251,872,717","250,866,368","180,430,282"\n';
    expect(parseRevenueCsv(csv)['2330'], (251872717.0, 180430282.0));
    final (ym, m) = parseRevenueOpenApi([
      {'出表日期': '1131011', '資料年月': '11309', '公司代號': '2330', '營業收入-當月營收': '251872717', '營業收入-去年當月營收': '180430282'},
    ]);
    expect(ym, '2024-09');
    expect(m['2330']!.$1, 251872717.0);
  });

  test('FRED CSV 跳過「.」，Yahoo 依交易所時區換成當地日期', () {
    final (d, v) = parseFredCsv('observation_date,VIXCLS\n2024-01-02,13.2\n2024-01-03,.\n2024-01-04,14.1\n');
    expect(d, ['2024-01-02', '2024-01-04']);
    expect(v, [13.2, 14.1]);
    // 2024-01-02 09:30 紐約（UTC-5）= 14:30 UTC
    final ts = DateTime.utc(2024, 1, 2, 14, 30).millisecondsSinceEpoch ~/ 1000;
    final (yd, yv) = parseYahooChart({
      'chart': {
        'result': [
          {
            'meta': {'gmtoffset': -18000},
            'timestamp': [ts, ts + 86400],
            'indicators': {
              'quote': [
                {
                  'close': [4500.5, null],
                },
              ],
            },
          },
        ],
      },
    });
    expect(yd, ['2024-01-02']);
    expect(yv, [4500.5]);
  });

  test('資料包一天的格式：完整列可以還原成日 K，精簡列只留收盤、張數、漲跌', () {
    const bar = DailyBar(
      date: '2024-01-02',
      open: 590,
      high: 593,
      low: 589,
      close: 593,
      volumeLots: 22000,
      change: 3.5,
    );
    final day = PackDay(
      date: '2024-01-02',
      taiex: 17853.76,
      tri: 35000.1,
      twse: {'2330': barRow(bar)},
      val: {
        '2330': [15.2, 4.1, null],
      },
      inst: {
        '2330': [1200, -30, 5],
      },
    );
    final back = PackDay.fromJson(jsonDecode(jsonEncode(day.toJson())) as Map<String, dynamic>);
    expect(back.twse['2330'], [590, 593, 589, 593, 22000, 3.5]);
    final snap = back.snapshot()!;
    expect(snap.bars['2330']!.close, 593);
    expect(snap.bars['2330']!.change, 3.5);
    expect(back.val['2330'], [15.2, 4.1, null]);
    final c = back.compacted();
    expect(c.twse['2330'], [593, 22000, 3.5]);
    expect(c.twse['2330']!.close, 593);
    expect(c.twse['2330']!.change, 3.5);
    expect(c.snapshot(), isNull);
  });

  test('營收資料：用去年當月營收補缺、最後一個月、壓縮存檔', () {
    final r = RevenueData('2012-01', null);
    r.addMonth('2013-03', {'2330': (100.0, 80.0)});
    expect(r.at('2330', RevenueData.monthIndex('2013-03')), 100);
    expect(r.at('2330', RevenueData.monthIndex('2012-03')), 80);
    expect(r.lastMonth, '2013-03');
    final back = RevenueData.fromJson(decodeGz(encodeGz(r.toJson())));
    expect(back.at('2330', RevenueData.monthIndex('2012-03')), 80);
    expect(back.countFor('2013-03'), 1);
  });
}
