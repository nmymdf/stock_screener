/// 一筆持股的詳細：今天的建議與原因、明日劇本、買進理由還成立嗎（健康度）、
/// 持有期間升降級、加碼時機、成本與損益、停損與目標、走勢圖、
/// 從買進到今天每個交易日的追蹤紀錄（含摘要、結案摘要、紀律）、買賣紀錄。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/stock_catalog.dart';
import '../../logic/engine/horizon.dart';
import '../../logic/holding_eval.dart';
import '../../models/holding.dart';
import '../format.dart';
import '../holding_helpers.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/horizon_widgets.dart';
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
          if (!h.fromStockAcc)
            IconButton(
              tooltip: '刪除這筆持股',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDeleteHolding(context, h) && context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: ListView(
            padding: pagePadding(context),
            children: [
              SplitView(
                left: [
                  _TodayCard(h: h, e: e, push: push),
                  if (h.closed && e.summary != null)
                    SectionCard(title: '結案摘要', child: Bullets(e.summary!.lines, BulletKind.info)),
                  if (e.scenario.isNotEmpty) _ScenarioCard(e: e),
                  if (e.thesisNow.isNotEmpty) _ThesisCard(h: h, e: e),
                  if (!h.closed && (e.addOnPlan.isNotEmpty || e.addOnRules.isNotEmpty)) _AddOnCard(e: e),
                  _MoneyCard(h: h, e: e),
                  SectionCard(
                    title: '持有方式：${h.style.label}（${h.style.period}）',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.style.rules, style: const TextStyle(fontSize: 13, height: 1.5)),
                        if (e.notes.isNotEmpty) ...[const SizedBox(height: 8), Bullets(e.notes, BulletKind.info)],
                        if (h.note != null) ...[
                          const SizedBox(height: 4),
                          Text('備註：${h.note}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ],
                right: [
                  _Chart(h: h, e: e),
                  if (e.log.isNotEmpty) _LogCard(h: h, e: e),
                  SectionCard(
                    title: h.fromStockAcc ? '買賣紀錄（來自 stock_acc）' : '買賣紀錄',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, b) in h.buys.indexed)
                          _RecordRow(
                            label: i == 0 ? '買進' : '加碼',
                            date: b.date,
                            price: b.price,
                            shares: b.shares,
                            color: AppColors.up,
                            cost: b.fee == null ? null : '手續費 ${f0(b.fee!)}',
                            onTap: h.fromStockAcc ? null : () => editLotDialog(context, h, buy: true, index: i),
                          ),
                        for (final (i, s) in h.sells.indexed)
                          _RecordRow(
                            label: '賣出${s.reason == null || h.fromStockAcc ? '' : '（${s.reason}）'}',
                            date: s.date,
                            price: s.price,
                            shares: s.shares,
                            color: AppColors.down,
                            cost: s.fee == null && s.tax == null ? null : '手續費 ${f0(s.fee ?? 0)}・稅 ${f0(s.tax ?? 0)}',
                            onTap: h.fromStockAcc ? null : () => editLotDialog(context, h, buy: false, index: i),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          h.fromStockAcc
                              ? '這些紀錄來自 stock_acc，要修改請到 stock_acc，回來在持股頁按「同步 stock_acc」。'
                              : '點任何一筆紀錄可以修改日期、價格、股數，或刪除。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
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

/// 今天的持續建議與原因。
class _TodayCard extends StatelessWidget {
  final Holding h;
  final HoldingEval e;
  final void Function(Widget) push;
  const _TodayCard({required this.h, required this.e, required this.push});

  @override
  Widget build(BuildContext context) {
    final c = actionColor(e.action);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionTag(e.action, big: true, style: h.style),
                if (e.health != null) HealthTag(e.health!),
                if (e.durationNow != null) Tag('D${e.durationNow} ${kDurationRange[e.durationNow]}', Colors.blueGrey),
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
            if (e.styleAdvice != null) ...[
              const SizedBox(height: 6),
              Bullets([e.styleAdvice!], BulletKind.warn),
            ],
            if (e.coneNote != null) ...[
              const SizedBox(height: 6),
              Bullets([e.coneNote!], BulletKind.info),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!h.closed && !h.fromStockAcc)
                  FilledButton.icon(
                    onPressed: () => push(SellPage(holding: h, eval: e)),
                    icon: const Icon(Icons.sell_outlined, size: 18),
                    label: const Text('記錄賣出'),
                  ),
                if (!h.closed && !h.fromStockAcc)
                  OutlinedButton.icon(
                    onPressed: () => push(AddHoldingPage(code: h.code)),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('加碼（記錄買進）'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => push(EditHoldingPage(holding: h)),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('修改設定'),
                ),
                if (!h.fromStockAcc)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () async {
                      if (await confirmDeleteHolding(context, h) && context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('刪除'),
                  ),
                if (!h.closed)
                  TextButton.icon(
                    onPressed: () => _restart(context),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('從今天重新開始追蹤'),
                  ),
                TextButton(
                  onPressed: () => push(StockReportScreen(code: h.code)),
                  child: const Text('看個股分析'),
                ),
              ],
            ),
            if (h.fromStockAcc)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '這筆來自 stock_acc 記帳：買賣請在 stock_acc 記，持有方式、停損、備註可以在這裡改。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

extension on _TodayCard {
  Future<void> _restart(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('從今天重新開始追蹤？'),
        content: const Text(
          '之前的走勢和出場訊號都不再算（不會再顯示「應已出場」），停損和防守價從今天的價位重新開始；'
          '買賣紀錄、成本和損益都不會變。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('重新開始')),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<HoldingsStore>().restartTracking(h.id);
  }
}

/// 明日劇本：收盤在哪個價位該做什麼。
class _ScenarioCard extends StatelessWidget {
  final HoldingEval e;
  const _ScenarioCard({required this.e});

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '明日劇本',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in e.scenario)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 34,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: actionColor(s.kind), borderRadius: BorderRadius.circular(2)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.when, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(s.action, style: TextStyle(fontSize: 13, color: actionColor(s.kind))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Text('以收盤價判斷；價格是實際股價。盤中碰到不用急，收盤確認後再照劇本做。', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

/// 持有理由：買進時的判斷、今天每一項還成立嗎、健康度走勢、持有期間。
class _ThesisCard extends StatelessWidget {
  final Holding h;
  final HoldingEval e;
  const _ThesisCard({required this.h, required this.e});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final entryOk = {for (final c in e.thesisAtEntry) c.key: c.ok};
    final broke = [
      for (final c in e.thesisNow)
        if (entryOk[c.key] == true && !c.ok) c.label,
    ];
    return SectionCard(
      title: '持有理由還成立嗎',
      trailing: e.health == null ? null : HealthTag(e.health!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (h.duration != null || h.reason != null) ...[
            const Text('買進時的判斷', style: TextStyle(fontWeight: FontWeight.w600)),
            if (h.duration != null)
              Text(
                '${h.opportunity ?? ''}・預估 D${h.duration}（${kDurationRange[h.duration]}）・信心 ${h.confidence ?? '—'}',
                style: const TextStyle(fontSize: 13),
              ),
            if (h.thesis.isNotEmpty)
              Bullets(h.thesis, BulletKind.good)
            else if (h.reason != null)
              Text('${h.strategy ?? ''} ${h.reason}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
          ],
          const Text('今天逐項檢查', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final c in e.thesisNow)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    c.ok ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: c.ok ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: c.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: '　${c.detail}', style: small),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (entryOk[c.key] == true && !c.ok)
                    const Text('新失效', style: TextStyle(fontSize: 11, color: Color(0xFFD32F2F))),
                ],
              ),
            ),
          if (broke.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '買進時成立、現在失效的理由：${broke.join('、')}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFD32F2F)),
              ),
            ),
          if (e.log.length >= 2) ...[
            const SizedBox(height: 10),
            Text('健康度走勢（買進 ${e.log.first.health} → 今天 ${e.log.last.health}）', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Sparkline([for (final r in e.log) r.health.toDouble()]),
            Text('70 以上健康、50～70 注意、連續兩天低於 40 會建議先減碼。', style: small),
          ],
          if (e.durationNow != null) ...[
            const SizedBox(height: 10),
            Text(
              '目前持有週期：D${e.durationNow}（${kDurationRange[e.durationNow]}）',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (e.durationWhy != null && e.durationWhy!.isNotEmpty) Text(e.durationWhy!, style: small),
            Text('只在已經獲利 +1R 以上時才會升級；降級隨時發生。升降級都記在每日紀錄裡。', style: small),
          ],
        ],
      ),
    );
  }
}

class _AddOnCard extends StatelessWidget {
  final HoldingEval e;
  const _AddOnCard({required this.e});

  @override
  Widget build(BuildContext context) {
    (String, Color) st(AddOnStatus s) => switch (s) {
      AddOnStatus.done => ('已達成', const Color(0xFF2E7D32)),
      AddOnStatus.ready => ('條件接近', AppColors.up),
      AddOnStatus.waiting => ('等待中', Colors.grey),
      AddOnStatus.blocked => ('虧損中，禁止', const Color(0xFFD32F2F)),
    };
    return SectionCard(
      title: '可能的加碼時機',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in e.addOnPlan)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a.title}${a.price == null ? '' : '：${f2(a.price!)}'}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        Text(a.condition, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Tag(st(a.status).$1, st(a.status).$2),
                ],
              ),
            ),
          if (e.addOnRules.isNotEmpty) ...[const SizedBox(height: 4), Bullets(e.addOnRules, BulletKind.info)],
        ],
      ),
    );
  }
}

class _MoneyCard extends StatelessWidget {
  final Holding h;
  final HoldingEval e;
  const _MoneyCard({required this.h, required this.e});

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '成本、損益、停損',
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
            note: '1R = 進場價到起始停損的距離。+1R 代表賺到一倍風險。',
          ),
        if (!h.closed && e.stop != null) ...[
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
      ],
    ),
  );
}

