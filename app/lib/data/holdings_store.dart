/// 我的持股：分兩組——
/// - 手動／模擬：自己輸入的，可以新增、修改、刪除（每台電腦都有）。
/// - stock_acc：從同一台電腦上的 stock_acc 記帳同步進來，買賣紀錄唯讀；
///   台股選股自己的設定（持有方式、停損、備註…）另外存，重新同步不會洗掉。
///   這台電腦沒有 stock_acc 就整組隱藏。
library;

import 'package:flutter/foundation.dart';

import '../models/holding.dart';
import 'local_store.dart';
import 'stock_acc_source.dart';

class HoldingsStore extends ChangeNotifier {
  static const fileName = 'stock_screener_holdings.json';
  final LocalStore _store;

  /// stock_acc 的讀取來源；null = 不同步（測試、或不想讀）。
  final StockAccSource? accSource;
  HoldingsStore({LocalStore? store, this.accSource}) : _store = store ?? LocalStore();

  final List<Holding> _items = [];
  final List<Holding> _accItems = [];
  final Map<String, Map<String, dynamic>> _accSettings = {};
  bool loaded = false;
  String? error;

  /// 這台電腦有沒有 stock_acc 的資料（沒有就隱藏整組）。
  bool accAvailable = false;
  bool accSyncing = false;
  DateTime? accLastSync;
  String? accError;
  int accTradeCount = 0;
  String? accPath;

  /// 手動／模擬的持股。
  List<Holding> get manual => List.unmodifiable(_items);

  /// 從 stock_acc 同步進來的持股。
  List<Holding> get accHoldings => List.unmodifiable(_accItems);

  List<Holding> get all => [..._items, ..._accItems];
  List<Holding> get open => all.where((h) => !h.closed).toList();
  List<Holding> get closed => all.where((h) => h.closed).toList();

  List<Holding> of(HoldingSource s) => s == HoldingSource.manual ? manual : accHoldings;

  Holding? byId(String id) {
    for (final h in all) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// 這檔股票目前還持有的那筆（同一組裡同一檔只會有一筆持有中的紀錄，加碼就加在它上面）。
  Holding? openFor(String code, {HoldingSource? source}) {
    for (final h in all) {
      if (h.code == code && !h.closed && (source == null || h.source == source)) return h;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final j = await _store.readNamed(fileName);
      final list = j?['holdings'] as List? ?? const [];
      _items
        ..clear()
        ..addAll([for (final x in list) Holding.fromJson(x as Map<String, dynamic>)]);
      final s = j?['accSettings'] as Map<String, dynamic>? ?? const {};
      _accSettings
        ..clear()
        ..addAll({for (final e in s.entries) e.key: e.value as Map<String, dynamic>});
    } catch (e) {
      error = '讀取持股紀錄失敗：$e';
    }
    loaded = true;
    notifyListeners();
    await syncAcc();
  }

  /// 讀 stock_acc 的交易、重算持股。讀不到完整檔案時保留上一次的結果。
  Future<void> syncAcc() async {
    final src = accSource;
    if (src == null || accSyncing) return;
    accSyncing = true;
    notifyListeners();
    try {
      final dir = await src.locate();
      accAvailable = dir != null;
      accPath = dir?.path;
      if (dir != null) {
        final trades = await src.readTrades();
        final positions = positionsFromTrades(trades);
        _accItems
          ..clear()
          ..addAll([for (final p in positions) p.withSettings(_accSettings[p.id])]);
        accTradeCount = trades.length;
        accLastSync = DateTime.now();
        accError = null;
      }
    } catch (e) {
      accError = e is FormatException ? '${e.message}，請稍後再按一次「同步 stock_acc」' : '讀取 stock_acc 失敗：$e';
    } finally {
      accSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _save() => _store.writeNamed(fileName, {
    'version': 2,
    'holdings': [for (final h in _items) h.toJson()],
    'accSettings': _accSettings,
  });

  String newId(String code) => '${code}_${DateTime.now().microsecondsSinceEpoch}';

  /// 新增或修改。stock_acc 的持股只會存台股選股自己的設定，買賣紀錄不變。
  Future<void> upsert(Holding h) async {
    if (h.fromStockAcc) {
      final i = _accItems.indexWhere((x) => x.id == h.id);
      if (i < 0) return;
      _accSettings[h.id] = h.settingsJson();
      _accItems[i] = _accItems[i].withSettings(_accSettings[h.id]);
    } else {
      final i = _items.indexWhere((x) => x.id == h.id);
      if (i >= 0) {
        _items[i] = h;
      } else {
        _items.add(h);
      }
    }
    notifyListeners();
    await _save();
  }

  Future<void> addBuy(String id, BuyLot lot) async {
    final h = byId(id);
    if (h == null || h.fromStockAcc) return;
    await upsert(h.copyWith(buys: [...h.buys, lot]));
  }

  Future<void> addSell(String id, SellLot lot) async {
    final h = byId(id);
    if (h == null || h.fromStockAcc) return;
    await upsert(h.copyWith(sells: [...h.sells, lot]));
  }

  Future<void> remove(String id) async {
    _items.removeWhere((h) => h.id == id && !h.fromStockAcc);
    notifyListeners();
    await _save();
  }
}

/// 修改買賣紀錄之後檢查合不合理：每一天收盤持股都不能是負的、至少要有一筆買進。
/// 回傳錯誤說明，沒問題回傳 null。
String? validateLots(List<BuyLot> buys, List<SellLot> sells) {
  if (buys.isEmpty) return '至少要有一筆買進紀錄；不要這筆持股了，請用「刪除整筆持股」';
  for (final b in buys) {
    if (b.shares <= 0 || b.price <= 0) return '買進的價格和股數都要大於 0';
  }
  for (final s in sells) {
    if (s.shares <= 0 || s.price <= 0) return '賣出的價格和股數都要大於 0';
  }
  final dates = {...buys.map((b) => b.date), ...sells.map((s) => s.date)}.toList()..sort();
  for (final d in dates) {
    final held =
        buys.where((b) => b.date.compareTo(d) <= 0).fold(0, (a, b) => a + b.shares) -
        sells.where((s) => s.date.compareTo(d) <= 0).fold(0, (a, b) => a + b.shares);
    if (held < 0) return '$d 賣出的股數超過當時持有的股數';
  }
  return null;
}
