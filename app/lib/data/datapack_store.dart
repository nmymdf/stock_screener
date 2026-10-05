/// 長期資料包：GitHub Actions 每個交易日晚上整理好、放在 GitHub Releases 的「data」，
/// App 下載到本機。第一次下載完整的（十幾年的資料，約 30 MB），之後每天只下載
/// 最近 30 天的小檔（約 1 MB）和有變動的營收、除權息、國際指標。
///
/// 下載的只有公開的市場資料；持股、stock_acc 的資料不會上傳到任何地方。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/pack.dart';
import '../models/daily_bar.dart';

class DataPackStore extends ChangeNotifier {
  static const defaultBase = 'https://github.com/nmymdf/stock_screener/releases/download/data';
  static const dirName = 'datapack';

  final String base;
  final http.Client _client;
  final Directory? _dirOverride;

  /// GitHub 偶爾會回 500／502／503 或斷線，等一下再試通常就好；這是每次重試前等多久。
  final List<Duration> retryDelays;

  DataPackStore({
    http.Client? client,
    Directory? dir,
    this.base = defaultBase,
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 12)],
  }) : _client = client ?? http.Client(),
       _dirOverride = dir;

  String? dirPath;
  Map<String, PackFileInfo> local = {};
  String? lastDate;
  DateTime? lastCheck;
  bool loaded = false;
  bool updating = false;
  int doneBytes = 0, totalBytes = 0;
  String? error;

  /// 本機檔案每變一次就加一（長期分析看這個決定要不要重算）。
  int version = 0;

  bool get hasPack => local.keys.any((k) => k.startsWith('lt-'));

  /// 本機資料包總大小。
  int get localBytes => local.values.fold(0, (a, b) => a + b.size);

  Future<Directory> _dir() async {
    final d = _dirOverride ?? Directory('${(await getApplicationSupportDirectory()).path}/$dirName');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    try {
      final d = await _dir();
      dirPath = d.path;
      final f = File('${d.path}/state.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        local = {
          for (final e in ((j['files'] as Map?) ?? const {}).entries)
            e.key as String: PackFileInfo.fromJson(e.key as String, e.value as Map<String, dynamic>),
        };
        // 檔案被刪掉的話當作沒有
        local.removeWhere((name, _) => !File('${d.path}/$name').existsSync());
        lastDate = j['lastDate'] as String?;
        final c = j['checked'] as String?;
        lastCheck = c == null ? null : DateTime.tryParse(c);
      }
    } catch (e) {
      error = '讀取本機資料包失敗：$e';
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _saveState() async {
    final d = await _dir();
    final f = File('${d.path}/state.json.tmp');
    await f.writeAsString(
      jsonEncode({
        'lastDate': lastDate,
        'checked': lastCheck?.toIso8601String(),
        'files': {for (final e in local.entries) e.key: e.value.toJson()},
      }),
    );
    await f.rename('${d.path}/state.json');
  }

  /// 檢查並下載更新。[lookbackDays] 決定要下載幾年的每日行情（給短線、持股、圖表用）。
  /// 回傳本機檔案有沒有變。
  Future<bool> update({int lookbackDays = 400, DateTime? now}) async {
    if (updating) return false;
    updating = true;
    error = null;
    doneBytes = 0;
    totalBytes = 0;
    notifyListeners();
    var changed = false;
    try {
      final body = await _retry('清單', (attempt) async {
        final res = await _client
            .get(Uri.parse('$base/manifest.json?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}&r=$attempt'))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 404) throw const HttpException('資料包還沒準備好（GitHub 上還沒有 data）');
        if (res.statusCode != 200) throw _HttpStatus('清單', res.statusCode);
        return res.bodyBytes;
      });
      final remote = PackManifest.fromJson(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
      final recentFirst = remote.files['recent.json.gz']?.first;
      final t = now ?? DateTime.now();
      final oldestBarsYear = t.subtract(Duration(days: lookbackDays)).year;
      final want = <PackFileInfo>[];
      for (final info in remote.files.values) {
        final have = local[info.name];
        if (have != null && have.hash == info.hash) continue;
        final m = RegExp(r'^(lt|bars)-(\d{4})\.json\.gz$').firstMatch(info.name);
        if (m != null) {
          final year = int.parse(m.group(2)!);
          if (m.group(1) == 'bars' && year < oldestBarsYear) continue;
          // 今年的檔案每天都會變，本機的只要跟「最近 30 天」接得上就不用重抓
          if (have != null && have.last != null && recentFirst != null && have.last!.compareTo(recentFirst) >= 0) {
            continue;
          }
        }
        want.add(info);
      }
      totalBytes = want.fold(0, (a, b) => a + b.size);
      notifyListeners();
      final d = await _dir();
      for (final info in want) {
        await _download(info, d);
        local[info.name] = info;
        changed = true;
        await _saveState();
      }
      // 遠端已經沒有的檔案（例如超過三年的每日行情）刪掉
      for (final name in local.keys.toList()) {
        if (!remote.files.containsKey(name)) {
          local.remove(name);
          final f = File('${d.path}/$name');
          if (await f.exists()) await f.delete();
          changed = true;
        }
      }
      lastDate = remote.lastDate;
      lastCheck = DateTime.now();
      await _saveState();
      if (changed) version++;
    } catch (e) {
      error = switch (e) {
        _HttpStatus(:final what, :final code, :final transient) when transient =>
          'GitHub 暫時出錯，下載$what失敗（HTTP $code，已自動重試 ${retryDelays.length} 次）。請過幾分鐘再按一次；已經下載好的檔案會保留，不用從頭來。',
        _HttpStatus(:final what, :final code) => '下載$what失敗（HTTP $code）',
        HttpException(:final message) => message,
        SocketException() ||
        TimeoutException() ||
        http.ClientException() => '連不上 GitHub（已自動重試 ${retryDelays.length} 次）。請確認網路後再按一次；已經下載好的檔案會保留。',
        _ => '更新資料包失敗：$e',
      };
    } finally {
      updating = false;
      notifyListeners();
    }
    return changed;
  }

  /// 遇到伺服器錯誤（5xx、429）或斷線就等一下再試，最多重試 [retryDelays] 那麼多次。
  Future<T> _retry<T>(String what, Future<T> Function(int attempt) run) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await run(attempt);
      } catch (e) {
        final transient = switch (e) {
          _HttpStatus(:final transient) => transient,
          SocketException() || TimeoutException() || http.ClientException() || HandshakeException() => true,
          _ => false,
        };
        if (!transient || attempt >= retryDelays.length) rethrow;
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  Future<void> _download(PackFileInfo info, Directory d) async {
    final tmp = File('${d.path}/${info.name}.part');
    final startBytes = doneBytes;
    await _retry(' ${info.name} ', (attempt) async {
      doneBytes = startBytes;
      // 重試時加個參數，避免中間的快取把錯誤的回應再送一次
      final req = http.Request('GET', Uri.parse(attempt == 0 ? '$base/${info.name}' : '$base/${info.name}?r=$attempt'));
      final res = await _client.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        await res.stream.drain<void>().catchError((_) {});
        // 清單上有、卻回 404：多半是晚上更新時檔案正在被換掉，等一下再試
        throw _HttpStatus(' ${info.name} ', res.statusCode, retry: res.statusCode == 404);
      }
      final sink = tmp.openWrite();
      var lastNotify = DateTime.now();
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          doneBytes += chunk.length;
          if (DateTime.now().difference(lastNotify).inMilliseconds > 200) {
            lastNotify = DateTime.now();
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
    });
    await tmp.rename('${d.path}/${info.name}');
  }

  /// 資料包裡 [from] 以後每一天的行情（上市＋上櫃，給「每日行情」匯入用，含休市日）。
  Future<List<DaySnapshot>> snapshotsSince(String from) async {
    final d = dirPath;
    if (d == null) return const [];
    final names = local.keys.where((n) => n.startsWith('bars-') || n == 'recent.json.gz').toList();
    final fromYear = int.parse(from.substring(0, 4));
    return Isolate.run(() => readSnapshots(d, names, from, fromYear));
  }

  Future<void> clear() async {
    final d = await _dir();
    for (final name in [...local.keys, 'state.json']) {
      final f = File('${d.path}/$name');
      if (await f.exists()) await f.delete();
    }
    local = {};
    lastDate = null;
    version++;
    notifyListeners();
  }
}

