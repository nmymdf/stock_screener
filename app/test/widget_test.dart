import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/data/history_store.dart';
import 'package:stock_screener/data/holdings_store.dart';
import 'package:stock_screener/data/local_store.dart';
import 'package:stock_screener/logic/holding_eval.dart';
import 'package:stock_screener/main.dart';
import 'package:stock_screener/models/daily_bar.dart';
import 'package:stock_screener/models/holding.dart';
import 'package:stock_screener/ui/home.dart';
import 'package:stock_screener/ui/screens/holding_detail_screen.dart';
import 'package:stock_screener/ui/screens/industry_screen.dart';
import 'package:stock_screener/ui/screens/stock_report_screen.dart';
import 'package:stock_screener/ui/screens/tools_screen.dart';
import 'package:stock_screener/ui/widgets/charts.dart';

import 'support/synthetic.dart';

Future<HoldingsStore> holdingsIn(WidgetTester tester, Directory dir) async {
  final h = HoldingsStore(store: LocalStore(dir: dir));
  await tester.runAsync(h.load);
  return h;
}

/// 讓真正的檔案讀寫有機會完成（widget 測試裡的時間是假的）。
Future<void> settleIo(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}

/// 260 個交易日的模擬市場，2330 最後一天放量突破。
Future<(Directory, HistoryStore, List<String>)> seededMarket(WidgetTester tester) async {
  final dates = tradingDays(260);
  final dir = await tester.runAsync(() async {
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
  final store = HistoryStore(store: LocalStore(dir: dir), useIsolate: false)..lookbackDays = 5000;
  await tester.runAsync(store.load);
  return (dir!, store, dates);
}

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

    await tester.pumpWidget(StockScreenerApp(store: store, holdings: await holdingsIn(tester, tmp!)));
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

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('寬螢幕用側邊選單', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('screener_widget'));
    final store = HistoryStore(store: LocalStore(dir: tmp), useIsolate: false);
    await tester.runAsync(store.load);
    await tester.pumpWidget(StockScreenerApp(store: store, holdings: await holdingsIn(tester, tmp!)));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.runAsync(() => tmp.delete(recursive: true));
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

    await tester.pumpWidget(StockScreenerApp(store: store, holdings: await holdingsIn(tester, tmp!)));
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
    expect(find.text('白話結論'), findsOneWidget);

    await tester.runAsync(() => tmp.delete(recursive: true));
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

    await tester.pumpWidget(StockScreenerApp(store: store, holdings: await holdingsIn(tester, tmp!)));
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

    await tester.runAsync(() => tmp.delete(recursive: true));
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
    final holdings = await holdingsIn(tester, tmp!);
    final b = store.rawSeriesOf('2330');
    await tester.runAsync(
      () => holdings.upsert(
        Holding(
          id: 'p1',
          code: '2330',
          style: HoldStyle.short,
          buys: [BuyLot(b[b.length - 25].date, b[b.length - 25].close, 2000)],
          strategy: 'B',
          duration: 1,
        ),
      ),
    );
    await tester.pumpWidget(StockScreenerApp(store: store, holdings: holdings));
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final tab in ['持股', '市場', '產業', '回測', '工具', '推薦']) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
    }
    for (final mode in ['觀察池', '被否決', '推薦']) {
      await tester.tap(find.textContaining(mode).first);
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
      IndustryDetailScreen(name: store.analysis!.industries.first.name),
      const HoldingDetailScreen(id: 'p1'),
    ]) {
      nav.push(MaterialPageRoute(builder: (_) => page));
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('持股：從個股報告「我已進場」加入，持股頁看得到狀態，點進去有停損與紀錄', (tester) async {
    useTallScreen(tester);
    final (tmp, store, dates) = await seededMarket(tester);
    final holdings = await holdingsIn(tester, tmp);
    await tester.pumpWidget(StockScreenerApp(store: store, holdings: holdings));
    await tester.pump();

    await tester.tap(find.text('持股').first);
    await tester.pump();
    expect(find.text('我的持股'), findsOneWidget);
    expect(find.text('持股追蹤怎麼用'), findsOneWidget);

    Navigator.of(tester.element(find.byType(HomeShell)))
        .push(MaterialPageRoute(builder: (_) => const StockReportScreen(code: '2330')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已進場（加入持股追蹤）'));
    await tester.pumpAndSettle();
    expect(find.text('新增持股'), findsOneWidget);
    expect(find.textContaining('使用推薦時的停損'), findsOneWidget);
    await tester.tap(find.text('加入我的持股'));
    await settleIo(tester);
    expect(holdings.open, hasLength(1));
    final h = holdings.open.single;
    expect(h.code, '2330');
    expect(h.strategy, 'A');
    expect(h.planStop, isNotNull);
    expect(find.textContaining('已持有 1000 股'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('今日摘要'), findsOneWidget);
    // 今日摘要裡列一次、持股卡片一次
    expect(find.text('2330 台積電'), findsNWidgets(2));

    await tester.tap(find.text('2330 台積電').last);
    await tester.pumpAndSettle();
    expect(find.byType(HoldingDetailScreen), findsOneWidget);
    expect(find.text('成本、損益、停損'), findsOneWidget);
    expect(find.text('買賣紀錄'), findsOneWidget);
    expect(find.text('記錄賣出'), findsOneWidget);

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('持股：虧損時加碼會出現「禁止向下攤平」，要勾選確認才能記錄', (tester) async {
    useTallScreen(tester);
    final (tmp, store, dates) = await seededMarket(tester);
    final holdings = await holdingsIn(tester, tmp);
    final last = store.rawSeriesOf('2330').last.close;
    await tester.runAsync(
      () => holdings.upsert(
        Holding(
          id: 'h1',
          code: '2330',
          style: HoldStyle.swing,
          buys: [BuyLot(dates[dates.length - 5], last * 1.3, 1000)],
        ),
      ),
    );
    await tester.pumpWidget(StockScreenerApp(store: store, holdings: holdings));
    await tester.pump();
    Navigator.of(tester.element(find.byType(HomeShell)))
        .push(MaterialPageRoute(builder: (_) => const HoldingDetailScreen(id: 'h1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加碼（記錄買進）'));
    await tester.pumpAndSettle();
    expect(find.text('⚠ 禁止向下攤平'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, '記錄加碼');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('持股詳細：明日劇本、持有理由、加碼時機、每日追蹤紀錄都看得到', (tester) async {
    useTallScreen(tester);
    final (tmp, store, dates) = await seededMarket(tester);
    final holdings = await holdingsIn(tester, tmp);
    final bars = store.rawSeriesOf('2330');
    final buy = bars[bars.length - 30];
    await tester.runAsync(
      () => holdings.upsert(
        Holding(
          id: 'h2',
          code: '2330',
          style: HoldStyle.swing,
          buys: [BuyLot(buy.date, buy.close, 1000)],
          strategy: 'A',
          opportunity: '波段機會',
          duration: 2,
          confidence: '中',
          thesis: const ['整理後放量突破'],
        ),
      ),
    );
    await tester.pumpWidget(StockScreenerApp(store: store, holdings: holdings));
    await tester.pump();
    Navigator.of(tester.element(find.byType(HomeShell)))
        .push(MaterialPageRoute(builder: (_) => const HoldingDetailScreen(id: 'h2')));
    await tester.pumpAndSettle();
    final e = evaluateHolding(
      holdings.byId('h2')!,
      adjusted: store.seriesOf('2330'),
      raw: bars,
      regimeByDate: store.analysis!.regimeByDate,
      taiex: store.taiexByDate,
    );
    expect(e.log, isNotEmpty);
    expect(find.text('持有理由還成立嗎'), findsOneWidget);
    expect(find.textContaining('每日追蹤紀錄'), findsOneWidget);
    expect(find.text(e.log.last.date), findsWidgets);
    if (e.scenario.isNotEmpty) expect(find.text('明日劇本'), findsOneWidget);
    if (!holdings.byId('h2')!.closed && e.addOnPlan.isNotEmpty) expect(find.text('可能的加碼時機'), findsOneWidget);
    expect(find.text('作者: ArchieKUO'), findsOneWidget);

    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  for (final width in [1500.0, 390.0]) {
    testWidgets('比較頁（寬 ${width.round()}）：單檔現況總覽、多檔綜合結論、相對走勢、逐項比較都畫得出來', (tester) async {
      tester.view.physicalSize = Size(width, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (tmp, store, _) = await seededMarket(tester);
      final codes = store.analysis!.stocks.where((s) => s.code != '2330').take(2).map((s) => s.code).toList();
      await tester.runAsync(() => store.setCompareCodes(['2330']));
      await tester.pumpWidget(StockScreenerApp(store: store, holdings: await holdingsIn(tester, tmp)));
      await tester.pump();
      await tester.tap(find.text('比較').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('現況總覽'), findsOneWidget);
      expect(find.text('關鍵價位'), findsOneWidget);

      await tester.runAsync(() => store.setCompareCodes(['2330', ...codes]));
      await tester.pumpAndSettle();
      expect(find.text('綜合結論'), findsOneWidget);
      expect(find.text('逐項比較'), findsOneWidget);
      expect(find.text('相對走勢（起點 = 100）'), findsOneWidget);
      await tester.tap(find.text('1 年'));
      await tester.pumpAndSettle();

      // 用輸入框一次加入多檔
      await tester.runAsync(() => store.setCompareCodes(const []));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '2330 ${codes.first}');
      await tester.tap(find.text('加入'));
      await tester.pumpAndSettle();
      expect(store.compareCodes, ['2330', codes.first]);

      if (width >= 1100) {
        expect(find.text('市場分數 '), findsOneWidget);
        // 抬頭的字體放大：A＋ 之後倍率變大並記住
        // 字體大小要影響整個 App，不只抬頭：頁面標題的字也要跟著變大
        double scaleOf(Finder f) => MediaQuery.textScalerOf(tester.element(f)).scale(10) / 10;
        final title = find.text('個股查詢與比較');
        final before = scaleOf(title);
        await tester.tap(find.text('A＋'));
        await tester.pumpAndSettle();
        expect(store.fontScale, greaterThan(1.15));
        expect(scaleOf(title), greaterThan(before));
        expect(scaleOf(title), closeTo(store.fontScale!, 1e-9));
      }
      await tester.runAsync(() => tmp.delete(recursive: true));
    });
  }
}
