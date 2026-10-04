/// 個股報告的長期部分：總分、六大類分數、白話數據、含息走勢、營收、配息。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/factors.dart';
import '../../core/lt_analysis.dart';
import '../../core/pack.dart';
import '../../data/longterm_store.dart';
import '../../data/stock_industry.dart';
import '../theme.dart';
import 'charts.dart';
import 'lt_widgets.dart';
import 'score_widgets.dart';

/// 左欄：總分與理由、六大類、白話數據。
List<Widget> ltLeftCards(BuildContext context, String code) {
  final lt = context.watch<LongTermStore>();
  final r = lt.result;
  if (r == null) return const [];
  final s = r.scoreOf(code);
  if (s == null) {
    final why = r.data.stock(code) == null
        ? (RegExp(r'^[1-9]\d{3}$').hasMatch(code) ? '長期評分只涵蓋上市普通股（這檔可能是上櫃）。' : 'ETF、特別股不做個股的長期評分。')
        : '上市未滿一年、或近期停止交易，資料不足以評分。';
    return [
      SectionCard(
        title: '長期評分',
        child: Text(why, style: const TextStyle(fontSize: 13)),
      ),
    ];
  }
  return [
    _LtHeader(r: r, s: s),
    SectionCard(title: '六大類分數（全市場百分位）', child: LtGroupBars(s)),
    SectionCard(
      title: '長期數據',
      child: Column(children: [for (final (k, v, note) in ltFacts(s)) KvRow(k, v, note: note)]),
    ),
  ];
}

/// 只要總分與理由那一張（持股詳細頁用）。
class LtSummaryCard extends StatelessWidget {
  final String code;
  const LtSummaryCard({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final r = context.watch<LongTermStore>().result;
    final s = r?.scoreOf(code);
    if (r == null || s == null) return const SizedBox.shrink();
    return _LtHeader(r: r, s: s);
  }
}

/// 右欄：含息走勢、營收、配息。
List<Widget> ltRightCards(BuildContext context, String code) {
  final r = context.watch<LongTermStore>().result;
  if (r == null || r.data.stock(code) == null) return const [];
  return [_TrChart(r: r, code: code), _Revenue(r: r, code: code), _Dividends(r: r, code: code)];
}

class _LtHeader extends StatelessWidget {
  final LtResult r;
  final LtScore s;
  const _LtHeader({required this.r, required this.s});

  @override
  Widget build(BuildContext context) {
    final total = r.live.ranked.length;
    final held = r.sim.holdings.containsKey(s.si);
    final ind = industryOf(s.code);
    final timing = entryTiming(shortReportOf(context, s.code), s);
    final hl = ltHighlights(s);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ScoreBadge(score: s.composite, size: 64, caption: '長期'),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rankText(s, total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        [?ind, if (held) '在理想組合裡', if (s.pct >= 0.9 && !held) '前 10%：可以列入候選'].join('・'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (s.flags.isNotEmpty) ...[const SizedBox(height: 4), LtFlagTags(s.flags, showIlliquid: true)],
                    ],
                  ),
                ),
              ],
            ),
            if (hl.isNotEmpty) ...[const SizedBox(height: 8), Bullets(hl, BulletKind.good)],
            if (s.broken) ...[
              const SizedBox(height: 4),
              Bullets(['長期理由已經破壞（年線下彎又營收衰退、虧損又轉弱，或排名掉到後 15%）：持有的話建議換掉'], BulletKind.bad),
            ],
            for (final f in s.flags)
              if (f != LtFlag.illiquid || !s.investable) Bullets([f.explain], BulletKind.warn),
            if (timing != null) ...[
              const SizedBox(height: 4),
              Text('進場時機（參考短線）：${timing.$1}', style: TextStyle(fontSize: 13, color: timing.$2)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrChart extends StatelessWidget {
  final LtResult r;
  final String code;
  const _TrChart({required this.r, required this.code});

  @override
  Widget build(BuildContext context) {
    final st = r.data.stock(code)!;
    final end = r.data.nd - 1;
    final start = math.max(st.start, end - 250 * 5);
    final a0 = st.trAt(start);
    final b0 = r.data.tri[start].isNaN ? r.data.taiex[start] : r.data.tri[start];
    final n = end - start + 1;
    final step = math.max(1, n ~/ 360);
    final mine = <double?>[], bench = <double?>[];
    for (var t = start; t <= end; t += step) {
      final a = st.trAt(t);
      final b = r.data.tri[t].isNaN ? r.data.taiex[t] : r.data.tri[t];
      mine.add(a.isNaN || a0.isNaN ? null : a / a0);
      bench.add(b.isNaN || b0.isNaN ? null : b / b0);
    }
    final hist = r.pctHistory(code);
    final last = mine.lastWhere((x) => x != null, orElse: () => null);
    final lastB = bench.lastWhere((x) => x != null, orElse: () => null);
    final years = n / 250;
    return SectionCard(
      title: '含息走勢 vs 加權報酬指數（近 ${years.toStringAsFixed(years < 4.5 ? 1 : 0)} 年）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SimpleChart(
            height: 200,
            series: [
              ChartSeries(code, mine, AppColors.up, width: 2),
              ChartSeries(r.data.hasTri ? '加權報酬指數' : '加權指數', bench, Colors.blueGrey),
            ],
            startLabel: r.data.dates[start],
            endLabel: r.data.dates[end],
            yFormat: (v) => v.toStringAsFixed(1),
          ),
          if (last != null && lastB != null)
            Text(
              '這段期間含息報酬 ${sp(last - 1, 0)}，指數 ${sp(lastB - 1, 0)}（股價已還原除權息，配息當作再投入）。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (hist.length >= 6) ...[
            const SizedBox(height: 10),
            Text('長期總分百分位走勢（每月）', style: Theme.of(context).textTheme.bodySmall),
            SimpleChart(
              height: 90,
              series: [
                ChartSeries('百分位', [
                  for (final h in hist.skip(math.max(0, hist.length - 60))) h.$2 * 100,
                ], AppColors.accent),
              ],
              minY: 0,
              maxY: 100,
              startLabel: hist[math.max(0, hist.length - 60)].$1,
              endLabel: hist.last.$1,
              yFormat: (v) => v.toStringAsFixed(0),
            ),
          ],
        ],
      ),
    );
  }
}

