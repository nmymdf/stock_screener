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
import '../../core/factors.dart';
import '../holding_helpers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/horizon_widgets.dart';
import '../widgets/lt_widgets.dart';
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
  bool _showNormal = false;
  bool _table = false;
  HoldingSource _source = HoldingSource.manual;
  bool _picked = false;

  static String _groupName(HoldingSource s) => s == HoldingSource.manual ? '手動／模擬' : 'stock_acc 記帳';

  @override
  Widget build(BuildContext context) {
    final holdings = context.watch<HoldingsStore>();
    final store = context.watch<HistoryStore>();
    final showAcc = holdings.accAvailable;
    // 還沒自己切換過：手動那組是空的、stock_acc 有持股，就直接打開 stock_acc 那組
    final manualOpen = holdings.manual.where((h) => !h.closed).length;
    final accOpen = holdings.accHoldings.where((h) => !h.closed).length;
    final src = !showAcc
        ? HoldingSource.manual
        : (_picked ? _source : (manualOpen == 0 && accOpen > 0 ? HoldingSource.stockAcc : HoldingSource.manual));
    final group = holdings.of(src);
    final open = [for (final h in group.where((h) => !h.closed)) (h, evalFor(context, h))]
      ..sort((a, b) => a.$2.action.index.compareTo(b.$2.action.index));
    final closed = group.where((h) => h.closed).toList()
      ..sort((a, b) => (b.lastSellDate ?? '').compareTo(a.lastSellDate ?? ''));
    final stats = tradeStats(group);
    final discipline = disciplineStats([for (final (_, e) in open) e, for (final h in closed) evalFor(context, h)]);
    var value = 0.0, unreal = 0.0;
    for (final (_, e) in open) {
      value += e.marketValue ?? 0;
      unreal += e.unrealized ?? 0;
    }
    // 長期評分轉弱（理由破壞、排名後 30%）也列在「需要注意」
    bool isNormal(Holding h, HoldingEval e) =>
        (e.action == DailyAction.hold || e.action == DailyAction.pending || e.action == DailyAction.addOn) &&
        ltAlert(ltScoreFor(context, h.code)) == null;
    final attention = open.where((x) => !isNormal(x.$1, x.$2)).toList();
    final normal = open.where((x) => isNormal(x.$1, x.$2)).toList();
    final other = src == HoldingSource.manual ? HoldingSource.stockAcc : HoldingSource.manual;
    final otherUrgent = showAcc
        ? holdings.of(other).where((h) => !h.closed && evalFor(context, h).action.needsAction).length
        : 0;

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
        if (showAcc) ...[
          SegmentedButton<HoldingSource>(
            showSelectedIcon: false,
            segments: [
              for (final s in HoldingSource.values)
                ButtonSegment(
                  value: s,
                  icon: Icon(s == HoldingSource.manual ? Icons.edit_note : Icons.menu_book_outlined, size: 18),
                  label: Text('${_groupName(s)} ${holdings.of(s).where((h) => !h.closed).length}'),
                ),
            ],
            selected: {src},
            onSelectionChanged: (v) => setState(() {
              _source = v.first;
              _picked = true;
            }),
          ),
          const SizedBox(height: 8),
          if (src == HoldingSource.stockAcc) _AccBar(holdings: holdings),
          if (otherUrgent > 0)
            TextButton.icon(
              onPressed: () => setState(() {
                _source = other;
                _picked = true;
              }),
              icon: Icon(Icons.priority_high, color: actionColor(DailyAction.stopLoss), size: 18),
              label: Text(
                '「${_groupName(other)}」有 $otherUrgent 檔需要處理，點這裡切過去',
                style: TextStyle(color: actionColor(DailyAction.stopLoss)),
              ),
            ),
        ],
        _SettingsCard(holdings: holdings, showAcc: showAcc),
        if (open.isNotEmpty) _TodaySummary(open: open, value: value, unreal: unreal, realized: stats.realized),
        if (open.isNotEmpty) _WeeklyCard(open: open),
        const SizedBox(height: 6),
        if (src == HoldingSource.manual)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddHoldingPage())),
            icon: const Icon(Icons.add),
            label: Text(showAcc ? '新增持股（手動／模擬）' : '新增持股'),
          ),
        const SizedBox(height: 8),
        if (open.isEmpty && src == HoldingSource.manual)
          SectionCard(
            title: '持股追蹤怎麼用',
            child: Bullets([
              '按「新增持股」填股票、買進價、股數、日期，或在推薦的個股報告按「我已進場」，自動帶入停損和目標。',
              if (showAcc) '「手動／模擬」可以放沒記在 stock_acc 的股票，或沒有真的買、只想照系統建議追蹤看看的模擬單。',
              '選持有方式：短線、波段、長期或自己設定，每種有不同的停損和出場規則。',
              '每天收盤資料更新後，每一檔會給一個持續建議：續抱、續抱但注意、可以加碼、先賣一半、出場、停損，並寫出原因。',
              '從買進那天起每個交易日都有一筆紀錄：收盤、損益、停損、當天發生的事、建議和原因。',
              '每天檢查「買進理由還成立嗎」（健康度），理由一項項失效時，跌破停損前就先提醒。',
              '明日劇本：收盤在哪個價位該做什麼，前一晚就知道。',
              '停損只會往上調、不會往下；只加贏家，虧損時加碼會警告「禁止向下攤平」。',
              '買賣紀錄可以點開修改或刪除；賣出時記錄下來，累積成你自己的交易紀錄、績效和紀律分數。',
            ], BulletKind.info),
          ),
        if (open.isEmpty && src == HoldingSource.stockAcc && holdings.accError == null)
          const SectionCard(child: Text('stock_acc 目前沒有持有中的股票。在 stock_acc 記帳買進後，回來按「同步 stock_acc」就會出現在這裡。')),
        if (open.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text('持有中 ${open.length} 檔', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined, size: 18), label: Text('卡片')),
                  ButtonSegment(value: true, icon: Icon(Icons.table_rows_outlined, size: 18), label: Text('表格')),
                ],
                selected: {_table},
                onSelectionChanged: (v) => setState(() => _table = v.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_table)
            _HoldingsTable(rows: open)
          else ...[
            if (attention.isNotEmpty) ...[
              Text(
                '需要注意 ${attention.length} 檔',
                style: TextStyle(fontWeight: FontWeight.w700, color: actionColor(DailyAction.caution)),
              ),
              const SizedBox(height: 4),
              CardGrid(
                children: [for (final (h, e) in attention) _HoldingCard(h: h, e: e)],
              ),
            ],
            if (normal.isNotEmpty) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setState(() => _showNormal = !_showNormal),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: actionColor(DailyAction.hold), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '正常 ${normal.length} 檔',
                        style: TextStyle(fontWeight: FontWeight.w700, color: actionColor(DailyAction.hold)),
                      ),
                      const SizedBox(width: 6),
                      if (attention.isNotEmpty) ...[
                        Text(_showNormal ? '收起' : '展開', style: Theme.of(context).textTheme.bodySmall),
                        Icon(_showNormal ? Icons.expand_less : Icons.expand_more, size: 18),
                      ],
                    ],
                  ),
                ),
              ),
              if (_showNormal || attention.isEmpty)
                CardGrid(
                  children: [for (final (h, e) in normal) _HoldingCard(h: h, e: e)],
                ),
            ],
          ],
        ],

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
        DisclaimerCard(
          text:
              '持股狀態是依規則在收盤後機械化判斷的提醒，不會自動下單，也不是投資建議。股利沒有算進已實現損益。'
              '${showAcc ? '「stock_acc 記帳」只讀取這台電腦上 stock_acc 的檔案，不會修改它，也不會傳到任何地方。' : ''}',
        ),
      ],
    );
  }
}

