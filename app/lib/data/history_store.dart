/// 資料中樞：管理本機的每日收盤行情快取、同步進度、使用者的篩選設定。
/// 畫面透過 provider 監聽這個物件，資料一變動畫面就會自動更新。
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../logic/adjust.dart';
import '../logic/engine/analysis.dart';
import '../logic/engine/backtest.dart';
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

  /// 分析要不要放到背景 isolate 跑（測試時關掉，比較好控制）。
  final bool useIsolate;

  /// 打開 App 時自動補抓缺的日期，App 開著時每 10 分鐘檢查一次
  /// （台北時間 15:00 以後就會去抓當天收盤）。第一次下載仍然要手動按。
  final bool autoSync;
  Timer? _autoTimer;

  HistoryStore({
    LocalStore? store,
    HistoryService? service,
    this.requestGap = const Duration(seconds: 3),
    this.useIsolate = true,
    this.autoSync = false,
  }) : _store = store ?? LocalStore(),
       _service = service ?? HistoryService();

  /// 最近一次自動同步的時間（顯示「已自動更新」用）。
  DateTime? lastAutoSync;

  void _maybeAutoSync() {
    if (syncing || tradingDates.isEmpty) return;
    if (missingDates().isEmpty) return;
    lastAutoSync = DateTime.now();
    sync();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  final Map<String, DaySnapshot> _days = {};
  Map<String, List<DailyBar>>? _seriesCache;

  bool loaded = false;
  bool syncing = false;
  bool _cancel = false;
  int syncDone = 0;
  int syncTotal = 0;
  String? lastError;
  String? dataDir;

  /// 預設回看 400 天（約 280 個交易日）：200 日均線、52 週新高、240 日線廣度
  /// 都需要一年左右的資料。天數少也能用，只是那些指標會顯示「資料不足」。
  int lookbackDays = 400;
  ScreenCriteria criteria = kScreenPresets.first.criteria;

  /// 顯示設定：字體大小（null = 依視窗寬度自動）、淺色／深色、比較清單。
  double? fontScale;
  ThemeMode themeMode = ThemeMode.system;
  List<String> compareCodes = const [];

  AnalysisResult? analysis;
  bool analyzing = false;
  String? analysisError;
  int _dataVersion = 0;
  int _analyzedVersion = -1;

  BacktestResult? backtest;
  bool backtesting = false;
  String? backtestError;

  /// 用本機所有資料跑一次回測（背景 isolate）。
  Future<void> runBacktest(BacktestConfig cfg) async {
    if (backtesting || tradingDates.isEmpty) return;
    backtesting = true;
    backtestError = null;
    notifyListeners();
    try {
      final input = AnalysisInput(tradingDates, seriesByCode, taiexByDate);
      backtest = useIsolate ? await _backtestInBackground(input, cfg) : runBacktestSync(input, cfg);
    } catch (e) {
      backtestError = '回測失敗：$e';
    } finally {
      backtesting = false;
      notifyListeners();
    }
  }

  Future<void> load() async {
    try {
      final s = await _store.readSettings();
      if (s != null) {
        lookbackDays = (s['lookbackDays'] as num?)?.round() ?? lookbackDays;
        final c = s['criteria'];
        if (c is Map<String, dynamic>) criteria = ScreenCriteria.fromJson(c);
        fontScale = (s['fontScale'] as num?)?.toDouble();
        themeMode = ThemeMode.values.firstWhere((m) => m.name == s['themeMode'], orElse: () => ThemeMode.system);
        compareCodes = [for (final x in (s['compareCodes'] as List? ?? const [])) x as String];
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
    refreshAnalysis();
    if (autoSync) {
      _maybeAutoSync();
      _autoTimer = Timer.periodic(const Duration(minutes: 10), (_) => _maybeAutoSync());
    }
  }

  Future<void> _saveSettings() => _store.writeSettings({
    'lookbackDays': lookbackDays,
    'criteria': criteria.toJson(),
    'fontScale': ?fontScale,
    'themeMode': themeMode.name,
    'compareCodes': compareCodes,
  });

  Future<void> setFontScale(double? v) async {
    fontScale = v;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCompareCodes(List<String> codes) async {
    compareCodes = List.unmodifiable(codes);
    notifyListeners();
    await _saveSettings();
  }

  /// 抓滿 [days] 天的歷史資料（例如回測要兩年）：調整回看天數後開始同步。
  Future<void> extendHistory(int days) async {
    if (lookbackDays < days) {
      lookbackDays = days;
      await _saveSettings();
    }
    await sync();
  }

  void _dataChanged() {
    _dataVersion++;
    _seriesCache = null;
  }

  /// 資料有變（同步完、清除、改天數）就在背景重新跑一次全市場分析。
  /// 同步中不跑（每抓一天就重算太浪費），同步結束後再跑。
  Future<void> refreshAnalysis() async {
    if (analyzing || syncing) return;
    if (_analyzedVersion == _dataVersion && analysis != null) return;
    final dates = tradingDates;
    final version = _dataVersion;
    if (dates.isEmpty) {
      analysis = AnalysisResult.empty;
      _analyzedVersion = version;
      notifyListeners();
      return;
    }
    analyzing = true;
    notifyListeners();
    try {
      final input = AnalysisInput(dates, seriesByCode, taiexByDate);
      analysis = useIsolate ? await _analyzeInBackground(input) : runAnalysis(input);
      _analyzedVersion = version;
      analysisError = null;
    } catch (e) {
      analysisError = '分析失敗：$e';
    } finally {
      analyzing = false;
      notifyListeners();
    }
    if (_dataVersion != version) await refreshAnalysis();
  }

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
    await refreshAnalysis();
  }

  /// 有收盤資料的交易日，由舊到新。
  List<String> get tradingDates => (_days.values.where((d) => d.trading).map((d) => d.date).toList()..sort());

  String? get latestDate {
    final t = tradingDates;
    return t.isEmpty ? null : t.last;
  }

  /// 還沒抓過的日期（休市日抓過一次就會記住，不會一直重抓）。
  List<String> missingDates([DateTime? now]) =>
      candidateDates(now ?? taipeiNow(), lookbackDays).where((d) => !_days.containsKey(d)).toList();

  /// 每檔股票的日 K 序列（舊 → 新，已還原權息），給分析、篩選、個股頁用。
  Map<String, List<DailyBar>> get seriesByCode {
    final cached = _seriesCache;
    if (cached != null) return cached;
    final raw = <String, List<DailyBar>>{};
    for (final date in tradingDates) {
      for (final e in _days[date]!.bars.entries) {
        (raw[e.key] ??= []).add(e.value);
      }
    }
    return _seriesCache = {for (final e in raw.entries) e.key: adjustForCorporateActions(e.value)};
  }

  Map<String, double> get taiexByDate => {
    for (final d in _days.values)
      if (d.taiex != null) d.date: d.taiex!,
  };

  List<DailyBar> seriesOf(String code) => seriesByCode[code] ?? const [];

  /// 沒有還原權息的原始日 K（實際成交價），給持股算真實損益用。
  List<DailyBar> rawSeriesOf(String code) => [
    for (final date in tradingDates)
      if (_days[date]!.bars[code] != null) _days[date]!.bars[code]!,
  ];

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
    final nowT = now ?? taipeiNow();
    final todayStr = ymd(nowT);
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
            lastError =
                '連續 3 天抓不到資料，先停下來（$lastError）。請確認網路，或過幾分鐘再試——'
                '證交所對太密集的請求會暫時封鎖。';
            break;
          }
        } else if (r.status == DayStatus.closed && date == todayStr && nowT.hour < 20) {
          // 平日下午「兩邊都沒資料」多半是今天的收盤還沒公布，不是休市：先不要記成休市，晚點再抓。
          lastError = '今天（$date）的收盤資料還沒公布，晚一點會再自動抓';
        } else {
          consecutiveFailures = 0;
          final snap = r.snapshot!;
          _days[date] = snap;
          _dataChanged();
          await _store.writeDay(date, snap.toJson());
        }
        syncDone = i + 1;
        notifyListeners();
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
    await refreshAnalysis();
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
    if (drop.isNotEmpty) _dataChanged();
  }

  Future<void> clearAll() async {
    for (final d in _days.keys.toList()) {
      await _store.deleteDay(d);
    }
    _days.clear();
    _dataChanged();
    notifyListeners();
    await refreshAnalysis();
  }
}

/// 放在最上層，確保丟進 isolate 的閉包只帶著 [input]，不會把整個 store 一起複製過去。
Future<AnalysisResult> _analyzeInBackground(AnalysisInput input) => Isolate.run(() => runAnalysis(input));

Future<BacktestResult> _backtestInBackground(AnalysisInput input, BacktestConfig cfg) =>
    Isolate.run(() => runBacktestSync(input, cfg));

BacktestResult runBacktestSync(AnalysisInput input, BacktestConfig cfg) => runBacktest(input, cfg);
