/// 「回測」：兩份候選名單、持股健檢、大盤抱法套到 2014 年以來每一個月，跟 0050、大盤（含息）比；
/// 另外列出研究過程中檢驗過、沒採用的方法，和各類分數的因子研究。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/lists.dart';
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
        const PageHeader(icon: Icons.science, title: '回測', subtitle: '名單、持股健檢、大盤抱法套到 2014 年以來每一個月，只用當時看得到的資料'),
        const _HowItWorks(),
        PackGate(
          builder: (context, r) {
            final st = r.strategy;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lt.analyzing) const LinearProgressIndicator(),
                if (st == null || r.lists.isEmpty)
                  const SectionCard(title: '需要更新資料包', child: Text('新版資料包加入了每家公司的發行股數，請到「選股」頁更新。'))
                else ...[
                  _Verdict(r: r, st: st),
                  SplitView(
                    left: [
                      for (final lr in r.lists.values)
                        SectionCard(
                          title: '候選名單：${lr.kind.label}',
                          child: ListStatTable(lr: lr),
                        ),
                    ],
                    right: [
                      _Market(st: st),
                      _NavChart(r: r, st: st),
                    ],
                  ),
                  SplitView(
                    left: [_Years(st: st)],
                    right: [
                      const _Caveats(),
                      _Tested(r: r, st: st),
                    ],
                  ),
                ],
                _Research(fr: r.research),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '回測是用過去的資料模擬，不保證未來；投資盈虧請自行負責。'),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (Icons.event, '每月檢視一次', '每月 11 日以後的第一個交易日收盤後（月營收 10 日前公布完），用當時的資料產生名單。'),
    (Icons.list_alt, '候選名單', '名單上的股票隔天收盤平均買進，分別抱 3、6、12 個月，看賺不賺錢、有沒有贏同期 0050。'),
    (Icons.health_and_safety_outlined, '持股健檢', '每個月把所有上市股票分成趨勢正常、跌破年線、理由破壞三組，看之後幾個月各組表現。'),
    (Icons.shield_outlined, '大盤抱法', '大盤（加權報酬指數）在 200 日均線上就抱 0050，跌破就放現金（年息 1%）。'),
    (Icons.receipt_long, '扣掉成本', '買進：手續費 0.1425% ＋ 滑價 0.1%；賣出：再加證交稅 0.3%。配息再投入（總報酬），減資照證交所參考價。'),
    (Icons.visibility_off, '不偷看未來', '每月只用當時看得到的股價、營收、評分；名單包含之後下市的股票。'),
  ];

  static const _terms = [
    ('賺錢機率', '每月一份名單，有幾成的名單抱到期是賺錢的。'),
    ('贏 0050', '有幾成的名單抱到期贏過同期的 0050。'),
    ('最差', '所有名單裡表現最差的一次。'),
    ('2014–2019／2020 以後', '兩種不同的行情：前一段多半是盤整，後一段是強勢多頭。'),
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
            InfoTable(_terms, keyWidth: 110),
          ],
        ),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  final LtResult r;
  final StrategyResult st;
  const _Verdict({required this.r, required this.st});

  @override
  Widget build(BuildContext context) {
    final f = st.full;
    String line(PickList k, int m) {
      final s = r.lists[k]?.stat(m, '全部期間');
      if (s == null) return '—';
      return '抱 $m 個月平均 ${sp(s.avg)}（0050 ${sp(s.etfAvg)}），賺錢機率 ${pc(s.upRate)}、贏 0050 ${pc(s.beatEtf)}';
    }

    return SectionCard(
      title: '結論',
      trailing: Text('${f.from} ～ ${f.to}', style: Theme.of(context).textTheme.bodySmall),
      child: InfoTable([
        ('先說實話', '過去 12 年，一檔上市股票抱一年贏 0050 的機會只有三成多（0050 裡的台積電漲太多）。任何選股名單都很難長期贏 0050，名單的用處是幫你挑、幫你避雷，不是保證贏。'),
        ('強勢成長', '${line(PickList.strong, 6)}。2020 以後的多頭有用，2014–2019 輸 0050；抱一年大多輸。'),
        ('穩健存股', '${line(PickList.income, 12)}。報酬比較少，但最穩。'),
        ('持股健檢', '之後 6 個月平均：2014–2019 趨勢正常 +3.6%、跌破年線 +1.1%、理由破壞 0.0%；2020 以後 +14.5%、+5.4%、+8.8%。看一年就差不多。'),
        (
          '大盤抱法',
          '在年線上抱 0050、跌破放現金：年化 ${sp(f.v[1].$1)}、最大跌幅 ${pc(f.v[1].$2)}；一直抱 0050 ${sp(f.v[3].$1)}、${pc(f.v[3].$2)}。'
              '報酬差不多，大跌少很多（${st.marketSwitches} 次進出）。',
        ),
      ], keyWidth: 84),
    );
  }
}

