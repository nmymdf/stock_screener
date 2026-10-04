/// 因子研究：每一類因子分數高的股票，之後是不是真的表現比較好？
///
/// 每個月檢視日把可投資的股票依分數分成五組（第 1 組最高），看隔天起 3 個月（63 個交易日）
/// 含息報酬比全部可投資股票平均多多少；資訊係數（IC）是分數排名和之後報酬排名的相關係數，
/// 正的越多越穩定代表這個因子有用。用的都是當時看得到的資料。
library;

import 'dart:math' as math;

import 'factors.dart';
import 'lt_analysis.dart';
import 'lt_data.dart';
import 'portfolio.dart';

class FactorStat {
  final String name;
  final List<double> quintiles; // 第 1～5 組平均超額報酬（每期）
  final double ic, icT, icHit;
  final int periods;
  const FactorStat(this.name, this.quintiles, this.ic, this.icT, this.icHit, this.periods);
  double get spread => quintiles.first - quintiles.last;
}

class FactorResearch {
  final int horizon;
  final String from, to;
  final int periods;
  final List<FactorStat> rows;

  /// 總分前 10% 的股票：之後 [horizon] 天賺錢的比例、贏過可投資股票平均的比例。
  final double topWin, topBeat;
  final double avgUniverse;

  const FactorResearch({
    required this.horizon,
    required this.from,
    required this.to,
    required this.periods,
    required this.rows,
    required this.topWin,
    required this.topBeat,
    required this.avgUniverse,
  });

  static const empty = FactorResearch(
    horizon: 63,
    from: '',
    to: '',
    periods: 0,
    rows: [],
    topWin: 0,
    topBeat: 0,
    avgUniverse: 0,
  );
}

double _spearman(List<double> x, List<double> y) {
  final n = x.length;
  if (n < 10) return double.nan;
  List<double> ranks(List<double> v) {
    final idx = List<int>.generate(n, (i) => i)..sort((a, b) => v[a].compareTo(v[b]));
    final r = List<double>.filled(n, 0);
    var i = 0;
    while (i < n) {
      var j = i;
      while (j + 1 < n && v[idx[j + 1]] == v[idx[i]]) {
        j++;
      }
      for (var k = i; k <= j; k++) {
        r[idx[k]] = (i + j) / 2;
      }
      i = j + 1;
    }
    return r;
  }

  final rx = ranks(x), ry = ranks(y);
  final mx = rx.reduce((a, b) => a + b) / n, my = ry.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (rx[i] - mx) * (ry[i] - my);
    sxx += (rx[i] - mx) * (rx[i] - mx);
    syy += (ry[i] - my) * (ry[i] - my);
  }
  return sxx == 0 || syy == 0 ? double.nan : sxy / math.sqrt(sxx * syy);
}

