import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stock_screener/data/history_store.dart';
import 'package:stock_screener/data/local_store.dart';
import 'package:stock_screener/logic/technical_screen.dart';
import 'package:stock_screener/services/history_service.dart';

Map<String, dynamic> twse(String code, double close) => {
  'stat': 'OK',
  'tables': [
    {
      'fields': ['證券代號', '證券名稱', '成交股數', '開盤價', '最高價', '最低價', '收盤價'],
      'data': [
        [code, 'x', '1,000,000', '$close', '$close', '$close', '$close'],
      ],
    },
  ],
};

Map<String, dynamic> tpex(String code, double close) => {
  'tables': [
    {
      'fields': ['代號', '名稱', '收盤', '漲跌', '開盤', '最高', '最低', '均價', '成交股數'],
      'data': [
        [code, 'y', '$close', '0', '$close', '$close', '$close', '$close', '2,000,000'],
      ],
    },
  ],
};

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('screener_test'));
  tearDown(() async => tmp.delete(recursive: true));

  test('candidateDates 跳過週末；15:00 前不含今天', () {
    // 2026-09-30 是星期三
    final morning = candidateDates(DateTime.utc(2026, 9, 30, 10), 7);
    expect(morning, ['2026-09-29', '2026-09-28', '2026-09-25', '2026-09-24', '2026-09-23']);
    final evening = candidateDates(DateTime.utc(2026, 9, 30, 16), 7);
    expect(evening.first, '2026-09-30');
  });

  test('同步：抓到的日子存進本機，休市日也記住，重開 App 讀得回來', () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      final isTwse = req.url.host.contains('twse');
      final date = req.url.queryParameters['date']!;
      // 9/28 當作休市（兩邊都沒資料）
      if (date.contains('0928') || date.contains('09/28')) {
        return http.Response.bytes(utf8.encode(jsonEncode(isTwse ? {'stat': '很抱歉，沒有符合條件的資料!'} : {'tables': []})), 200);
      }
      final close = date.contains('0929') || date.contains('09/29') ? 110.0 : 100.0;
      return http.Response.bytes(utf8.encode(jsonEncode(isTwse ? twse('2330', close) : tpex('6488', close))), 200);
    });
    final now = DateTime.utc(2026, 9, 30, 10);
    final store = HistoryStore(
      store: LocalStore(dir: tmp),
      service: HistoryService(client: client),
      requestGap: Duration.zero,
    );
    await store.load();
    await store.setLookbackDays(5);
    expect(store.missingDates(now), ['2026-09-29', '2026-09-28', '2026-09-25']);

    await store.sync(now: now);
    expect(store.lastError, isNull);
    expect(store.tradingDates, ['2026-09-25', '2026-09-29']);
    expect(store.missingDates(now), isEmpty);
    expect(store.seriesOf('2330').map((b) => b.close), [100, 110]);
    expect(store.seriesOf('6488').map((b) => b.volumeLots), [2000, 2000]);

    // 重新開一個 store（模擬重開 App），資料和設定都要讀得回來，而且不用重抓
    final before = requests;
    final reopened = HistoryStore(
      store: LocalStore(dir: tmp),
      service: HistoryService(client: client),
    );
    await reopened.load();
    expect(reopened.lookbackDays, 5);
    expect(reopened.tradingDates, ['2026-09-25', '2026-09-29']);
    expect(reopened.missingDates(now), isEmpty);
    expect(requests, before);
  });

  test('連續 3 天抓不到就停下來，不存任何失敗的日子', () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      return http.Response('blocked', 403);
    });
    final now = DateTime.utc(2026, 9, 30, 10);
    final store = HistoryStore(
      store: LocalStore(dir: tmp),
      service: HistoryService(client: client),
      requestGap: Duration.zero,
    );
    await store.load();
    await store.sync(now: now);
    expect(store.lastError, contains('連續 3 天'));
    expect(store.tradingDates, isEmpty);
    expect(requests, 6); // 3 天 × 上市/上櫃
  });

  test('篩選條件會存檔', () async {
    final store = HistoryStore(store: LocalStore(dir: tmp));
    await store.load();
    await store.setCriteria(const ScreenCriteria(rsiMax: 30, sort: ScreenSort.rsi));
    final reopened = HistoryStore(store: LocalStore(dir: tmp));
    await reopened.load();
    expect(reopened.criteria.rsiMax, 30);
    expect(reopened.criteria.sort, ScreenSort.rsi);
  });
}
