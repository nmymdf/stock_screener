/// 產業強弱與輪動引擎（規格書 §3）：同一家公司在強勢產業和弱勢產業裡的
/// 成功機率不同，所以先看產業、再挑個股。
///
/// 每個產業用成員股的中位數報酬、站上均線比例、創新高比例、成交值變化，
/// 跟其他產業比排名，得到 Industry Score 0～100；再跟 10 個交易日前的分數比，
/// 分成「領先、改善、同步、轉弱、落後」五類。
library;

import '../ta.dart';

/// 一檔股票在某一天、給產業引擎用的指標。
class IndustryInput {
  final double roc20, roc60, roc120;
  final bool above20, above60, newHigh60;
  final double value5, value20;
  const IndustryInput(
    this.roc20,
    this.roc60,
    this.roc120,
    this.above20,
    this.above60,
    this.newHigh60,
    this.value5,
    this.value20,
  );

  static IndustryInput? at(StockSeries s, int i) {
    if (i < 61 || !ok(s.sma20[i]) || !ok(s.sma60[i])) return null;
    return IndustryInput(
      s.roc(i, 20),
      s.roc(i, 60),
      s.roc(i, 120),
      s.close[i] > s.sma20[i],
      s.close[i] > s.sma60[i],
      s.close[i] > maxIn(s.close, i - 60, i - 1),
      avgIn(s.value, i - 4, i),
      avgIn(s.value, i - 19, i),
    );
  }
}

enum IndustryClass { leading, improving, neutral, weakening, lagging }

extension IndustryClassInfo on IndustryClass {
  String get label => switch (this) {
    IndustryClass.leading => '領先',
    IndustryClass.improving => '改善',
    IndustryClass.neutral => '同步',
    IndustryClass.weakening => '轉弱',
    IndustryClass.lagging => '落後',
  };

  String get explain => switch (this) {
    IndustryClass.leading => '產業分數 70 以上，資金正在這裡，優先考慮。',
    IndustryClass.improving => '分數比 10 天前明顯上升，資金開始流入。',
    IndustryClass.neutral => '跟大盤差不多，沒有特別強或弱。',
    IndustryClass.weakening => '分數比 10 天前明顯下降，資金在流出，要小心。',
    IndustryClass.lagging => '分數低於 40，相對弱勢，原則上避開。',
  };
}

class IndustryReport {
  final String name;
  final int members;
  final double score;
  final double? prevScore;
  final IndustryClass cls;
  final double medRoc20, medRoc60, medRoc120;
  final double excess20; // 相對全市場中位數的超額報酬
  final double pctAbove20, pctAbove60, pctNewHigh60;
  final double valueChange; // 近 5 日均成交值 ÷ 20 日均成交值
  final List<String> codes;
  final List<String> leaders; // 60 日漲幅前 3 名

  const IndustryReport({
    required this.name,
    required this.members,
    required this.score,
    required this.prevScore,
    required this.cls,
    required this.medRoc20,
    required this.medRoc60,
    required this.medRoc120,
    required this.excess20,
    required this.pctAbove20,
    required this.pctAbove60,
    required this.pctNewHigh60,
    required this.valueChange,
    required this.codes,
    required this.leaders,
  });

  double? get delta => prevScore == null ? null : score - prevScore!;
}

double _median(List<double> v) {
  final x = v.where(ok).toList()..sort();
  if (x.isEmpty) return double.nan;
  final m = x.length ~/ 2;
  return x.length.isOdd ? x[m] : (x[m - 1] + x[m]) / 2;
}

class _Agg {
  final String name;
  final List<String> codes = [];
  final List<IndustryInput> inputs = [];
  _Agg(this.name);

  Map<String, double> metrics() {
    final n = inputs.length;
    double frac(bool Function(IndustryInput) f) => inputs.where(f).length / n;
    var v5 = 0.0, v20 = 0.0;
    for (final x in inputs) {
      v5 += x.value5;
      v20 += x.value20;
    }
    return {
      'roc20': _median([for (final x in inputs) x.roc20]),
      'roc60': _median([for (final x in inputs) x.roc60]),
      'roc120': _median([for (final x in inputs) x.roc120]),
      'above20': frac((x) => x.above20),
      'above60': frac((x) => x.above60),
      'newHigh': frac((x) => x.newHigh60),
      'value': v20 == 0 ? 1 : v5 / v20,
    };
  }
}

