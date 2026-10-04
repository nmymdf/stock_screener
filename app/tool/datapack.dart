// 資料包產生程式：在 GitHub Actions 上跑（App 所在的電腦不用跑）。
//
//   dart run tool/datapack.dart probe                       # 試抓每個來源，印出解析結果
//   dart run tool/datapack.dart year --year 2024 --dir pack [--tpex] [--compact]
//   dart run tool/datapack.dart revenue --dir pack --from 2012-01
//   dart run tool/datapack.dart dividends --dir pack --years 2013-2026
//   dart run tool/datapack.dart intl --dir pack
//   dart run tool/datapack.dart assemble --dir pack         # 產生 recent.json.gz、manifest.json
//   dart run tool/datapack.dart daily --dir pack            # 每天收盤後：補今年、營收、股利、國際、組裝
//   dart run tool/datapack.dart research --dir pack         # 用資料包跑長期回測，印出結果
//
// 證交所對太密集的請求會暫時封鎖，每個網站兩次請求之間至少隔 2.5 秒。
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:stock_screener/core/pack.dart';
import 'package:stock_screener/core/research.dart';
import 'package:stock_screener/core/sources.dart';
import 'package:stock_screener/services/history_service.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    print('用法見檔案開頭的說明');
    exit(64);
  }
  final cmd = argv.first;
  final args = _Args(argv.skip(1).toList());
  final f = Fetcher();
  final dir = Directory(args.get('dir') ?? 'pack')..createSync(recursive: true);
  try {
    switch (cmd) {
      case 'probe':
        await probe(f);
      case 'year':
        final y = int.parse(args.get('year')!);
        await updateYear(f, dir, y, tpex: args.flag('tpex'), compact: args.flag('compact'));
      case 'revenue':
        await updateRevenue(f, dir, from: args.get('from') ?? '2012-01', full: args.flag('full'));
      case 'dividends':
        final (a, b) = _range(args.get('years') ?? '${_taipeiNow().year}');
        await updateDividends(f, dir, a, b);
      case 'intl':
        await updateIntl(f, dir);
      case 'assemble':
        assemble(dir);
      case 'daily':
        await daily(f, dir);
      case 'research':
        research(dir);
      default:
        print('不認得的指令：$cmd');
        exit(64);
    }
  } finally {
    f.close();
  }
}

class _Args {
  final List<String> a;
  _Args(this.a);
  String? get(String k) {
    final i = a.indexOf('--$k');
    return i >= 0 && i + 1 < a.length ? a[i + 1] : null;
  }

  bool flag(String k) => a.contains('--$k');
}

(int, int) _range(String s) {
  final p = s.split('-');
  return (int.parse(p.first), int.parse(p.last));
}

DateTime _taipeiNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 依網站控制請求間隔、失敗重試。
class Fetcher {
  final http.Client _c = http.Client();
  final Map<String, DateTime> _last = {};
  final Duration gap;
  int requests = 0;
  Fetcher({this.gap = const Duration(milliseconds: 2500)});

  void close() => _c.close();