/// 每日追蹤紀錄：上面是持有摘要，下面從最新一天往回，每天一筆。
class _LogCard extends StatefulWidget {
  final Holding h;
  final HoldingEval e;
  const _LogCard({required this.h, required this.e});

  @override
  State<_LogCard> createState() => _LogCardState();
}

class _LogCardState extends State<_LogCard> {
  bool _all = false;
  bool _eventsOnly = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final rows = e.log.reversed.where((r) => !_eventsOnly || r.events.isNotEmpty || r.action.needsAction).toList();
    final shown = _all ? rows : rows.take(15).toList();
    return SectionCard(
      title: '每日追蹤紀錄（${e.log.length} 個交易日）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.summary != null && !widget.h.closed) ...[
            const Text('持有摘要', style: TextStyle(fontWeight: FontWeight.w600)),
            Bullets(e.summary!.lines, BulletKind.info),
            const SizedBox(height: 6),
          ],
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('只看有發生事情的日子', style: TextStyle(fontSize: 13)),
            value: _eventsOnly,
            onChanged: (v) => setState(() => _eventsOnly = v),
          ),
          for (final r in shown) _DayTile(r: r, style: widget.h.style),
          if (rows.length > shown.length)
            TextButton(onPressed: () => setState(() => _all = true), child: Text('顯示全部 ${rows.length} 筆')),
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  final DayRecord r;
  final HoldStyle style;
  const _DayTile({required this.r, required this.style});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final c = actionColor(r.action);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c, width: 3)),
        color: c.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(r.date, style: const TextStyle(fontWeight: FontWeight.w700)),
              ActionTag(r.action, style: style),
              Text(
                '收盤 ${f2(r.close)}${r.changePct == null ? '' : '（${pctTxt(r.changePct)}）'}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(
                '損益 ${r.pnlPct >= 0 ? '+' : ''}${r.pnlPct.toStringAsFixed(1)}%（${r.r >= 0 ? '+' : ''}${r.r.toStringAsFixed(1)}R）',
                style: small?.copyWith(color: changeColor(context, r.pnlPct), fontWeight: FontWeight.w600),
              ),
              Text(
                r.stopRaised ? '停損 ${f2(r.prevStop!)} → ${f2(r.stop)} ↑' : '停損 ${f2(r.stop)}',
                style: small?.copyWith(fontWeight: r.stopRaised ? FontWeight.w700 : null),
              ),
              Text(
                '健康度 ${r.health}（${r.okCount}/${r.checkCount}）',
                style: small?.copyWith(color: healthColor(r.health)),
              ),
              Text('D${r.duration}', style: small),
              Text('${r.shares} 股', style: small),
            ],
          ),
          if (r.events.isNotEmpty) ...[
            const SizedBox(height: 3),
            for (final ev in r.events) Text('• $ev', style: const TextStyle(fontSize: 12, height: 1.35)),
          ],
          const SizedBox(height: 3),
          Text('建議：${r.reason}', style: TextStyle(fontSize: 12, color: c, height: 1.35)),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final String label, date;
  final double price;
  final int shares;
  final Color color;
  final String? cost;
  final VoidCallback? onTap;
  const _RecordRow({
    required this.label,
    required this.date,
    required this.price,
    required this.shares,
    required this.color,
    this.cost,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(
        children: [
          Tag(label, color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$date · ${f2(price)} × $shares 股${cost == null ? '' : '（$cost）'}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (onTap != null) Icon(Icons.edit_outlined, size: 16, color: Theme.of(context).colorScheme.outline),
        ],
      ),
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