class _Revenue extends StatelessWidget {
  final LtResult r;
  final String code;
  const _Revenue({required this.r, required this.code});

  @override
  Widget build(BuildContext context) {
    final rev = r.data.revenue;
    final last = rev.lastIdxOf(code);
    if (last == null) return const SizedBox.shrink();
    final rows = <(String, double, double?)>[];
    for (var k = last; k > last - 24 && k >= rev.startIdx; k--) {
      final v = rev.at(code, k);
      if (v == null) continue;
      final ly = rev.lastYearAt(code, k);
      rows.add((RevenueData.monthOf(k), v, ly == null || ly <= 0 ? null : v / ly - 1));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final chrono = rows.reversed.toList();
    return SectionCard(
      title: '月營收（近 24 個月）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SimpleChart(
            height: 120,
            series: [
              ChartSeries(
                '年增率 %',
                [for (final x in chrono) x.$3 == null ? null : x.$3! * 100],
                AppColors.accent,
                width: 2,
              ),
            ],
            lines: const [ChartLine('0%', 0, Colors.grey)],
            startLabel: chrono.first.$1,
            endLabel: chrono.last.$1,
            yFormat: (v) => '${v.toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 6),
          for (final x in rows.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text(x.$1, style: const TextStyle(fontSize: 13))),
                  Expanded(child: Text('${(x.$2 / 1e5).toStringAsFixed(2)} 億', style: const TextStyle(fontSize: 13))),
                  Text(
                    x.$3 == null ? '—' : '年增 ${sp(x.$3!)}',
                    style: TextStyle(fontSize: 13, color: x.$3 == null ? null : changeColor(context, x.$3!)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Dividends extends StatelessWidget {
  final LtResult r;
  final String code;
  const _Dividends({required this.r, required this.code});

  @override
  Widget build(BuildContext context) {
    final ev = r.data.dividends.byCode[code];
    if (ev == null || ev.isEmpty) return const SizedBox.shrink();
    final recent = ev.reversed.take(8).toList();
    final byYear = <String, double>{};
    for (final e in ev) {
      byYear[e.date.substring(0, 4)] = (byYear[e.date.substring(0, 4)] ?? 0) + e.value;
    }
    final years = byYear.keys.toList()..sort();
    return SectionCard(
      title: '除權息紀錄',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '每年合計（權值＋息值）：${years.reversed.take(6).map((y) => '$y ${byYear[y]!.toStringAsFixed(2)}').join('、')}',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 6),
          for (final e in recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 96, child: Text(e.date, style: const TextStyle(fontSize: 13))),
                  Tag(e.kind, e.cash ? AppColors.accent : const Color(0xFFC98A00)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('每股 ${e.value.toStringAsFixed(2)} 元', style: const TextStyle(fontSize: 13))),
                  Text('前收 ${e.before.toStringAsFixed(1)}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
