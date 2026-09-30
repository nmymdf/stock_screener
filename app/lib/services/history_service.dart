/// 抓「某一天全市場的收盤行情」：上市用證交所的每日收盤行情（MI_INDEX），
/// 上櫃用櫃買中心的上櫃股票行情。一次請求就拿到一整天所有股票，比一檔一檔
/// 抓歷史快非常多——技術選股需要的 60 多個交易日，全市場大約 2×70 次請求。
///
/// 兩邊回應的欄位順序以前改過好幾次，所以不寫死欄位位置，而是用欄位名稱
/// （「證券代號」「收盤價」「成交股數」……）找出每一欄在哪裡。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/daily_bar.dart';
import 'quote_service.dart' show parseNum;

enum DayStatus { ok, closed, failed }

class DayFetchResult {
  final DayStatus status;
  final DaySnapshot? snapshot;
  final String? message;
  const DayFetchResult(this.status, {this.snapshot, this.message});
}

class HistoryService {
  final http.Client _client;
  HistoryService({http.Client? client}) : _client = client ?? http.Client();

  /// 抓 [date]（yyyy-MM-dd）這天上市＋上櫃的收盤行情。兩邊都說「沒資料」
  /// 代表休市；任何一邊連不到就算失敗，下次同步會再重抓。
  Future<DayFetchResult> fetchDay(String date) async {
    final results = await Future.wait([_fetchTwse(date), _fetchTpex(date)]);
    final twse = results[0];
    final tpex = results[1];
    if (twse == null || tpex == null) {
      return DayFetchResult(DayStatus.failed,
          message: twse == null ? '連不到證交所（上市）' : '連不到櫃買中心（上櫃）');
    }
    if (twse.isEmpty && tpex.isEmpty) {
      return DayFetchResult(DayStatus.closed, snapshot: DaySnapshot(date: date, trading: false, bars: const {}));
    }
    // 只有一邊有資料很少見（多半是其中一邊還沒公布），當作失敗，之後重抓，
    // 免得存下半套的資料之後不會再補。
    if (twse.isEmpty || tpex.isEmpty) {
      return DayFetchResult(DayStatus.failed,
          message: twse.isEmpty ? '證交所（上市）這天還沒有資料' : '櫃買中心（上櫃）這天還沒有資料');
    }
    return DayFetchResult(
      DayStatus.ok,
      snapshot: DaySnapshot(date: date, trading: true, bars: {...tpex, ...twse}),
    );
  }

  /// null = 連線失敗；空 Map = 這天沒有資料（休市）。
  Future<Map<String, DailyBar>?> _fetchTwse(String date) async {
    final uri = Uri.https('www.twse.com.tw', '/rwd/zh/afterTrading/MI_INDEX', {
      'date': date.replaceAll('-', ''),
      'type': 'ALLBUT0999', // 全部（不含權證、牛熊證）
      'response': 'json',
    });
    final body = await _getJson(uri);
    if (body == null) return null;
    return parseTwseDaily(date, body);
  }

  Future<Map<String, DailyBar>?> _fetchTpex(String date) async {
    final uri = Uri.https('www.tpex.org.tw', '/www/zh-tw/afterTrading/otc', {
      'date': date.replaceAll('-', '/'),
      'type': 'EW', // 不含權證
      'response': 'json',
    });
    final body = await _getJson(uri);
    if (body == null) return null;
    return parseTpexDaily(date, body);
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final res = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// 解析證交所 MI_INDEX 的回應。新版格式是 `tables: [{fields, data}, ...]`，
/// 舊版是 `fields9` / `data9` 這種帶編號的鍵，兩種都認。
Map<String, DailyBar> parseTwseDaily(String date, Map<String, dynamic> body) {
  final tables = <(List, List)>[];
  final t = body['tables'];
  if (t is List) {
    for (final tb in t) {
      if (tb is Map && tb['fields'] is List && tb['data'] is List) {
        tables.add((tb['fields'] as List, tb['data'] as List));
      }
    }
  }
  for (final k in body.keys) {
    final m = RegExp(r'^fields(\d*)$').firstMatch(k);
    if (m == null) continue;
    final data = body['data${m.group(1)}'];
    if (body[k] is List && data is List) tables.add((body[k] as List, data));
  }
  for (final (fields, data) in tables) {
    final cols = _Columns.find(fields);
    if (cols != null) return cols.parse(date, data);
  }
  return {};
}

/// 解析櫃買中心上櫃股票行情。新版格式是 `tables: [{fields, data}]`；舊版
/// （stk_wn1430_result.php）只有 `aaData`、沒有欄位名稱，欄位順序固定是
/// 代號、名稱、收盤、漲跌、開盤、最高、最低、均價、成交股數……
Map<String, DailyBar> parseTpexDaily(String date, Map<String, dynamic> body) {
  final t = body['tables'];
  if (t is List) {
    for (final tb in t) {
      if (tb is Map && tb['fields'] is List && tb['data'] is List) {
        final cols = _Columns.find(tb['fields'] as List);
        if (cols != null) return cols.parse(date, tb['data'] as List);
      }
    }
  }
  final aa = body['aaData'];
  if (aa is List) {
    return const _Columns(code: 0, close: 2, open: 4, high: 5, low: 6, volume: 8).parse(date, aa);
  }
  return {};
}

class _Columns {
  final int code, open, high, low, close, volume;
  const _Columns({
    required this.code,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  static _Columns? find(List fields) {
    final names = [for (final f in fields) f.toString().replaceAll(RegExp(r'\s'), '')];
    int idx(bool Function(String) test) => names.indexWhere(test);
    final code = idx((n) => n.contains('代號'));
    final open = idx((n) => n.startsWith('開盤'));
    final high = idx((n) => n.startsWith('最高'));
    final low = idx((n) => n.startsWith('最低'));
    final close = idx((n) => n.startsWith('收盤'));
    final volume = idx((n) => n.contains('成交股數'));
    if ([code, open, high, low, close, volume].any((i) => i < 0)) return null;
    return _Columns(code: code, open: open, high: high, low: low, close: close, volume: volume);
  }

  Map<String, DailyBar> parse(String date, List data) {
    final out = <String, DailyBar>{};
    for (final raw in data) {
      if (raw is! List || raw.length <= [code, open, high, low, close, volume].reduce((a, b) => a > b ? a : b)) {
        continue;
      }
      final c = raw[code].toString().trim();
      final px = parseNum(raw[close]);
      // 當天沒有成交的股票收盤價是 '--'，沒有意義的一天就不存。
      if (c.isEmpty || px == null || px <= 0) continue;
      final shares = parseNum(raw[volume]) ?? 0;
      out[c] = DailyBar(
        date: date,
        open: parseNum(raw[open]) ?? px,
        high: parseNum(raw[high]) ?? px,
        low: parseNum(raw[low]) ?? px,
        close: px,
        volumeLots: (shares / 1000).round(),
      );
    }
    return out;
  }
}
