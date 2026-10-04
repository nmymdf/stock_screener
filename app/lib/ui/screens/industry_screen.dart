/// 「產業」：產業強弱排名與輪動分類（規格書 §3），點進去看產業內的個股。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../layout.dart';
import '../../data/history_store.dart';
import '../../logic/engine/analysis.dart';
import '../../logic/engine/industry_engine.dart';
import '../../logic/engine/signals.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/analysis_gate.dart';
import '../widgets/common.dart';
import '../widgets/score_widgets.dart';
import 'stock_report_screen.dart';

class IndustryScreen extends StatelessWidget {
  const IndustryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnalysisGate(
      builder: (context, a) {
        final list = a.industries;
        return [
          const PageHeader(icon: Icons.category, title: '產業強弱與輪動', subtitle: '先判斷產業，再挑個股（規格書 §3）'),
          Text(
            '同一家公司，在強勢產業和弱勢產業裡的成功機率不同。'
            '產業分數由成員股的 20／60／120 日報酬中位數、站上 20／60 日線比例、創 60 日新高比例、成交值變化，'
            '跟其他產業比排名而來。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in IndustryClass.values)
                Tooltip(
                  message: c.explain,
                  child: Tag('${c.label} ${list.where((x) => x.cls == c).length}', industryClassColor(c)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const Card(
              child: Padding(padding: EdgeInsets.all(16), child: Text('資料不足，需要至少 60 個交易日才能算產業分數。')),
            ),
          for (var i = 0; i < list.length; i++) _IndustryRow(rank: i + 1, r: list[i], a: a),
        ];
      },
    );
  }
}

class _IndustryRow extends StatelessWidget {
  final int rank;
  final IndustryReport r;
  final AnalysisResult a;
  const _IndustryRow({required this.rank, required this.r, required this.a});

  @override
  Widget build(BuildContext context) {
    final recs = r.codes.where((c) => a.stock(c)?.recommended ?? false).length;
    final d = r.delta;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IndustryDetailScreen(name: r.name))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '$rank',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.grey),
                ),
              ),
              ScoreBadge(score: r.score, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(r.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        Tag(r.cls.label, industryClassColor(r.cls)),
                        if (d != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${d >= 0 ? '▲' : '▼'}${d.abs().toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 12, color: changeColor(context, d)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '20 日 ${pctTxt(r.medRoc20)}（超額 ${pctTxt(r.excess20)}）· 站上月線 ${(r.pctAbove20 * 100).toStringAsFixed(0)}%'
                      ' · 新高 ${(r.pctNewHigh60 * 100).toStringAsFixed(0)}% · ${r.members} 檔${recs > 0 ? ' · 推薦 $recs 檔' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class IndustryDetailScreen extends StatelessWidget {
  final String name;
  const IndustryDetailScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final a = context.watch<HistoryStore>().analysis;
    final r = a?.industry(name);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: r == null || a == null
          ? const Center(child: Text('沒有這個產業的資料'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                child: ListView(
                  padding: pagePadding(context),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            ScoreBadge(score: r.score, size: 64, caption: '產業分數'),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tag(r.cls.label, industryClassColor(r.cls), filled: true),
                                  const SizedBox(height: 6),
                                  Text(r.cls.explain, style: const TextStyle(fontSize: 13)),
                                  if (r.delta != null)
                                    Text(
                                      '10 個交易日前 ${r.prevScore!.toStringAsFixed(0)} 分 → 現在 ${r.score.toStringAsFixed(0)} 分',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    StatGrid(
                      stats: [
                        ('20 日報酬中位數', pctTxt(r.medRoc20), changeColor(context, r.medRoc20)),
                        ('60 日報酬中位數', pctTxt(r.medRoc60), changeColor(context, r.medRoc60)),
                        ('120 日報酬中位數', r.medRoc120.isNaN ? '—' : pctTxt(r.medRoc120), null),
                        ('相對全市場（20 日）', pctTxt(r.excess20), changeColor(context, r.excess20)),
                        ('站上 20 日線', '${(r.pctAbove20 * 100).toStringAsFixed(0)}%', null),
                        ('站上 60 日線', '${(r.pctAbove60 * 100).toStringAsFixed(0)}%', null),
                        ('創 60 日新高', '${(r.pctNewHigh60 * 100).toStringAsFixed(0)}%', null),
                        ('成交值變化', '${r.valueChange.toStringAsFixed(2)} 倍', null),
                      ],
                    ),
                    SectionCard(
                      title: '領漲股（60 日漲幅前 3）',
                      child: Text(
                        r.leaders.map((c) => '$c ${a.stock(c)?.name ?? ''}').join('、'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SectionHeader(left: '產業內個股（依總分排序）'),
                    RowList(
                      children: [
                        for (final s
                            in (r.codes.map(a.stock).whereType<StockReport>().toList()
                              ..sort((x, y) => y.total.compareTo(x.total))))
                          InfoRow(
                            onTap: () =>
                                Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => StockReportScreen(code: s.code))),
                            title: Row(
                              children: [
                                Flexible(child: Text('${s.code} ${s.name}', overflow: TextOverflow.ellipsis)),
                                if (s.recommended) ...[
                                  const SizedBox(width: 6),
                                  const Tag('推薦', Color(0xFF0B7A6F), filled: true),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '總分 ${s.total.toStringAsFixed(0)}'
                              '${s.rsRank == null ? '' : ' · RS 第 ${s.rsRank} 名'}'
                              '${s.hits.isEmpty ? '' : ' · 訊號 ${s.hits.map((h) => h.hit.strategy.code).join('/')}'}',
                            ),
                            trailingTop: Text(f2(s.close)),
                            trailingBottom: Text(
                              pctTxt(s.changePct),
                              style: TextStyle(color: changeColor(context, s.changePct)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