FactorResearch factorResearch(LtData data, ScoreBook book, {int horizon = 63, String from = '2014-01-01'}) {
  final names = ['總分', for (final g in FactorGroup.values) g.label];
  final qSum = List.generate(names.length, (_) => List<double>.filled(5, 0));
  final qCnt = List.generate(names.length, (_) => List<int>.filled(5, 0));
  final ics = List.generate(names.length, (_) => <double>[]);
  var topN = 0, topWin = 0, topBeat = 0, periods = 0;
  var uniSum = 0.0;
  String? first, last;
  for (var s = 0; s < data.samples.length; s++) {
    final sm = data.samples[s];
    if (sm.live || sm.date.compareTo(from) < 0) continue;
    final t0 = sm.t + 1, t1 = sm.t + 1 + horizon;
    if (t1 >= data.nd) break;
    final si = <int>[];
    final fwd = <double>[];
    for (final k in book.order[s]) {
      final j = book.at(s, k);
      if (book.flags[j] & (1 << LtFlag.illiquid.index) != 0) continue;
      final st = data.stocks[k];
      final a = st.trAt(t0), b = st.trAt(t1);
      if (a.isNaN || b.isNaN || a <= 0) continue;
      si.add(k);
      fwd.add(b / a - 1);
    }
    if (si.length < 50) continue;
    periods++;
    first ??= sm.date;
    last = sm.date;
    final mean = fwd.reduce((a, b) => a + b) / fwd.length;
    uniSum += mean;
    for (var f = 0; f < names.length; f++) {
      final xs = <double>[], ys = <double>[];
      for (var i = 0; i < si.length; i++) {
        final j = book.at(s, si[i]);
        final v = f == 0 ? book.composite[j] : book.groups[j * 6 + f - 1];
        if (v.isNaN) continue;
        xs.add(v);
        ys.add(fwd[i]);
      }
      if (xs.length < 50) continue;
      final ic = _spearman(xs, ys);
      if (!ic.isNaN) ics[f].add(ic);
      final idx = List<int>.generate(xs.length, (i) => i)..sort((a, b) => xs[b].compareTo(xs[a]));
      for (var r = 0; r < idx.length; r++) {
        final q = math.min(4, r * 5 ~/ idx.length);
        qSum[f][q] += ys[idx[r]] - mean;
        qCnt[f][q]++;
      }
      if (f == 0) {
        final top = (idx.length * 0.1).ceil();
        for (var r = 0; r < top; r++) {
          topN++;
          if (ys[idx[r]] > 0) topWin++;
          if (ys[idx[r]] > mean) topBeat++;
        }
      }
    }
  }
  final overlap = math.sqrt(math.max(1, horizon / 21));
  final rows = <FactorStat>[];
  for (var f = 0; f < names.length; f++) {
    final l = ics[f];
    if (l.isEmpty) continue;
    final m = l.reduce((a, b) => a + b) / l.length;
    final sd = math.sqrt(l.fold(0.0, (a, x) => a + (x - m) * (x - m)) / math.max(1, l.length - 1));
    rows.add(
      FactorStat(
        names[f],
        [for (var q = 0; q < 5; q++) qCnt[f][q] == 0 ? 0 : qSum[f][q] / qCnt[f][q]],
        m,
        sd == 0 ? 0 : m / sd * math.sqrt(l.length) / overlap,
        l.where((x) => x > 0).length / l.length,
        l.length,
      ),
    );
  }
  return FactorResearch(
    horizon: horizon,
    from: first ?? '',
    to: last ?? '',
    periods: periods,
    rows: rows,
    topWin: topN == 0 ? 0 : topWin / topN,
    topBeat: topN == 0 ? 0 : topBeat / topN,
    avgUniverse: periods == 0 ? 0 : uniSum / periods,
  );
}

String _p(double x, [int d = 1]) => x.isNaN ? '—' : '${x >= 0 ? '+' : ''}${(x * 100).toStringAsFixed(d)}%';