const _weights = {
  'roc20': 25.0,
  'roc60': 20.0,
  'roc120': 10.0,
  'above20': 15.0,
  'above60': 15.0,
  'newHigh': 10.0,
  'value': 5.0,
};

/// 對每個產業的每個指標做「在所有產業中的百分位」，再加權成 0～100。
Map<String, double> _scores(Map<String, Map<String, double>> m) {
  final names = m.keys.toList();
  final out = {for (final n in names) n: 0.0};
  final wsum = {for (final n in names) n: 0.0};
  for (final e in _weights.entries) {
    final vals = [for (final n in names) (n, m[n]![e.key]!)].where((x) => ok(x.$2)).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    if (vals.length < 2) continue;
    for (var k = 0; k < vals.length; k++) {
      out[vals[k].$1] = out[vals[k].$1]! + e.value * k / (vals.length - 1);
      wsum[vals[k].$1] = wsum[vals[k].$1]! + e.value;
    }
  }
  return {for (final n in names) n: wsum[n]! == 0 ? 50 : out[n]! / wsum[n]! * 100};
}

/// [now]／[prev]：代號 → (產業, 今天／10 天前的指標)。
List<IndustryReport> buildIndustries(
  Map<String, (String, IndustryInput)> now,
  Map<String, (String, IndustryInput)> prev,
  double marketMedRoc20,
) {
  Map<String, _Agg> group(Map<String, (String, IndustryInput)> src) {
    final g = <String, _Agg>{};
    for (final e in src.entries) {
      final a = g.putIfAbsent(e.value.$1, () => _Agg(e.value.$1));
      a.codes.add(e.key);
      a.inputs.add(e.value.$2);
    }
    g.removeWhere((_, a) => a.inputs.length < 3);
    return g;
  }

  final gNow = group(now), gPrev = group(prev);
  if (gNow.isEmpty) return const [];
  final mNow = {for (final e in gNow.entries) e.key: e.value.metrics()};
  final mPrev = {for (final e in gPrev.entries) e.key: e.value.metrics()};
  final sNow = _scores(mNow);
  final sPrev = mPrev.length >= 2 ? _scores(mPrev) : <String, double>{};

  final out = <IndustryReport>[];
  for (final e in gNow.entries) {
    final m = mNow[e.key]!;
    final score = sNow[e.key]!;
    final prevScore = sPrev[e.key];
    final delta = prevScore == null ? 0.0 : score - prevScore;
    final cls = score >= 70
        ? IndustryClass.leading
        : delta >= 10
        ? IndustryClass.improving
        : delta <= -10
        ? IndustryClass.weakening
        : score < 40
        ? IndustryClass.lagging
        : IndustryClass.neutral;
    final idx = List.generate(e.value.codes.length, (k) => k)
      ..sort(
        (a, b) => (e.value.inputs[b].roc60.isNaN ? -1e9 : e.value.inputs[b].roc60).compareTo(
          e.value.inputs[a].roc60.isNaN ? -1e9 : e.value.inputs[a].roc60,
        ),
      );
    out.add(
      IndustryReport(
        name: e.key,
        members: e.value.inputs.length,
        score: score,
        prevScore: prevScore,
        cls: cls,
        medRoc20: m['roc20']!,
        medRoc60: m['roc60']!,
        medRoc120: m['roc120']!,
        excess20: m['roc20']! - marketMedRoc20,
        pctAbove20: m['above20']!,
        pctAbove60: m['above60']!,
        pctNewHigh60: m['newHigh']!,
        valueChange: m['value']!,
        codes: e.value.codes,
        leaders: [for (final k in idx.take(3)) e.value.codes[k]],
      ),
    );
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}
