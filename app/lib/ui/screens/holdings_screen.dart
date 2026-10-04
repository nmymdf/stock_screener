/// 「持股」：我投資了哪些股票，每天收盤後告訴我每一檔要續抱、注意、加碼、
/// 先賣一半、出場還是停損；最上面是今日摘要和明天要盯的價位。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../layout.dart';
import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/stock_catalog.dart';
import '../../data/stock_industry.dart';
import '../../logic/engine/horizon.dart';
import '../../logic/holding_eval.dart';
import '../../models/holding.dart';
import '../format.dart';
import '../holding_helpers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/horizon_widgets.dart';
import '../widgets/score_widgets.dart';
import '../widgets/sync_status.dart';
import 'holding_detail_screen.dart';
import 'holding_forms.dart';

class HoldingsScreen extends StatefulWidget {
  const HoldingsScreen({super.key});

  @override
  State<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends State<HoldingsScreen> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final holdings = context.watch<HoldingsStore>();
    final store = context.watch<HistoryStore>();
    final open = [for (final h in holdings.open) (h, evalFor(context, h))]
      ..sort((a, b) => a.$2.action.index.compareTo(b.$2.action.index));
    final closed = holdings.closed;
    final stats = tradeStats(holdings.all);
    final discipline = disciplineStats([for (final (_, e) in open) e, for (final h in closed) evalFor(context, h)]);
    var value = 0.0, unreal = 0.0;
    for (final (_, e) in open) {
      value += e.marketValue ?? 0;
      unreal += e.unrealized ?? 0;
    }

    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeader(
          icon: Icons.account_balance_wallet,
          title: '我的持股',
          subtitle: '每天收盤後告訴你每一檔要續抱、注意、加碼、先賣一半、出場還是停損，並寫出原因',
          trailing: store.latestDate == null
              ? null
              : Text('依 ${store.latestDate} 收盤判斷', style: Theme.of(context).textTheme.bodySmall),
        ),
        if (store.syncing || store.missingDates().isNotEmpty) const SyncStatusCard(),
        if (open.isNotEmpty) _TodaySummary(open: open, value: value, unreal: unreal, realized: stats.realized),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddHoldingPage())),
          icon: const Icon(Icons.add),
          label: const Text('新增持股'),
        ),
        const SizedBox(height: 8),
        if (open.isEmpty)
          const SectionCard(
            title: '持股追蹤怎麼用',
            child: Bullets([
              '按「新增持股」填股票、買進價、股數、日期，或在推薦的個股報告按「我已進場」，自動帶入停損和目標。',
              '選持有方式：短線、波段、長期或自己設定，每種有不同的停損和出場規則。',
              '每天收盤資料更新後，每一檔會給一個持續建議：續抱、續抱但注意、可以加碼、先賣一半、出場、停損，並寫出原因。',
              '從買進那天起每個交易日都有一筆紀錄：收盤、損益、停損、當天發生的事、建議和原因。',
              '每天檢查「買進理由還成立嗎」（健康度），理由一項項失效時，跌破停損前就先提醒。',
              '明日劇本：收盤在哪個價位該做什麼，前一晚就知道。',
              '停損只會往上調、不會往下；只加贏家，虧損時加碼會警告「禁止向下攤平」。',
              '賣出時記錄下來，累積成你自己的交易紀錄、績效和紀律分數。',
            ], BulletKind.info),
          ),
        CardGrid(
          children: [for (final (h, e) in open) _HoldingCard(h: h, e: e)],
        ),
        if (closed.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: '交易紀錄（已全部賣出 ${stats.closed} 筆）',
            trailing: TextButton(
              onPressed: () => setState(() => _showClosed = !_showClosed),
              child: Text(_showClosed ? '收起' : '展開'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatGrid(
                  bare: true,
                  stats: [
                    ('勝率', '${(stats.winRate * 100).toStringAsFixed(0)}%', null),
                    ('賺錢', '${stats.wins} 筆', null),
                    ('平均賺', moneyTxt(stats.avgWin), changeColor(context, stats.avgWin)),
                    ('平均賠', moneyTxt(stats.avgLoss), changeColor(context, stats.avgLoss)),
                    ('已實現合計', moneyTxt(stats.realized), changeColor(context, stats.realized)),
                  ],
                ),
                if (!discipline.isEmpty) ...[const SizedBox(height: 8), _DisciplineRow(d: discipline)],
                if (_showClosed) ...[const SizedBox(height: 8), for (final h in closed) _ClosedRow(h: h)],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        const DisclaimerCard(text: '持股狀態是依規則在收盤後機械化判斷的提醒，不會自動下單，也不是投資建議。股利沒有算進已實現損益。'),
      ],
    );
  }
}