  Future<void> _pace(String host) async {
    final last = _last[host];
    if (last != null) {
      final wait = gap - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _last[host] = DateTime.now();
  }

  /// 回傳原始位元組；連不上或不是 200 就重試，最後還是失敗回傳 null。
  Future<List<int>?> bytes(
    Uri uri, {
    Map<String, String> headers = const {},
    int tries = 4,
    String method = 'GET',
    Map<String, String>? form,
  }) async {
    for (var t = 0; t < tries; t++) {
      if (t > 0) await Future<void>.delayed(Duration(seconds: [0, 15, 45, 90][t]));
      await _pace(uri.host);
      requests++;
      try {
        final h = {'User-Agent': 'Mozilla/5.0 (stock_screener datapack)', ...headers};
        final res = await (method == 'POST' ? _c.post(uri, headers: h, body: form) : _c.get(uri, headers: h)).timeout(
          const Duration(seconds: 40),
        );
        if (res.statusCode == 200) return res.bodyBytes;
        stderr.writeln('  HTTP ${res.statusCode}：$uri');
        if (res.statusCode == 404) return null;
      } catch (e) {
        stderr.writeln('  連線失敗（$e）：$uri');
      }
    }
    return null;
  }

  /// 證交所的 JSON。回應不是 JSON（被擋的時候會回 HTML）也當作失敗重試。
  Future<Map<String, dynamic>?> json(Uri uri, {int tries = 4}) async {
    for (var t = 0; t < tries; t++) {
      final b = await bytes(uri, tries: 1, headers: const {'Accept': 'application/json'});
      if (b != null) {
        try {
          final d = jsonDecode(utf8.decode(b, allowMalformed: true));
          if (d is Map<String, dynamic>) return d;
        } catch (_) {
          stderr.writeln('  回應不是 JSON（可能被暫時封鎖）：$uri');
        }
      }
      if (t + 1 < tries) await Future<void>.delayed(Duration(seconds: [15, 45, 90, 120][t]));
    }
    return null;
  }
}

String _compact(String date) => date.replaceAll('-', '');

Uri _twse(String path, Map<String, String> q) => Uri.https('www.twse.com.tw', path, {...q, 'response': 'json'});

/// 證交所的「查無資料」：stat 不是 OK，或沒有任何表格。
bool _twseEmpty(Map<String, dynamic> body) {
  final stat = body['stat']?.toString() ?? '';
  return stat.contains('沒有符合') || stat.contains('查詢無資料') || twseTables(body).isEmpty;
}

class DayParts {
  Map<String, dynamic>? mi;
  Map<String, dynamic>? bw;
  Map<String, dynamic>? t86;
  Map<String, dynamic>? tpex;
}

Future<Map<String, dynamic>?> fetchMiIndex(Fetcher f, String date) =>
    f.json(_twse('/rwd/zh/afterTrading/MI_INDEX', {'date': _compact(date), 'type': 'ALLBUT0999'}));

Future<Map<String, dynamic>?> fetchBwibbu(Fetcher f, String date) =>
    f.json(_twse('/rwd/zh/afterTrading/BWIBBU_d', {'date': _compact(date), 'selectType': 'ALL'}));

Future<Map<String, dynamic>?> fetchT86(Fetcher f, String date) =>
    f.json(_twse('/rwd/zh/fund/T86', {'date': _compact(date), 'selectType': 'ALLBUT0999'}));

Future<Map<String, dynamic>?> fetchTpex(Fetcher f, String date) => f.json(
  Uri.https('www.tpex.org.tw', '/www/zh-tw/afterTrading/otc', {
    'date': date.replaceAll('-', '/'),
    'type': 'EW',
    'response': 'json',
  }),
);

Future<Map<String, dynamic>?> fetchTwt49u(Fetcher f, String from, String to) =>
    f.json(_twse('/rwd/zh/exRight/TWT49U', {'startDate': _compact(from), 'endDate': _compact(to)}));

// ───────────────────────────── probe ─────────────────────────────

Future<void> probe(Fetcher f) async {
  final now = _taipeiNow();
  var d = DateTime.utc(now.year, now.month, now.day).subtract(const Duration(days: 1));
  while (d.weekday > 5) {
    d = d.subtract(const Duration(days: 1));
  }
  for (final date in [_ymd(d), '2013-03-05', '2018-06-05']) {
    print('\n==== $date ====');
    final mi = await fetchMiIndex(f, date);
    if (mi == null) {
      print('MI_INDEX：失敗');
    } else {
      final bars = parseTwseDaily(date, mi);
      final names = parseTwseNames(mi);
      print(
        'MI_INDEX：stat=${mi['stat']} 表格=${twseTables(mi).length} 股票=${bars.length} '
        '普通股=${bars.keys.where(isCommonStockCode).length} 加權=${parseTaiex(mi)} 報酬指數=${parseTaiexTotalReturn(mi)}',
      );
      final b = bars['2330'];
      print('  2330 ${names['2330']} 收=${b?.close} 張=${b?.volumeLots} 漲跌=${b?.change}');
      for (final (fields, data) in twseTables(mi)) {
        print('  表：${fields.take(4).join('|')}…（${data.length} 列）');
      }
    }
    final bw = await fetchBwibbu(f, date);
    if (bw == null) {
      print('BWIBBU_d：失敗');
    } else {
      final v = parseBwibbu(bw);
      print('BWIBBU_d：stat=${bw['stat']} 筆數=${v.length} 欄位=${twseTables(bw).firstOrNull?.$1}');
      print('  2330 ${v['2330']}  2412 ${v['2412']}');
    }
    final t = await fetchT86(f, date);
    if (t == null) {
      print('T86：失敗');
    } else {
      final v = parseT86(t);
      print('T86：stat=${t['stat']} 筆數=${v.length} 欄位=${twseTables(t).firstOrNull?.$1}');
      print('  2330 ${v['2330']}  2317 ${v['2317']}');
    }
    final o = await fetchTpex(f, date);
    print('上櫃：${o == null ? '失敗' : '${parseTpexDaily(date, o).length} 檔'}');
  }

  print('\n==== 除權息 TWT49U ====');
  for (final (a, b) in [('2024-01-01', '2024-12-31'), ('2013-01-01', '2013-12-31')]) {
    final r = await fetchTwt49u(f, a, b);
    if (r == null) {
      print('$a～$b：失敗');
      continue;
    }
    final ev = parseTwt49u(r);
    print('$a～$b：stat=${r['stat']} 股票=${ev.length} 事件=${ev.values.fold(0, (s, l) => s + l.length)}');
    print('  欄位=${twseTables(r).firstOrNull?.$1}');
    print('  2330 ${ev['2330']?.map((e) => '${e.date} ${e.kind} ${e.value}').join('; ')}');
  }

  print('\n==== 月營收 ====');
  for (final ym in ['2024-08', '2013-01', '2012-06']) {
    final r = await fetchRevenueMonth(f, ym, verbose: true);
    print('$ym：${r.length} 家，2330=${r['2330']}，1101=${r['1101']}');
  }
  final (ym, latest) = await fetchRevenueOpenApi(f);
  print('OpenAPI 最新：$ym ${latest.length} 家，2330=${latest['2330']}');

  print('\n==== 國際指標 ====');
  final intl = await fetchIntl(f, verbose: true);
  for (final s in intl.series.values) {
    print(
      '${s.key}（${s.source}，延後 ${s.lagDays} 天）：${s.dates.length} 筆 ${s.dates.firstOrNull}～${s.dates.lastOrNull} 最新=${s.values.lastOrNull}',
    );
  }
  print('\n共 ${f.requests} 次請求');
}

// ───────────────────────────── 每日行情 ─────────────────────────────

File _yearFile(Directory dir, int y) => File('${dir.path}/daily-$y.json.gz');

PackYear loadYear(Directory dir, int y) {
  final file = _yearFile(dir, y);
  if (!file.existsSync()) return PackYear(y);
  return PackYear.fromJson(decodeGz(file.readAsBytesSync()));
}

void saveYear(Directory dir, PackYear py) => _yearFile(dir, py.year).writeAsBytesSync(encodeGz(py.toJson()));

/// 這一年要抓的平日（今天要等台北時間 17:00 法人資料出來以後）。
List<String> weekdaysOf(int year) {
  final now = _taipeiNow();
  final today = DateTime.utc(now.year, now.month, now.day);
  final out = <String>[];
  for (var d = DateTime.utc(year, 1, 1); d.year == year; d = d.add(const Duration(days: 1))) {
    if (d.isAfter(today) || (d == today && now.hour < 17)) break;
    if (d.weekday <= 5) out.add(_ymd(d));
  }
  return out;
}

Future<void> updateYear(Fetcher f, Directory dir, int year, {bool tpex = false, bool compact = false}) async {
  final py = loadYear(dir, year);
  final now = _taipeiNow();
  final todayStr = _ymd(now);
  final todo = [
    for (final d in weekdaysOf(year))
      if (!py.days.containsKey(d) && !py.closed.contains(d)) d,
  ];
  print(
    '$year：已有 ${py.days.length} 天、休市 ${py.closed.length} 天，要抓 ${todo.length} 天'
    '${py.partial.isEmpty ? '' : '，補 ${py.partial.length} 天缺的部分'}',
  );
  var fails = 0, n = 0;
  for (final date in todo) {
    final mi = await fetchMiIndex(f, date);
    if (mi == null) {
      fails++;
      print('  $date：抓不到（連續 $fails 次）');
      if (fails >= 6) {
        print('  連續失敗太多次，先存檔停下來');
        break;
      }
      continue;
    }
    fails = 0;
    if (_twseEmpty(mi) || parseTwseDaily(date, mi).isEmpty) {
      // 今天還沒公布不算休市
      if (date != todayStr) py.closed.add(date);
      continue;
    }
    py.days[date] = await _fetchRest(f, date, mi, tpex: tpex, py: py);
    n++;
    if (n % 20 == 0) {
      saveYear(dir, py);
      print('  已抓 $n 天（到 $date），${f.requests} 次請求');
    }
  }
  // 補之前缺的部分（每次最多 30 天）
  for (final date in py.partial.keys.toList().take(30)) {
    final day = py.days[date];
    if (day == null) {
      py.partial.remove(date);
      continue;
    }
    py.days[date] = await _fillParts(f, day, py.partial[date]!, py);
  }
  if (compact) {
    for (final e in py.days.entries.toList()) {
      py.days[e.key] = e.value.compacted();
    }
    py.partial.removeWhere((_, v) => v.length == 1 && v.first == 'o');
  }
  saveYear(dir, py);
  print('$year：完成，共 ${py.days.length} 個交易日（新抓 $n 天），${f.requests} 次請求');
}

Future<PackDay> _fetchRest(
  Fetcher f,
  String date,
  Map<String, dynamic> mi, {
  required bool tpex,
  required PackYear py,
}) async {
  final bars = parseTwseDaily(date, mi);
  py.names.addAll(parseTwseNames(mi));
  var day = PackDay(
    date: date,
    taiex: parseTaiex(mi),
    tri: parseTaiexTotalReturn(mi),
    twse: {for (final e in bars.entries) e.key: barRow(e.value)},
  );
  return _fillParts(f, day, ['f', 'i', if (tpex) 'o'], py);
}

/// 抓本益比（f）、法人（i）、上櫃（o）；抓不到的記在 partial，下次再補。
Future<PackDay> _fillParts(Fetcher f, PackDay day, List<String> parts, PackYear py) async {
  final missing = <String>[];
  var d = day;
  for (final p in parts) {
    switch (p) {
      case 'f':
        final b = await fetchBwibbu(f, day.date);
        final v = b == null ? null : parseBwibbu(b);
        if (v == null || v.isEmpty) {
          missing.add(p);
        } else {
          d = d.copyWith(
            val: {
              for (final e in v.entries) e.key: [for (final x in e.value) x == null ? null : packNum(x)],
            },
          );
        }
      case 'i':
        final b = await fetchT86(f, day.date);
        final v = b == null ? null : parseT86(b);
        // 2012 年 5 月以前沒有這份資料
        if (v == null || (v.isEmpty && day.date.compareTo('2012-05-02') >= 0 && b == null)) {
          missing.add(p);
        } else if (v.isNotEmpty) {
          d = d.copyWith(inst: v);
        }
      case 'o':
        final b = await fetchTpex(f, day.date);
        final v = b == null ? null : parseTpexDaily(day.date, b);
        if (v == null || v.isEmpty) {
          missing.add(p);
        } else {
          d = d.copyWith(tpex: {for (final e in v.entries) e.key: barRow(e.value)});
        }
    }
  }
  if (missing.isEmpty) {
    py.partial.remove(day.date);
  } else {
    py.partial[day.date] = missing;
  }
  return d;
}

// ───────────────────────────── 月營收 ─────────────────────────────

/// 一個月的上市公司營收。依序試：觀測站舊站 HTML（國內＋國外公司）、CSV 下載。
Future<MonthRevenue> fetchRevenueMonth(Fetcher f, String ym, {bool verbose = false}) async {
  final y = int.parse(ym.substring(0, 4)) - 1911;
  final m = int.parse(ym.substring(5, 7));
  final out = <String, (double, double?)>{};
  for (final host in ['mopsov.twse.com.tw', 'mops.twse.com.tw']) {
    for (final suffix in ['_0', '_1', '']) {
      if (suffix == '' && out.isNotEmpty) continue;
      final uri = Uri.https(host, '/nas/t21/sii/t21sc03_${y}_$m$suffix.html');
      final b = await f.bytes(uri, tries: 2);
      if (b == null) {
        if (verbose) print('  $uri：失敗');
        continue;
      }
      final r = parseRevenueHtml(latin1.decode(b));
      if (verbose) print('  $uri：${b.length} bytes，${r.length} 家');
      out.addAll(r);
    }
    if (out.isNotEmpty) return out;
  }
  final csvUri = Uri.https('mopsov.twse.com.tw', '/server-java/FileDownLoad');
  final b = await f.bytes(
    csvUri,
    method: 'POST',
    tries: 2,
    form: {'step': '9', 'functionName': 'show_file2', 'filePath': '/t21/sii/', 'fileName': 't21sc03_${y}_$m.csv'},
  );
  if (b != null) {
    final r = parseRevenueCsv(utf8.decode(b, allowMalformed: true));
    if (verbose) print('  CSV：${b.length} bytes，${r.length} 家');
    out.addAll(r);
  } else if (verbose) {
    print('  CSV：失敗');
  }
  return out;
}

Future<(String?, MonthRevenue)> fetchRevenueOpenApi(Fetcher f) async {
  final b = await f.bytes(Uri.https('openapi.twse.com.tw', '/v1/opendata/t187ap05_L'), tries: 2);
  if (b == null) return (null, <String, (double, double?)>{});
  try {
    final j = jsonDecode(utf8.decode(b));
    if (j is List) return parseRevenueOpenApi(j);
  } catch (_) {}
  return (null, <String, (double, double?)>{});
}

File _revFile(Directory dir) => File('${dir.path}/revenue.json.gz');

Future<void> updateRevenue(Fetcher f, Directory dir, {required String from, bool full = false}) async {
  final file = _revFile(dir);
  final rev = file.existsSync() ? RevenueData.fromJson(decodeGz(file.readAsBytesSync())) : RevenueData(from, null);
  final now = _taipeiNow();
  final lastIdx = now.year * 12 + now.month - 2; // 上個月
  final firstIdx = RevenueData.monthIndex(from);
  var n = 0;
  for (var k = firstIdx; k <= lastIdx; k++) {
    final ym = RevenueData.monthOf(k);
    // 最近 3 個月每天重抓（公司陸續公布、會更正）；更早的有 600 家以上就不再抓
    final recent = k > lastIdx - 3;
    if (!full && !recent && rev.countFor(ym) >= 600) continue;
    if (!full && !recent && k < RevenueData.monthIndex('2013-01') && rev.countFor(ym) >= 300) continue;
    final m = await fetchRevenueMonth(f, ym);
    if (m.isEmpty) {
      print('  $ym：抓不到');
      continue;
    }
    rev.addMonth(ym, m);
    n++;
    print('  $ym：${m.length} 家');
  }
  final (ym, latest) = await fetchRevenueOpenApi(f);
  if (ym != null && latest.isNotEmpty) {
    rev.addMonth(ym, latest);
    print('  OpenAPI $ym：${latest.length} 家');
  }
  file.writeAsBytesSync(encodeGz(rev.toJson()));
  print('營收：更新 $n 個月，最新 ${rev.lastMonth}，${rev.byCode.length} 家公司');
}

// ───────────────────────────── 除權息 ─────────────────────────────

Future<void> updateDividends(Fetcher f, Directory dir, int fromYear, int toYear) async {
  final file = File('${dir.path}/dividends.json.gz');
  final div = file.existsSync() ? DividendData.fromJson(decodeGz(file.readAsBytesSync())) : DividendData();
  final today = _ymd(_taipeiNow());
  for (var y = fromYear; y <= toYear; y++) {
    final end = '$y-12-31'.compareTo(today) > 0 ? today : '$y-12-31';
    final r = await fetchTwt49u(f, '$y-01-01', end);
    var ev = r == null ? <String, List<DivEvent>>{} : parseTwt49u(r);
    if (ev.isEmpty) {
      // 一次查一整年不行的話，改成一個月一個月查
      for (var m = 1; m <= 12; m++) {
        final a = '$y-${m.toString().padLeft(2, '0')}-01';
        if (a.compareTo(today) > 0) break;
        final b = '$y-${m.toString().padLeft(2, '0')}-${DateTime.utc(y, m + 1, 0).day}';
        final rm = await fetchTwt49u(f, a, b.compareTo(today) > 0 ? today : b);
        if (rm != null) {
          final x = parseTwt49u(rm);
          for (final e in x.entries) {
            (ev[e.key] ??= []).addAll(e.value);
          }
        }
      }
    }
    div.merge(ev);
    print('  $y：${ev.length} 檔、${ev.values.fold(0, (s, l) => s + l.length)} 筆除權息');
  }
  file.writeAsBytesSync(encodeGz(div.toJson()));
}

// ───────────────────────────── 國際指標 ─────────────────────────────

/// key → (Yahoo 代號, FRED 代號, FRED 延後天數)
const _intlSources = {
  'SOX': ('^SOX', null, 0),
  'NASDAQ': ('^IXIC', 'NASDAQCOM', 2),
  'VIX': ('^VIX', 'VIXCLS', 2),
  'USDTWD': ('TWD=X', 'DEXTAUS', 8),
  'US10Y': ('^TNX', 'DGS10', 2),
};

Future<IntlData> fetchIntl(Fetcher f, {bool verbose = false}) async {
  final out = <String, IntlSeries>{};
  final p1 = DateTime.utc(2012, 1, 1).millisecondsSinceEpoch ~/ 1000;
  final p2 = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  for (final e in _intlSources.entries) {
    final (yahoo, fred, fredLag) = e.value;
    IntlSeries? s;
    for (final host in ['query1.finance.yahoo.com', 'query2.finance.yahoo.com']) {
      final b = await f.bytes(
        Uri.https(host, '/v8/finance/chart/$yahoo', {'period1': '$p1', 'period2': '$p2', 'interval': '1d'}),
        tries: 2,
        headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      );
      if (b == null) continue;
      try {
        final (d, v) = parseYahooChart(jsonDecode(utf8.decode(b)) as Map<String, dynamic>);
        if (d.length > 500) {
          s = IntlSeries(e.key, 'Yahoo $yahoo', 1, d, [for (final x in v) packNum(x, 4).toDouble()]);
          break;
        }
      } catch (err) {
        if (verbose) print('  Yahoo $yahoo 解析失敗：$err');
      }
    }
    if (s == null && fred != null) {
      final b = await f.bytes(
        Uri.https('fred.stlouisfed.org', '/graph/fredgraph.csv', {'id': fred, 'cosd': '2012-01-01'}),
        tries: 2,
      );
      if (b != null) {
        final (d, v) = parseFredCsv(utf8.decode(b));
        if (d.length > 500) {
          s = IntlSeries(e.key, 'FRED $fred', fredLag, d, [for (final x in v) packNum(x, 4).toDouble()]);
        }
      }
    }
    if (s != null) {
      out[e.key] = s;
    } else if (verbose) {
      print('  ${e.key}：抓不到');
    }
  }
  return IntlData(out);
}

Future<void> updateIntl(Fetcher f, Directory dir) async {
  final file = File('${dir.path}/intl.json.gz');
  final fresh = await fetchIntl(f);
  // 抓不到的指標保留上一次的資料
  final old = file.existsSync() ? IntlData.fromJson(decodeGz(file.readAsBytesSync())) : const IntlData({});
  final merged = IntlData({...old.series, ...fresh.series});
  file.writeAsBytesSync(encodeGz(merged.toJson()));
  print('國際指標：${merged.series.entries.map((e) => '${e.key} ${e.value.dates.lastOrNull}').join('、')}');
}

// ───────────────────────────── 組裝 ─────────────────────────────

void assemble(Directory dir, {int recentDays = 30}) {
  final years = [
    for (final f in dir.listSync().whereType<File>())
      if (RegExp(r'daily-(\d{4})\.json\.gz$').hasMatch(f.path))
        int.parse(RegExp(r'daily-(\d{4})\.json\.gz$').firstMatch(f.path)!.group(1)!),
  ]..sort();
  final files = <String, PackFileInfo>{};
  final recent = <PackDay>[];
  final names = <String, String>{};
  String? lastDate;
  for (final y in years.reversed) {
    final py = loadYear(dir, y);
    final bytes = _yearFile(dir, y).readAsBytesSync();
    files['daily-$y.json.gz'] = PackFileInfo(
      'daily-$y.json.gz',
      bytes.length,
      fingerprint(bytes),
      first: py.firstDate,
      last: py.lastDate,
    );
    lastDate ??= py.lastDate;
    if (recent.length < recentDays) {
      final days = py.sortedDays.reversed.take(recentDays - recent.length);
      recent.addAll(days);
      names.addAll({...py.names, ...names});
    }
  }
  recent.sort((a, b) => a.date.compareTo(b.date));
  final rb = encodeGz(RecentPack(recent, names).toJson());
  File('${dir.path}/recent.json.gz').writeAsBytesSync(rb);
  files['recent.json.gz'] = PackFileInfo(
    'recent.json.gz',
    rb.length,
    fingerprint(rb),
    first: recent.firstOrNull?.date,
    last: recent.lastOrNull?.date,
  );
  for (final n in ['revenue.json.gz', 'dividends.json.gz', 'intl.json.gz']) {
    final file = File('${dir.path}/$n');
    if (!file.existsSync()) continue;
    final b = file.readAsBytesSync();
    String? last;
    if (n == 'revenue.json.gz') last = RevenueData.fromJson(decodeGz(b)).lastMonth;
    files[n] = PackFileInfo(n, b.length, fingerprint(b), last: last);
  }
  final m = PackManifest(DateTime.now().toUtc().toIso8601String(), lastDate, files);
  File('${dir.path}/manifest.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(m.toJson()));
  print(
    '組裝完成：最新 $lastDate，${files.length} 個檔案，共 ${(files.values.fold(0, (s, x) => s + x.size) / 1e6).toStringAsFixed(1)} MB',
  );
  for (final e in files.entries) {
    print('  ${e.key} ${(e.value.size / 1e3).toStringAsFixed(0)} KB ${e.value.first ?? ''}～${e.value.last ?? ''}');
  }
}

/// 每天收盤後：補今年（一月初也補去年）、營收、股利、國際指標，然後組裝。
Future<void> daily(Fetcher f, Directory dir) async {
  final now = _taipeiNow();
  if (now.month == 1 && now.day <= 15) await updateYear(f, dir, now.year - 1, tpex: true);
  await updateYear(f, dir, now.year, tpex: true);
  await updateRevenue(f, dir, from: '2012-01');
  await updateDividends(f, dir, now.year, now.year);
  await updateIntl(f, dir);
  assemble(dir);
}

void research(Directory dir) {
  final report = runPackResearch(dir.path);
  print(report);
}
