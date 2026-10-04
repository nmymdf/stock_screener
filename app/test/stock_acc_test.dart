import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_screener/data/holdings_store.dart';
import 'package:stock_screener/data/local_store.dart';
import 'package:stock_screener/data/stock_acc_source.dart';
import 'package:stock_screener/data/stock_industry.dart';
import 'package:stock_screener/logic/holding_eval.dart';
import 'package:stock_screener/models/holding.dart';

AccTrade t(
  String date,
  String code,
  bool buy,
  int shares,
  double price, {
  double fee = 20,
  double tax = 0,
  int order = 0,
}) => AccTrade(
  date: date,
  code: code,
  name: '',
  buy: buy,
  shares: shares,
  price: price,
  fee: fee,
  tax: tax,
  order: order,
);

/// 跟 stock_acc 存檔一模一樣的格式（Trade.toJson）。
Map<String, dynamic> trade(String id, String acc, String date, String code, String side, int shares, double price) => {
  'id': id,
  'accountId': acc,
  'date': '${date}T00:00:00.000',
  'code': code,
  'name': '名稱',
  'side': side,
  'shares': shares,
  'price': price,
  'fee': 20,
  'tax': side == 'sell' ? 150 : 0,
  'updatedAt': '2026-01-01T00:00:00.000',
};