class _HoldingCard extends StatelessWidget {
  final Holding h;
  final HoldingEval e;
  const _HoldingCard({required this.h, required this.e});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final c = actionColor(e.action);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: e.action == DailyAction.hold ? Theme.of(context).colorScheme.outlineVariant : c,
          width: e.action == DailyAction.hold ? 1 : 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HoldingDetailScreen(id: h.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ActionTag(e.action),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Tag(h.style.label, Colors.blueGrey),
                ],
              ),
              if (e.health != null || e.durationNow != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    if (e.health != null) HealthTag(e.health!),
                    if (e.durationNow != null)
                      Tag('D${e.durationNow} ${kDurationRange[e.durationNow]}', Colors.blueGrey),
                    if (e.summary != null) Tag('持有第 ${e.summary!.days} 天', Colors.blueGrey),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(
                e.headline,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: e.action == DailyAction.hold ? null : c,
                ),
              ),
              if (e.addOn != null)
                Padding(padding: const EdgeInsets.only(top: 4), child: Bullets([e.addOn!], BulletKind.good)),
              const Divider(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 2,
                children: [
                  Text('${h.shares} 股 · 成本 ${f2(h.avgCost)}', style: small),
                  if (e.lastClose != null) Text('現價 ${f2(e.lastClose!)}', style: small),
                  if (e.unrealized != null)
                    Text(
                      '損益 ${moneyTxt(e.unrealized!)}（${pctTxt(e.unrealizedPct)}）',
                      style: small?.copyWith(color: changeColor(context, e.unrealized!), fontWeight: FontWeight.w600),
                    ),
                  if (e.stop != null) Text('停損 ${f2(e.stop!)}', style: small),
                  if (e.target != null && !e.halfDone && e.state != HoldState.stopLoss)
                    Text('目標 ${f2(e.target!)}', style: small),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClosedRow extends StatelessWidget {
  final Holding h;
  const _ClosedRow({required this.h});

  @override
  Widget build(BuildContext context) {
    final r = realizedPnl(h, securityTypeOf(h.code));
    return InfoRow(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HoldingDetailScreen(id: h.id))),
      title: Text('${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}'),
      subtitle: Text(
        '${h.firstBuyDate} 買 → ${h.lastSellDate} 賣 · ${h.sells.map((s) => s.reason ?? '').where((x) => x.isNotEmpty).join('、')}',
      ),
      trailingTop: Text(moneyTxt(r), style: TextStyle(color: changeColor(context, r))),
    );
  }
}

/// 今日摘要：總覽數字、依建議分組的持股、明天要盯的價位。
class _TodaySummary extends StatelessWidget {
  final List<(Holding, HoldingEval)> open;
  final double value, unreal, realized;
  const _TodaySummary({required this.open, required this.value, required this.unreal, required this.realized});

  @override
  Widget build(BuildContext context) {
    String name(Holding h) => '${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}'.trim();
    final groups = <DailyAction, List<Holding>>{};
    for (final (h, e) in open) {
      (groups[e.action] ??= []).add(h);
    }
    final urgent = open.where((x) => x.$2.action.needsAction).length;
    final watchLines = <String>[];
    for (final (h, e) in open) {
      if (e.scenario.isEmpty) continue;
      final s = e.scenario.first;
      watchLines.add('${name(h)}：${s.when} → ${s.action}');
    }
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('今日摘要', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            StatGrid(
              bare: true,
              stats: [
                ('持有', '${open.length} 檔', null),
                ('市值', f0(value), null),
                ('未實現損益', moneyTxt(unreal), changeColor(context, unreal)),
                ('已實現損益', moneyTxt(realized), changeColor(context, realized)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              urgent > 0 ? '今天有 $urgent 檔需要處理（排在最上面）' : '今天沒有需要出場的持股',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: urgent > 0 ? actionColor(DailyAction.stopLoss) : actionColor(DailyAction.hold),
              ),
            ),
            const SizedBox(height: 6),
            for (final a in DailyAction.values)
              if (groups[a] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 132,
                        child: Align(alignment: Alignment.centerLeft, child: ActionTag(a)),
                      ),
                      Expanded(child: Text(groups[a]!.map(name).join('、'), style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
            if (watchLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('明天要盯的價位', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              for (final l in watchLines.take(6)) Text('• $l', style: small?.copyWith(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DisciplineRow extends StatelessWidget {
  final DisciplineStats d;
  const _DisciplineRow({required this.d});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (d.judged > 0) '出場訊號準時處理 ${d.onTime}／${d.judged}（${(d.rate * 100).toStringAsFixed(0)}%）',
      if (d.late > 0) '晚處理平均晚 ${d.avgDelay.toStringAsFixed(1)} 天、多賠約 ${f0(d.lateCost)} 元',
      if (d.pending > 0) '${d.pending} 個出場訊號還沒處理',
      if (d.early > 0) '${d.early} 次在訊號前自己先賣',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('你的紀律', style: TextStyle(fontWeight: FontWeight.w600)),
        Text(parts.join('；'), style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
