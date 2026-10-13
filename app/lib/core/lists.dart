/// 候選名單與持股健檢：規則事先定好，用 2014 年以來每個月的真實資料檢驗過。
///
/// 檢驗結果（扣成本，詳見回測頁）：
/// - 強勢成長（趨勢模板）：抱 3～6 個月在多頭年有用；抱一年大多輸 0050。
/// - 穩健存股：報酬比 0050 少，但抱一年賺錢的機率最高、最差的一次跌得最少。
/// - 剛轉強、相對便宜：兩段期間都輸平均股票，沒有放進 App。
/// - 持股健檢：之後 3～6 個月「趨勢正常」的股票明顯比「跌破年線」「理由破壞」的好；看一年就沒差。
library;

import 'dart:math' as math;

import '../data/stock_industry.dart' show industryOf;
import 'bluechip.dart' show capRanking, etfWeights;
import 'factors.dart';
import 'lt_data.dart';
import 'strategy.dart';

enum PickList { strong, income }

extension PickListInfo on PickList {
  String get label => switch (this) {
    PickList.strong => '強勢成長',
    PickList.income => '穩健存股',
  };

  String get oneLine => switch (this) {
    PickList.strong => '營收成長、股價多頭排列的強勢股；適合抱幾個月、跌破 50 日線就走',
    PickList.income => '大型、年年配息、殖利率 3% 以上、波動小；適合長期領股息、求穩',
  };
}

/// 同一個產業最多幾檔（避免整份名單押同一個題材）。
const kPerIndustry = 2;
const kListSize = 10;
const _cost = 0.002425 + 0.005425; // 買賣手續費＋證交稅＋滑價

bool _mine(LtScore x) =>
    x.flags.contains(LtFlag.loss) ||
    (x.flags.contains(LtFlag.downtrend) && x.flags.contains(LtFlag.revenueDrop)) ||
    x.flags.contains(LtFlag.yieldTrap) ||
    x.flags.contains(LtFlag.illiquid);

List<LtScore> _capIndustry(Iterable<LtScore> sorted) {
  final cnt = <String, int>{};
  final out = <LtScore>[];
  for (final x in sorted) {
    final ind = industryOf(x.code) ?? '其他';
    if ((cnt[ind] ?? 0) >= kPerIndustry) continue;
    cnt[ind] = (cnt[ind] ?? 0) + 1;
    out.add(x);
    if (out.length >= kListSize) break;
  }
  return out;
}

/// 強勢成長：趨勢模板（多頭排列、接近一年高點、一年漲幅前 30%、營收年增 20% 以上、每天成交 2 億以上、沒有地雷），
/// 一年漲幅由高到低，同產業最多 2 檔。
List<LtScore> strongList(LtData d, SampleScores sc) {
  final tp = trendPicks(d, sc, const StrategyConfig(picks: 999));
  return _capIndustry([
    for (final t in tp)
      if (sc.of(t.si) != null) sc.of(t.si)!,
  ]);
}

/// 穩健存股：市值前 100 大、近 5 年都配息、殖利率 3% 以上、波動低於這群股票的中位數、年線沒有下彎、沒有地雷；
/// 殖利率由高到低，同產業最多 2 檔。
List<LtScore> incomeList(LtData d, SampleScores sc, int sample) {
  final top = {for (final (si, _) in capRanking(d, sample).take(100)) si};
  final u = [
    for (final x in sc.ranked)
      if (top.contains(x.si) && x.investable && !_mine(x)) x,
  ];
  if (u.isEmpty) return const [];
  final vols = [for (final x in u) x.raw.vol].where((v) => !v.isNaN).toList()..sort();
  final vm = vols.isEmpty ? double.nan : vols[vols.length ~/ 2];
  final l = [
    for (final x in u)
      if (x.raw.divYears >= 5 && x.raw.yld >= 3 && x.raw.vol <= vm && !x.flags.contains(LtFlag.downtrend)) x,
  ]..sort((a, b) => b.raw.yld.compareTo(a.raw.yld));
  return _capIndustry(l);
}

List<LtScore> pickList(PickList k, LtData d, SampleScores sc, int sample) =>
    k == PickList.strong ? strongList(d, sc) : incomeList(d, sc, sample);

