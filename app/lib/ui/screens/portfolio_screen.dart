/// 「組合」：長期投資的主畫面。
///
/// - 大型股避雷組合：照市值持有台股最大的 30 家公司，把有地雷的拿掉；單一檔最多 40%，
///   太小的部位放 0050。不預測誰會漲最多（用真實資料檢驗過，全市場挑贏家沒有比較好）。
/// - 依我的持股調整：手上每一檔在不在組合裡、有沒有地雷，一個月最多換幾檔。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bluechip.dart';
import '../../core/factors.dart';
import '../../core/lt_analysis.dart';
import '../../core/portfolio.dart';
import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/longterm_store.dart';
import '../home.dart';
import '../layout.dart';
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
          subtitle: '長期投資：持有台股最大的公司、避開地雷，每月檢視一次',
          trailing: lt.result == null
              ? null
              : Text('資料到 ${lt.result!.date}', style: Theme.of(context).textTheme.bodySmall),
        ),
        PackGate(
          builder: (context, r) {
            final bc = r.bluechip;
            if (bc == null || bc.current == null) return const _NeedShares();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, icon: Icon(Icons.verified_outlined), label: Text('大型股避雷組合')),
                      ButtonSegment(value: 1, icon: Icon(Icons.swap_horiz), label: Text('依我的持股調整')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                ),
                const SizedBox(height: 8),
                if (_mode == 0) _PickView(r: r, bc: bc) else _SwapView(r: r, pick: bc.current!),
                if (lt.analyzing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '依公開資料、固定規則算出來的參考，不是投資建議。過去的回測成績不代表未來，實際買賣前請自己判斷。'),
      ],
    );
  }
}

void _openStock(BuildContext context, String code) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: code)));

/// 舊資料包沒有發行股數：請使用者更新。
class _NeedShares extends StatelessWidget {
  const _NeedShares();

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    return SectionCard(
      title: '需要更新資料包',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('新的組合要用每家公司的發行股數算市值，這份資料在新版資料包裡（約 0.1 MB）。'),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: lt.analyzing ? null : lt.updatePack, child: const Text('更新資料包')),
        ],
      ),
    );
  }
}

class _PickView extends StatelessWidget {
  final LtResult r;
  final BcResult bc;
  const _PickView({required this.r, required this.bc});

  @override
  Widget build(BuildContext context) {
    final p = bc.current!;
    final f = bc.full;
    final small = Theme.of(context).textTheme.bodySmall;
    final reviewDay = !r.data.samples.last.live;
    final left = <Widget>[
      SectionCard(
        title: '大型股避雷組合：${p.stocks.length} 檔＋0050',
        trailing: Text(reviewDay ? '今天是檢視日' : '下次檢視 ${nextReviewText(r.date!)}', style: small),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '照市值持有台股最大的 30 家公司，把有地雷的拿掉；單一檔最多 40%（連 0050 裡的一起算），'
              '不到 1.5% 的小部位改放 0050。不預測誰會漲最多。',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 4),
            Text(
              '回測 ${f.from.substring(0, 7)}～${f.to.substring(0, 7)}（扣成本）：年化 ${sp(f.cagr)}，'
              '0050 ${sp(f.etfCagr)}、大盤含息 ${sp(f.benchCagr)}；最大跌幅 ${pc(f.mdd)}（0050 ${pc(f.etfMdd)}、大盤 ${pc(f.benchMdd)}）。',
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _CapitalField(),
                TextButton(onPressed: () => HomeShell.goTo(context, HomeShell.backtest), child: const Text('看完整回測 →')),
              ],
            ),
            const Divider(height: 8),
            for (final st in p.stocks) _StockRow(r: r, st: st),
            _EtfRow(weight: p.etfWeight),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('比重是目標；漲跌後會自然偏離，跟目標差不到 1/4 就不用調，每月檢視日再看一次。', style: small),
            ),
          ],
        ),
      ),
    ];
    final right = <Widget>[
      _Changes(r: r, bc: bc, reviewDay: reviewDay),
      SectionCard(
        title: '被排除的地雷',
        trailing: Text('市值前 30 大裡', style: small),
        child: p.landmines.isEmpty
            ? const Text('目前市值前 30 大都沒有地雷。', style: TextStyle(fontSize: 13))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final m in p.landmines) _MineRow(r: r, m: m),
                  const SizedBox(height: 4),
                  Text(
                    bc.mines.isEmpty
                        ? '有地雷的大型股不買；手上有的話建議換掉。'
                        : '過去 ${bc.mines.length} 個月的檢視：被排除的地雷之後 6 個月，有 ${pc(bc.mineLagRate)} 的時候比沒地雷的大型股差，'
                              '平均少賺 ${pc(-bc.mineAvgGap, 1)}。',
                    style: small,
                  ),
                ],
              ),
      ),
      SectionCard(
        title: '最簡單的做法',
        child: Text(
          '不想管個股：全部買 0050，長期抱著。回測年化 ${sp(f.etfCagr)}、最大跌幅 ${pc(f.etfMdd)}；'
          '這個組合多做的是「去掉地雷、台積電不超過 40%」，每年多 ${sp(f.cagr - f.etfCagr)}，但要自己每月檢視。',
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
      ),
      SectionCard(
        title: '規則',
        child: Bullets(const [
          '範圍：上市公司市值（發行股數 × 股價）前 30 大。大家熟悉、成交量大，買得到也賣得掉。',
          '地雷：虧損、年線下彎又營收衰退、殖利率陷阱（配的比賺的多）、成交量太小、總分在全市場後 20%。有地雷就不買。',
          '比重：照市值；單一檔最多 40%（連 0050 裡的一起算）；不到 1.5% 的改放 0050，不買零碎部位。',
          '每月 11 日以後第一個交易日檢視；比重跟目標差不到 1/4 就不調，減少交易。',
          '不預測誰會漲最多：真實資料檢驗過，全市場評分挑贏家，抱 3～6 個月贏大盤的次數只有一半。',
        ], BulletKind.info),
      ),
    ];
    return SplitView(left: left, right: right, leftFlex: 12, rightFlex: 9);
  }
}

