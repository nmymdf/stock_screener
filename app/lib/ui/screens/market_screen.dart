/// 「市場」：Market Score、市場狀態與建議曝險、分數組成、廣度數據、
/// 歷史走勢圖（規格書 §2）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/longterm_store.dart';
import '../layout.dart';
import '../../logic/engine/market_engine.dart';
import '../format.dart';
import '../widgets/analysis_gate.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/lt_widgets.dart';
import '../widgets/score_widgets.dart';

class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnalysisGate(
      header: const [
        PageHeader(icon: Icons.speed, title: '市場環境', subtitle: '長期：建議股票比例（台股＋國際）；短期：用全市場廣度算的每日市場分數'),
        _LongTermExposure(),
      ],
      builder: (context, a) {
        final t = a.today;
        if (t == null) return [const Text('沒有資料')];
        final r = t.regime;
        final days = a.market;
        final from = math.max(0, days.length - 160);
        final shown = days.sublist(from);
        String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(0)}%';
        final b = t.breadth;
        return [
          SectionHeader(left: '每日市場分數（短期廣度，短線分頁用）', right: a.latestDate),
          Card(
            color: regimeColor(r).withValues(alpha: .08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ScoreBadge(score: t.score, size: 84, caption: '市場分數'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tag(r?.label ?? '資料不足', regimeColor(r), filled: true),
                        const SizedBox(height: 6),
                        if (r != null)
                          Text(
                            '建議最大總曝險 ${r.exposure}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        const SizedBox(height: 4),
                        Text(r?.attitude ?? '資料不足，至少需要約 20 個交易日才能算分數。', style: const TextStyle(fontSize: 13)),
                        if (r != null)
                          Text(
                            '個股推薦門檻：總分 ≥ ${r.minTotalScore > 100 ? '—（停止新單）' : r.minTotalScore.toStringAsFixed(0)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (t.warnings.isNotEmpty) SectionCard(title: '風險提醒', child: Bullets(t.warnings, BulletKind.warn)),
          SectionCard(
            title: '分數怎麼來的',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Market Score 不預測指數點數，只把市場分類成可交易的「狀態」（規格書 §2）。'
                  '趨勢用${t.usesTaiex ? '加權指數' : '全市場等權指數（本機還沒有加權指數資料）'}，其餘都用全市場股票的廣度。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                for (final c in t.components)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScoreBar(
                          label: c.name,
                          score: c.value == null ? null : c.value! * 100,
                          trailing: '權重 ${c.weight.toStringAsFixed(0)}',
                          subtitle: c.explain,
                        ),
                        if (c.detail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(c.detail, style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: '今日市場廣度（一般股票，不含 ETF）',
            child: StatGrid(
              bare: true,
              stats: [
                ('上漲／下跌', '${b.adv}／${b.dec}', null),
                ('漲停／跌停', '${b.limitUp}／${b.limitDown}', null),
                ('站上 20 日線', pct(b.pctAbove20), null),
                ('站上 60 日線', pct(b.pctAbove60), null),
                ('站上 120 日線', pct(b.pctAbove120), null),
                ('站上 240 日線', pct(b.pctAbove240), null),
                ('20 日新高／新低', '${b.nh20}／${b.nl20}', null),
                ('60 日新高／新低', '${b.nh60}／${b.nl60}', null),
                ('250 日新高／新低', b.n240 == 0 && b.nh250 == 0 ? '資料不足' : '${b.nh250}／${b.nl250}', null),
                if (b.taiex != null) ('加權指數', f2(b.taiex!), null),
              ],
            ),
          ),
          if (t.notes.isNotEmpty) SectionCard(title: '結構觀察', child: Bullets(t.notes, BulletKind.info)),
          SectionCard(
            title: 'Market Score 走勢',
            child: SimpleChart(
              height: 180,
              minY: 0,
              maxY: 100,
              yFormat: (v) => v.toStringAsFixed(0),
              bands: [
                ChartBand(80, 100, regimeColor(Regime.strongBull).withValues(alpha: .10)),
                ChartBand(65, 80, regimeColor(Regime.bull).withValues(alpha: .08)),
                ChartBand(50, 65, regimeColor(Regime.range).withValues(alpha: .08)),
                ChartBand(35, 50, regimeColor(Regime.weak).withValues(alpha: .08)),
                ChartBand(0, 35, regimeColor(Regime.bear).withValues(alpha: .10)),
              ],
              series: [
                ChartSeries(
                  'Market Score',
                  [for (final d in shown) d.score],
                  Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ],
              startLabel: shown.first.date,
              endLabel: shown.last.date,
            ),
          ),
          SectionCard(
            title: '站上均線的股票比例',
            child: SimpleChart(
              height: 160,
              minY: 0,
              maxY: 100,
              yFormat: (v) => '${v.toStringAsFixed(0)}%',
              series: [
                ChartSeries('站上 20 日線', [
                  for (final d in shown) d.breadth.pctAbove20 == null ? null : d.breadth.pctAbove20! * 100,
                ], Colors.orange),
                ChartSeries('站上 60 日線', [
                  for (final d in shown) d.breadth.pctAbove60 == null ? null : d.breadth.pctAbove60! * 100,
                ], Colors.purple),
              ],
              startLabel: shown.first.date,
              endLabel: shown.last.date,
            ),
          ),
          SectionCard(
            title: t.usesTaiex ? '加權指數' : '全市場等權指數',
            child: SimpleChart(
              height: 160,
              series: [
                ChartSeries(
                  t.usesTaiex ? '加權指數' : '等權指數',
                  [for (final d in shown) t.usesTaiex ? d.breadth.taiex : d.breadth.ewIndex],
                  Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                ChartSeries('上市等權', [
                  for (final d in shown) t.usesTaiex ? null : d.breadth.ewTwse,
                ], Colors.teal.withValues(alpha: .6)),
                ChartSeries('上櫃等權', [
                  for (final d in shown) t.usesTaiex ? null : d.breadth.ewTpex,
                ], Colors.indigo.withValues(alpha: .6)),
              ],
              startLabel: shown.first.date,
              endLabel: shown.last.date,
            ),
          ),
          const SectionCard(
            title: '規格書對照（§2.5 市場狀態分類）',
            child: Column(
              children: [
                KvRow('80–100 強勢多頭', '曝險 80–90%', note: '可積極使用突破與趨勢策略'),
                KvRow('65–79 一般多頭', '曝險 60–70%', note: '正常交易，保留現金'),
                KvRow('50–64 震盪', '曝險 30–40%', note: '降低追價、提高門檻；只有這時啟用 D 均值回歸'),
                KvRow('35–49 弱勢', '曝險 10–20%', note: '少量、短週期、嚴格風控'),
                KvRow('0–34 空頭／極端風險', '曝險 0–10%', note: '停止一般多單'),
              ],
            ),
          ),
          const Text(
            '尚未納入：全球風險環境（美股、費半、VIX、匯率、台指期夜盤，§2.4）、60／15 分鐘盤中週期（§2.1）——需要另外的資料來源。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          const DisclaimerCard(text: '市場分數描述的是「現在的環境」，不是預測明天漲跌。'),
        ];
      },
    );
  }
}

/// 長期組合用的市場環境（每月檢視日調整股票比例），含國際指標。
class _LongTermExposure extends StatelessWidget {
  const _LongTermExposure();

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    final r = lt.result;
    if (r == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('下載長期資料包之後，這裡會顯示長期組合建議的股票比例，以及費半、Nasdaq、VIX、匯率、美債等國際指標。'),
        ),
      );
    }
    return ExposureCard(r.exposure, mode: lt.cfg.exposure);
  }
}