/// 某個持有期間、某段期間的成績。
class ListStat {
  final int months;
  final String period; // 全部期間／2014–2019／2020 以後
  final int n; // 幾次（每月一次）
  final double upRate; // 整份名單賺錢的比例
  final double avg; // 名單平均報酬（扣成本）
  final double etfAvg; // 同期 0050 平均
  final double beatEtf; // 名單贏 0050 的比例
  final double worst; // 最差的一次
  const ListStat(this.months, this.period, this.n, this.upRate, this.avg, this.etfAvg, this.beatEtf, this.worst);
}

class ListResult {
  final PickList kind;
  final List<LtScore> now; // 最新一天的名單
  final List<ListStat> stats;
  final String from, to;
  final double avgCount; // 平均每次幾檔
  const ListResult(this.kind, this.now, this.stats, this.from, this.to, this.avgCount);

  ListStat? stat(int months, String period) {
    for (final s in stats) {
      if (s.months == months && s.period == period) return s;
    }
    return null;
  }

  bool contains(int si) => now.any((x) => x.si == si);
}

const kStatPeriods = ['全部期間', '2014–2019', '2020 以後'];
const kStatMonths = [3, 6, 12];

/// 回測：每月檢視日的名單，隔天收盤買進、抱 3／6／12 個月（含息、扣成本），跟同期 0050（市值前 50 大）比。
ListResult listBacktest(
  PickList kind,
  LtData d,
  Map<int, List<int>> picksBySample,
  List<LtScore> now, {
  String from = '2014-01-01',
}) {
  final samples = [
    for (var s = 0; s < d.samples.length; s++)
      if (!d.samples[s].live && d.samples[s].date.compareTo(from) >= 0 && picksBySample.containsKey(s)) s,
  ];
  double fwd(int si, int a, int b) {
    final st = d.stocks[si];
    final x = st.trAt(a), y = st.trAt(math.min(b, d.nd - 1));
    return x.isNaN || y.isNaN || x <= 0 ? double.nan : y / x - 1;
  }

  final etfCache = <int, Map<int, double>>{};
  double etf(int s, int a, int b) {
    final w = etfCache[s] ??= etfWeights(capRanking(d, s), 50);
    var r = 0.0, tw = 0.0;
    w.forEach((si, wt) {
      final f = fwd(si, a, b);
      if (!f.isNaN) {
        r += wt * f;
        tw += wt;
      }
    });
    return tw == 0 ? double.nan : r / tw;
  }

  final stats = <ListStat>[];
  for (final m in kStatMonths) {
    final h = m == 12 ? 250 : m * 21;
    final rows = <(String, double, double)>[];
    for (final s in samples) {
      final a = d.samples[s].t + 1, b = a + h;
      if (b >= d.nd) break;
      final ps = picksBySample[s]!;
      if (ps.isEmpty) continue;
      final r = [for (final si in ps) fwd(si, a, b)].where((v) => !v.isNaN).toList();
      if (r.isEmpty) continue;
      rows.add((d.samples[s].date, r.reduce((x, y) => x + y) / r.length - _cost, etf(s, a, b)));
    }
    for (final p in kStatPeriods) {
      final l = rows.where((r) {
        if (p == '2014–2019') return r.$1.compareTo('2020') < 0;
        if (p == '2020 以後') return r.$1.compareTo('2020') >= 0;
        return true;
      }).toList();
      if (l.isEmpty) continue;
      double mean(Iterable<double> x) {
        final v = x.where((e) => !e.isNaN).toList();
        return v.isEmpty ? double.nan : v.reduce((a, b) => a + b) / v.length;
      }

      stats.add(
        ListStat(
          m,
          p,
          l.length,
          l.where((r) => r.$2 > 0).length / l.length,
          mean(l.map((r) => r.$2)),
          mean(l.map((r) => r.$3)),
          l.where((r) => r.$2 > r.$3).length / l.length,
          l.map((r) => r.$2).reduce(math.min),
        ),
      );
    }
  }
  final counts = [for (final s in samples) picksBySample[s]!.length];
  return ListResult(
    kind,
    now,
    stats,
    samples.isEmpty ? '' : d.samples[samples.first].date,
    samples.isEmpty ? '' : d.samples[samples.last].date,
    counts.isEmpty ? 0 : counts.reduce((a, b) => a + b) / counts.length,
  );
}

// ───────────────────────── 持股健檢 ─────────────────────────

enum Health { ok, belowYear, broken }

