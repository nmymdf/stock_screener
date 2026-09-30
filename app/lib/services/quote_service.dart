/// 抓證交所「基本市況報導」的即時報價（跟 stock_acc 同一個來源），給「今日雷達」用。
/// 免費不用帳號，但不是正式公開的 API，查不到、逾時的股票會直接跳過。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/stock_catalog.dart';

/// 當日即時報價：開高低、成交量、昨收，用來算漲跌幅、量能、離今天高點的距離。
class LiveQuote {
  final String code;
  final double price;
  final double prevClose;
  final double open;
  final double high;
  final double low;
  final int volumeLots; // 成交量，單位：張

  const LiveQuote({
    required this.code,
    required this.price,
    required this.prevClose,
    required this.open,
    required this.high,
    required this.low,
    required this.volumeLots,
  });

  double get changePct => prevClose == 0 ? 0 : (price - prevClose) / prevClose * 100;
}

class QuoteService {
  /// 一次最多查幾支，太多的話分批查詢，避免單一請求太長被拒。
  static const batchSize = 30;

  final http.Client _client;
  QuoteService({http.Client? client}) : _client = client ?? http.Client();

  /// 查一批代號當天完整的開高低量，查不到、逾時的股票直接跳過（回傳的清單
  /// 可能比要求的代號少），不影響其他候選股。
  Future<List<LiveQuote>> fetch(List<String> codes) async {
    final out = <LiveQuote>[];
    for (var i = 0; i < codes.length; i += batchSize) {
      final end = i + batchSize > codes.length ? codes.length : i + batchSize;
      out.addAll(await _fetchBatch(codes.sublist(i, end)));
    }
    return out;
  }

  Future<List<LiveQuote>> _fetchBatch(List<String> codes) async {
    // 上市用 tse_ 前綴、上櫃用 otc_（查錯市場證交所會回空值）。
    final exCh = codes
        .map((c) {
          final prefix = kBuiltinStocksByCode[c]?.market == '上櫃' ? 'otc' : 'tse';
          return '${prefix}_$c.tw';
        })
        .join('|');
    final uri = Uri.https(
      'mis.twse.com.tw',
      '/stock/api/getStockInfo.jsp',
      {'ex_ch': exCh, 'json': '1', 'delay': '0'},
    );
    try {
      final res = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      return parseLiveQuotes(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      // 沒有網路、逾時、證交所格式變了……都當作「這批抓不到」。
      return const [];
    }
  }
}

/// 解析 getStockInfo.jsp 的回應。拆出來是為了能直接用假資料測試。
List<LiveQuote> parseLiveQuotes(Map<String, dynamic> body) {
  final list = body['msgArray'] as List? ?? const [];
  final out = <LiveQuote>[];
  for (final raw in list) {
    final row = raw as Map<String, dynamic>;
    final code = row['c'] as String?;
    if (code == null) continue;
    final zStr = row['z'] as String?; // 成交價，'-' 代表還沒成交
    final yStr = row['y'] as String?; // 昨收
    final price = parseNum((zStr == '-' ? null : zStr) ?? yStr);
    final prevClose = parseNum(yStr);
    if (price == null || prevClose == null || prevClose == 0) continue;
    out.add(LiveQuote(
      code: code,
      price: price,
      prevClose: prevClose,
      open: parseNum(row['o']) ?? price,
      high: parseNum(row['h']) ?? price,
      low: parseNum(row['l']) ?? price,
      volumeLots: (parseNum(row['v']) ?? 0).round(),
    ));
  }
  return out;
}

/// 證交所/櫃買的數字常帶千分位逗號，沒成交時是 '--' 或 '-'，一律轉成 null。
double? parseNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '').trim());
}
