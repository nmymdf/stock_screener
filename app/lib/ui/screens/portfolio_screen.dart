/// 「組合」：長期投資的主畫面。
///
/// - 理想組合：不管手上有什麼，照規則該持有的 10～15 檔、各配多少（跟回測同一套規則，
///   所以回測的成績就是這個組合過去的成績）。
/// - 依我的持股汰弱留強：看手上每一檔還值不值得抱，一個月最多換幾檔、換成更強的。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/factors.dart';
import '../../core/lt_analysis.dart';
import '../../core/portfolio.dart';
import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/longterm_store.dart';
import '../home.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/lt_widgets.dart';
import '../widgets/score_widgets.dart';
import 'stock_report_screen.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeader(
          icon: Icons.pie_chart_outline,
          title: '組合',
          subtitle: '長期投資：每月檢視一次、汰弱留強，不追高、不殺低',
          trailing: lt.result == null
              ? null
              : Text('資料到 ${lt.result!.date}', style: Theme.of(context).textTheme.bodySmall),
        ),
        PackGate(
          builder: (context, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExposureCard(
                r.exposure,
                mode: lt.cfg.exposure,
                compact: true,
                onTap: () => HomeShell.goTo(context, HomeShell.market),
              ),
              const SizedBox(height: 4),
              Center(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, icon: Icon(Icons.auto_awesome_outlined), label: Text('理想組合')),
                    ButtonSegment(value: 1, icon: Icon(Icons.swap_horiz), label: Text('依我的持股汰弱留強')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              const SizedBox(height: 8),
              if (_mode == 0) _IdealView(r: r) else _SwapView(r: r),
              if (lt.analyzing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '依公開資料、固定規則算出來的參考，不是投資建議。過去的回測成績不代表未來，實際買賣前請自己判斷。'),
      ],
    );
  }
}

void _openStock(BuildContext context, String code) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: code)));

class _IdealView extends StatelessWidget {
  final LtResult r;
  const _IdealView({required this.r});

