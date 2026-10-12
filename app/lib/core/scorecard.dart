/// 選股名單成績單：倒回過去每一個月，用「當時」看得到的資料選出的名單，
/// 抱 3 個月、6 個月以後，有沒有贏大盤（加權報酬指數，含息）。
///
/// 只看選股部分（不含大盤核心）。每次名單的每一檔放一樣多錢，檢視日隔天收盤買進，
/// 含配息、不扣成本；每月一次、抱好幾個月，所以前後期間會重疊，次數不是互相獨立的。
library;

import 'factors.dart';
import 'lt_data.dart';
import 'portfolio.dart';

/// 某一次檢視日選出的名單、抱 [days] 個交易日的結果。
class CohortRow {
  final String date;
  final List<String> codes;

  /// 名單平均報酬、同期大盤、同期全部可投資股票平均。
  final double ret, bench, avgStock;

  /// 名單裡贏大盤的檔數。
  final int stockWins;

  /// 實際抱了幾個交易日（還沒滿的那幾次比較少）。
  final int days;
  const CohortRow(this.date, this.codes, this.ret, this.bench, this.avgStock, this.stockWins, this.days);
  bool get beat => ret > bench;
  double get excess => ret - bench;
}

class YearScore {
  final String year;
  final int n, wins;
  final double ret, bench;
  const YearScore(this.year, this.n, this.wins, this.ret, this.bench);
  double get winRate => n == 0 ? 0 : wins / n;
}

/// 抱某個長度的整體成績。
class HorizonScore {
  final int days;
  final String label;
  final List<CohortRow> rows;
  const HorizonScore(this.days, this.label, this.rows);

  int get n => rows.length;
  double _rate(Iterable<CohortRow> l) {
    final x = l.toList();
    return x.isEmpty ? double.nan : x.where((r) => r.beat).length / x.length;
  }

  double _avg(Iterable<double> l) {
    final x = l.toList();
    return x.isEmpty ? double.nan : x.reduce((a, b) => a + b) / x.length;
  }

  double get winRate => _rate(rows);
  double get avgExcess => _avg(rows.map((r) => r.excess));
  double get medianExcess {
    if (rows.isEmpty) return double.nan;
    final s = rows.map((r) => r.excess).toList()..sort();
    return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
  }

  double get avgRet => _avg(rows.map((r) => r.ret));
  double get avgBench => _avg(rows.map((r) => r.bench));
  Iterable<CohortRow> get upRows => rows.where((r) => r.bench > 0);
  Iterable<CohortRow> get downRows => rows.where((r) => r.bench <= 0);
  double get upWin => _rate(upRows);
  double get downWin => _rate(downRows);

  /// 贏「平均一檔股票」的比例和平均多賺。
  double get vsAvgWin => rows.isEmpty ? double.nan : rows.where((r) => r.ret > r.avgStock).length / rows.length;
  double get vsAvgExcess => _avg(rows.map((r) => r.ret - r.avgStock));

  /// 名單裡單一檔贏大盤的比例。
  double get stockWinRate {
    final n = rows.fold(0, (a, r) => a + r.codes.length);
    return n == 0 ? double.nan : rows.fold(0, (a, r) => a + r.stockWins) / n;
  }

  /// 最近 [k] 次（例如一年）的勝率。
  double recentWinRate(int k) => _rate(rows.skip(rows.length > k ? rows.length - k : 0));

  List<YearScore> get years {
    final by = <String, List<CohortRow>>{};
    for (final r in rows) {
      (by[r.date.substring(0, 4)] ??= []).add(r);
    }
    return [
      for (final e in by.entries)
        YearScore(
          e.key,
          e.value.length,
          e.value.where((r) => r.beat).length,
          _avg(e.value.map((r) => r.ret)),
          _avg(e.value.map((r) => r.bench)),
        ),
    ];
  }
}

class Scorecard {
  final int size;
  final List<HorizonScore> horizons;

  /// 最近幾次還沒抱滿 3 個月的名單，到目前為止的表現。
  final List<CohortRow> inProgress;
  const Scorecard(this.size, this.horizons, this.inProgress);
  HorizonScore? of(int days) => horizons.where((h) => h.days == days).firstOrNull;
}

/// 每個檢視日都假設「手上什麼都沒有」，照規則重新選一次名單（跟「理想組合」第一次建立時一樣）。
Scorecard buildScorecard(
  LtData data,
  ScoreBook book,
  PortfolioSim sim, {
  List<(int, String)> horizons = const [(63, '3 個月'), (126, '6 個月')],
}) {
  final rows = <int, List<CohortRow>>{for (final h in horizons) h.$1: []};
  final inProgress = <CohortRow>[];
  final s0 = sim.startSample;
  if (s0 < 0 || !data.hasTri) return Scorecard(sim.cfg.size, const [], const []);
  final shortest = horizons.map((h) => h.$1).reduce((a, b) => a < b ? a : b);
  final last = data.nd - 1;
  for (var s = s0; s < data.samples.length; s++) {
    final sm = data.samples[s];
    if (sm.live) continue;
    final e = sm.t + 1;
    if (e > last) continue;
    final view = BookView(book, data, s);
    final picks = [for (final b in sim.decide(view, entryT: const {}).buys) b.$1];
    if (picks.isEmpty) continue;
    final all = view.investable.toList();
    CohortRow? at(int x) {
      final b0 = data.tri[e], b1 = data.tri[x];
      if (b0.isNaN || b1.isNaN || b0 <= 0) return null;
      final bench = b1 / b0 - 1;
      double r(int si) {
        final st = data.stocks[si];
        final a = st.trAt(e), z = st.trAt(x);
        return (a.isNaN || z.isNaN || a <= 0) ? double.nan : z / a - 1;
      }

      final pr = [for (final si in picks) r(si)].where((v) => !v.isNaN).toList();
      if (pr.isEmpty) return null;
      final ar = [for (final si in all) r(si)].where((v) => !v.isNaN).toList();
      return CohortRow(
        sm.date,
        [for (final si in picks) data.stocks[si].code],
        pr.reduce((a, b) => a + b) / pr.length,
        bench,
        ar.isEmpty ? double.nan : ar.reduce((a, b) => a + b) / ar.length,
        pr.where((v) => v > bench).length,
        x - e,
      );
    }

    for (final (h, _) in horizons) {
      if (e + h > last) continue;
      final row = at(e + h);
      if (row != null) rows[h]!.add(row);
    }
    if (e + shortest > last && e < last) {
      final row = at(last);
      if (row != null) inProgress.add(row);
    }
  }
  return Scorecard(sim.cfg.size, [for (final (h, label) in horizons) HorizonScore(h, label, rows[h]!)], inProgress);
}
