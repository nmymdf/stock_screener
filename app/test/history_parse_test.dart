import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/services/history_service.dart';

void main() {
  test('證交所新版 tables 格式：用欄位名稱找欄位，股數換算成張', () {
    final bars = parseTwseDaily('2026-09-29', {
      'stat': 'OK',
      'tables': [
        {'title': '大盤統計資訊', 'fields': ['指數', '收盤指數'], 'data': [['發行量加權股價指數', '23,000.00']]},
        {
          'title': '每日收盤行情(全部(不含權證、牛熊證))',
          'fields': ['證券代號', '證券名稱', '成交股數', '成交筆數', '成交金額', '開盤價', '最高價', '最低價', '收盤價', '漲跌(+/-)', '漲跌價差'],
          'data': [
            ['2330', '台積電', '35,123,456', '50,000', '1', '1,010.00', '1,060.00', '1,005.00', '1,050.00', '<p>+</p>', '50.00'],
            ['9999', '沒成交', '0', '0', '0', '--', '--', '--', '--', '', '0.00'],
          ],
        },
      ],
    });
    expect(bars.keys, ['2330']);
    final b = bars['2330']!;
    expect([b.open, b.high, b.low, b.close], [1010, 1060, 1005, 1050]);
    expect(b.volumeLots, 35123);
    expect(b.date, '2026-09-29');
  });

  test('證交所舊版 fieldsN / dataN 格式也認得', () {
    final bars = parseTwseDaily('2026-09-29', {
      'stat': 'OK',
      'fields9': ['證券代號', '證券名稱', '成交股數', '成交筆數', '成交金額', '開盤價', '最高價', '最低價', '收盤價'],
      'data9': [
        ['0050', '元大台灣50', '10,000,000', '1', '1', '180.00', '182.00', '179.00', '181.50'],
      ],
    });
    expect(bars['0050']!.close, 181.5);
    expect(bars['0050']!.volumeLots, 10000);
  });

  test('證交所休市日（沒有資料）回傳空的', () {
    expect(parseTwseDaily('2026-10-10', {'stat': '很抱歉，沒有符合條件的資料!'}), isEmpty);
  });

  test('櫃買新版 tables 格式：欄位名稱有空白也能對上', () {
    final bars = parseTpexDaily('2026-09-29', {
      'stat': 'ok',
      'tables': [
        {
          'fields': ['代號', '名稱', '收盤 ', '漲跌', '開盤 ', '最高 ', '最低', '均價 ', '成交股數  ', '成交金額(元)'],
          'data': [
            ['6488', '環球晶', '500.00', '+5.00', '495.00', '505.00', '490.00', '499.00', '2,345,678', '1'],
          ],
        },
      ],
    });
    final b = bars['6488']!;
    expect([b.open, b.high, b.low, b.close], [495, 505, 490, 500]);
    expect(b.volumeLots, 2346);
  });

  test('櫃買舊版 aaData 格式（沒有欄位名稱，照固定順序）', () {
    final bars = parseTpexDaily('2026-09-29', {
      'aaData': [
        ['5347', '世界', '100.00', '+1.00', '99.00', '101.00', '98.50', '100.1', '12,000,000'],
      ],
    });
    expect(bars['5347']!.close, 100);
    expect(bars['5347']!.low, 98.5);
    expect(bars['5347']!.volumeLots, 12000);
  });

  test('櫃買休市日 tables 裡沒資料回傳空的', () {
    expect(
      parseTpexDaily('2026-10-10', {
        'tables': [
          {'fields': ['代號', '名稱', '收盤', '漲跌', '開盤', '最高', '最低', '均價', '成交股數'], 'data': []},
        ],
      }),
      isEmpty,
    );
  });
}
