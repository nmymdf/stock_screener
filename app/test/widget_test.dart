import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/data/history_store.dart';
import 'package:stock_screener/data/local_store.dart';
import 'package:stock_screener/main.dart';
import 'package:stock_screener/models/daily_bar.dart';
import 'package:stock_screener/ui/home.dart';
import 'package:stock_screener/ui/screens/industry_screen.dart';
import 'package:stock_screener/ui/screens/risk_settings_screen.dart';
import 'package:stock_screener/ui/screens/stock_report_screen.dart';
import 'package:stock_screener/ui/screens/tools_screen.dart';
import 'package:stock_screener/ui/widgets/charts.dart';

import 'support/synthetic.dart';

void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('沒有資料時：顯示說明和「開始抓歷史資料」，五個分頁都切得過去', (tester) async {
    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('screener_widget'));
    final store = HistoryStore(store: LocalStore(dir: tmp), useIsolate: false);
    await tester.runAsync(store.load);

    await tester.pumpWidget(StockScreenerApp(store: store));
    await tester.pump();
    expect(find.text('台股選股系統'), findsOneWidget);
    expect(find.text('開始抓歷史資料'), findsOneWidget);

    await tester.tap(find.text('市場'));
    await tester.pump();
    expect(find.text('開始抓歷史資料'), findsOneWidget);

    await tester.tap(find.text('回測'));
    await tester.pump();
    expect(find.text('策略回測'), findsOneWidget);

    await tester.tap(find.text('工具'));
    await tester.pump();
    await tester.tap(find.text('資料管理'));
    await tester.pumpAndSettle();
    expect(find.text('清除所有歷史資料'), findsOneWidget);

    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('寬螢幕用側邊選單', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('screener_widget'));
    final store = HistoryStore(store: LocalStore(dir: tmp), useIsolate: false);
    await tester.runAsync(store.load);
    await tester.pumpWidget(StockScreenerApp(store: store));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('有資料時：推薦、市場、產業、回測、個股報告都畫得出來', (tester) async {
    useTallScreen(tester);
    final dates = tradingDays(260);
    final tmp = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('screener_widget');
      final local = LocalStore(dir: dir);
      final series = syntheticMarket(dates, stocks: 90, bias: 0.3);
      series['2330'] = breakoutStock(dates);
      for (var d = 0; d < dates.length; d++) {
        await local.writeDay(
          dates[d],
          DaySnapshot(
            date: dates[d],
            trading: true,
            bars: {for (final e in series.entries) e.key: e.value[d]},
          ).toJson(),
        );
      }
      return dir;
    });
    final store = HistoryStore(store: LocalStore(dir: tmp), useIsolate: false)..lookbackDays = 5000;
    await tester.runAsync(store.load);
    expect(store.analysis?.latestDate, dates.last);

    await tester.pumpWidget(StockScreenerApp(store: store));
    await tester.pump();
    expect(find.text('今日推薦'), findsOneWidget);
    expect(find.text('通過否決＝推薦'), findsOneWidget);

    await tester.tap(find.text('市場').first);
    await tester.pump();
    expect(find.text('市場環境'), findsOneWidget);
    expect(find.text('分數怎麼來的'), findsOneWidget);

    await tester.tap(find.text('產業').first);
    await tester.pump();
    expect(find.text('產業強弱與輪動'), findsOneWidget);
    expect(store.analysis!.industries, isNotEmpty);
    expect(find.text(store.analysis!.industries.first.name), findsWidgets);

    // 個股報告：2330 有 A 突破訊號，一定有交易計畫
    Navigator.of(tester.element(find.byType(HomeShell)))
        .push(MaterialPageRoute(builder: (_) => const StockReportScreen(code: '2330')));
    await tester.pumpAndSettle();
    expect(find.textContaining('交易計畫 · A 突破型'), findsOneWidget);
    expect(find.text('為什麼選它'), findsOneWidget);
    expect(find.byType(SimpleChart), findsOneWidget);
    expect(find.textContaining('分數拆解'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('回測').first);
    await tester.pump();
    await tester.tap(find.text('開始回測'));
    await tester.pump();
    await tester.pump();
    expect(store.backtest, isNotNull);
    expect(find.textContaining('結果：'), findsOneWidget);

    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('自訂條件篩選：列出結果，點進去是個股報告', (tester) async {
    useTallScreen(tester);
    final tmp = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('screener_widget');
      final local = LocalStore(dir: dir);
      for (var i = 0; i < 70; i++) {
        final date = ymd(DateTime.utc(2026, 5, 1).add(Duration(days: i)));
        DailyBar bar(double c) => DailyBar(date: date, open: c, high: c, low: c, close: c, volumeLots: 2000);
        await local.writeDay(
          date,
          DaySnapshot(date: date, trading: true, bars: {'2330': bar(500.0 + i * 5), '2317': bar(200.0 - i)}).toJson(),
        );
      }
      return dir;
    });
    final store = HistoryStore(store: LocalStore(dir: tmp), useIsolate: false)..lookbackDays = 5000;
    await tester.runAsync(store.load);

    await tester.pumpWidget(StockScreenerApp(store: store));
    await tester.pump();
    await tester.tap(find.text('工具'));
    await tester.pump();
    await tester.tap(find.text('自訂條件篩選'));
    await tester.pumpAndSettle();
    expect(find.textContaining('符合 1 檔'), findsOneWidget);
    await tester.tap(find.textContaining('2330 台積電'));
    await tester.pumpAndSettle();
    expect(find.text('符合自訂條件'), findsOneWidget);
    expect(find.byType(SimpleChart), findsOneWidget);

    await tester.runAsync(() => tmp!.delete(recursive: true));
  });

  testWidgets('手機寬度（390）每個畫面都不會跑版', (tester) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dates = tradingDays(260);
    final tmp = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('screener_widget');
      final local = LocalStore(dir: dir);
      final series = syntheticMarket(dates, stocks: 90, bias: 0.3);
      series['2330'] = breakoutStock(dates);
      for (var d = 0; d < dates.length; d++) {
        await local.writeDay(
          dates[d],
          DaySnapshot(date: dates[d], trading: true, bars: {for (final e in series.entries) e.key: e.value[d]}).toJson(),
        );
      }
      return dir;
    });
    final store = HistoryStore(store: LocalStore(dir: tmp), useIsolate: false)..lookbackDays = 5000;
    await tester.runAsync(store.load);
    await tester.pumpWidget(StockScreenerApp(store: store));
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final tab in ['市場', '產業', '回測', '工具', '推薦']) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
    }
    await tester.tap(find.text('回測').last);
    await tester.pump();
    await tester.tap(find.text('開始回測'));
    await tester.pump();
    await tester.pump();
    Navigator.of(tester.element(find.byType(HomeShell)))
        .push(MaterialPageRoute(builder: (_) => const StockReportScreen(code: '2330')));
    await tester.pumpAndSettle();
    expect(find.text('為什麼選它'), findsOneWidget);
    final nav = Navigator.of(tester.element(find.byType(HomeShell, skipOffstage: false)));
    for (final page in <Widget>[
      const MethodScreen(),
      const RiskSettingsScreen(),
      IndustryDetailScreen(name: store.analysis!.industries.first.name),
    ]) {
      nav.push(MaterialPageRoute(builder: (_) => page));
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() => tmp!.delete(recursive: true));
  });
}