  @override
  Widget build(BuildContext context) {
    final sim = r.sim;
    final s = sim.stats;
    final hold = sim.holdings.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final d = sim.pending ?? r.preview;
    final total = r.live.ranked.length;
    final held = sim.holdings.keys.toSet();
    final bench = r.data.hasTri ? '加權報酬指數（含息）' : '加權指數';
    final candidates = [
      for (final x in r.live.ranked)
        if (x.investable && !held.contains(x.si) && !x.broken && !x.flags.contains(LtFlag.loss)) x,
    ].take(15).toList();
    final left = <Widget>[
      SectionCard(
        title: '策略目前持有 ${hold.length} 檔',
        trailing: Text(
          '股票 ${pc(1 - math.max(0.0, sim.cashWeight))}・現金 ${pc(math.max(0.0, sim.cashWeight))}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '照同一套規則從 ${s.from} 開始操作到今天：年化 ${sp(s.cagr)}（同期$bench ${sp(s.benchCagr)}），'
              '${s.yearRows.length} 年中有 ${s.yearRows.where((y) => y.beat).length} 年贏指數，最大跌幅 ${pc(s.mdd)}；'
              '每筆持股平均抱 ${(s.avgHoldDays / 21).toStringAsFixed(1)} 個月，${pc(s.posWin)} 賣出時是賺錢的。',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            Row(
              children: [
                const Expanded(child: _CapitalField()),
                TextButton(onPressed: () => HomeShell.goTo(context, HomeShell.backtest), child: const Text('看完整回測 →')),
              ],
            ),
            const Divider(height: 8),
            for (final e in hold) _HoldRow(r: r, si: e.key, weight: e.value.$1, since: e.value.$2, total: total),
            if (sim.rebalances.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '上次檢視 ${sim.rebalances.last.date}（${sim.rebalances.last.execDate} 收盤調整）；權重是目前市值的比例，漲跌後會自然偏離，不用天天調整。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ];
    final right = <Widget>[
      SectionCard(
        title: sim.pending != null ? '本月調整（明天收盤執行）' : '如果今天檢視',
        child: d == null || (d.sells.isEmpty && d.buys.isEmpty)
            ? Text('目前不需要換股。下次檢視：${nextReviewText(r.date!)}。', style: const TextStyle(fontSize: 13))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in d.sells.entries)
                    _ChangeRow(
                      code: r.data.stocks[e.key].code,
                      name: r.data.stocks[e.key].name,
                      sell: true,
                      reason: e.value,
                    ),
                  for (final b in d.buys)
                    _ChangeRow(
                      code: r.data.stocks[b.$1].code,
                      name: r.data.stocks[b.$1].name,
                      sell: false,
                      reason: b.$2,
                      weight: d.target[b.$1],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    sim.pending != null
                        ? '今天是每月檢視日，規則在收盤後決定、隔天收盤成交。'
                        : '今天不是檢視日，這只是「現在檢視會怎麼做」的參考；正式調整在 ${nextReviewText(r.date!)}。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
      SectionCard(
        title: '候補名單',
        trailing: Text('總分前 15、還沒持有', style: Theme.of(context).textTheme.bodySmall),
        child: Column(
          children: [for (final x in candidates) _CandidateRow(r: r, s: x, total: total)],
        ),
      ),
      SectionCard(
        title: '規則',
        child: Bullets(const [
          '每月 11 日以後第一個交易日檢視一次（月營收 10 日前公布完），隔天收盤調整。',
          '新買：全市場總分前 10%、成交量夠、沒有過熱、沒有虧損。',
          '續抱：總分還在前 30% 就不動；至少抱 3 個月，除非長期理由破壞（年線下彎又營收衰退、虧損又轉弱、或掉到後 15%）。',
          '每月最多換 5 檔，換上去的要明顯更強；單一檔最多 15%、單一產業最多 30%。',
          '權重：分數越高、波動越低的配越多。',
        ], BulletKind.info),
      ),
    ];
    return SplitView(left: left, right: right, leftFlex: 12, rightFlex: 9);
  }
}

class _HoldRow extends StatelessWidget {
  final LtResult r;
  final int si;
  final double weight;
  final String since;
  final int total;
  const _HoldRow({required this.r, required this.si, required this.weight, required this.since, required this.total});

  @override
  Widget build(BuildContext context) {
    final st = r.data.stocks[si];
    final s = r.live.of(si);
    final timing = entryTiming(shortReportOf(context, st.code), s);
    return InkWell(
      onTap: () => _openStock(context, st.code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Text(pc(weight, 1), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${st.code} ${st.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(
                    [if (s != null) rankText(s, total), '買進 $since', if (s != null) ...ltHighlights(s)].join('・'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (s != null && s.flags.isNotEmpty) ...[const SizedBox(height: 3), LtFlagTags(s.flags)],
                  if (timing != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('進場時機：${timing.$1}', style: TextStyle(fontSize: 12, color: timing.$2)),
                    ),
                  _Amount(weight: weight, price: s?.raw.close),
                ],
              ),
            ),
            if (s != null) ScoreBadge(score: s.composite, size: 40),
          ],
        ),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final String code, name, reason;
  final bool sell;
  final double? weight;
  const _ChangeRow({required this.code, required this.name, required this.sell, required this.reason, this.weight});

  @override
  Widget build(BuildContext context) {
    final c = sell ? const Color(0xFF5B8DB8) : const Color(0xFFCF3528);
    return InkWell(
      onTap: () => _openStock(context, code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tag(sell ? '賣出' : '買進', c, filled: true),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$code $name${weight == null ? '' : '（約 ${pc(weight!, 0)}）'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(reason, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final LtResult r;
  final LtScore s;
  final int total;
  const _CandidateRow({required this.r, required this.s, required this.total});

  @override
  Widget build(BuildContext context) {
    final st = r.data.stocks[s.si];
    final timing = entryTiming(shortReportOf(context, st.code), s);
    return InkWell(
      onTap: () => _openStock(context, st.code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RankBadge(rank: s.rank),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${st.code} ${st.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [...ltHighlights(s), if (timing != null) timing.$1].join('・'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (s.flags.isNotEmpty) ...[const SizedBox(height: 2), LtFlagTags(s.flags)],
                ],
              ),
            ),
            ScoreBadge(score: s.composite, size: 36),
          ],
        ),
      ),
    );
  }
}

class _SwapView extends StatelessWidget {
  final LtResult r;
  const _SwapView({required this.r});

  /// 手上持股（兩組合併、同一檔加總），市值用最新收盤。
  List<HoldingInput> _inputs(BuildContext context) {
    final holdings = context.watch<HoldingsStore>();
    final history = context.read<HistoryStore>();
    final by = <String, (double, String, int)>{};
    for (final h in holdings.open) {
      final raw = history.rawSeriesOf(h.code);
      final st = r.data.stock(h.code);
      double? px = raw.isNotEmpty ? raw.last.close : null;
      if (px == null && st != null) {
        final s = r.live.sample;
        final c = s.close[r.data.index[h.code]!];
        if (!c.isNaN) px = c;
      }
      final v = (px ?? h.avgCost) * h.shares;
      final old = by[h.code];
      final since = old == null || h.firstBuyDate.compareTo(old.$2) < 0 ? h.firstBuyDate : old.$2;
      by[h.code] = ((old?.$1 ?? 0) + v, since, h.shares + (old?.$3 ?? 0));
    }
    return [for (final e in by.entries) HoldingInput(e.key, r.data.stock(e.key)?.name ?? '', e.value.$1, e.value.$2)];
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    final inputs = _inputs(context);
    if (inputs.isEmpty) {
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('「持股」頁還沒有持股。輸入（或從 stock_acc 同步）你手上的股票之後，這裡會逐檔檢查：哪些續抱、哪些觀察、哪些建議換掉、換成什麼。'),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: () => HomeShell.goTo(context, HomeShell.holdings), child: const Text('到持股頁')),
          ],
        ),
      );
    }
    final adv = swapAdvice(inputs, r.live, r.data, maxSwaps: lt.maxSwaps, cfg: lt.cfg);
    final total = r.live.ranked.length;
    final groups = <SwapAction, List<SwapRow>>{};
    for (final row in adv.rows) {
      (groups[row.action] ??= []).add(row);
    }
    final keep = groups[SwapAction.keep]?.length ?? 0, watch = groups[SwapAction.watch]?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '汰弱留強：${adv.replaceCount == 0 ? '這個月不用換' : '建議換 ${adv.replaceCount} 檔'}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('每月最多換', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 4),
              DropdownButton<int>(
                value: lt.maxSwaps,
                underline: const SizedBox.shrink(),
                items: [
                  for (final n in const [2, 3, 4, 5]) DropdownMenuItem(value: n, child: Text('$n 檔')),
                ],
                onChanged: (v) {
                  if (v != null) lt.setMaxSwaps(v);
                },
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '手上 ${inputs.length} 檔：續抱 $keep、觀察 $watch、建議汰換 ${adv.replaceCount}'
                '${groups[SwapAction.notRated] == null ? '' : '、不在評分範圍 ${groups[SwapAction.notRated]!.length}'}。'
                '不全面換股：只換長期理由已經破壞、或排名落到後段又抱超過 3 個月的，而且換上去的要明顯更強。',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              if (adv.notes.isNotEmpty) ...[const SizedBox(height: 6), Bullets(adv.notes, BulletKind.warn)],
            ],
          ),
        ),
        for (final a in const [SwapAction.replace, SwapAction.watch, SwapAction.keep, SwapAction.notRated])
          if (groups[a] != null) ...[
            SectionHeader(left: '${a.label}（${groups[a]!.length}）'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < groups[a]!.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _SwapRowTile(row: groups[a]![i], total: total),
                  ],
                ],
              ),
            ),
          ],
      ],
    );
  }
}