Future<Directory> writeAcc(Directory root, {bool legacy = false}) async {
  final dir = Directory('${root.path}/stock_acc')..createSync(recursive: true);
  final g1 = {
    'schemaVersion': 1,
    'persons': [],
    'accounts': [],
    'trades': [
      trade('1', 'a1', '2026-01-05', '2330', 'buy', 1000, 600),
      trade('2', 'a1', '2026-02-10', '2330', 'sell', 1000, 650),
      trade('3', 'a1', '2026-03-02', '2330', 'buy', 2000, 700),
    ],
    'watchlist': [],
  };
  final g2 = {
    'schemaVersion': 1,
    'trades': [
      trade('4', 'b1', '2026-03-05', '2330', 'buy', 1000, 720),
      trade('5', 'b1', '2026-03-06', '2317', 'buy', 3000, 150),
    ],
  };
  if (legacy) {
    File('${dir.path}/stock_acc_data.json').writeAsStringSync(jsonEncode(g1));
  } else {
    File('${dir.path}/stock_acc_groups.json').writeAsStringSync(
      jsonEncode({
        'groups': [
          {'id': 'g1', 'name': '我', 'createdAt': '2026-01-01T00:00:00.000'},
          {'id': 'g2', 'name': '家人', 'createdAt': '2026-01-01T00:00:00.000'},
        ],
        'activeId': 'g1',
      }),
    );
    File('${dir.path}/stock_acc_data_g1.json').writeAsStringSync(jsonEncode(g1));
    File('${dir.path}/stock_acc_data_g2.json').writeAsStringSync(jsonEncode(g2));
  }
  return dir;
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('acc_test'));
  tearDown(() async => tmp.delete(recursive: true));

  group('交易整理成持股', () {
    test('賣到 0 就結案；之後再買是新的一筆；不同帳戶同一檔合併', () {
      final p = positionsFromTrades([
        t('2026-01-05', '2330', true, 1000, 600),
        t('2026-02-10', '2330', false, 1000, 650, tax: 1950),
        t('2026-03-02', '2330', true, 2000, 700),
        t('2026-03-05', '2330', true, 1000, 720), // 另一個帳戶
        t('2026-03-06', '2317', true, 3000, 150),
      ]);
      final tsmc = p.where((h) => h.code == '2330').toList();
      expect(tsmc, hasLength(2));
      expect(tsmc.first.closed, true);
      expect(tsmc.first.sells.single.tax, 1950);
      expect(tsmc.last.closed, false);
      expect(tsmc.last.shares, 3000);
      expect(tsmc.last.firstBuyDate, '2026-03-02');
      expect(tsmc.last.id, 'acc_2330_2026-03-02');
      expect(p.every((h) => h.fromStockAcc), true);
    });

    test('同一天先算買進再算賣出；超賣（記帳錯誤）不會變成負股數', () {
      final p = positionsFromTrades([
        t('2026-01-05', '2330', false, 1000, 610, order: 0),
        t('2026-01-05', '2330', true, 1000, 600, order: 1),
        t('2026-01-08', '2454', true, 1000, 900),
        t('2026-01-09', '2454', false, 3000, 950, tax: 3000),
      ]);
      expect(p.firstWhere((h) => h.code == '2330').closed, true);
      final mtk = p.firstWhere((h) => h.code == '2454');
      expect(mtk.closed, true);
      expect(mtk.sells.single.shares, 1000);
      expect(mtk.sells.single.tax, closeTo(1000, 1e-9)); // 稅照比例
    });

    test('已實現損益用 stock_acc 的實際手續費和稅', () {
      final h = positionsFromTrades([
        t('2026-01-05', '2330', true, 1000, 600, fee: 500),
        t('2026-02-10', '2330', false, 1000, 650, fee: 500, tax: 1950),
      ]).single;
      expect(realizedPnl(h, SecurityType.stock), closeTo(650000 - 500 - 1950 - 600000 - 500, 1e-6));
    });
  });

  group('讀 stock_acc 的檔案', () {
    test('讀所有群體的交易', () async {
      await writeAcc(tmp);
      final src = StockAccSource(dir: Directory('${tmp.path}/stock_acc'));
      expect(await src.locate(), isNotNull);
      final trades = await src.readTrades();
      expect(trades, hasLength(5));
      expect(trades.first.date, '2026-01-05');
      expect(trades.where((x) => x.code == '2317').single.shares, 3000);
    });

    test('舊版只有一個資料檔也讀得到', () async {
      await writeAcc(tmp, legacy: true);
      final trades = await StockAccSource(dir: Directory('${tmp.path}/stock_acc')).readTrades();
      expect(trades, hasLength(3));
    });

    test('沒有 stock_acc（朋友的電腦）：找不到，什麼都不讀', () async {
      final src = StockAccSource(dir: Directory('${tmp.path}/stock_acc'));
      expect(await src.locate(), isNull);
      expect(await src.readTrades(), isEmpty);
    });

    test('檔案讀到一半（不完整）：丟出格式錯誤', () async {
      final dir = await writeAcc(tmp);
      File('${dir.path}/stock_acc_data_g2.json').writeAsStringSync('{"trades": [ {"id": ');
      expect(() => StockAccSource(dir: dir).readTrades(), throwsA(isA<FormatException>()));
    });
  });

  group('持股的兩組', () {
    test('同步 stock_acc；設定保留；手動持股不受影響；stock_acc 的買賣不能在這裡改', () async {
      final accDir = await writeAcc(tmp);
      final local = LocalStore(dir: Directory('${tmp.path}/mine'));
      final store = HoldingsStore(
        store: local,
        accSource: StockAccSource(dir: accDir),
      );
      await store.load();
      expect(store.accAvailable, true);
      expect(store.accHoldings.where((h) => !h.closed).map((h) => h.code), containsAll(['2330', '2317']));
      expect(store.manual, isEmpty);

      // 手動持股同一檔也可以存在
      await store.upsert(
        const Holding(id: 'm1', code: '2330', style: HoldStyle.short, buys: [BuyLot('2026-03-01', 690, 1000)]),
      );
      expect(store.openFor('2330', source: HoldingSource.manual)!.id, 'm1');
      expect(store.openFor('2330', source: HoldingSource.stockAcc)!.shares, 3000);

      // 改 stock_acc 持股的持有方式、停損 → 重新同步、重開 App 都還在
      final acc = store.openFor('2330', source: HoldingSource.stockAcc)!;
      await store.upsert(acc.copyWith(style: HoldStyle.long, manualStop: 650, note: '長抱'));
      await store.syncAcc();
      final reopened = HoldingsStore(
        store: local,
        accSource: StockAccSource(dir: accDir),
      );
      await reopened.load();
      final again = reopened.openFor('2330', source: HoldingSource.stockAcc)!;
      expect(again.style, HoldStyle.long);
      expect(again.manualStop, 650);
      expect(again.note, '長抱');
      expect(again.shares, 3000);
      expect(reopened.manual.single.id, 'm1');

      // stock_acc 的買賣紀錄不能在台股選股加減、也不能刪
      await reopened.addBuy(again.id, const BuyLot('2026-03-10', 700, 1000));
      await reopened.remove(again.id);
      expect(reopened.openFor('2330', source: HoldingSource.stockAcc)!.shares, 3000);
    });

    test('沒有 stock_acc：整組隱藏，手動照常', () async {
      final store = HoldingsStore(
        store: LocalStore(dir: Directory('${tmp.path}/mine')),
        accSource: StockAccSource(dir: Directory('${tmp.path}/none')),
      );
      await store.load();
      expect(store.accAvailable, false);
      expect(store.accHoldings, isEmpty);
    });

    test('stock_acc 檔案壞掉：保留上一次的結果並說明', () async {
      final accDir = await writeAcc(tmp);
      final store = HoldingsStore(
        store: LocalStore(dir: Directory('${tmp.path}/mine')),
        accSource: StockAccSource(dir: accDir),
      );
      await store.load();
      final before = store.accHoldings.length;
      File('${accDir.path}/stock_acc_data_g1.json').writeAsStringSync('{"trades": [');
      await store.syncAcc();
      expect(store.accHoldings.length, before);
      expect(store.accError, contains('再按一次'));
    });
  });

  test('修改買賣紀錄的檢查：不能沒有買進、不能賣超過持有', () {
    expect(validateLots(const [], const []), contains('刪除整筆持股'));
    expect(
      validateLots(const [BuyLot('2026-01-02', 100, 1000)], const [SellLot('2026-01-05', 110, 2000)]),
      contains('超過'),
    );
    expect(
      validateLots(const [BuyLot('2026-01-05', 100, 1000)], const [SellLot('2026-01-02', 110, 500)]),
      contains('超過'),
    );
    expect(validateLots(const [BuyLot('2026-01-02', 100, 1000)], const [SellLot('2026-01-05', 110, 1000)]), isNull);
  });

  group('長期持有習慣與追蹤起點', () {
    test('stock_acc 預設長期；已經持有兩週以上的，從第一次同步那天開始追蹤；設定會存下來', () async {
      final accDir = await writeAcc(tmp);
      final local = LocalStore(dir: Directory('${tmp.path}/mine'));
      final store = HoldingsStore(
        store: local,
        accSource: StockAccSource(dir: accDir),
      )..today = () => '2026-06-01';
      await store.load();
      final tsmc = store.openFor('2330', source: HoldingSource.stockAcc)!;
      expect(tsmc.style, HoldStyle.long);
      expect(tsmc.trackSince, '2026-06-01');
      expect(tsmc.takenOver, true);
      // 已結案的不用設追蹤起點
      expect(store.accHoldings.where((h) => h.closed).every((h) => h.trackSince == null), true);

      // 改預設持有習慣、回落容忍 → 存檔，重開還在；追蹤起點不會因為隔天再同步而往後跑
      await store.setAccDefaultStyle(HoldStyle.swing);
      await store.setDrawdownLimit(0.3);
      expect(store.openFor('2330', source: HoldingSource.stockAcc)!.style, HoldStyle.swing);
      final reopened = HoldingsStore(
        store: local,
        accSource: StockAccSource(dir: accDir),
      )..today = () => '2026-06-20';
      await reopened.load();
      expect(reopened.accDefaultStyle, HoldStyle.swing);
      expect(reopened.drawdownLimit, 0.3);
      expect(reopened.openFor('2330', source: HoldingSource.stockAcc)!.trackSince, '2026-06-01');

      // 個別改過的持有方式不受預設影響
      final h = reopened.openFor('2317', source: HoldingSource.stockAcc)!;
      await reopened.upsert(h.copyWith(style: HoldStyle.long));
      await reopened.setAccDefaultStyle(HoldStyle.short);
      expect(reopened.openFor('2317', source: HoldingSource.stockAcc)!.style, HoldStyle.long);
      expect(reopened.openFor('2330', source: HoldingSource.stockAcc)!.style, HoldStyle.short);

      // 從今天重新開始追蹤
      reopened.today = () => '2026-07-01';
      await reopened.restartTracking(h.id);
      expect(reopened.openFor('2317', source: HoldingSource.stockAcc)!.trackSince, '2026-07-01');
    });

    test('手動新增的持股買進日是兩週以前，也從今天開始追蹤；最近買的照常從買進日', () async {
      final store = HoldingsStore(store: LocalStore(dir: Directory('${tmp.path}/mine')))..today = () => '2026-06-01';
      await store.load();
      await store.upsert(
        const Holding(id: 'a', code: '2330', style: HoldStyle.long, buys: [BuyLot('2025-01-02', 500, 1000)]),
      );
      await store.upsert(
        const Holding(id: 'b', code: '2317', style: HoldStyle.swing, buys: [BuyLot('2026-05-28', 150, 1000)]),
      );
      expect(store.byId('a')!.trackSince, '2026-06-01');
      expect(store.byId('b')!.trackSince, isNull);
    });
  });
}
