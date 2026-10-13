/// 「回測」：穩健＋進攻策略套到 2014 年以來每一天，跟 0050、大盤（含息）比；
/// 另外列出研究過程中檢驗過、沒採用的方法，和各類分數的因子研究。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/lt_analysis.dart';
import '../../core/research.dart';
import '../../core/strategy.dart';
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
        const PageHeader(icon: Icons.science, title: '回測', subtitle: '穩健＋進攻策略套到過去十幾年，每個月只用當時看得到的資料'),
        const _HowItWorks(),
        PackGate(
          builder: (context, r) {
            final st = r.strategy;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lt.analyzing) const LinearProgressIndicator(),
                if (st == null)
                  const SectionCard(title: '需要更新資料包', child: Text('新版資料包加入了每家公司的發行股數，請到「組合」頁更新。'))
                else ...[
                  _Verdict(st: st),
                  SplitView(
                    left: [
                      _NavChart(r: r, st: st),
                      _Years(st: st),
                    ],
                    right: [
                      const _Caveats(),
                      _Tested(r: r),
                    ],
                  ),
                ],
                _Research(fr: r.research),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '回測是用過去的資料模擬，不保證未來。試過很多方法後挑出最好的，多少有運氣成分；投資盈虧請自行負責。'),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (Icons.event, '每月檢視一次', '每月 11 日以後的第一個交易日收盤後（月營收 10 日前公布完），隔天收盤調整。'),
    (Icons.shield_outlined, '穩健 70%', '0050。大盤（加權報酬指數）在 200 日均線上就持有，跌破就改放現金（年息 1%）。'),
    (Icons.trending_up, '進攻 30%', '趨勢模板＋營收成長挑 10 檔強勢股平均配置；不足 10 檔的部分放 0050。'),
    (Icons.do_not_disturb_on_outlined, '停損', '進攻名單任何一檔收盤跌破 50 日均線，當天賣出放現金，下次檢視再挑。'),
    (Icons.receipt_long, '扣掉成本', '買進：手續費 0.1425% ＋ 滑價 0.1%；賣出：再加證交稅 0.3%。配息再投入（總報酬），減資照證交所參考價。'),
    (Icons.visibility_off, '不偷看未來', '每月只用當時看得到的股價、營收、評分；名單包含之後下市的股票。'),
  ];

  static const _terms = [
    ('年化報酬', '平均每年的報酬率（複利）。'),
    ('最大跌幅', '帳面從最高點最多回落多少：決定你撐不撐得住。'),
    ('2014–2019／2020 以後', '兩種不同的行情：前一段多半是盤整，後一段是強勢多頭。好的方法兩段都要站得住。'),
    ('0050', '用市值前 50 大、每月調整模擬。'),
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
  final StrategyResult st;
  const _Verdict({required this.st});

  @override
  Widget build(BuildContext context) {
    final f = st.full;
    final yrs = (st.endT - st.startT) / 250.0;
    final scheme = Theme.of(context).colorScheme;
    TableRow row(List<String> cells, {bool head = false, bool strong = false}) => TableRow(
      decoration: head ? BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: .8)) : null,
      children: [
        for (final c in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: Text(
              c,
              style: TextStyle(fontSize: 13, fontWeight: head || strong ? FontWeight.w800 : FontWeight.w500),
            ),
          ),
      ],
    );
    return SectionCard(
      title: '結論',
      trailing: Text('${f.from} ～ ${f.to}', style: Theme.of(context).textTheme.bodySmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(horizontalInside: BorderSide(color: scheme.outlineVariant)),
              children: [
                row(['', ...StrategyResult.names], head: true),
                row([
                  '${f.from.substring(0, 4)} 年投入 100 萬',
                  for (var i = 0; i < 5; i++) '${(100 * math.pow(1 + f.v[i].$1, yrs)).toStringAsFixed(0)} 萬',
                ], strong: true),
                for (final p in st.periods) ...[
                  row(['${p.label} 年化', for (final v in p.v) sp(v.$1)]),
                  row(['　最大跌幅', for (final v in p.v) pc(v.$2)]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          InfoTable([
            ('比 0050', '全期每年多 ${sp(f.v[0].$1 - f.v[3].$1)}；最大跌幅 ${pc(f.v[0].$2)}，0050 是 ${pc(f.v[3].$2)}（大約一半）。'),
            ('兩段期間', '2020 以後明顯多賺；2014–2019 大約跟 0050 打平。優勢主要來自強勢多頭。'),
            ('穩健部分', '0050＋200 日均線：報酬跟一直持有差不多，大跌少很多（12 年進出 ${st.marketSwitches} 次）。'),
            ('進攻部分', '強勢股＋50 日均線停損：報酬最高、波動也最大；12 年停損 ${st.stops} 次（大約每週一次）。'),
          ], keyWidth: 96),
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
  final StrategyResult st;
  const _NavChart({required this.r, required this.st});

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '資產走勢（起點 = 1）',
    child: SimpleChart(
      height: 240,
      series: [
        ChartSeries('穩健＋進攻', _thin(st.navs[0], 420), AppColors.up, width: 2),
        ChartSeries('0050', _thin(st.navs[3], 420), const Color(0xFFC9A000)),
        ChartSeries('大盤（含息）', _thin(st.navs[4], 420), Colors.blueGrey),
      ],
      startLabel: r.data.dates[st.startT],
      endLabel: r.data.dates[st.endT],
      yFormat: (v) => v.toStringAsFixed(1),
    ),
  );
}

class _Years extends StatelessWidget {
  final StrategyResult st;
  const _Years({required this.st});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '逐年',
      trailing: st.years.any((y) => y.partial) ? Text('* 不滿一整年', style: Theme.of(context).textTheme.bodySmall) : null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(horizontalInside: BorderSide(color: scheme.outlineVariant)),
          children: [
            TableRow(
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: .8)),
              children: [
                for (final h in ['年份', ...StrategyResult.names])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                    child: Text(h, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            for (final y in st.years)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    child: Text(
                      y.partial ? '${y.year}*' : '${y.year}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final v in y.v)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                      child: Text(sp(v), style: TextStyle(fontSize: 13, color: changeColor(context, v))),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Caveats extends StatelessWidget {
  const _Caveats();

  @override
  Widget build(BuildContext context) => const SectionCard(
    title: '要注意',
    child: InfoTable([
      ('不是聖杯', '前後試了二十幾種方法，這是最好的一個，多少有運氣成分；未來大概會比回測差一些。'),
      ('靠強勢多頭', '2020 以後的 AI 多頭對強勢股特別有利；2014–2019 這種盤整年，大約只跟 0050 打平。'),
      ('要準時', '晚一週買進、或改成兩三個月才調整，2014–2019 的成績就明顯變差。'),
      ('穩健性', '挑 5～15 檔、相對強度門檻、營收門檻、進攻比例 20～40% 都試過：每一種都比 0050 跌得少、2020 以後都多賺；2014–2019 好壞各半。'),
      ('資料限制', '只有上市股票、只有收盤價（停損用收盤判斷）；沒有完整財報（現金流、負債）。'),
    ], keyWidth: 96),
  );
}

/// 研究過程中檢驗過、沒採用的方法（同樣的條件：每天成交 2 億以上、沒有地雷、扣成本）。
class _Tested extends StatelessWidget {
  final LtResult r;
  const _Tested({required this.r});

  @override
  Widget build(BuildContext context) {
    final bc = r.bluechip;
    return SectionCard(
      title: '檢驗過、沒採用的方法',
      child: InfoTable([
        ('全市場評分挑 15 檔', '每月名單抱 3～6 個月，贏大盤的次數約一半；挑到的多是冷門中小型股。'),
        if (bc != null)
          ('市值前 30 大去地雷', '年化 ${sp(bc.full.cagr)}（0050 ${sp(bc.full.etfCagr)}）：幾乎就是 0050，不算選股。現在放在「市值」頁當排行參考。'),
        ('神奇公式（Greenblatt）', '2020 以後名單贏平均股票的次數只有 26%。'),
        ('趨勢價值（O\'Shaughnessy）', '兩段都輸平均股票。'),
        ('低波動', '兩段都輸平均股票。'),
        ('產業動能', '年化約 16%，輸 0050。'),
        ('自訂長／中／短期規則', '長期高股息、中期成長＋品質、短期營收公告後延續：都沒有穩定贏平均股票。'),
        ('趨勢模板不停損', '報酬更高，但進攻部分曾經跌 54%；加 50 日均線停損後降到 40%，混合後只剩約 18%。'),
      ], keyWidth: 140),
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
