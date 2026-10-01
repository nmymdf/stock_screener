/// 一筆持股的詳細：今天的建議與理由、成本與損益、停損怎麼一路上調、
/// 持有方式的規則、走勢圖（成本線、停損線、目標線）、買賣紀錄。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/stock_catalog.dart';
import '../../logic/holding_eval.dart';
import '../../models/holding.dart';
import '../format.dart';
import '../holding_helpers.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/score_widgets.dart';
import 'holding_forms.dart';
import 'stock_report_screen.dart';

class HoldingDetailScreen extends StatelessWidget {
  final String id;
  const HoldingDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final holdings = context.watch<HoldingsStore>();
    final h = holdings.byId(id);
    if (h == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('這筆持股已經刪除')),
      );
    }
    final e = evalFor(context, h);
    final name = kBuiltinStocksByCode[h.code]?.name ?? '';
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(
        title: Text('${h.code} $name'),
        actions: [
          IconButton(
            tooltip: '修改設定',
            icon: const Icon(Icons.edit),
            onPressed: () => push(EditHoldingPage(holding: h)),
          ),
          IconButton(
            tooltip: '刪除這筆持股',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, h),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: stateColor(e.state), width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StateChip(e.state, big: true),
                          const Spacer(),
                          if (e.asOf != null) Text('依 ${e.asOf} 收盤', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(e.headline, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if (e.reasons.isNotEmpty) ...[const SizedBox(height: 6), Bullets(e.reasons, BulletKind.info)],
                      if (e.addOn != null) ...[
                        const SizedBox(height: 6),
                        Bullets([e.addOn!], BulletKind.good),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (!h.closed)
                            FilledButton.icon(
                              onPressed: () => push(SellPage(holding: h, eval: e)),
                              icon: const Icon(Icons.sell_outlined, size: 18),
                              label: const Text('記錄賣出'),
                            ),
                          if (!h.closed)
                            OutlinedButton.icon(
                              onPressed: () => push(AddHoldingPage(code: h.code)),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('加碼（記錄買進）'),
                            ),
                          TextButton(
                            onPressed: () => push(StockReportScreen(code: h.code)),
                            child: const Text('看個股分析'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SectionCard(
                title: '成本與損益',
                child: Column(
                  children: [
                    KvRow('持有股數', '${h.shares} 股${h.soldShares > 0 ? '（已賣出 ${h.soldShares} 股）' : ''}'),
                    KvRow('平均成本', f2(h.avgCost)),
                    if (e.lastClose != null)
                      KvRow('現價', '${f2(e.lastClose!)}${e.changePct == null ? '' : '（今日 ${pctTxt(e.changePct)}）'}'),
                    if (e.marketValue != null && h.shares > 0) KvRow('市值', f0(e.marketValue!)),
                    if (e.unrealized != null && h.shares > 0)
                      KvRow(
                        '未實現損益',
                        '${moneyTxt(e.unrealized!)}（${pctTxt(e.unrealizedPct)}）',
                        color: changeColor(context, e.unrealized!),
                        note: '已扣掉預估的賣出手續費和證交稅',
                      ),
                    KvRow('已實現損益', moneyTxt(e.realized), color: changeColor(context, e.realized)),
                    if (e.rNow != null && h.shares > 0)
                      KvRow(
                        '目前賺賠（R）',
                        '${e.rNow! >= 0 ? '+' : ''}${e.rNow!.toStringAsFixed(2)} R',
                        note: '1R = 進場價到起始停損的距離（每股 ${e.risk == null ? '—' : f2(e.risk!)}）。+1R 代表賺到一倍風險。',
                      ),
                  ],
                ),
              ),
              if (!h.closed && e.stop != null)
                SectionCard(
                  title: '停損與目標',
                  child: Column(
                    children: [
                      KvRow(
                        '目前停損',
                        '${f2(e.stop!)}（距離 ${e.distToStopPct?.toStringAsFixed(1) ?? '—'}%）',
                        color: AppColors.down,
                        note: '收盤跌破就出場。停損只會往上調、不會往下。',
                      ),
                      if (e.initialStop != null) KvRow('起始停損', f2(e.initialStop!)),
                      if (e.target != null && e.state != HoldState.stopLoss)
                        KvRow(
                          h.style == HoldStyle.short ? '2R 目標（先賣一半）' : '目標價',
                          f2(e.target!),
                          color: AppColors.up,
                          note: e.halfDone ? '已經到過目標、也記錄了賣出' : null,
                        ),
                    ],
                  ),
                ),
              SectionCard(
                title: '持有方式：${h.style.label}（${h.style.period}）',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.style.rules, style: const TextStyle(fontSize: 13, height: 1.5)),
                    if (e.notes.isNotEmpty) ...[const SizedBox(height: 8), Bullets(e.notes, BulletKind.info)],
                    if (h.reason != null) ...[
                      const SizedBox(height: 8),
                      Text('當初買進理由（${h.strategy ?? ''}）：${h.reason}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (h.note != null) ...[
                      const SizedBox(height: 4),
                      Text('備註：${h.note}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              _Chart(h: h, e: e),
              SectionCard(
                title: '買賣紀錄',
                child: Column(
                  children: [
                    for (final (i, b) in h.buys.indexed)
                      _RecordRow(
                        label: '買進',
                        date: b.date,
                        price: b.price,
                        shares: b.shares,
                        color: AppColors.up,
                        onDelete: h.buys.length <= 1
                            ? null
                            : () => context.read<HoldingsStore>().upsert(h.copyWith(buys: [...h.buys]..removeAt(i))),
                      ),
                    for (final (i, s) in h.sells.indexed)
                      _RecordRow(
                        label: '賣出${s.reason == null ? '' : '（${s.reason}）'}',
                        date: s.date,
                        price: s.price,
                        shares: s.shares,
                        color: AppColors.down,
                        onDelete: () =>
                            context.read<HoldingsStore>().upsert(h.copyWith(sells: [...h.sells]..removeAt(i))),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Holding h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除這筆持股？'),
        content: const Text('會刪掉這檔的所有買賣紀錄。如果只是賣掉了，請用「記錄賣出」，交易紀錄才會留下來。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<HoldingsStore>().remove(h.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _RecordRow extends StatelessWidget {
  final String label, date;
  final double price;
  final int shares;
  final Color color;
  final VoidCallback? onDelete;
  const _RecordRow({
    required this.label,
    required this.date,
    required this.price,
    required this.shares,
    required this.color,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Tag(label, color),
        const SizedBox(width: 8),
        Expanded(child: Text('$date · ${f2(price)} × $shares 股', style: const TextStyle(fontSize: 13))),
        if (onDelete != null)
          IconButton(
            tooltip: '刪除這筆紀錄（輸入錯誤時用）',
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
          ),
      ],
    ),
  );
}

class _Chart extends StatelessWidget {
  final Holding h;
  final HoldingEval e;
  const _Chart({required this.h, required this.e});

  @override
  Widget build(BuildContext context) {
    final bars = context.watch<HistoryStore>().seriesOf(h.code);
    if (bars.length < 2 || e.pathDates.isEmpty) return const SizedBox.shrink();
    final startIdx = bars.indexWhere((b) => b.date == e.pathDates.first);
    if (startIdx < 0) return const SizedBox.shrink();
    final from = math.max(0, startIdx - 40);
    final shown = bars.sublist(from);
    final stopByDate = {for (var i = 0; i < e.pathDates.length; i++) e.pathDates[i]: e.stopPath[i]};
    return SectionCard(
      title: '走勢與停損（買進前 40 天起）',
      child: SimpleChart(
        height: 220,
        series: [
          ChartSeries('收盤', [for (final b in shown) b.close], Theme.of(context).colorScheme.primary, width: 2),
          ChartSeries('停損（一路上調）', [for (final b in shown) stopByDate[b.date]], AppColors.down, width: 1.6),
        ],
        lines: [
          ChartLine('成本', h.avgCost, Colors.grey),
          if (e.target != null && !e.halfDone) ChartLine('目標', e.target!, AppColors.up),
        ],
        startLabel: shown.first.date,
        endLabel: shown.last.date,
      ),
    );
  }
}
