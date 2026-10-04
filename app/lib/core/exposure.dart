/// 市場曝險：建議股票部位佔資金的比例（100%／75%／50%）。
///
/// 只在每月檢視日調整、看的是年線這種慢指標，不會因為某一天大跌就叫你賣。
/// - 台股本身：加權指數在不在年線（200 日均）上、年線方向、站上年線的股票比例（廣度）。
/// - 國際（可選）：費城半導體、Nasdaq、VIX 恐慌指數、美元兌台幣、美國 10 年期公債殖利率。
///   美國收盤在台灣隔天開盤之前，所以台股某一天只用「前一天以前」的國際資料。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'lt_data.dart';

enum ExposureMode { none, local, localIntl }

extension ExposureModeInfo on ExposureMode {
  String get label => switch (this) {
    ExposureMode.none => '一直滿倉',
    ExposureMode.local => '看台股環境調整',
    ExposureMode.localIntl => '看台股＋國際環境調整',
  };
}

class IntlReading {
  final String key, label;
  final double? value;
  final bool risk;
  final String note;
  const IntlReading(this.key, this.label, this.value, this.risk, this.note);
}

class ExposureState {
  final String date;

  /// 建議的股票比例（依選的模式）。
  final double level;
  final double localLevel, intlLevel;
  final double taiexDist; // 加權指數 / 年線 − 1
  final bool taiexSlopeUp;
  final double breadth;
  final int localScore;
  final int intlRisk;
  final List<IntlReading> intl;

  const ExposureState({
    required this.date,
    required this.level,
    required this.localLevel,
    required this.intlLevel,
    required this.taiexDist,
    required this.taiexSlopeUp,
    required this.breadth,
    required this.localScore,
    required this.intlRisk,
    required this.intl,
  });

  static String levelLabel(double level) =>
      level >= 0.999 ? '積極（股票 100%）' : (level >= 0.749 ? '中性（股票 75%）' : '保守（股票 50%）');

  String get label => levelLabel(level);

  /// 白話說明。
  List<String> get reasons => [
    if (!taiexDist.isNaN)
      '加權指數${taiexDist >= 0 ? '在年線之上' : '跌破年線'}（${taiexDist >= 0 ? '+' : ''}${(taiexDist * 100).toStringAsFixed(1)}%），年線${taiexSlopeUp ? '往上' : '往下'}',
    if (!breadth.isNaN)
      '站上年線的股票 ${(breadth * 100).toStringAsFixed(0)}%${breadth >= 0.5 ? '，多數股票健康' : (breadth < 0.3 ? '，多數股票轉弱' : '')}',
    if (intl.isNotEmpty) '國際風險訊號 $intlRisk／${intl.length} 項${intlRisk >= 3 ? '，偏高' : ''}',
  ];
}

class ExposureEngine {
  final LtData data;
  final Float64List _sma;
  final Map<String, (List<String>, Float64List)> _intl = {};

  ExposureEngine(this.data) : _sma = _taiexSma(data.taiex) {
    for (final e in data.intl.series.entries) {
      final s = e.value;
      final usable = [for (final d in s.dates) _addDays(d, s.lagDays)];
      _intl[e.key] = (usable, Float64List.fromList(s.values));
    }
  }

  static Float64List _taiexSma(Float64List ix) {
    final n = ix.length;
    final out = Float64List(n)..fillRange(0, n, double.nan);
    var sum = 0.0, cnt = 0;
    final cf = Float64List(n);
    var last = double.nan;
    for (var k = 0; k < n; k++) {
      if (!ix[k].isNaN) last = ix[k];
      cf[k] = last;
    }
    for (var k = 0; k < n; k++) {
      if (!cf[k].isNaN) {
        sum += cf[k];
        cnt++;
      }
      if (k >= 200 && !cf[k - 200].isNaN) {
        sum -= cf[k - 200];
        cnt--;
      }
      if (cnt >= 200) out[k] = sum / cnt;
    }
    return out;
  }

