import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/logic/momentum.dart';
import 'package:stock_screener/services/quote_service.dart';

LiveQuote _q({
  required String code,
  required double price,
  required double prevClose,
  double? open,
  double? high,
  double? low,
  int volumeLots = 0,
}) => LiveQuote(
  code: code,
  price: price,
  prevClose: prevClose,
  open: open ?? price,
  high: high ?? price,
  low: low ?? price,
  volumeLots: volumeLots,
);

void main() {
  test('只保留今天上漲的股票，下跌或平盤的不算候選', () {
    final hits = rankByMomentum([
      _q(code: 'A', price: 110, prevClose: 100),
      _q(code: 'B', price: 100, prevClose: 100),
      _q(code: 'C', price: 90, prevClose: 100),
    ]);
    expect(hits.map((h) => h.code), ['A']);
  });

  test('漲幅大的排前面，量能大、貼近今日高點的分數會加分', () {
    final hits = rankByMomentum([
      _q(code: 'SMALL_RISE', price: 101, prevClose: 100, high: 105, low: 99, volumeLots: 100),
      _q(code: 'BIG_RISE_STRONG', price: 108, prevClose: 100, high: 108, low: 98, volumeLots: 5000),
    ]);
    expect(hits.first.code, 'BIG_RISE_STRONG');
    expect(hits.first.score, greaterThan(hits.last.score));
  });

  test('解析即時報價：還沒成交（z = -）用昨收，數字有千分位也能讀', () {
    final quotes = parseLiveQuotes({
      'msgArray': [
        {'c': '2330', 'z': '1,050.00', 'y': '1,000.00', 'o': '1,010', 'h': '1,060', 'l': '1,005', 'v': '35,123'},
        {'c': '0050', 'z': '-', 'y': '180.5'},
        {'c': 'BAD', 'z': '-', 'y': '-'},
      ],
    });
    expect(quotes.map((q) => q.code), ['2330', '0050']);
    expect(quotes.first.changePct, closeTo(5, 1e-9));
    expect(quotes.first.volumeLots, 35123);
    expect(quotes.last.price, 180.5);
  });
}