/// GitHub Actions 上用資料包跑一次完整分析，印成文字報告。
String runPackResearch(String dir) {
  final sw = Stopwatch()..start();
  final data = loadPackDir(dir);
  final sb = StringBuffer();
  sb.writeln(
    '資料：${data.dates.firstOrNull}～${data.lastDate}，${data.nd} 個交易日、${data.stocks.length} 檔上市普通股、'
    '${data.samples.length} 個檢視日（讀取 ${sw.elapsedMilliseconds} ms）',
  );
  sb.writeln(
    '報酬指數：${data.hasTri ? '有' : '沒有（改用加權指數，會低估基準）'}；營收 ${data.revenue.cur.length} 家、最新 ${data.revenue.lastMonth}；'
    '除權息 ${data.dividends.byCode.length} 家；國際指標 ${data.intl.series.keys.join('、')}',
  );
  final r = runLtAnalysis(data);
  sb.writeln('分析耗時 ${r.elapsed.inMilliseconds} ms');
  // 各年資料涵蓋率
  sb.writeln('\n── 各年評分涵蓋（平均每個檢視日）──');
  final byYear = <String, List<int>>{};
  for (var s = 0; s < data.samples.length; s++) {
    final y = data.samples[s].date.substring(0, 4);
    final l = byYear[y] ??= List<int>.filled(8, 0);
    l[0]++;
    l[1] += r.book.count(s);
    for (final si in r.book.order[s]) {
      final j = r.book.at(s, si);
      for (final g in FactorGroup.values) {
        if (!r.book.groups[j * 6 + g.index].isNaN) l[2 + g.index]++;
      }
    }
  }
  for (final e in byYear.entries) {
    final l = e.value;
    final n = l[1] == 0 ? 1 : l[1];
    sb.writeln(
      '${e.key}：${(l[1] / l[0]).round()} 檔　'
      '${[for (final g in FactorGroup.values) '${g.label} ${(l[2 + g.index] / n * 100).round()}%'].join('　')}',
    );
  }
  void stats(String label, PerfStats s) {
    sb.writeln('\n── $label（${s.from}～${s.to}，${s.years.toStringAsFixed(1)} 年）──');
    sb.writeln('年化報酬 ${_p(s.cagr)}　報酬指數 ${_p(s.benchCagr)}　超額 ${_p(s.excessCagr)}　等權全市場 ${_p(s.eqwCagr)}');
    sb.writeln(
      '最大跌幅 ${_p(-s.mdd)}（指數 ${_p(-s.benchMdd)}）　波動 ${_p(s.vol)}　夏普 ${s.sharpe.toStringAsFixed(2)}　平均股票部位 ${(s.avgExposure * 100).round()}%',
    );
    sb.writeln(
      '每月贏指數 ${(s.monthlyWin * 100).round()}%　每年贏指數 ${(s.yearlyWin * 100).round()}%　'
      '每筆持股賺錢 ${(s.posWin * 100).round()}%、贏指數 ${(s.posBeat * 100).round()}%（${s.positions} 筆，平均抱 ${(s.avgHoldDays / 21).toStringAsFixed(1)} 個月）',
    );
    sb.writeln('年週轉率 ${(s.turnover * 100).round()}%　前半段超額 ${_p(s.firstHalfExcess)}　後半段超額 ${_p(s.secondHalfExcess)}');
  }

  for (final v in r.variants) {
    stats(v.label, v.stats);
  }
  final s = r.sim.stats;
  sb.writeln('\n── 逐年（目前設定）──');
  for (final y in s.yearRows) {
    sb.writeln('${y.year}：組合 ${_p(y.ret)}　指數 ${_p(y.bench)}　${y.beat ? '贏' : '輸'}');
  }
  sb.writeln('\n── 壓力期間 ──');
  for (final x in s.stress) {
    sb.writeln('${x.label}（${x.from}～${x.to}）：組合 ${_p(x.ret)}　指數 ${_p(x.bench)}');
  }
  for (final fr in [r.research, factorResearch(data, r.book, horizon: 126)]) {
    sb.writeln('\n── 因子研究：之後 ${fr.horizon} 個交易日（${fr.from}～${fr.to}，${fr.periods} 期）──');
    sb.writeln(
      '總分前 10%：之後賺錢 ${(fr.topWin * 100).round()}%、贏過可投資股票平均 ${(fr.topBeat * 100).round()}%；全體平均每期 ${_p(fr.avgUniverse)}',
    );
    for (final x in fr.rows) {
      sb.writeln(
        '${x.name.padRight(4, '　')}：五組超額 ${x.quintiles.map((q) => _p(q)).join(' / ')}　'
        '一減五 ${_p(x.spread)}　IC ${x.ic.toStringAsFixed(3)}（t=${x.icT.toStringAsFixed(1)}，正的 ${(x.icHit * 100).round()}%）',
      );
    }
  }
  sb.writeln('\n── 最新（${r.date}）──');
  sb.writeln('市場：${r.exposure.label}；${r.exposure.reasons.join('；')}');
  for (final x in r.exposure.intl) {
    sb.writeln('  ${x.risk ? '⚠' : '・'} ${x.note}');
  }
  sb.writeln('理想組合（目前持有 ${r.sim.holdings.length} 檔，現金 ${(r.sim.cashWeight * 100).toStringAsFixed(0)}%）：');
  final hold = r.sim.holdings.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
  for (final e in hold) {
    final st = data.stocks[e.key];
    final sc = r.live.of(e.key);
    sb.writeln(
      '  ${st.code} ${st.name}　${(e.value.$1 * 100).toStringAsFixed(1)}%　買進 ${e.value.$2}　'
      '${sc == null ? '' : '總分第 ${sc.rank} 名 ${sc.flags.map((f) => f.label).join(' ')}'}',
    );
  }
  final d = r.sim.pending ?? r.preview;
  if (d != null) {
    sb.writeln(
      '${r.sim.pending != null ? '本月調整（明天收盤執行）' : '如果今天檢視'}：'
      '賣 ${d.sells.entries.map((e) => '${data.stocks[e.key].code}（${e.value}）').join('、')}　'
      '買 ${d.buys.map((b) => data.stocks[b.$1].code).join('、')}',
    );
  }
  sb.writeln('總分前 15：');
  for (final x in r.live.ranked.take(15)) {
    sb.writeln(
      '  ${x.rank}. ${x.code} ${data.stocks[x.si].name}　${x.composite.toStringAsFixed(1)}　'
      '${[for (final g in FactorGroup.values) '${g.label.substring(0, 2)}${x.groups[g]?.round() ?? '—'}'].join(' ')}　'
      '${x.flags.map((f) => f.label).join(' ')}',
    );
  }
  sb.writeln('\n總耗時 ${sw.elapsedMilliseconds} ms');
  return sb.toString();
}
