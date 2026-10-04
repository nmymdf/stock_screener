/// 長期分析的中樞：管理資料包更新、把資料包的每日行情匯入本機、在背景跑長期分析，
/// 以及使用者的組合設定（檔數、每月最多換幾檔、要不要看市場環境調整股票比例）。
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../core/exposure.dart';
import '../core/lt_analysis.dart';
import '../core/pack.dart';
import '../core/portfolio.dart';
import 'datapack_store.dart';
import 'history_store.dart';
import 'local_store.dart';

class LongTermStore extends ChangeNotifier {
  static const fileName = 'stock_screener_longterm.json';

  final DataPackStore pack;
  final HistoryStore history;
  final LocalStore _store;
  final bool useIsolate;

  /// 打開 App 時檢查資料包更新，之後每小時一次（第一次下載要自己按）。
  final bool autoUpdate;
  Timer? _timer;

  LongTermStore({
    required this.pack,
    required this.history,
    LocalStore? store,
    this.useIsolate = true,
    this.autoUpdate = false,
  }) : _store = store ?? LocalStore();

  LtConfig cfg = const LtConfig();

  /// 汰弱留強：每月最多建議換幾檔（2～5）。
  int maxSwaps = 3;

  /// 理想組合試算用的投入金額（萬元）；null = 不試算。
  double? capital;

  LtResult? result;
  bool analyzing = false;
  bool loaded = false;
  String? error;
  int _doneVersion = -1;
  String? _doneExtra;

  Future<void> load() async {
    try {
      final j = await _store.readNamed(fileName);
      if (j != null) {
        cfg = cfg.copyWith(
          size: (j['size'] as num?)?.toInt(),
          maxChanges: (j['maxChanges'] as num?)?.toInt(),
          exposure: ExposureMode.values.where((m) => m.name == j['exposure']).firstOrNull,
        );
        maxSwaps = (j['maxSwaps'] as num?)?.toInt() ?? maxSwaps;
        capital = (j['capital'] as num?)?.toDouble();
      }
    } catch (_) {}
    if (!pack.loaded) await pack.load();
    loaded = true;
    pack.addListener(_onChange);
    history.addListener(_onChange);
    notifyListeners();
    if (pack.hasPack) {
      unawaited(refresh());
      if (autoUpdate) unawaited(updatePack());
    }
    if (autoUpdate) {
      _timer = Timer.periodic(const Duration(minutes: 60), (_) {
        if (pack.hasPack) updatePack();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    pack.removeListener(_onChange);
    history.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _save() => _store.writeNamed(fileName, {
    'size': cfg.size,
    'maxChanges': cfg.maxChanges,
    'exposure': cfg.exposure.name,
    'maxSwaps': maxSwaps,
    'capital': ?capital,
  });

  /// App 自己抓到、比資料包更新的日子（今天收盤後直接從證交所抓的）。
  String? _extraKey() {
    final h = history.latestDate, p = pack.lastDate;
    return h != null && p != null && h.compareTo(p) > 0 ? h : null;
  }

  void _onChange() {
    if (!loaded || !pack.hasPack || analyzing || pack.updating || !history.loaded) return;
    if (pack.version != _doneVersion || _extraKey() != _doneExtra) refresh();
  }

  /// 下載／更新資料包，有新資料就匯入每日行情、重跑分析。
  Future<void> updatePack() async {
    final changed = await pack.update(lookbackDays: history.lookbackDays);
    if (changed || history.missingDates().isNotEmpty) await importHistory();
    if (changed) await refresh();
  }

  /// 把資料包裡的每日行情匯入本機（短線、持股、圖表用），不用再一天一天跟證交所抓。
  Future<int> importHistory() async {
    if (!pack.hasPack) return 0;
    final dates = candidateDates(taipeiNow(), history.lookbackDays)..sort();
    if (dates.isEmpty) return 0;
    final snaps = await pack.snapshotsSince(dates.first);
    return history.importSnapshots(snaps);
  }

  Future<void> refresh() async {
    if (analyzing || !pack.hasPack || pack.dirPath == null) return;
    analyzing = true;
    error = null;
    notifyListeners();
    final version = pack.version;
    final extraKey = _extraKey();
    try {
      final dir = pack.dirPath!;
      final extra = history.packDaysAfter(pack.lastDate);
      final c = cfg;
      result = useIsolate ? await _analyzeInBackground(dir, extra, c) : _analyze(dir, extra, c);
    } catch (e) {
      error = '長期分析失敗：$e';
    } finally {
      // 失敗也記下來，避免一直重試
      _doneVersion = version;
      _doneExtra = extraKey;
      analyzing = false;
      notifyListeners();
    }
    if (pack.version != _doneVersion || _extraKey() != _doneExtra) await refresh();
  }

  Future<void> setConfig({int? size, int? maxChanges, ExposureMode? exposure}) async {
    cfg = cfg.copyWith(size: size, maxChanges: maxChanges, exposure: exposure);
    notifyListeners();
    await _save();
    _doneVersion = -1;
    await refresh();
  }

  Future<void> setCapital(double? v) async {
    capital = v == null || v <= 0 ? null : v;
    notifyListeners();
    await _save();
  }

  Future<void> setMaxSwaps(int n) async {
    maxSwaps = n;
    notifyListeners();
    await _save();
  }
}

LtResult _analyze(String dir, List<PackDay> extra, LtConfig cfg) =>
    runLtAnalysis(loadPackDir(dir, extraDays: extra), cfg: cfg);

/// 放在最上層，丟進 isolate 的只有路徑、幾天的資料和設定。
Future<LtResult> _analyzeInBackground(String dir, List<PackDay> extra, LtConfig cfg) =>
    Isolate.run(() => _analyze(dir, extra, cfg));
