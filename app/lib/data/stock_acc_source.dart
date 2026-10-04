/// 讀取同一台電腦上 stock_acc（股票記帳）的交易紀錄，整理成持股。
///
/// - 只讀不寫：台股選股永遠不會修改 stock_acc 的檔案。
/// - 只在電腦版：兩個 App 的資料都在 `%APPDATA%\com.archiekuo\` 底下，
///   台股選股的資料夾旁邊就是 `stock_acc`。手機上每個 App 互相隔離，讀不到。
/// - 找不到 stock_acc 的資料（例如朋友的電腦）就當作沒有，畫面會整組隱藏。
/// - 所有群體、人、券商帳戶的交易依股票代號合併成一筆持股。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/holding.dart';

/// stock_acc 的一筆交易（只取我們需要的欄位）。
class AccTrade {
  final String date; // yyyy-MM-dd
  final String code;
  final String name;
  final bool buy;
  final int shares;
  final double price;
  final double fee, tax;
  final int order; // 檔案裡的先後順序，同一天的交易照這個排
  const AccTrade({
    required this.date,
    required this.code,
    required this.name,
    required this.buy,
    required this.shares,
    required this.price,
    required this.fee,
    required this.tax,
    this.order = 0,
  });
}

class StockAccSource {
  static const groupsFile = 'stock_acc_groups.json';
  static const legacyFile = 'stock_acc_data.json';
  static String dataFileFor(String groupId) => 'stock_acc_data_$groupId.json';

  /// 測試時直接指定資料夾。
  final Directory? _override;
  StockAccSource({Directory? dir}) : _override = dir;

  /// stock_acc 的資料夾；這台電腦沒有就回傳 null。
  Future<Directory?> locate() async {
    Directory dir;
    if (_override != null) {
      dir = _override;
    } else {
      if (Platform.isAndroid || Platform.isIOS) return null;
      final mine = await getApplicationSupportDirectory();
      dir = Directory('${mine.parent.path}${Platform.pathSeparator}stock_acc');
    }
    if (!await dir.exists()) return null;
    final hasGroups = await File('${dir.path}/$groupsFile').exists();
    final hasLegacy = await File('${dir.path}/$legacyFile').exists();
    return hasGroups || hasLegacy ? dir : null;
  }

  /// 讀出所有群體的全部交易。檔案不完整、格式不對會丟出 [FormatException]。
  Future<List<AccTrade>> readTrades() async {
    final dir = await locate();
    if (dir == null) return const [];
    final files = <File>[];
    final groups = File('${dir.path}/$groupsFile');
    if (await groups.exists()) {
      final j = _decode(await groups.readAsString(), groupsFile);
      for (final g in (j['groups'] as List? ?? const [])) {
        final id = (g as Map<String, dynamic>)['id'] as String;
        files.add(File('${dir.path}/${dataFileFor(id)}'));
      }
    } else {
      files.add(File('${dir.path}/$legacyFile'));
    }
    final out = <AccTrade>[];
    var order = 0;
    for (final f in files) {
      if (!await f.exists()) continue;
      final text = await f.readAsString();
      if (text.trim().isEmpty) continue;
      final j = _decode(text, f.uri.pathSegments.last);
      for (final t in (j['trades'] as List? ?? const [])) {
        final m = t as Map<String, dynamic>;
        final shares = (m['shares'] as num?)?.round() ?? 0;
        final code = (m['code'] as String? ?? '').trim().toUpperCase();
        final date = (m['date'] as String? ?? '');
        if (shares <= 0 || code.isEmpty || date.length < 10) continue;
        out.add(
          AccTrade(
            date: date.substring(0, 10),
            code: code,
            name: m['name'] as String? ?? '',
            buy: m['side'] == 'buy',
            shares: shares,
            price: (m['price'] as num?)?.toDouble() ?? 0,
            fee: (m['fee'] as num?)?.toDouble() ?? 0,
            tax: (m['tax'] as num?)?.toDouble() ?? 0,
            order: order++,
          ),
        );
      }
    }
    return out;
  }

  static Map<String, dynamic> _decode(String text, String name) {
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw FormatException('stock_acc 的檔案 $name 讀不完整');
    }
  }
}

/// 把交易整理成持股：每檔股票從 0 股變成有股數就是一筆新持股，賣到 0 就結案。
/// 不同帳戶、不同群體的同一檔股票合併計算。
List<Holding> positionsFromTrades(List<AccTrade> trades, {HoldStyle style = HoldStyle.long}) {
  final byCode = <String, List<AccTrade>>{};
  for (final t in trades) {
    (byCode[t.code] ??= []).add(t);
  }
  final out = <Holding>[];
  for (final e in byCode.entries) {
    // 同一天先算買進再算賣出（當沖或同日加減碼），避免中途出現負股數
    final list = [...e.value]
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        if (d != 0) return d;
        if (a.buy != b.buy) return a.buy ? -1 : 1;
        return a.order.compareTo(b.order);
      });
    var held = 0;
    List<BuyLot>? buys;
    List<SellLot>? sells;
    void close() {
      if (buys == null || buys!.isEmpty) return;
      out.add(
        Holding(
          id: 'acc_${e.key}_${buys!.first.date}',
          code: e.key,
          style: style,
          buys: buys!,
          sells: sells!,
          source: HoldingSource.stockAcc,
        ),
      );
      buys = null;
      sells = null;
    }

    for (final t in list) {
      if (t.buy) {
        if (held == 0) {
          buys = [];
          sells = [];
        }
        buys!.add(BuyLot(t.date, t.price, t.shares, fee: t.fee));
        held += t.shares;
      } else {
        if (held == 0 || buys == null) continue; // 記帳裡沒有對應買進的賣出，略過
        final n = t.shares > held ? held : t.shares;
        // 部分超賣（記帳資料有誤）就照比例算手續費和稅
        final k = n / t.shares;
        sells!.add(SellLot(t.date, t.price, n, reason: 'stock_acc 記帳', fee: t.fee * k, tax: t.tax * k));
        held -= n;
        if (held == 0) close();
      }
    }
    close(); // 還持有中的那一筆
  }
  out.sort((a, b) => a.firstBuyDate.compareTo(b.firstBuyDate));
  return out;
}
