import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/data/history_store.dart';
import 'package:stock_screener/data/local_store.dart';
import 'package:stock_screener/main.dart';
import 'package:stock_screener/models/daily_bar.dart';
import 'package:stock_screener/ui/screens/stock_detail_screen.dart';

void main() {
  testWidgets('App 開得起來，三個分頁都切得過去', (tester) async {
    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('screener_widget'));
    final store = HistoryStore(store: LocalStore(dir: tmp));
    await tester.runAsync(store.load);

    await tester.pumpWidget(StockScreenerApp(store: store));
    await tester.pump();
    expect(find.textContaining('不是投資建議'), findsOneWidget);
    expect(find.text('開始抓歷史資料'), findsOneWidget);

    await tester.tap(find.text('今日雷達'));
    await tester.pump();
    expect(find.text('開始掃描'), findsOneWidget);

    await tester.tap(find.text('資料'));
    await tester.pump();
    expect(find.text('清除所有歷史資料'), findsOneWidget);

    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('寬螢幕用側邊選單', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('screener_widget'));
    final store = HistoryStore(store: LocalStore(dir: tmp));
    await tester.runAsync(store.load);
    await tester.pumpWidget(StockScreenerApp(store: store));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('有歷史資料時列出篩選結果，點進去看得到個股頁和走勢圖', (tester) async {
    final tmp = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('screener_widget');
      final local = LocalStore(dir: dir);
      // 70 個交易日：2330 一路漲（多頭排列），2317 一路跌
      for (var i = 0; i < 70; i++) {
        final date = ymd(DateTime.utc(2026, 5, 1).add(Duration(days: i)));
        DailyBar bar(double c) => DailyBar(date: date, open: c, high: c, low: c, close: c, volumeLots: 2000);
        await local.writeDay(date, DaySnapshot(date: date, trading: true, bars: {
          '2330': bar(500.0 + i * 5),
          '2317': bar(200.0 - i),
        }).toJson());
      }
      return dir;
    });
    final store = HistoryStore(store: LocalStore(dir: tmp));
    await tester.runAsync(store.load);
    expect(store.tradingDates.length, 70);

    await tester.pumpWidget(StockScreenerApp(store: store));
    await tester.pump();
    expect(find.textContaining('符合 1 檔'), findsOneWidget);
    expect(find.textContaining('2330 台積電'), findsOneWidget);

    await tester.tap(find.textContaining('2330 台積電'));
    await tester.pumpAndSettle();
    expect(find.byType(PriceChart), findsOneWidget);
    expect(find.text('上榜理由'), findsOneWidget);

    await tester.runAsync(() => tmp!.delete(recursive: true));
  });
}