Color swapColor(SwapAction a) => switch (a) {
  SwapAction.replace => const Color(0xFFD32F2F),
  SwapAction.watch => const Color(0xFFC98A00),
  SwapAction.keep => const Color(0xFF2E7D32),
  SwapAction.notRated => Colors.grey,
};

class _SwapRowTile extends StatelessWidget {
  final SwapRow row;
  final int total;
  const _SwapRowTile({required this.row, required this.total});

  @override
  Widget build(BuildContext context) {
    final s = row.score;
    final h = row.holding;
    return InkWell(
      onTap: () => _openStock(context, h.code),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tag(row.action.label, swapColor(row.action), filled: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${h.code} ${h.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Text('佔 ${pc(row.weight, 0)}', style: Theme.of(context).textTheme.bodySmall),
                if (s != null) ...[const SizedBox(width: 8), ScoreBadge(score: s.composite, size: 36)],
              ],
            ),
            const SizedBox(height: 4),
            if (s != null) Text(rankText(s, total), style: Theme.of(context).textTheme.bodySmall),
            Bullets(row.reasons, row.action == SwapAction.keep ? BulletKind.good : BulletKind.info),
            if (s != null && s.flags.isNotEmpty) LtFlagTags(s.flags),
            if (row.candidates.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('可以換成：', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in row.candidates)
                    ActionChip(
                      avatar: CircleAvatar(
                        backgroundColor: scoreColor(context, c.composite),
                        child: Text(
                          c.composite.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                      label: Text('${c.code}（第 ${c.rank} 名）'),
                      onPressed: () => _openStock(context, c.code),
                    ),
                ],
              ),
            ] else if (row.action == SwapAction.replace) ...[
              const SizedBox(height: 4),
              Text('目前找不到明顯更強、又不會讓產業太集中的替代股，可以先減碼、保留現金。', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// 試算投入金額（萬元）。
class _CapitalField extends StatefulWidget {
  const _CapitalField();

  @override
  State<_CapitalField> createState() => _CapitalFieldState();
}

class _CapitalFieldState extends State<_CapitalField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    final v = context.read<LongTermStore>().capital;
    _c = TextEditingController(text: v == null ? '' : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      width: 190,
      child: TextField(
        controller: _c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          isDense: true,
          labelText: '試算投入金額',
          suffixText: '萬元',
          border: OutlineInputBorder(),
        ),
        onChanged: (t) => context.read<LongTermStore>().setCapital(double.tryParse(t.replaceAll(',', '').trim())),
      ),
    ),
  );
}

/// 有填投入金額時：這檔大約要買多少錢、幾股。
class _Amount extends StatelessWidget {
  final double weight;
  final double? price;
  const _Amount({required this.weight, required this.price});

  @override
  Widget build(BuildContext context) {
    final cap = context.select<LongTermStore, double?>((s) => s.capital);
    if (cap == null) return const SizedBox.shrink();
    final money = cap * 10000 * weight;
    final p = price;
    final shares = p == null || p.isNaN || p <= 0 ? null : (money / p).floor();
    final lots = shares == null ? null : shares ~/ 1000;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        '約 ${(money / 10000).toStringAsFixed(1)} 萬'
        '${shares == null ? '' : '・約 ${lots! >= 1 ? '$lots 張${shares % 1000 >= 100 ? '又 ${shares % 1000} 股' : ''}' : '$shares 股（零股）'}'}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