  static String _addDays(String d, int n) {
    final t = DateTime.utc(
      int.parse(d.substring(0, 4)),
      int.parse(d.substring(5, 7)),
      int.parse(d.substring(8, 10)),
    ).add(Duration(days: n));
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  /// 台股第 [date] 天可以用的最後一筆國際資料位置（-1 = 沒有）。
  int _idx(List<String> usable, String date) {
    var lo = 0, hi = usable.length - 1, ans = -1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (usable[m].compareTo(date) <= 0) {
        ans = m;
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    return ans;
  }

  static double _avg(Float64List v, int from, int to) {
    var s = 0.0;
    for (var k = from; k <= to; k++) {
      s += v[k];
    }
    return s / (to - from + 1);
  }

  List<IntlReading> intlAt(String date) {
    final out = <IntlReading>[];
    for (final key in const ['SOX', 'NASDAQ', 'VIX', 'USDTWD', 'US10Y']) {
      final s = _intl[key];
      if (s == null) continue;
      final (usable, v) = s;
      final k = _idx(usable, date);
      if (k < 220) continue;
      switch (key) {
        case 'SOX':
        case 'NASDAQ':
          final sma = _avg(v, k - 199, k), smaLag = _avg(v, k - 219, k - 20);
          final below = v[k] < sma;
          final risk = key == 'SOX' ? below && sma < smaLag : below;
          final name = key == 'SOX' ? '費城半導體' : 'Nasdaq';
          out.add(
            IntlReading(
              key,
              name,
              v[k],
              risk,
              '$name ${below ? '在 200 日線之下' : '在 200 日線之上'}（${((v[k] / sma - 1) * 100).toStringAsFixed(1)}%）'
              '${key == 'SOX' ? '，200 日線${sma >= smaLag ? '往上' : '往下'}' : ''}',
            ),
          );
        case 'VIX':
          final a = _avg(v, k - 9, k);
          out.add(
            IntlReading(
              key,
              'VIX 恐慌指數',
              v[k],
              a > 25,
              'VIX 近 10 日平均 ${a.toStringAsFixed(1)}${a > 25 ? '（高於 25，市場緊張）' : ''}',
            ),
          );
        case 'USDTWD':
          final c = v[k] / v[k - 60] - 1;
          out.add(
            IntlReading(
              key,
              '美元兌台幣',
              v[k],
              c > 0.03,
              '台幣近 3 個月${c > 0 ? '貶值' : '升值'} ${(c.abs() * 100).toStringAsFixed(1)}%${c > 0.03 ? '（外資可能撤出）' : ''}',
            ),
          );
        case 'US10Y':
          final c = v[k] - v[k - 120];
          out.add(
            IntlReading(
              key,
              '美國 10 年期公債殖利率',
              v[k],
              c > 0.75,
              '殖利率 ${v[k].toStringAsFixed(2)}%，半年${c >= 0 ? '上升' : '下降'} ${c.abs().toStringAsFixed(2)} 個百分點${c > 0.75 ? '（利率快速上升，壓抑股價）' : ''}',
            ),
          );
      }
    }
    return out;
  }

  ExposureState at(int t, double breadth, {ExposureMode mode = ExposureMode.local}) {
    final date = data.dates[t];
    final ix = data.taiex[t], sma = _sma[t];
    final smaLag = t >= 20 ? _sma[t - 20] : double.nan;
    final dist = ix.isNaN || sma.isNaN ? double.nan : ix / sma - 1;
    final slopeUp = !sma.isNaN && !smaLag.isNaN && sma > smaLag;
    var score = 0;
    if (!dist.isNaN && dist > 0) score++;
    if (slopeUp) score++;
    if (!breadth.isNaN && breadth >= 0.5) score++;
    if (!breadth.isNaN && breadth < 0.3) score--;
    final local = dist.isNaN ? 1.0 : (score >= 2 ? 1.0 : (score == 1 ? 0.75 : 0.5));
    final intl = intlAt(date);
    final risk = intl.where((x) => x.risk).length;
    var withIntl = local;
    if (risk >= 3) withIntl = math.max(0.5, local - 0.25);
    if (risk >= 4 && score <= 1) withIntl = 0.5;
    final level = switch (mode) {
      ExposureMode.none => 1.0,
      ExposureMode.local => local,
      ExposureMode.localIntl => withIntl,
    };
    return ExposureState(
      date: date,
      level: level,
      localLevel: local,
      intlLevel: withIntl,
      taiexDist: dist,
      taiexSlopeUp: slopeUp,
      breadth: breadth,
      localScore: score,
      intlRisk: risk,
      intl: intl,
    );
  }
}