/// 大盤抱法 vs 一直抱 0050 vs 大盤（含息）。
class _Market extends StatelessWidget {
  final StrategyResult st;
  const _Market({required this.st});

  static const idx = [1, 3, 4];
  static const names = ['在年線上才抱', '一直抱 0050', '大盤（含息）'];

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
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: 13, fontWeight: head || strong ? FontWeight.w800 : FontWeight.w500),
            ),
          ),
      ],
    );
    return SectionCard(
      title: '大盤抱法：0050＋200 日均線',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(horizontalInside: BorderSide(color: scheme.outlineVariant)),
          children: [
            row(['', ...names], head: true),
            row([
              '${f.from.substring(0, 4)} 年投入 100 萬',
              for (final i in idx) '${(100 * math.pow(1 + f.v[i].$1, yrs)).toStringAsFixed(0)} 萬',
            ], strong: true),
            for (final p in st.periods) ...[
              row(['${p.label} 年化', for (final i in idx) sp(p.v[i].$1)]),
              row(['　最大跌幅', for (final i in idx) pc(p.v[i].$2)]),
            ],
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
  final StrategyResult st;
  const _NavChart({required this.r, required this.st});

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '大盤抱法走勢（起點 = 1）',
    child: SimpleChart(
      height: 220,
      series: [
        ChartSeries('在年線上才抱', _thin(st.navs[1], 420), const Color(0xFF0B7A6F), width: 2),
        ChartSeries('一直抱 0050', _thin(st.navs[3], 420), const Color(0xFFC9A000)),
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
      title: '大盤抱法逐年',
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
                for (final h in ['年份', ..._Market.names])
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
                  for (final i in _Market.idx)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                      child: Text(sp(y.v[i]), style: TextStyle(fontSize: 13, color: changeColor(context, y.v[i]))),
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
      ('規則先定好', '名單和健檢的規則都是先定好再檢驗，沒有回頭調數字去配合結果。'),
      ('靠行情', '強勢股在 2020 以後的 AI 多頭特別有利；盤整年就普通。'),
      ('名單是平均買', '成績是名單上每一檔平均買的結果；你只挑其中幾檔，結果會差很多。'),
      ('資料限制', '只有上市股票、只有收盤價；沒有完整財報（現金流、負債）。'),
    ], keyWidth: 96),
  );
}

/// 研究過程中檢驗過、沒採用的方法。
class _Tested extends StatelessWidget {
  final LtResult r;
  final StrategyResult st;
  const _Tested({required this.r, required this.st});

  @override
  Widget build(BuildContext context) {
    final bc = r.bluechip;
    final f = st.full;
    return SectionCard(
      title: '檢驗過、沒採用的方法',
      child: InfoTable([
        ('剛轉強', '剛站上年線、營收加速：抱一年平均 +14.4%（0050 +21.9%），贏 0050 只有 37%。'),
        ('相對便宜', '本益比在自己 5 年低檔、營收沒衰退：抱一年平均 +9.4%（0050 +22.3%），贏 0050 只有 20%。'),
        (
          '穩健 70%＋強勢 30% 配比例',
          '年化 ${sp(f.v[0].$1)}、最大跌幅 ${pc(f.v[0].$2)}，數字最好看；但要每天照規則買賣、照比例配置，多賺的幾乎都在 2020 以後。改成名單由你挑，不再替你配比例。',
        ),
        ('全市場評分挑 15 檔', '每月名單抱 3～6 個月，贏大盤的次數約一半；挑到的多是冷門中小型股。'),
        if (bc != null)
          ('市值前 30 大去地雷', '年化 ${sp(bc.full.cagr)}（0050 ${sp(bc.full.etfCagr)}）：幾乎就是 0050，不算選股。現在放在「市值」頁當排行參考。'),
        ('神奇公式（Greenblatt）', '2020 以後名單贏平均股票的次數只有 26%。'),
        ('趨勢價值（O\'Shaughnessy）', '兩段都輸平均股票。'),
        ('低波動', '兩段都輸平均股票。'),
        ('產業動能', '年化約 16%，輸 0050。'),
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
