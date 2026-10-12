/// 「回測」：大型股避雷組合套到 2014 年以來每一個月，跟 0050、大盤（含息）比；
/// 另外列出舊方法（全市場評分挑股）的成績，和各類分數的因子研究。
///
/// 每個月只用「當時看得到」的資料決定（發行股數、股價、評分），隔天收盤成交，扣手續費、證交稅、滑價；
/// 股票名單包含之後下市的，沒有存活者偏差；減資、變更面額照證交所參考價接起來。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bluechip.dart';
import '../../core/lt_analysis.dart';
import '../../core/research.dart';
import '../../data/longterm_store.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/lt_widgets.dart';
import '../widgets/score_widgets.dart';

class BacktestScreen extends StatelessWidget {
  const BacktestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    return ListView(
      padding: pagePadding(context),
      children: [
        const PageHeader(icon: Icons.science, title: '回測', subtitle: '大型股避雷組合套到過去十幾年，每個月只用當時看得到的資料'),
        const _HowItWorks(),
        PackGate(
          builder: (context, r) {
            final bc = r.bluechip;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lt.analyzing) const LinearProgressIndicator(),
                if (bc == null)
                  const SectionCard(title: '需要更新資料包', child: Text('新版資料包加入了每家公司的發行股數（算市值用），請到「組合」頁更新。'))
                else ...[
                  _Verdict(bc: bc),
                  SplitView(
                    left: [
                      _NavChart(r: r, bc: bc),
                      _Years(bc: bc),
                    ],
                    right: [
                      _Stress(bc: bc),
                      _Mines(bc: bc),
                      _OldMethod(r: r, bc: bc),
                    ],
                  ),
                ],
                _Research(fr: r.research),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '回測是用過去的資料模擬，不保證未來。規則事先決定、用沒看過的期間檢驗過，但市場會變，請把結果當作「這套方法大概的個性」，不是報酬保證。'),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (Icons.event, '每月檢視一次', '每月 11 日以後的第一個交易日收盤後，隔天收盤買賣。股數用當天公布的發行股數，股價用當天收盤。'),
    (Icons.apartment, '市值前 30 大', '市值 = 發行股數 × 股價。只看最大的 30 家：大家熟悉、成交量大，買得到也賣得掉。'),
    (Icons.report_problem_outlined, '去掉地雷', '虧損、年線下彎又營收衰退、殖利率陷阱、成交量太小、總分在全市場後 20%：有其中一項就不買。'),
    (Icons.pie_chart_outline, '照市值配置', '單一檔最多 40%（連 0050 裡的一起算）；不到 1.5% 的改放 0050；跟目標差不到 1/4 就不調。'),
    (Icons.receipt_long, '扣掉成本', '買進：手續費 0.1425% ＋ 滑價 0.1%；賣出：再加證交稅 0.3%。配息照實際除息再投入（總報酬），減資照證交所參考價。'),
    (Icons.balance, '跟誰比', '0050（用市值前 50 大每月調整模擬）和加權股價報酬指數（含息）。'),
  ];

  static const _terms = [
    ('年化報酬', '平均每年的報酬率（複利）。'),
    ('最大跌幅', '帳面從最高點最多回落多少：決定你撐不撐得住。'),
    ('2014–2019／2020 以後', '規則只看前一段（2014–2019）決定，後一段（2020 以後）是事先沒看過的檢驗。'),
    ('地雷成績單', '每個月被排除的大型股，之後 6 個月跟沒地雷的大型股比，看「去掉地雷」是不是真的有用。'),
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

class _Verdict extends StatelessWidget {
  final BcResult bc;
  const _Verdict({required this.bc});

  @override
  Widget build(BuildContext context) {
    final f = bc.full;
    final money = 100 * math.pow(1 + f.cagr, (bc.endT - bc.startT) / 250.0);
    final etfMoney = 100 * math.pow(1 + f.etfCagr, (bc.endT - bc.startT) / 250.0);
    final benchMoney = 100 * math.pow(1 + f.benchCagr, (bc.endT - bc.startT) / 250.0);
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
      children: [
        for (final c in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Text(c, style: TextStyle(fontSize: 13, fontWeight: head ? FontWeight.w800 : FontWeight.w500)),
          ),
      ],
    );
    return SectionCard(
      title: '結論',
      trailing: Text('${f.from} ～ ${f.to}', style: Theme.of(context).textTheme.bodySmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${f.from.substring(0, 4)} 年投入 100 萬：大型股避雷組合約 ${money.toStringAsFixed(0)} 萬，'
            '0050 約 ${etfMoney.toStringAsFixed(0)} 萬，大盤含息約 ${benchMoney.toStringAsFixed(0)} 萬（都已扣交易成本）。',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                row(['期間', '組合 年化／最大跌幅', '0050', '大盤（含息）'], head: true),
                for (final p in bc.periods)
                  row([
                    p.label,
                    '${sp(p.cagr)}／${pc(p.mdd)}',
                    '${sp(p.etfCagr)}／${pc(p.etfMdd)}',
                    '${sp(p.benchCagr)}／${pc(p.benchMdd)}',
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Bullets([
            '兩段期間都比 0050 好一點（${sp(bc.periods[1].cagr - bc.periods[1].etfCagr)}、${sp(bc.periods[2].cagr - bc.periods[2].etfCagr)}／年），'
                '差別主要來自「去掉地雷」和「台積電不超過 40%」。',
            '跟 0050 一樣，比大盤（含息）好，因為大型公司這十幾年漲得比中小型公司多。',
            '最大跌幅比大盤深（${pc(f.mdd)} 對 ${pc(f.benchMdd)}）：大型股、尤其台積電佔很重，大跌時一起跌。這是持有大型股的代價。',
            '每年週轉約 ${(bc.turnover * 100).round()}%（0050 模擬約 ${(bc.etfTurnover * 100).round()}%），成本已經扣掉。',
          ], BulletKind.info),
        ],
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
  final BcResult bc;
  const _NavChart({required this.r, required this.bc});

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '資產走勢（起點 = 1）',
    child: SimpleChart(
      height: 240,
      series: [
        ChartSeries('大型股避雷組合', _thin(bc.nav, 420), AppColors.up, width: 2),
        ChartSeries('0050（模擬）', _thin(bc.etf, 420), const Color(0xFFC9A000)),
        ChartSeries('加權報酬指數', _thin(bc.bench, 420), Colors.blueGrey),
      ],
      startLabel: r.data.dates[bc.startT],
      endLabel: r.data.dates[bc.endT],
      yFormat: (v) => v.toStringAsFixed(1),
    ),
  );
}

class _Years extends StatelessWidget {
  final BcResult bc;
  const _Years({required this.bc});

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '逐年',
    trailing: bc.years.any((y) => y.partial) ? Text('* 不滿一整年', style: Theme.of(context).textTheme.bodySmall) : null,
    child: Column(
      children: [
        for (final y in bc.years)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    y.partial ? '${y.year}*' : '${y.year}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text('組合 ${sp(y.ret)}', style: TextStyle(color: changeColor(context, y.ret))),
                ),
                Expanded(child: Text('0050 ${sp(y.etf)}', style: Theme.of(context).textTheme.bodySmall)),
                Expanded(child: Text('大盤 ${sp(y.bench)}', style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Stress extends StatelessWidget {
  final BcResult bc;
  const _Stress({required this.bc});

  @override
  Widget build(BuildContext context) => bc.stress.isEmpty
      ? const SizedBox.shrink()
      : SectionCard(
          title: '大跌期間',
          child: Column(
            children: [
              for (final x in bc.stress)
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
                      Expanded(flex: 2, child: Text('0050 ${sp(x.etf)}', style: Theme.of(context).textTheme.bodySmall)),
                      Expanded(flex: 2, child: Text('大盤 ${sp(x.bench)}', style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ),
                ),
            ],
          ),
        );
}

/// 地雷成績單：被排除的地雷之後 6 個月 vs 沒地雷的大型股。
class _Mines extends StatelessWidget {
  final BcResult bc;
  const _Mines({required this.bc});

  @override
  Widget build(BuildContext context) {
    if (bc.mines.isEmpty) return const SizedBox.shrink();
    final recent = bc.mines.reversed.take(8).toList();
    return SectionCard(
      title: '地雷成績單',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '過去 ${bc.mines.length} 次有地雷的檢視日：被排除的大型股之後 6 個月，有 ${pc(bc.mineLagRate)} 的時候比沒地雷的大型股差，'
            '平均少賺 ${pc(-bc.mineAvgGap, 1)}。去掉地雷是這個組合比 0050 好的主要原因。',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 6),
          for (final m in recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(m.date, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(
                      '地雷 ${m.mines} 檔 ${sp(m.mineRet)}・其他 ${sp(m.okRet)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Tag(m.mineRet < m.okRet ? '避開對了' : '避開錯了', m.mineRet < m.okRet ? AppColors.up : AppColors.down),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 舊方法（全市場評分挑 15 檔）的成績，誠實列出來對照。
class _OldMethod extends StatelessWidget {
  final LtResult r;
  final BcResult bc;
  const _OldMethod({required this.r, required this.bc});

  @override
  Widget build(BuildContext context) {
    final s = r.sim.stats;
    final h = r.scorecard.of(126);
    return SectionCard(
      title: '對照：舊方法（全市場評分挑股）',
      child: Bullets([
        '全市場 1,000 多檔一起評分、挑分數最高的 15 檔（加上一半 0050）：年化 ${sp(s.cagr)}、最大跌幅 ${pc(s.mdd)}，'
            '比這個組合（${sp(bc.full.cagr)}）低。',
        if (h != null && h.n > 0) '每個月的名單抱 6 個月，贏大盤的次數只有 ${pc(h.winRate)}：分數擅長找出「最差的」，但挑不出「最好的」，而且挑到的多是冷門中小型股。',
        '所以改成：不預測贏家，只用分數排除地雷，其他照市值持有大型股。',
      ], BulletKind.info),
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
