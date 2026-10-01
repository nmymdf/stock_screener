/// 「持股」：我投資了哪些股票，每天收盤後告訴我每一檔要保留、注意、出場還是停損。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/stock_catalog.dart';
import '../../data/stock_industry.dart';
import '../../logic/holding_eval.dart';
import '../../models/holding.dart';
import '../format.dart';
import '../holding_helpers.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
      ..sort((a, b) => a.$2.state.urgency.compareTo(b.$2.state.urgency));
    final closed = holdings.closed;
    final stats = tradeStats(holdings.all);
    var value = 0.0, unreal = 0.0;
    for (final (_, e) in open) {
      value += e.marketValue ?? 0;
      unreal += e.unrealized ?? 0;
    }
    int count(HoldState s) => open.where((x) => x.$2.state == s).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('我的持股', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            if (store.latestDate != null)
              Text('依 ${store.latestDate} 收盤判斷', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        if (store.syncing || store.missingDates().isNotEmpty) const SyncStatusCard(),
        if (open.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatGrid(
                    bare: true,
                    stats: [
                      ('持有', '${open.length} 檔', null),
                      ('市值', f0(value), null),
                      ('未實現損益', moneyTxt(unreal), changeColor(context, unreal)),
                      ('已實現損益', moneyTxt(stats.realized), changeColor(context, stats.realized)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final s in [HoldState.stopLoss, HoldState.exit, HoldState.watch, HoldState.hold])
                        if (count(s) > 0)
                          Row(mainAxisSize: MainAxisSize.min, children: [StateChip(s), Text(' ${count(s)} 檔')]),
                    ],
                  ),
                  if (count(HoldState.stopLoss) + count(HoldState.exit) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '今天有 ${count(HoldState.stopLoss) + count(HoldState.exit)} 檔需要處理，排在最上面。',
                        style: TextStyle(color: stateColor(HoldState.stopLoss), fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
              '每天收盤資料更新後，每一檔會自動標成：保留、注意、建議出場、停損，並寫出理由。',
              '停損只會往上調、不會往下；只加贏家，虧損時加碼會警告「禁止向下攤平」。',
              '賣出時記錄下來，累積成你自己的交易紀錄和績效。',
            ], BulletKind.info),
          ),
        for (final (h, e) in open) _HoldingCard(h: h, e: e),
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
    final c = stateColor(e.state);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: e.state == HoldState.hold ? Theme.of(context).colorScheme.outlineVariant : c,
          width: e.state == HoldState.hold ? 1 : 2,
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
                  StateChip(e.state),
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
              const SizedBox(height: 6),
              Text(
                e.headline,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: e.state == HoldState.hold ? null : c,
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
