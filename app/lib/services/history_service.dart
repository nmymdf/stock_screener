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
    final (twse, tpex) = await (_fetchTwse(date), _fetchTpex(date)).wait;
    if (twse == null || tpex == null) {
      return DayFetchResult(DayStatus.failed, message: twse == null ? '連不到證交所（上市）' : '連不到櫃買中心（上櫃）');
    }
    if (twse.bars.isEmpty && tpex.isEmpty) {
      return DayFetchResult(
        DayStatus.closed,
        snapshot: DaySnapshot(date: date, trading: false, bars: const {}),
      );
    }
    // 只有一邊有資料很少見（多半是其中一邊還沒公布），當作失敗，之後重抓，
    // 免得存下半套的資料之後不會再補。
    if (twse.bars.isEmpty || tpex.isEmpty) {
      return DayFetchResult(DayStatus.failed, message: twse.bars.isEmpty ? '證交所（上市）這天還沒有資料' : '櫃買中心（上櫃）這天還沒有資料');
    }
    return DayFetchResult(
      DayStatus.ok,
      snapshot: DaySnapshot(date: date, trading: true, bars: {...tpex, ...twse.bars}, taiex: twse.taiex),
    );
  }

  /// null = 連線失敗；bars 是空的 = 這天沒有資料（休市）。
  Future<({Map<String, DailyBar> bars, double? taiex})?> _fetchTwse(String date) async {
    final uri = Uri.https('www.twse.com.tw', '/rwd/zh/afterTrading/MI_INDEX', {
      'date': date.replaceAll('-', ''),
      'type': 'ALLBUT0999', // 全部（不含權證、牛熊證）
      'response': 'json',
    });
    final body = await _getJson(uri);
    if (body == null) return null;
    return (bars: parseTwseDaily(date, body), taiex: parseTaiex(body));
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
  for (final (fields, data) in twseTables(body)) {
    final cols = _Columns.find(fields);
    if (cols != null) return cols.parse(date, data);
  }
  return {};
}

/// 從證交所 MI_INDEX 的「價格指數」表找出發行量加權股價指數的收盤。
double? parseTaiex(Map<String, dynamic> body) {
  for (final (fields, data) in twseTables(body)) {
    final names = [for (final f in fields) f.toString().replaceAll(RegExp(r'\s'), '')];
    final nameCol = names.indexWhere((n) => n == '指數');
    final closeCol = names.indexWhere((n) => n.contains('收盤指數'));
    if (nameCol < 0 || closeCol < 0) continue;
    for (final row in data) {
      if (row is List && row.length > closeCol && row[nameCol].toString().contains('發行量加權股價指數')) {
        return parseNum(row[closeCol]);
      }
    }
  }
  return null;
}

/// 證交所回應裡所有的 (欄位名稱, 資料) 表格，新版 `tables` 和舊版 `fieldsN`／`dataN` 都認。
List<(List, List)> twseTables(Map<String, dynamic> body) {
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
  return tables;
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
    return const _Columns(code: 0, close: 2, open: 4, high: 5, low: 6, volume: 8, change: 3).parse(date, aa);
  }
  return {};
}

class _Columns {
  final int code, open, high, low, close, volume;

  /// 漲跌價差那一欄（證交所是不帶正負號的價差，正負號另外一欄 [sign]；
  /// 櫃買是帶正負號的數字）。找不到就是 -1。
  final int change;
  final int sign;

  const _Columns({
    required this.code,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.change = -1,
    this.sign = -1,
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
    final sign = idx((n) => n.startsWith('漲跌(+/-)'));
    final change = sign >= 0 ? idx((n) => n.startsWith('漲跌價差')) : idx((n) => n == '漲跌');
    return _Columns(
      code: code,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
      change: change,
      sign: sign,
    );
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
        change: _signedChange(raw),
      );
    }
    return out;
  }

  /// 帶正負號的漲跌價差。證交所的正負號欄是 HTML（例如 `<p style= color:red>+</p>`），
  /// 出現 'X'（不比價，常見於除權息當天）時正負號不明，回傳 null。
  double? _signedChange(List raw) {
    if (change < 0 || change >= raw.length) return null;
    final mag = parseNum(raw[change]);
    if (mag == null) return null;
    if (sign < 0) return mag; // 櫃買：本身就帶正負號
    if (sign >= raw.length) return null;
    final s = raw[sign].toString().replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (s.contains('+')) return mag.abs();
    if (s.contains('-')) return -mag.abs();
    if (mag == 0 && s.isEmpty) return 0;
    return null;
  }
}