class _StockRow extends StatelessWidget {
  final LtResult r;
  final BcStock st;
  const _StockRow({required this.r, required this.st});

  @override
  Widget build(BuildContext context) {
    final s = r.data.stocks[st.si];
    final x = r.live.of(st.si);
    return InkWell(
      onTap: () => _openStock(context, s.code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Text(pc(st.weight, 1), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s.code} ${s.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(
                    [
                      '市值第 ${st.capRank} 大',
                      '沒有地雷',
                      if (x != null && !x.raw.val60.isNaN) '每天成交約 ${moneyText(x.raw.val60)}',
                      if (x != null) ...ltHighlights(x).take(2),
                    ].join('・'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (x != null && x.flags.contains(LtFlag.overheat))
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('短期漲多：照比重分批買就好，不用追', style: TextStyle(fontSize: 12, color: Color(0xFFE8743B))),
                    ),
                  TrendSpark(r: r, si: st.si),
                  _Amount(weight: st.weight, price: x?.raw.close),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 0050 那一列。
class _EtfRow extends StatelessWidget {
  final double weight;
  const _EtfRow({required this.weight});

  @override
  Widget build(BuildContext context) {
    final bars = context.read<HistoryStore>().rawSeriesOf('0050');
    return InkWell(
      onTap: () => _openStock(context, '0050'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Text(pc(weight, 1), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('0050 元大台灣50', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(
                    '市值前 30 大裡比重不到 1.5% 的那些公司，用 0050 一次買齊（006208 也可以）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _Amount(weight: weight, price: bars.isEmpty ? null : bars.last.close),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MineRow extends StatelessWidget {
  final LtResult r;
  final BcLandmine m;
  const _MineRow({required this.r, required this.m});

  @override
  Widget build(BuildContext context) {
    final s = r.data.stocks[m.si];
    return InkWell(
      onTap: () => _openStock(context, s.code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Tag('地雷', Color(0xFFB71C1C), filled: true),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s.code} ${s.name}（市值第 ${m.capRank} 大）', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(m.reasons.join('、'), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 跟上次檢視比：新買、賣出、比重大幅改變的。
class _Changes extends StatelessWidget {
  final LtResult r;
  final BcResult bc;
  final bool reviewDay;
  const _Changes({required this.r, required this.bc, required this.reviewDay});

  @override
  Widget build(BuildContext context) {
    final cur = bc.current!, prev = bc.previous;
    final small = Theme.of(context).textTheme.bodySmall;
    final rows = <Widget>[];
    String name(int si) => '${r.data.stocks[si].code} ${r.data.stocks[si].name}';
    if (prev != null) {
      final prevMines = {for (final m in prev.landmines) m.si};
      final curMines = {for (final m in cur.landmines) m.si: m};
      for (final st in cur.stocks) {
        final old = prev.of(st.si);
        if (old == null) {
          rows.add(
            _ChangeRow(
              code: r.data.stocks[st.si].code,
              label: name(st.si),
              kind: '買進',
              reason: prevMines.contains(st.si) ? '地雷解除' : '進入市值前 30 大，或比重超過 1.5%',
              weight: st.weight,
            ),
          );
        } else if ((st.weight - old.weight).abs() > bc.cfg.band * old.weight) {
          rows.add(
            _ChangeRow(
              code: r.data.stocks[st.si].code,
              label: name(st.si),
              kind: st.weight > old.weight ? '加碼' : '減碼',
              reason: '目標比重 ${pc(old.weight, 1)} → ${pc(st.weight, 1)}',
              weight: st.weight,
            ),
          );
        }
      }
      for (final st in prev.stocks) {
        if (cur.of(st.si) != null) continue;
        final m = curMines[st.si];
        rows.add(
          _ChangeRow(
            code: r.data.stocks[st.si].code,
            label: name(st.si),
            kind: '賣出',
            reason: m != null ? '有地雷：${m.reasons.join('、')}' : '掉出市值前 30 大或比重不到 1.5%，改由 0050 持有',
          ),
        );
      }
    }
    return SectionCard(
      title: reviewDay ? '本月調整（明天收盤執行）' : '如果今天檢視',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty) const Text('跟上次檢視比，不用調整。', style: TextStyle(fontSize: 13)) else ...rows,
          const SizedBox(height: 6),
          Text(
            reviewDay
                ? '今天是每月檢視日，跟上次（${prev?.date ?? '—'}）比較。'
                : '今天不是檢視日，這是跟上次檢視（${prev?.date ?? '—'}）比「現在檢視會怎麼調」的參考；正式調整在 ${nextReviewText(r.date!)}。',
            style: small,
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final String code, label, kind, reason;
  final double? weight;
  const _ChangeRow({required this.code, required this.label, required this.kind, required this.reason, this.weight});

  @override
  Widget build(BuildContext context) {
    final c = switch (kind) {
      '賣出' || '減碼' => const Color(0xFF5B8DB8),
      _ => const Color(0xFFCF3528),
    };
    return InkWell(
      onTap: () => _openStock(context, code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tag(kind, c, filled: true),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label${weight == null ? '' : '（約 ${pc(weight!, 1)}）'}',
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

class _SwapView extends StatelessWidget {
  final LtResult r;
  final BcPick pick;
  const _SwapView({required this.r, required this.pick});

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
            const Text('「持股」頁還沒有持股。輸入（或從 stock_acc 同步）你手上的股票之後，這裡會逐檔檢查：在不在組合裡、有沒有地雷、建議換成什麼。'),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: () => HomeShell.goTo(context, HomeShell.holdings), child: const Text('到持股頁')),
          ],
        ),
      );
    }
    final adv = bcSwapAdvice(inputs, pick, r.data, r.live, maxSwaps: lt.maxSwaps);
    final groups = <SwapAction, List<SwapRow>>{};
    for (final row in adv.rows) {
      (groups[row.action] ??= []).add(row);
    }
    final keep = groups[SwapAction.keep]?.length ?? 0, watch = groups[SwapAction.watch]?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: adv.replaceCount == 0 ? '這個月不用換' : '建議換 ${adv.replaceCount} 檔',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text('每月最多換', style: Theme.of(context).textTheme.bodySmall),
                  DropdownButton<int>(
                    value: lt.maxSwaps,
                    isDense: true,
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
              Text(
                '手上 ${inputs.length} 檔：在組合裡 $keep、不在組合但沒地雷 $watch、有地雷建議換 ${adv.replaceCount}'
                '${groups[SwapAction.core] == null ? '' : '、0050 類 ${groups[SwapAction.core]!.length}'}'
                '${groups[SwapAction.notRated] == null ? '' : '、不在判斷範圍 ${groups[SwapAction.notRated]!.length}'}。'
                '不全面換股：只換有地雷的，換成組合裡還沒持有、比重大的公司。',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              if (adv.notes.isNotEmpty) ...[const SizedBox(height: 6), Bullets(adv.notes, BulletKind.warn)],
            ],
          ),
        ),
        for (final a in const [
          SwapAction.replace,
          SwapAction.watch,
          SwapAction.keep,
          SwapAction.core,
          SwapAction.notRated,
        ])
          if (groups[a] != null) ...[
            SectionHeader(left: '${_label(a)}（${groups[a]!.length}）'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < groups[a]!.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _SwapRowTile(r: r, row: groups[a]![i]),
                  ],
                ],
              ),
            ),
          ],
      ],
    );
  }
}

String _label(SwapAction a) => switch (a) {
  SwapAction.keep => '在組合裡：續抱',
  SwapAction.watch => '不在組合裡、沒有地雷',
  SwapAction.replace => '有地雷：建議換掉',
  SwapAction.core => '0050 類',
  SwapAction.notRated => '不在判斷範圍',
};

Color swapColor(SwapAction a) => switch (a) {
  SwapAction.replace => const Color(0xFFD32F2F),
  SwapAction.watch => const Color(0xFFC98A00),
  SwapAction.keep => const Color(0xFF2E7D32),
  SwapAction.core => const Color(0xFF1565C0),
  SwapAction.notRated => Colors.grey,
};

class _SwapRowTile extends StatelessWidget {
  final LtResult r;
  final SwapRow row;
  const _SwapRowTile({required this.r, required this.row});

  @override
  Widget build(BuildContext context) {
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
              ],
            ),
            const SizedBox(height: 4),
            Bullets(row.reasons, row.action == SwapAction.keep ? BulletKind.good : BulletKind.info),
            if (row.candidates.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('可以換成（組合裡還沒持有的）：', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in row.candidates)
                    ActionChip(
                      label: Text('${c.code} ${r.data.stock(c.code)?.name ?? ''}'),
                      onPressed: () => _openStock(context, c.code),
                    ),
                ],
              ),
            ] else if (row.action == SwapAction.replace) ...[
              const SizedBox(height: 4),
              Text('組合裡的股票都已經有了：賣掉的錢可以放 0050。', style: Theme.of(context).textTheme.bodySmall),
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
    widthFactor: 1,
    child: SizedBox(
      width: 170,
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