extension HealthInfo on Health {
  String get label => switch (this) {
    Health.ok => '趨勢正常',
    Health.belowYear => '跌破年線',
    Health.broken => '理由破壞',
  };

  String get advice => switch (this) {
    Health.ok => '站在年線上、長期理由還在：可以續抱',
    Health.belowYear => '股價在年線（200 日均線）之下：之後幾個月通常比較弱，想抱要有自己的理由',
    Health.broken => '趨勢轉弱又營收衰退、虧損又轉弱，或總分掉到全市場後 15%：建議檢討要不要換掉',
  };
}

/// 一個面向的好／中／差。
class HealthDim {
  final String name;
  final int grade; // 2 好、1 中、0 差、-1 沒資料
  final String detail;
  const HealthDim(this.name, this.grade, this.detail);
}

class HoldingHealth {
  final String code;
  final Health health;
  final List<HealthDim> dims;
  final double gap200, gap50; // 股價離 200／50 日均線（含息）
  final double ret1y; // 一年含息報酬
  final List<String> flags; // 長期警示
  final List<PickList> inLists;
  const HoldingHealth(this.code, this.health, this.dims, this.gap200, this.gap50, this.ret1y, this.flags, this.inLists);
}

String _pct(double x, [int d = 0]) => x.isNaN ? '—' : '${x >= 0 ? '+' : ''}${(x * 100).toStringAsFixed(d)}%';

/// 上市股票的健檢（用最新一天的評分）；上櫃、ETF 沒有評分回傳 null。
HoldingHealth? healthOf(LtData d, SampleScores live, String code, Map<PickList, ListResult> lists) {
  final si = d.index[code];
  if (si == null) return null;
  final x = live.of(si);
  if (x == null) return null;
  final st = d.stocks[si];
  final t = live.t;
  final px = st.trAt(t);
  final m200 = trMa(st, t, 200), m50 = trMa(st, t, 50);
  final gap200 = px.isNaN || m200.isNaN ? double.nan : px / m200 - 1;
  final gap50 = px.isNaN || m50.isNaN ? double.nan : px / m50 - 1;
  final h = x.broken ? Health.broken : (!gap200.isNaN && gap200 < 0 ? Health.belowYear : Health.ok);
  int grade(FactorGroup g) {
    final v = x.groups[g];
    if (v == null || v.isNaN) return -1;
    return v >= 67 ? 2 : (v >= 34 ? 1 : 0);
  }

  final r = x.raw;
  final dims = <HealthDim>[
    HealthDim(
      '趨勢',
      grade(FactorGroup.momentum),
      '離年線 ${_pct(gap200)}${r.slope200.isNaN ? '' : (r.slope200 >= 0 ? '・年線往上' : '・年線往下')}',
    ),
    HealthDim(
      '營收',
      grade(FactorGroup.revenue),
      '近 3 月年增 ${_pct(r.revYoy3)}${r.revPos12.isNaN ? '' : '・一年 ${(r.revPos12 * 12).round()} 個月成長'}',
    ),
    HealthDim(
      '獲利',
      grade(FactorGroup.quality),
      r.roe.isNaN ? (x.flags.contains(LtFlag.loss) ? '虧損' : '—') : 'ROE ${(r.roe * 100).toStringAsFixed(0)}%',
    ),
    HealthDim(
      '價格',
      grade(FactorGroup.value),
      [
        if (!r.pe.isNaN && r.pe > 0) '本益比 ${r.pe.toStringAsFixed(1)}',
        if (!r.pePct.isNaN) '5 年本益比位置 ${(r.pePct * 100).round()}%（越低越便宜）',
        if (!r.yld.isNaN) '殖利率 ${r.yld.toStringAsFixed(1)}%',
      ].join('・'),
    ),
    HealthDim(
      '法人',
      grade(FactorGroup.flow),
      r.fi.isNaN ? '—' : '外資 60 日${r.fi >= 0 ? '買' : '賣'}超、投信${r.it >= 0 ? '買' : '賣'}超',
    ),
    HealthDim('波動', grade(FactorGroup.stability), r.vol.isNaN ? '—' : '一年波動 ${(r.vol * 100).round()}%'),
  ];
  return HoldingHealth(
    code,
    h,
    dims,
    gap200,
    gap50,
    r.mom12,
    [for (final f in x.flags) f.label],
    [
      for (final e in lists.entries)
        if (e.value.contains(si)) e.key,
    ],
  );
}
