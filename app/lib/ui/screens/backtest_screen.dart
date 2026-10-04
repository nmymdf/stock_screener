/// 「回測」：把長期組合的規則套到 2014 年以來的每一個月，看照做的話會怎樣；
/// 再看每一類因子過去是不是真的有用（因子研究）。
///
/// 每個月只用「當時看得到」的資料決定（營收保守假設 11 日以後才知道），隔天收盤成交，
/// 扣手續費、證交稅、滑價；股票名單包含之後下市的，沒有存活者偏差。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/exposure.dart';
import '../../core/lt_analysis.dart';
import '../../core/portfolio.dart';
import '../../core/research.dart';
import '../../data/longterm_store.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/lt_widgets.dart';
import '../widgets/score_widgets.dart';
import 'stock_report_screen.dart';

class BacktestScreen extends StatelessWidget {
  const BacktestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    return ListView(
      padding: pagePadding(context),
      children: [
        const PageHeader(icon: Icons.science, title: '回測', subtitle: '長期組合的規則套到過去十幾年，每個月只用當時看得到的資料'),
        const _HowItWorks(),
        PackGate(
          builder: (context, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Settings(lt: lt),
              if (lt.analyzing) const LinearProgressIndicator(),
              _Verdict(r: r),
              SplitView(
                left: [
                  _NavChart(r: r),
                  _Years(s: r.sim.stats),
                  _Stress(s: r.sim.stats),
                ],
                right: [
                  _Kpis(r: r),
                  _Variants(r: r),
                  _Positions(r: r),
                ],
              ),
              _Research(fr: r.research),
              _Rebalances(r: r),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '回測是用過去的資料模擬，不保證未來。規則是事先決定、沒有拿回測結果去調整，但市場會變，請把結果當作「這套方法大概的個性」，不是報酬保證。'),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (Icons.event, '每月檢視一次', '每月 11 日以後的第一個交易日收盤後（上市公司月營收 10 日前公布完），隔天收盤買賣。'),
    (Icons.leaderboard, '六大類分數', '動能趨勢、營收成長、獲利品質、價值股利各 20%，法人籌碼、穩定度各 10%，換成全市場百分位再加權。權重事先決定，不拿回測結果去調。'),
    (Icons.swap_horiz, '汰弱留強', '新買前 10%、還在前 30% 就續抱、至少抱 3 個月（理由破壞除外）、每月最多換 5 檔，單一檔 15%、單一產業 30%。'),
    (Icons.receipt_long, '扣掉成本', '買進：手續費 0.1425% ＋ 滑價 0.1%；賣出：再加證交稅 0.3%。配息照實際除息再投入（總報酬）。'),
    (Icons.visibility_off, '不偷看未來', '本益比、殖利率用當天公布的；營收假設 11 日以後才知道；股價只用當天以前的；名單包含之後下市的股票。'),
    (Icons.balance, '跟誰比', '加權股價報酬指數（含現金股利再投入，最公平的比較基準），以及「全部可投資股票平均分配」。'),
  ];

  static const _terms = [
    ('年化報酬', '平均每年的報酬率（複利）。'),
    ('超額報酬', '比報酬指數每年多賺（或少賺）多少。'),
    ('最大跌幅', '帳面從最高點最多回落多少：決定你撐不撐得住。'),
    ('每年贏指數', '每個日曆年組合報酬 > 報酬指數的比例。長期策略能 60～70% 已經很好。'),
    ('每筆持股賺錢', '每一次買進到賣出（含配息、扣成本）是賺錢的比例。'),
    ('週轉率', '一年換掉多少比例的持股。越低越省成本、越符合長期。'),
    ('資訊係數 IC', '分數排名和之後報酬排名的相關係數；長期平均 0.03～0.05 以上、而且多數月份是正的，就代表有用。'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.menu_book_outlined, color: scheme.primary),
          title: const Text('回測怎麼做、數字怎麼看', style: TextStyle(fontWeight: FontWeight.w800)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            CardGrid(
              minItemWidth: 340,
              spacing: 10,
              children: [
                for (final (i, (icon, title, body)) in _steps.indexed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: scheme.primary,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 16, color: scheme.primary),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(body, style: const TextStyle(fontSize: 12.5, height: 1.45)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            for (final (k, v) in _terms)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(k, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(child: Text(v, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Settings extends StatelessWidget {
  final LongTermStore lt;
  const _Settings({required this.lt});

  @override
  Widget build(BuildContext context) {
    final busy = lt.analyzing;
    Widget dd<T>(String label, T value, List<(T, String)> items, void Function(T) on) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        DropdownButton<T>(
          value: value,
          underline: const SizedBox.shrink(),
          items: [for (final (v, t) in items) DropdownMenuItem(value: v, child: Text(t))],
          onChanged: busy
              ? null
              : (v) {
                  if (v != null) on(v);
                },
        ),
      ],
    );
    return SectionCard(
      title: '組合設定',
      trailing: Text('改了會重新回測，「組合」頁也一起用', style: Theme.of(context).textTheme.bodySmall),
      child: Wrap(
        spacing: 20,
        runSpacing: 4,
        children: [
          dd('檔數', lt.cfg.size, [
            for (final n in const [10, 12, 15]) (n, '$n 檔'),
          ], (v) => lt.setConfig(size: v)),
          dd('每月最多換', lt.cfg.maxChanges, [
            for (final n in const [2, 3, 4, 5]) (n, '$n 檔'),
          ], (v) => lt.setConfig(maxChanges: v)),
          dd('股票比例', lt.cfg.exposure, [
            for (final m in ExposureMode.values) (m, m.label),
          ], (v) => lt.setConfig(exposure: v)),
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  final LtResult r;
  const _Verdict({required this.r});

  @override
  Widget build(BuildContext context) {
    final s = r.sim.stats;
    final beatYears = s.yearRows.where((y) => y.beat).length;
    final good = s.excessCagr > 0.02 && s.yearlyWin >= 0.6;
    final ok = s.excessCagr > 0;
    final (label, color, icon) = good
        ? ('長期勝過大盤', AppColors.up, Icons.thumb_up_alt_outlined)
        : ok
        ? ('小幅勝過大盤', const Color(0xFFC98A00), Icons.trending_flat)
        : ('沒有勝過大盤', const Color(0xFF5B8DB8), Icons.thumb_down_alt_outlined);
    final bench = r.sim.benchIsTri ? '加權報酬指數（含息）' : '加權指數（不含息，基準被低估）';
    final money = 1000000 * (1 + s.totalRet);
    final benchMoney = 1000000 * (1 + s.benchTotal);
    return Card(
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 5)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                    ),
                  ],
                ),
                Text('${s.from} ～ ${s.to}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '照這套規則，${s.from.substring(0, 4)} 年投入 100 萬，到現在約 ${(money / 10000).toStringAsFixed(0)} 萬'
              '（年化 ${sp(s.cagr)}）；同期 $bench 約 ${(benchMoney / 10000).toStringAsFixed(0)} 萬（年化 ${sp(s.benchCagr)}）。\n'
              '${s.yearRows.length} 個完整年度中有 $beatYears 年贏指數，每個月贏指數的比例 ${pc(s.monthlyWin)}；'
              '最大跌幅 ${pc(s.mdd)}（指數 ${pc(s.benchMdd)}）；平均每筆抱 ${(s.avgHoldDays / 21).toStringAsFixed(1)} 個月，'
              '${pc(s.posWin)} 的持股賣出時是賺錢的。',
              style: const TextStyle(fontSize: 14, height: 1.55),
            ),
            const SizedBox(height: 6),
            Text(
              '前半段每年超額 ${sp(s.firstHalfExcess)}、後半段 ${sp(s.secondHalfExcess)}'
              '${(s.firstHalfExcess > 0) == (s.secondHalfExcess > 0) ? '：前後一致，不是只靠某一段運氣' : '：前後不一致，要保守看待'}。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 長序列抽樣成大約 [n] 點畫圖。
List<double?> _thin(List<double> v, int n) {
  if (v.length <= n) return v;
  final step = v.length / n;
  return [for (var i = 0; i < n; i++) v[math.min(v.length - 1, (i * step).floor())], v.last];
}

class _NavChart extends StatelessWidget {
  final LtResult r;
  const _NavChart({required this.r});

  @override
  Widget build(BuildContext context) {
    final sim = r.sim;
    return SectionCard(
      title: '資產走勢（起點 = 1）',
      child: SimpleChart(
        height: 240,
        series: [
          ChartSeries('組合', _thin(sim.nav, 420), AppColors.up, width: 2),
          ChartSeries(sim.benchIsTri ? '加權報酬指數' : '加權指數', _thin(sim.bench, 420), Colors.blueGrey),
          ChartSeries('全部可投資股票平均', _thin(sim.eqw, 420), const Color(0xFFC9A000)),
        ],
        startLabel: r.data.dates[sim.startT],
        endLabel: r.data.dates[sim.endT],
        yFormat: (v) => v.toStringAsFixed(1),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  final LtResult r;
  const _Kpis({required this.r});

  @override
  Widget build(BuildContext context) {
    final s = r.sim.stats;
    final up = AppColors.up, down = AppColors.down;
    return SectionCard(
      title: '重點數字',
      child: StatGrid(
        bare: true,
        stats: [
          ('年化報酬', sp(s.cagr), s.cagr >= 0 ? up : down),
          ('報酬指數年化', sp(s.benchCagr), null),
          ('每年超額', sp(s.excessCagr), s.excessCagr >= 0 ? up : down),
          ('最大跌幅', pc(s.mdd), null),
          ('指數最大跌幅', pc(s.benchMdd), null),
          ('每年贏指數', pc(s.yearlyWin), null),
          ('每月贏指數', pc(s.monthlyWin), null),
          ('夏普值', s.sharpe.toStringAsFixed(2), null),
          ('年波動度', pc(s.vol), null),
          ('年週轉率', pc(s.turnover), null),
          ('平均股票部位', pc(s.avgExposure), null),
          ('等權全市場年化', sp(s.eqwCagr), null),
        ],
      ),
    );
  }
}

class _Years extends StatelessWidget {
  final PerfStats s;
  const _Years({required this.s});

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '逐年',
    trailing: s.yearRows.any((y) => y.partial) ? Text('* 不滿一整年', style: Theme.of(context).textTheme.bodySmall) : null,
    child: Column(
      children: [
        for (final y in s.yearRows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    y.partial ? '${y.year}*' : '${y.year}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text('組合 ${sp(y.ret)}', style: TextStyle(color: changeColor(context, y.ret))),
                ),
                Expanded(child: Text('指數 ${sp(y.bench)}', style: Theme.of(context).textTheme.bodySmall)),
                Tag(y.beat ? '贏' : '輸', y.beat ? AppColors.up : AppColors.down),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Stress extends StatelessWidget {
  final PerfStats s;
  const _Stress({required this.s});

  @override
  Widget build(BuildContext context) => s.stress.isEmpty
      ? const SizedBox.shrink()
      : SectionCard(
          title: '大跌期間（壓力測試）',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final x in s.stress)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(x.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('組合 ${sp(x.ret)}', style: TextStyle(color: changeColor(context, x.ret))),
                      ),
                      Expanded(flex: 2, child: Text('指數 ${sp(x.bench)}', style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ),
                ),
              Text('跌得比指數少，就代表分散、低波動、環境判斷有發揮作用。', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
}

class _Variants extends StatelessWidget {
  final LtResult r;
  const _Variants({required this.r});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return SectionCard(
      title: '不同設定比較',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(flex: 4, child: Text('設定', style: small)),
              Expanded(flex: 2, child: Text('年化', style: small)),
              Expanded(flex: 2, child: Text('最大跌幅', style: small)),
              Expanded(flex: 2, child: Text('每年贏', style: small)),
            ],
          ),
          const Divider(height: 10),
          for (final v in r.variants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      v.label,
                      style: TextStyle(fontWeight: v.label == '目前設定' ? FontWeight.w800 : FontWeight.w500, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(sp(v.stats.cagr), style: TextStyle(color: changeColor(context, v.stats.cagr))),
                  ),
                  Expanded(flex: 2, child: Text(pc(v.stats.mdd))),
                  Expanded(flex: 2, child: Text(pc(v.stats.yearlyWin))),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '目前設定：${r.sim.cfg.size} 檔、每月最多換 ${r.sim.cfg.maxChanges} 檔、${r.sim.cfg.exposure.label}。'
            '各設定差不多，代表規則穩健、不是剛好調到某個數字；差很多就要小心。',
            style: small,
          ),
        ],
      ),
    );
  }
}

class _Positions extends StatelessWidget {
  final LtResult r;
  const _Positions({required this.r});

  @override
  Widget build(BuildContext context) {
    final closed = r.sim.episodes.where((e) => !e.open).toList();
    if (closed.isEmpty) return const SizedBox.shrink();
    final rets = closed.map((e) => e.ret).toList()..sort();
    final median = rets[rets.length ~/ 2];
    final best = [...closed]..sort((a, b) => b.ret.compareTo(a.ret));
    return SectionCard(
      title: '每一筆持股',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KvRow('買賣過幾次', '${closed.length} 筆'),
          KvRow('賣出時賺錢', pc(r.sim.stats.posWin)),
          KvRow('同期間贏指數', pc(r.sim.stats.posBeat)),
          KvRow('報酬中位數（含息、扣成本）', sp(median)),
          KvRow('平均持有', '${(r.sim.stats.avgHoldDays / 21).toStringAsFixed(1)} 個月'),
          const SizedBox(height: 6),
          Text('賺最多的', style: Theme.of(context).textTheme.bodySmall),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final e in best.take(5))
                ActionChip(
                  label: Text('${e.code} ${sp(e.ret, 0)}'),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: e.code))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Research extends StatelessWidget {
  final FactorResearch fr;
  const _Research({required this.fr});

  @override
  Widget build(BuildContext context) {
    if (fr.rows.isEmpty) return const SizedBox.shrink();
    final small = Theme.of(context).textTheme.bodySmall;
    return SectionCard(
      title: '因子研究：分數高的股票之後真的比較好嗎？',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${fr.from} ～ ${fr.to} 共 ${fr.periods} 個月，每個月把可投資的股票依分數分成五組（第 1 組最高），'
            '看之後 ${fr.horizon} 個交易日（約 3 個月）含息報酬比全部平均多多少。'
            '總分前 10% 的股票，之後 3 個月賺錢的比例 ${pc(fr.topWin)}、贏過平均的比例 ${pc(fr.topBeat)}。',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 34,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 36,
              columnSpacing: 16,
              columns: [
                const DataColumn(label: Text('因子')),
                for (var q = 1; q <= 5; q++) DataColumn(label: Text('第 $q 組'), numeric: true),
                const DataColumn(label: Text('一減五'), numeric: true),
                const DataColumn(label: Text('IC'), numeric: true),
                const DataColumn(label: Text('IC 為正'), numeric: true),
              ],
              rows: [
                for (final x in fr.rows)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(x.name, style: TextStyle(fontWeight: x.name == '總分' ? FontWeight.w800 : FontWeight.w600)),
                      ),
                      for (final q in x.quintiles)
                        DataCell(Text(sp(q), style: TextStyle(color: changeColor(context, q), fontSize: 13))),
                      DataCell(Text(sp(x.spread), style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text(x.ic.toStringAsFixed(3))),
                      DataCell(Text(pc(x.icHit))),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '怎麼看：第 1 組到第 5 組由高到低排得越整齊、「一減五」越大、IC 為正的月份越多，代表這類分數越有用。'
            '權重是事先決定的，這張表只用來檢查，不拿來調權重（避免對過去量身訂做）。',
            style: small,
          ),
        ],
      ),
    );
  }
}

class _Rebalances extends StatelessWidget {
  final LtResult r;
  const _Rebalances({required this.r});

  @override
  Widget build(BuildContext context) {
    final list = r.sim.rebalances.reversed.where((x) => x.trades.isNotEmpty).take(12).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('最近 12 次調整紀錄', style: TextStyle(fontWeight: FontWeight.w800)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final x in list) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Text(
                    '${x.date} 檢視（${x.execDate} 成交）・股票 ${pc(x.exposure)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              for (final t in x.trades)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tag(t.buy ? '買' : '賣', t.buy ? AppColors.up : const Color(0xFF5B8DB8)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${t.code.isEmpty ? '' : '${t.code} ${r.data.stock(t.code)?.name ?? ''}　'}${pc(t.weight, 1)}　${t.reason}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