class _HttpStatus implements Exception {
  final String what;
  final int code;
  final bool retry;
  const _HttpStatus(this.what, this.code, {this.retry = false});
  bool get transient => retry || code >= 500 || code == 429 || code == 408;
  @override
  String toString() => '下載$what失敗（HTTP $code）';
}

/// 在背景 isolate 讀 bars／recent，轉成每日行情。
List<DaySnapshot> readSnapshots(String dir, List<String> names, String from, int fromYear) {
  final out = <String, DaySnapshot>{};
  for (final n in names..sort()) {
    final m = RegExp(r'^bars-(\d{4})').firstMatch(n);
    if (m != null && int.parse(m.group(1)!) < fromYear) continue;
    final f = File('$dir/$n');
    if (!f.existsSync()) continue;
    final j = decodeGz(f.readAsBytesSync());
    if (n == 'recent.json.gz') {
      final rp = RecentPack.fromJson(j);
      final dates = <String>[];
      for (final day in rp.days) {
        final s = day.snapshot();
        if (s != null && day.date.compareTo(from) >= 0) out[day.date] = s;
        dates.add(day.date);
      }
      // 最近 30 天中間沒出現的平日就是休市
      if (dates.length >= 2) {
        var t = DateTime.parse(dates.first);
        final end = DateTime.parse(dates.last);
        final have = dates.toSet();
        while (t.isBefore(end)) {
          final ds =
              '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
          if (t.weekday <= 5 && !have.contains(ds) && ds.compareTo(from) >= 0) {
            out.putIfAbsent(ds, () => DaySnapshot(date: ds, trading: false, bars: const {}));
          }
          t = t.add(const Duration(days: 1));
        }
      }
      continue;
    }
    for (final c in (j['closed'] as List? ?? const [])) {
      final ds = c as String;
      if (ds.compareTo(from) >= 0) out.putIfAbsent(ds, () => DaySnapshot(date: ds, trading: false, bars: const {}));
    }
    for (final day in (j['days'] as List? ?? const [])) {
      final s = DaySnapshot.fromJson(day as Map<String, dynamic>);
      if (s.date.compareTo(from) >= 0) out[s.date] = s;
    }
  }
  return out.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}
