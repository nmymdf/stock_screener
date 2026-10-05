import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stock_screener/core/pack.dart';
import 'package:stock_screener/core/sources.dart';
import 'package:stock_screener/data/datapack_store.dart';
import 'package:stock_screener/data/history_store.dart';
import 'package:stock_screener/data/local_store.dart';
import 'package:stock_screener/logic/dividend_income.dart';
import 'package:stock_screener/models/daily_bar.dart';
import 'package:stock_screener/models/holding.dart';

/// 假的 GitHub Releases：檔名 → 內容。
class FakeRelease {
  final Map<String, List<int>> files = {};
  final List<String> requested = [];

  void put(String name, Map<String, dynamic> json) => files[name] = encodeGz(json);

  Map<String, dynamic> manifest({String lastDate = '2026-10-02', Map<String, (String?, String?)> ranges = const {}}) =>
      {
        'v': 1,
        'updated': '2026-10-02T13:40:00Z',
        'lastDate': lastDate,
        'files': {
          for (final e in files.entries)
            e.key: {
              'size': e.value.length,
              'hash': fingerprint(e.value),
              'first': ranges[e.key]?.$1,
              'last': ranges[e.key]?.$2,
            },
        },
      };

  http.Client client(Map<String, dynamic> Function() m) => MockClient((req) async {
    final name = req.url.pathSegments.last;
    requested.add(name);
    if (name == 'manifest.json') return http.Response(jsonEncode(m()), 200);
    final b = files[name];
    return b == null ? http.Response('not found', 404) : http.Response.bytes(b, 200);
  });
}

