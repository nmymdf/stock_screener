/// 存檔的實際讀寫：JSON 檔案，放在系統的「應用程式資料」資料夾。
/// Windows、Linux、Android 都用同一套 `path_provider` API，不用分平台寫。
///
/// - 設定（篩選條件、歷史天數）存在 [settingsFileName]。
/// - 持股紀錄存在 `stock_screener_holdings.json`。
/// - 每日收盤行情一天一個檔案，放在 `history/yyyy-MM-dd.json`，已經抓過的
///   交易日不會再抓第二次（過去的收盤行情不會變）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalStore {
  static const settingsFileName = 'stock_screener_settings.json';
  static const historyDirName = 'history';

  /// 測試時可以指定一個暫存資料夾，不經過 path_provider。
  final Directory? _override;
  LocalStore({Directory? dir}) : _override = dir;

  Future<Directory> _dir() async {
    final dir = _override ?? await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _historyDir() async {
    final d = Directory('${(await _dir()).path}/$historyDirName');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 資料實際存放的資料夾路徑，給「資料」頁顯示，方便使用者自己去核對。
  Future<String> dirPath() async => (await _dir()).path;

  Future<Map<String, dynamic>?> readSettings() async {
    final f = File('${(await _dir()).path}/$settingsFileName');
    return _readJson(f);
  }

  Future<void> writeSettings(Map<String, dynamic> json) async {
    final f = File('${(await _dir()).path}/$settingsFileName');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// 讀出所有存過的交易日資料（每個檔案一天）。壞掉的檔案直接跳過，
  /// 之後同步時會當作缺資料重新抓。
  Future<List<Map<String, dynamic>>> readAllDays() async {
    final dir = await _historyDir();
    final out = <Map<String, dynamic>>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final j = await _readJson(e);
        if (j != null) out.add(j);
      } catch (_) {
        // 檔案寫到一半被中斷之類的，忽略
      }
    }
    return out;
  }

  Future<void> writeDay(String date, Map<String, dynamic> json) async {
    final dir = await _historyDir();
    // 先寫暫存檔再改名，避免寫到一半被關掉留下壞檔。
    final tmp = File('${dir.path}/$date.json.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename('${dir.path}/$date.json');
  }

  Future<void> deleteDay(String date) async {
    final f = File('${(await _historyDir()).path}/$date.json');
    if (await f.exists()) await f.delete();
  }

  /// 一般的 JSON 檔（例如持股紀錄），放在資料夾最上層。
  Future<Map<String, dynamic>?> readNamed(String fileName) async => _readJson(File('${(await _dir()).path}/$fileName'));

  Future<void> writeNamed(String fileName, Map<String, dynamic> json) async {
    final dir = await _dir();
    final tmp = File('${dir.path}/$fileName.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    await tmp.rename('${dir.path}/$fileName');
  }

  Future<Map<String, dynamic>?> _readJson(File f) async {
    if (!await f.exists()) return null;
    final text = await f.readAsString();
    if (text.trim().isEmpty) return null;
    return jsonDecode(text) as Map<String, dynamic>;
  }
}