/// stock_acc 這一組最上面：同步按鈕、上次同步時間、讀了幾筆、錯誤訊息。
class _AccBar extends StatelessWidget {
  final HoldingsStore holdings;
  const _AccBar({required this.holdings});

  @override
  Widget build(BuildContext context) {
    final t = holdings.accLastSync;
    String two(int v) => v.toString().padLeft(2, '0');
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: holdings.accSyncing ? null : holdings.syncAcc,
                icon: holdings.accSyncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: const Text('同步 stock_acc'),
              ),
              if (t != null)
                Text(
                  '上次同步 ${two(t.hour)}:${two(t.minute)}・讀到 ${holdings.accTradeCount} 筆交易',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          if (holdings.accError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                holdings.accError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '買賣請在 stock_acc 記帳，記完回來按「同步 stock_acc」。所有帳戶的同一檔股票合併成一筆；'
            '持有方式、停損、備註可以在這裡改，重新同步不會洗掉。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
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
                  ActionTag(e.action, style: h.style),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (h.fromStockAcc) ...[const Tag('stock_acc', Color(0xFF6A4C93)), const SizedBox(width: 4)],
                  Tag(h.style.label, Colors.blueGrey),
                  HoldingMenu(h: h, e: e),
                ],
              ),
              if (e.health != null || e.durationNow != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    if (e.health != null) HealthTag(e.health!),
                    if (e.durationNow != null && h.style != HoldStyle.long)
                      Tag('D${e.durationNow} ${kDurationRange[e.durationNow]}', Colors.blueGrey),
                    if (e.summary != null) Tag('${h.takenOver ? '追蹤' : '持有'}第 ${e.summary!.days} 天', Colors.blueGrey),
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
              _LtLine(code: h.code),
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
                  if (e.stop != null) Text('${h.style == HoldStyle.long ? '防守價' : '停損'} ${f2(e.stop!)}', style: small),
                  if (h.takenOver) Text('${h.trackSince} 起追蹤', style: small),
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

/// 今日摘要：總覽數字、需要注意的（依建議分組）、其他都正常、只列很接近關鍵價位的。
class _TodaySummary extends StatelessWidget {
  final List<(Holding, HoldingEval)> open;
  final double value, unreal, realized;
  const _TodaySummary({required this.open, required this.value, required this.unreal, required this.realized});

  @override
  Widget build(BuildContext context) {
    String name(Holding h) => '${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}'.trim();
    final groups = <String, (DailyAction, HoldStyle, List<Holding>)>{};
    final ltWeak = <Holding>[];
    var normal = 0;
    for (final (h, e) in open) {
      if (e.action == DailyAction.hold || e.action == DailyAction.pending) {
        // 走勢正常、但長期評分轉弱（理由破壞或排名後 30%）
        if (ltAlert(ltScoreFor(context, h.code)) != null) {
          ltWeak.add(h);
        } else {
          normal++;
        }
        continue;
      }
      final label = actionText(e.action, h.style);
      final g = groups[label];
      groups[label] = (e.action, h.style, [...?g?.$3, h]);
    }
    final ordered = groups.values.toList()..sort((a, b) => a.$1.index.compareTo(b.$1.index));
    final attention = open.length - normal;
    // 只列離關鍵價位 3% 以內的
    final near = <(double, String)>[];
    for (final (h, e) in open) {
      final d = e.distToLevelPct, l = e.nearestLevel;
      if (d != null && l != null && d <= 3) {
        near.add((d, '${name(h)}：收盤 < ${f2(l.price)}（差 ${d.toStringAsFixed(1)}%）→ ${l.what}'));
      }
    }
    near.sort((a, b) => a.$1.compareTo(b.$1));
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
              attention > 0 ? '今天需要注意 $attention 檔，其他 $normal 檔正常' : '全部 $normal 檔都正常，今天不用做什麼',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: attention > 0 ? actionColor(DailyAction.caution) : actionColor(DailyAction.hold),
              ),
            ),
            const SizedBox(height: 6),
            for (final (a, style, hs) in ordered)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 132,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ActionTag(a, style: style),
                      ),
                    ),
                    Expanded(child: Text(hs.map(name).join('、'), style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            if (ltWeak.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 132,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Tag('長期評分轉弱', actionColor(DailyAction.caution), filled: true),
                      ),
                    ),
                    Expanded(child: Text(ltWeak.map(name).join('、'), style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            if (near.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('接近關鍵價位（3% 以內）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              for (final l in near.take(8)) Text('• ${l.$2}', style: small?.copyWith(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 週報：最近 5 個交易日的變化。
class _WeeklyCard extends StatelessWidget {
  final List<(Holding, HoldingEval)> open;
  const _WeeklyCard({required this.open});

  @override
  Widget build(BuildContext context) {
    final w = weeklyReport(open, (h) => '${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}'.trim());
    if (w == null) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.event_note_outlined),
          title: const Text('本週報告', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            '${w.from} ～ ${w.to}・市值 ${moneyTxt(w.change)}'
            '${w.quiet ? '・狀態沒有變化' : '・${w.worse.length} 檔變差、${w.better.length} 檔好轉'}',
            style: TextStyle(fontSize: 12, color: changeColor(context, w.change)),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (w.worse.isNotEmpty) ...[
              const Text('狀態變差', style: TextStyle(fontWeight: FontWeight.w700)),
              Bullets(w.worse, BulletKind.warn),
            ],
            if (w.better.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text('狀態好轉', style: TextStyle(fontWeight: FontWeight.w700)),
              Bullets(w.better, BulletKind.good),
            ],
            if (w.up.isNotEmpty) Text('本週漲最多：${w.up.join('、')}', style: const TextStyle(fontSize: 13)),
            if (w.down.isNotEmpty) Text('本週跌最多：${w.down.join('、')}', style: const TextStyle(fontSize: 13)),
            if (w.quiet) const Text('這週所有持股的狀態都沒有改變。', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// 持股設定：stock_acc 的預設持有習慣、長期的回落容忍。
class _SettingsCard extends StatelessWidget {
  final HoldingsStore holdings;
  final bool showAcc;
  const _SettingsCard({required this.holdings, required this.showAcc});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.tune),
          title: const Text('持股設定', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${showAcc ? 'stock_acc 預設：${holdings.accDefaultStyle.label}・' : ''}'
            '長期回落容忍 ${(holdings.drawdownLimit * 100).round()}%',
            style: const TextStyle(fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAcc) ...[
              const Text('stock_acc 同步進來的股票，預設的持有習慣', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in const [HoldStyle.long, HoldStyle.swing, HoldStyle.short])
                    ChoiceChip(
                      label: Text('${s.label}（${s.period}）'),
                      selected: holdings.accDefaultStyle == s,
                      onSelected: (_) => holdings.setAccDefaultStyle(s),
                    ),
                ],
              ),
              Text('個別股票可以在「⋮ → 修改設定」另外改，改過的不受這裡影響。', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
            ],
            const Text('長期持有：從高點回落多少算「考慮減碼」', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final v in const [0.2, 0.25, 0.3, 0.35])
                  ChoiceChip(
                    label: Text('${(v * 100).round()}%'),
                    selected: (holdings.drawdownLimit - v).abs() < 0.001,
                    onSelected: (_) => holdings.setDrawdownLimit(v),
                  ),
              ],
            ),
            Text('回落一半（例如 25% 的一半 12.5%）就先列「觀察」，超過設定值才是「考慮減碼」。', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// 表格：一檔一行，持股多的時候比較好看。
class _HoldingsTable extends StatelessWidget {
  final List<(Holding, HoldingEval)> rows;
  const _HoldingsTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const widths = [118.0, 150.0, 80.0, 86.0, 86.0, 86.0, 110.0, 96.0, 70.0, 92.0];
    const heads = ['狀態', '股票', '股數', '成本', '現價', '損益%', '損益（元）', '離關鍵價', '健康度', '長期排名'];
    Widget cell(int i, Widget child, {bool head = false}) => Container(
      width: widths[i],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      alignment: i >= 2 ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: head ? scheme.surfaceContainerLow : null,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: child,
    );
    Text txt(String s, {Color? color, bool bold = false}) => Text(
      s,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w700 : null),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < heads.length; i++)
                  cell(i, txt(heads[i], bold: true, color: scheme.onSurfaceVariant), head: true),
              ],
            ),
            for (final (h, e) in rows)
              InkWell(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => HoldingDetailScreen(id: h.id))),
                child: Row(
                  children: [
                    cell(0, ActionTag(e.action, style: h.style)),
                    cell(1, txt('${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}', bold: true)),
                    cell(2, txt('${h.shares}')),
                    cell(3, txt(f2(h.avgCost))),
                    cell(4, txt(e.lastClose == null ? '—' : f2(e.lastClose!))),
                    cell(
                      5,
                      txt(pctTxt(e.unrealizedPct), color: changeColor(context, e.unrealizedPct ?? 0), bold: true),
                    ),
                    cell(
                      6,
                      txt(
                        e.unrealized == null ? '—' : moneyTxt(e.unrealized!),
                        color: changeColor(context, e.unrealized ?? 0),
                      ),
                    ),
                    cell(
                      7,
                      txt(
                        e.distToLevelPct == null ? '—' : '${e.distToLevelPct!.toStringAsFixed(1)}%',
                        color: (e.distToLevelPct ?? 99) <= 3 ? actionColor(DailyAction.caution) : null,
                      ),
                    ),
                    cell(
                      8,
                      txt(
                        e.health == null ? '—' : '${e.health}',
                        color: e.health == null ? null : healthColor(e.health!),
                      ),
                    ),
                    cell(
                      9,
                      Builder(
                        builder: (context) {
                          final s = ltScoreFor(context, h.code);
                          return txt(
                            s == null ? '—' : '前 ${((1 - s.pct) * 100).clamp(1, 100).toStringAsFixed(0)}%',
                            color: s == null ? null : (ltAlert(s) != null ? actionColor(DailyAction.caution) : null),
                            bold: s != null && s.pct >= 0.7,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
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

/// 持股卡片上的長期評分：排名、旗標、提醒。
class _LtLine extends StatelessWidget {
  final String code;
  const _LtLine({required this.code});

  @override
  Widget build(BuildContext context) {
    final s = ltScoreFor(context, code);
    if (s == null) return const SizedBox.shrink();
    final alert = ltAlert(s);
    final total = ltTotal(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '長期 ${rankText(s, total)}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pctColor(context, s.pct)),
          ),
          for (final f in s.flags)
            if (f != LtFlag.illiquid) Tag(f.label, ltFlagColor(f)),
          if (alert != null)
            Text(
              '⚠ $alert',
              style: TextStyle(fontSize: 12, color: actionColor(DailyAction.caution), fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}
