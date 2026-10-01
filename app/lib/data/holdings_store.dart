/// 我的持股：讀寫本機的持股紀錄檔，畫面透過 provider 監聽變動。
library;

import 'package:flutter/foundation.dart';

import '../models/holding.dart';
import 'local_store.dart';

class HoldingsStore extends ChangeNotifier {
  static const fileName = 'stock_screener_holdings.json';
  final LocalStore _store;
  HoldingsStore({LocalStore? store}) : _store = store ?? LocalStore();

  final List<Holding> _items = [];
  bool loaded = false;
  String? error;

  List<Holding> get all => List.unmodifiable(_items);
  List<Holding> get open => _items.where((h) => !h.closed).toList();
  List<Holding> get closed => _items.where((h) => h.closed).toList();

  Holding? byId(String id) {
    for (final h in _items) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// 這檔股票目前還持有的那筆（同一檔只會有一筆持有中的紀錄，加碼就加在它上面）。
  Holding? openFor(String code) {
    for (final h in _items) {
      if (h.code == code && !h.closed) return h;
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
    } catch (e) {
      error = '讀取持股紀錄失敗：$e';
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() => _store.writeNamed(fileName, {
    'version': 1,
    'holdings': [for (final h in _items) h.toJson()],
  });

  String newId(String code) => '${code}_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> upsert(Holding h) async {
    final i = _items.indexWhere((x) => x.id == h.id);
    if (i >= 0) {
      _items[i] = h;
    } else {
      _items.add(h);
    }
    notifyListeners();
    await _save();
  }

  Future<void> addBuy(String id, BuyLot lot) async {
    final h = byId(id);
    if (h == null) return;
    await upsert(h.copyWith(buys: [...h.buys, lot]));
  }

  Future<void> addSell(String id, SellLot lot) async {
    final h = byId(id);
    if (h == null) return;
    await upsert(h.copyWith(sells: [...h.sells, lot]));
  }

  Future<void> remove(String id) async {
    _items.removeWhere((h) => h.id == id);
    notifyListeners();
    await _save();
  }
}
