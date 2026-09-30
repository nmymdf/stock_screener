/// 資料中樞：管理本機的每日收盤行情快取、同步進度、使用者的篩選設定。
/// 畫面透過 provider 監聽這個物件，資料一變動畫面就會自動更新。
library;

import 'package:flutter/foundation.dart';

import '../logic/technical_screen.dart';
import '../models/daily_bar.dart';
import '../services/history_service.dart';
import 'local_store.dart';

/// 台北時間的「現在」。證交所的日期都是台灣時間，不能用裝置的時區。
DateTime taipeiNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 回看 [lookbackDays] 天內，所有「可能是交易日」的日期（週一到週五），由新到舊。
/// 今天要等收盤資料公布後（台北時間 15:00 以後）才算進來。
List<String> candidateDates(DateTime taipeiNow, int lookbackDays) {
  final today = DateTime.utc(taipeiNow.year, taipeiNow.month, taipeiNow.day);
  final includeToday = taipeiNow.hour >= 15;
  final out = <String>[];
  for (var i = includeToday ? 0 : 1; i <= lookbackDays; i++) {
    final d = today.subtract(Duration(days: i));
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) continue;
    out.add(ymd(d));
  }
  return out;
}

class HistoryStore extends ChangeNotifier {
  final LocalStore _store;
  final HistoryService _service;

  /// 兩次請求之間要等多久。證交所對太密集的請求會暫時封鎖 IP，寧可慢一點。
  final Duration requestGap;

  HistoryStore({LocalStore? store, HistoryService? service, this.requestGap = const Duration(seconds: 3)})
      : _store = store ?? LocalStore(),
        _service = service ?? HistoryService();

  final Map<String, DaySnapshot> _days = {};
  Map<String, List<DailyBar>>? _seriesCache;

  bool loaded = false;
  bool syncing = false;
  bool _cancel = false;
  int syncDone = 0;
  int syncTotal = 0;
  String? lastError;
  String? dataDir;

  int lookbackDays = 120;
  ScreenCriteria criteria = kScreenPresets.first.criteria;

  Future<void> load() async {
    try {
      final s = await _store.readSettings();
      if (s != null) {
        lookbackDays = (s['lookbackDays'] as num?)?.round() ?? lookbackDays;
        final c = s['criteria'];
        if (c is Map<String, dynamic>) criteria = ScreenCriteria.fromJson(c);
      }
      for (final j in await _store.readAllDays()) {
        final snap = DaySnapshot.fromJson(j);
        _days[snap.date] = snap;
      }
      dataDir = await _store.dirPath();
    } catch (e) {
      lastError = '讀取本機資料失敗：$e';
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _saveSettings() => _store.writeSettings({
        'lookbackDays': lookbackDays,
        'criteria': criteria.toJson(),
      });

  Future<void> setCriteria(ScreenCriteria c) async {
    criteria = c;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLookbackDays(int days) async {
    lookbackDays = days;
    await _prune();
    notifyListeners();
    await _saveSettings();
  }

  /// 有收盤資料的交易日，由舊到新。
  List<String> get tradingDates =>
      (_days.values.where((d) => d.trading).map((d) => d.date).toList()..sort());

  String? get latestDate {
    final t = tradingDates;
    return t.isEmpty ? null : t.last;
  }

  /// 還沒抓過的日期（休市日抓過一次就會記住，不會一直重抓）。
  List<String> missingDates([DateTime? now]) =>
      candidateDates(now ?? taipeiNow(), lookbackDays).where((d) => !_days.containsKey(d)).toList();

  /// 每檔股票的日 K 序列（舊 → 新），給篩選和個股頁用。
  Map<String, List<DailyBar>> get seriesByCode {
    final cached = _seriesCache;
    if (cached != null) return cached;
    final out = <String, List<DailyBar>>{};
    for (final date in tradingDates) {
      for (final e in _days[date]!.bars.entries) {
        (out[e.key] ??= []).add(e.value);
      }
    }
    return _seriesCache = out;
  }

  List<DailyBar> seriesOf(String code) => seriesByCode[code] ?? const [];

  /// 把缺的日期補抓回來，由新到舊抓（最近的資料最有用，中途停掉也能先用）。
  /// 連續失敗 3 次就停下來，多半是沒網路或被證交所暫時擋掉。
  Future<void> sync({DateTime? now}) async {
    if (syncing) return;
    final todo = missingDates(now);
    syncing = true;
    _cancel = false;
    syncDone = 0;
    syncTotal = todo.length;
    lastError = null;
    notifyListeners();

    var consecutiveFailures = 0;
    try {
      for (var i = 0; i < todo.length; i++) {
        if (_cancel) break;
        if (i > 0) await Future<void>.delayed(requestGap);
        if (_cancel) break;
        final date = todo[i];
        final r = await _service.fetchDay(date);
        if (r.status == DayStatus.failed) {
          consecutiveFailures++;
          lastError = '$date：${r.message ?? '抓取失敗'}';
          if (consecutiveFailures >= 3) {
            lastError = '連續 3 天抓不到資料，先停下來（$lastError）。請確認網路，或過幾分鐘再試——'
                '證交所對太密集的請求會暫時封鎖。';
            break;
          }
        } else {
          consecutiveFailures = 0;
          final snap = r.snapshot!;
          _days[date] = snap;
          _seriesCache = null;
          await _store.writeDay(date, snap.toJson());
        }
        syncDone = i + 1;
        notifyListeners();
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  void cancelSync() => _cancel = true;

  /// 刪掉超出回看天數的舊資料，不讓本機檔案一直長大。
  Future<void> _prune() async {
    final keep = candidateDates(taipeiNow(), lookbackDays).toSet();
    final oldest = keep.isEmpty ? null : (keep.toList()..sort()).first;
    if (oldest == null) return;
    final drop = _days.keys.where((d) => d.compareTo(oldest) < 0).toList();
    for (final d in drop) {
      _days.remove(d);
      await _store.deleteDay(d);
    }
    if (drop.isNotEmpty) _seriesCache = null;
  }

  Future<void> clearAll() async {
    for (final d in _days.keys.toList()) {
      await _store.deleteDay(d);
    }
    _days.clear();
    _seriesCache = null;
    notifyListeners();
  }
}