PackDay day(String date, double close, {double? change}) => PackDay(
  date: date,
  taiex: 20000,
  tri: 40000,
  twse: {
    '2330': [close, close, close, close, 1000, ?change],
  },
  tpex: {
    '6488': [100, 100, 100, 100, 50, 0],
  },
);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('datapack'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('第一次下載全部；之後今年的檔案跟最近 30 天接得上就不重抓，舊年份有變才重抓', () async {
    final rel = FakeRelease();
    rel.put('lt-2025.json.gz', {'v': 1, 'dates': [], 'ix': [], 'tr': [], 's': {}});
    rel.put('lt-2026.json.gz', {
      'v': 1,
      'dates': ['2026-09-30'],
      'ix': [1],
      'tr': [1],
      's': {},
    });
    rel.put('recent.json.gz', RecentPack([day('2026-09-30', 900)], const {}).toJson());
    var ranges = {'lt-2026.json.gz': ('2026-01-02', '2026-09-30'), 'recent.json.gz': ('2026-08-20', '2026-09-30')};
    final store = DataPackStore(
      dir: tmp,
      client: rel.client(() => rel.manifest(ranges: ranges)),
      base: 'https://x/data',
    );
    await store.load();
    expect(store.hasPack, isFalse);
    expect(await store.update(now: DateTime(2026, 10, 3)), isTrue);
    expect(store.hasPack, isTrue);
    expect(store.version, 1);
    expect(store.lastDate, '2026-10-02');
    expect(rel.requested.where((n) => n != 'manifest.json').toSet(), {
      'lt-2025.json.gz',
      'lt-2026.json.gz',
      'recent.json.gz',
    });

    // 隔天：今年的檔案變了，但本機的跟最近 30 天接得上 → 只下載 recent
    rel.requested.clear();
    rel.put('lt-2026.json.gz', {
      'v': 1,
      'dates': ['2026-09-30', '2026-10-01'],
      'ix': [1, 1],
      'tr': [1, 1],
      's': {},
    });
    rel.put('recent.json.gz', RecentPack([day('2026-09-30', 900), day('2026-10-01', 910)], const {}).toJson());
    ranges = {'lt-2026.json.gz': ('2026-01-02', '2026-10-01'), 'recent.json.gz': ('2026-08-21', '2026-10-01')};
    expect(await store.update(now: DateTime(2026, 10, 3)), isTrue);
    expect(rel.requested.where((n) => n != 'manifest.json').toList(), ['recent.json.gz']);

    // 很久沒開：本機今年的檔案接不上最近 30 天 → 重抓今年
    rel.requested.clear();
    rel.put('recent.json.gz', RecentPack([day('2026-12-30', 950)], const {}).toJson());
    ranges = {'lt-2026.json.gz': ('2026-01-02', '2026-12-30'), 'recent.json.gz': ('2026-11-18', '2026-12-30')};
    await store.update(now: DateTime(2026, 12, 31));
    expect(rel.requested.where((n) => n != 'manifest.json').toSet(), {'lt-2026.json.gz', 'recent.json.gz'});

    // 遠端拿掉的檔案，本機也刪掉
    rel.files.remove('lt-2025.json.gz');
    await store.update(now: DateTime(2026, 12, 31));
    expect(File('${tmp.path}/lt-2025.json.gz').existsSync(), isFalse);
    expect(store.local.containsKey('lt-2025.json.gz'), isFalse);

    // 重新打開：狀態有存下來
    final again = DataPackStore(
      dir: tmp,
      client: rel.client(() => rel.manifest(ranges: ranges)),
      base: 'https://x/data',
    );
    await again.load();
    expect(again.hasPack, isTrue);
    expect(again.local.keys, containsAll(['lt-2026.json.gz', 'recent.json.gz']));
  });

  test('連不上或還沒有資料包：顯示原因，不會當掉', () async {
    final store = DataPackStore(
      dir: tmp,
      client: MockClient((_) async => http.Response('no', 404)),
      base: 'https://x/data',
    );
    await store.load();
    expect(await store.update(), isFalse);
    expect(store.error, contains('還沒準備好'));
    expect(store.updating, isFalse);
  });

  test('GitHub 偶爾回 500：自動重試；一直失敗就保留已下載的檔案，下次只補沒下載的', () async {
    final rel = FakeRelease();
    // 跟真的清單一樣，今年的排第一個
    rel.put('lt-2026.json.gz', {'v': 1, 'dates': [], 'ix': [], 'tr': [], 's': {}});
    rel.put('lt-2025.json.gz', {'v': 1, 'dates': [], 'ix': [], 'tr': [], 's': {}});
    final ok = rel.client(() => rel.manifest());
    Future<http.Response> pass(http.Request req) async =>
        http.Response.fromStream(await ok.send(http.Request('GET', req.url)));
    var fails = <String, int>{'lt-2026.json.gz': 2};
    final missingOnce = {'lt-2025.json.gz'};
    final flaky = MockClient((req) async {
      final name = req.url.pathSegments.last;
      // 晚上更新時檔案正在被換掉：清單上有，但暫時 404
      if (missingOnce.remove(name)) return http.Response('not found', 404);
      final left = fails[name] ?? 0;
      if (left > 0) {
        fails[name] = left - 1;
        return http.Response('oops', 500);
      }
      return pass(req);
    });
    final store = DataPackStore(
      dir: tmp,
      client: flaky,
      base: 'https://x/data',
      retryDelays: const [Duration.zero, Duration.zero],
    );
    await store.load();
    // 失敗兩次，第三次成功；暫時 404 的也重試
    expect(await store.update(), isTrue);
    expect(store.error, isNull);
    expect(store.local.keys, containsAll(['lt-2025.json.gz', 'lt-2026.json.gz']));

    // 一直失敗：顯示好懂的原因，成功的檔案留著
    store.local.clear();
    for (final f in tmp.listSync()) {
      f.deleteSync();
    }
    fails = {'lt-2025.json.gz': 99};
    rel.requested.clear();
    expect(await store.update(), isTrue);
    expect(store.error, contains('GitHub 暫時出錯'));
    expect(store.error, contains('lt-2025.json.gz'));
    expect(store.local.keys, ['lt-2026.json.gz']);
    expect(File('${tmp.path}/lt-2025.json.gz').existsSync(), isFalse);

    // 再按一次：只補沒下載的
    fails = {};
    rel.requested.clear();
    await store.update();
    expect(store.error, isNull);
    expect(rel.requested.where((n) => n != 'manifest.json').toList(), ['lt-2025.json.gz']);
  });

  test('每日行情匯入：bars 檔的交易日、休市日，加上最近 30 天，只補回看天數內本機沒有的', () async {
    final raw = PackYear(2026, closed: {'2026-09-28'});
    for (final (d, c) in [('2026-09-24', 880.0), ('2026-09-25', 890.0), ('2026-09-29', 895.0)]) {
      raw.days[d] = day(d, c, change: 1);
    }
    File('${tmp.path}/bars-2026.json.gz').writeAsBytesSync(encodeGz(barsYearJson(raw)));
    File('${tmp.path}/recent.json.gz').writeAsBytesSync(
      encodeGz(RecentPack([day('2026-09-29', 895, change: 5), day('2026-10-01', 905, change: 10)], const {}).toJson()),
    );
    final snaps = readSnapshots(tmp.path, ['bars-2026.json.gz', 'recent.json.gz'], '2026-09-25', 2026);
    expect(snaps.map((s) => s.date).toList(), ['2026-09-25', '2026-09-28', '2026-09-29', '2026-09-30', '2026-10-01']);
    expect(snaps.firstWhere((s) => s.date == '2026-09-28').trading, isFalse);
    // 2026-09-30 在最近 30 天中間但沒有資料 → 休市
    expect(snaps.firstWhere((s) => s.date == '2026-09-30').trading, isFalse);
    expect(snaps.firstWhere((s) => s.date == '2026-10-01').bars.keys, containsAll(['2330', '6488']));

    final hdir = Directory('${tmp.path}/h')..createSync();
    final history = HistoryStore(store: LocalStore(dir: hdir), useIsolate: false)..lookbackDays = 30;
    await history.load();
    // 本機已經有 09-29 的資料，不會被覆蓋
    await LocalStore(dir: hdir).writeDay(
      '2026-09-29',
      DaySnapshot(
        date: '2026-09-29',
        trading: true,
        bars: {'2330': const DailyBar(date: '2026-09-29', open: 1, high: 1, low: 1, close: 1, volumeLots: 1)},
      ).toJson(),
    );
    await history.load();
    final n = await history.importSnapshots(snaps, now: DateTime(2026, 10, 2, 9));
    expect(n, 4);
    expect(history.tradingDates, containsAll(['2026-09-25', '2026-09-29', '2026-10-01']));
    expect(history.rawSeriesOf('2330').firstWhere((b) => b.date == '2026-09-29').close, 1);
    // 長期分析要接的「資料包之後」的日子
    expect(history.packDaysAfter('2026-09-29').map((d) => d.date), ['2026-10-01']);
  });

  test('股利收入：除息前一天持有的股數 × 每股權值＋息值；上櫃用參考價推算', () {
    final h = Holding(
      id: 'x',
      code: '2330',
      style: HoldStyle.long,
      buys: const [BuyLot('2024-01-10', 600, 1000), BuyLot('2024-06-13', 900, 1000)],
      sells: const [SellLot('2024-09-20', 950, 500)],
    );
    const events = [
      DivEvent('2023-12-14', 580, 577, 3, '息'), // 還沒買
      DivEvent('2024-03-18', 750, 746.5, 3.5, '息'), // 1000 股
      DivEvent('2024-06-13', 900, 896.5, 3.5, '息'), // 當天買的不算：1000 股
      DivEvent('2024-09-12', 950, 946, 4, '息'), // 2000 股
      DivEvent('2024-12-12', 1080, 1076, 4, '息'), // 賣掉 500：1500 股
    ];
    final items = dividendIncome(h, events);
    expect(items.map((i) => i.shares).toList(), [1000, 1000, 2000, 1500]);
    expect(items.fold(0.0, (a, i) => a + i.amount), 3500 + 3500 + 8000 + 6000);

    const raw = [
      DailyBar(date: '2024-07-01', open: 100, high: 100, low: 100, close: 100, volumeLots: 1, change: 0),
      // 除息 3 元：參考價 97，收 98（漲 1）
      DailyBar(date: '2024-07-02', open: 98, high: 98, low: 98, close: 98, volumeLots: 1, change: 1),
      DailyBar(date: '2024-07-03', open: 99, high: 99, low: 99, close: 99, volumeLots: 1, change: 1),
    ];
    final ev = derivedDividends(raw);
    expect(ev.single.date, '2024-07-02');
    expect(ev.single.value, closeTo(3, 1e-9));
  });
}
