/// 「組合」：穩健 70%（0050＋大盤 200 日均線）＋進攻 30%（趨勢模板強勢股＋50 日均線停損）。
///
/// - 穩健：大盤站在 200 日均線上就持有 0050，跌破就改放現金；每月檢視一次。
/// - 進攻：每月挑 10 檔強勢股（股價多頭排列、接近一年高點、相對強度前 30%、營收大成長），
///   任何一檔收盤跌破 50 日均線就賣出放現金，下次檢視再挑。
/// - 依我的持股調整：手上每一檔照同一套規則看該續抱、賣出還是換。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/lt_analysis.dart';
import '../../core/portfolio.dart' show coreEtfCodes;
import '../../core/strategy.dart';
import '../../data/history_store.dart';
import '../../data/stock_catalog.dart';
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
          subtitle: '穩健 70%（0050＋大盤均線）＋進攻 30%（強勢股＋停損）；每月檢視、每天看停損',
          trailing: lt.result == null
              ? null
              : Text('資料到 ${lt.result!.date}', style: Theme.of(context).textTheme.bodySmall),
        ),
        PackGate(
          builder: (context, r) {
            final st = r.strategy;
            if (st == null) return const _NeedUpdate();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, icon: Icon(Icons.auto_graph), label: Text('策略組合')),
                      ButtonSegment(value: 1, icon: Icon(Icons.swap_horiz), label: Text('依我的持股調整')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                ),
                const SizedBox(height: 8),
                if (_mode == 0) _PlanView(r: r, st: st) else _HoldingsView(r: r, st: st),
                if (lt.analyzing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '依公開資料、固定規則算出來的參考，不是投資建議。過去的回測成績不代表未來，投資盈虧請自行負責。'),
      ],
    );
  }
}

void _openStock(BuildContext context, String code) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: code)));

class _NeedUpdate extends StatelessWidget {
  const _NeedUpdate();

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    return SectionCard(
      title: '需要更新資料包',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('新版要用每家公司的發行股數和完整的大盤資料，請先更新資料包（約 0.1 MB）。'),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: lt.analyzing ? null : lt.updatePack, child: const Text('更新資料包')),
        ],
      ),
    );
  }
}

/// 比重欄：固定寬度、不換行（字放大時縮小，不會擠成兩行）。
class _Weight extends StatelessWidget {
  final String text;
  final Color? color;
  const _Weight(this.text, {this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
      ),
    ),
  );
}

class _PlanView extends StatelessWidget {
  final LtResult r;
  final StrategyResult st;
  const _PlanView({required this.r, required this.st});

  @override
  Widget build(BuildContext context) {
    final cfg = st.cfg;
    final stable = 1 - cfg.aggressive;
    final per = cfg.aggressive / cfg.picks;
    final holding = st.picks.where((p) => p.stoppedOn == null).length;
    final stopped = st.picks.length - holding;
    final empty = cfg.picks - st.picks.length;
    final small = Theme.of(context).textTheme.bodySmall;
    final reviewDay = !r.data.samples.last.live;
    final f = st.full;
    final today = r.date!;
    final left = <Widget>[
      SectionCard(
        title: '現在的配置',
        trailing: Text(
          reviewDay ? '今天是檢視日（明天收盤調整）' : '上次檢視 ${st.reviewDate}・下次 ${nextReviewText(today)}',
          style: small,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoTable([
              (
                '穩健 ${pc(stable)}',
                st.marketOn
                    ? '0050 持有：大盤在 200 日均線上（檢視日 ${sp(st.reviewGap)}；今天 ${sp(st.marketGapNow)}）'
                    : '現金：大盤跌破 200 日均線（檢視日 ${sp(st.reviewGap)}；今天 ${sp(st.marketGapNow)}），等站回去再買 0050',
              ),
              (
                '進攻 ${pc(cfg.aggressive)}',
                '${st.picks.length} 檔強勢股，每檔 ${pc(per, 1)}：持有 $holding 檔'
                    '${stopped > 0 ? '、已跌破 50 日均線改放現金 $stopped 檔' : ''}'
                    '${empty > 0 ? '；名單不足 10 檔，空的 ${pc(per * empty, 1)} 放 0050' : ''}',
              ),
              ('要做的事', _todo(st, today, reviewDay)),
            ], keyWidth: 96),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _CapitalField(),
                TextButton(onPressed: () => HomeShell.goTo(context, HomeShell.backtest), child: const Text('看完整回測 →')),
              ],
            ),
          ],
        ),
      ),
      SectionCard(
        title: '穩健：0050',
        trailing: Text(st.marketOn ? '持有' : '現金', style: small),
        child: _EtfRow(weight: st.marketOn ? stable + per * empty : per * empty, marketOn: st.marketOn),
      ),
      SectionCard(
        title: '進攻名單（${st.reviewDate} 檢視）',
        trailing: Text('跌破 50 日均線就賣', style: small),
        child: st.picks.isEmpty
            ? const Text('這個月沒有符合條件的股票：進攻部位全部放 0050。', style: TextStyle(fontSize: 13))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in st.picks) _PickRow(r: r, ps: p, weight: per),
                  const SizedBox(height: 4),
                  Text(
                    '入選條件：股價多頭排列（50 日線 > 150 日線 > 200 日線且往上）、離一年高點 25% 以內、一年漲幅全市場前 30%、'
                    '近 3 個月營收年增 20% 以上、每天成交 2 億元以上、沒有地雷。名單都是漲很多的強勢股，這套方法就是「買強、跌破就跑」。',
                    style: small,
                  ),
                ],
              ),
      ),
    ];
    final right = <Widget>[
      SectionCard(
        title: '回測成績（扣成本）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PerfTable(st: st),
            const SizedBox(height: 6),
            Text('${f.from.substring(0, 7)}～${f.to.substring(0, 7)}，每月檢視、隔天收盤調整。', style: small),
          ],
        ),
      ),
      const SectionCard(
        title: '要注意',
        child: InfoTable([
          ('不是聖杯', '試過二十幾種方法後最好的一個，多少有運氣成分；未來大概會比回測差一些。'),
          ('盤整年普通', '優勢主要在強勢多頭（2020 年以後）；2014–2019 大約跟 0050 打平。'),
          ('要準時', '每月檢視日隔天調整；跌破 50 日均線當天就賣。晚一週、少調整，效果明顯變差。'),
          ('進攻波動大', '進攻部分單獨看曾經跌 40%；所以只放 30%，穩健部分負責穩住。'),
          ('停損很常見', '平均大約每週一次有股票跌破 50 日均線要賣，是正常的。'),
        ], keyWidth: 96),
      ),
      SectionCard(
        title: '規則',
        child: InfoTable([
          ('穩健 70%', '0050。大盤（加權報酬指數）在 200 日均線上就持有，跌破就改放現金；每月 11 日後第一個交易日檢視。'),
          ('進攻 30%', '每月挑 10 檔強勢股平均配置，條件見名單下方；不足 10 檔的部分放 0050。'),
          ('停損', '進攻名單任何一檔收盤跌破 50 日均線，當天賣出放現金，下次檢視再重新挑。'),
          ('比例', '每月檢視時調回 70／30。'),
        ], keyWidth: 96),
      ),
    ];
    return SplitView(left: left, right: right, leftFlex: 12, rightFlex: 9);
  }

  static String _todo(StrategyResult st, String today, bool reviewDay) {
    final out = <String>[];
    final stopToday = st.picks.where((p) => p.stoppedOn == today).length;
    if (reviewDay) out.add('今天是每月檢視日：明天收盤照名單和比例調整');
    if (stopToday > 0) out.add('今天有 $stopToday 檔跌破 50 日均線：收盤賣出、改放現金');
    final near = st.picks.where((p) => p.stoppedOn == null && p.gap50 < 0.03).length;
    if (near > 0) out.add('$near 檔離 50 日均線不到 3%，留意');
    if (out.isEmpty) out.add('不用動作；每天收盤後看一下有沒有跌破 50 日均線');
    return out.join('；');
  }
}

class _PerfTable extends StatelessWidget {
  final StrategyResult st;
  const _PerfTable({required this.st});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
      decoration: head ? BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: .8)) : null,
      children: [
        for (final c in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: Text(c, style: TextStyle(fontSize: 13, fontWeight: head ? FontWeight.w800 : FontWeight.w500)),
          ),
      ],
    );
    const idx = [0, 3, 4]; // 策略、0050、大盤
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(horizontalInside: BorderSide(color: scheme.outlineVariant)),
        children: [
          row(['期間', for (final i in idx) StrategyResult.names[i]], head: true),
          for (final p in st.periods) ...[
            row(['${p.label} 年化', for (final i in idx) sp(p.v[i].$1)]),
            row(['　最大跌幅', for (final i in idx) pc(p.v[i].$2)]),
          ],
        ],
      ),
    );
  }
}

class _EtfRow extends StatelessWidget {
  final double weight;
  final bool marketOn;
  const _EtfRow({required this.weight, required this.marketOn});

  @override
  Widget build(BuildContext context) {
    final bars = context.read<HistoryStore>().rawSeriesOf('0050');
    return InkWell(
      onTap: () => _openStock(context, '0050'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Weight(pc(weight, 1)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('0050 元大台灣50', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const CloseText('0050'),
                      Tag(
                        marketOn ? '持有' : '改放現金',
                        marketOn ? const Color(0xFF2E7D32) : const Color(0xFF5B8DB8),
                        filled: true,
                      ),
                    ],
                  ),
                  Text(
                    marketOn ? '大盤在 200 日均線上：持有（006208 也可以）' : '大盤跌破 200 日均線：先放現金，等站回去再買',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const PriceTrend('0050'),
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

class _PickRow extends StatelessWidget {
  final LtResult r;
  final PickStatus ps;
  final double weight;
  const _PickRow({required this.r, required this.ps, required this.weight});

  @override
  Widget build(BuildContext context) {
    final s = r.data.stocks[ps.pick.si];
    final x = r.live.of(ps.pick.si);
    final stopped = ps.stoppedOn != null;
    final (tag, color) = stopped
        ? ('已跌破 50 日線', const Color(0xFF5B8DB8))
        : ps.gap50 < 0.03
        ? ('接近停損', const Color(0xFFC98A00))
        : ('持有', const Color(0xFF2E7D32));
    return InkWell(
      onTap: () => _openStock(context, s.code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Weight(pc(weight, 1), color: stopped ? Theme.of(context).disabledColor : null),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${s.code} ${s.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      CloseText(s.code),
                      Tag(tag, color, filled: true),
                    ],
                  ),
                  Text(
                    [
                      '一年漲 ${sp(ps.pick.mom12, 0)}',
                      '營收近 3 月年增 ${sp(ps.pick.revYoy3, 0)}',
                      '離一年高點 ${sp(ps.pick.distHigh, 0)}',
                      stopped ? '${ps.stoppedOn} 跌破 50 日均線：賣出放現金' : '比 50 日均線高 ${pc(ps.gap50, 1)}',
                      if (x != null && !x.raw.val60.isNaN) '每天成交約 ${moneyText(x.raw.val60)}',
                    ].join('・'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  PriceTrend(s.code),
                  if (!stopped) _Amount(weight: weight, price: x?.raw.close),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 百萬元 → 「3,000 萬」「2.5 億」。
String moneyText(double millions) => millions >= 100
    ? '${(millions / 100).toStringAsFixed(millions >= 1000 ? 0 : 1)} 億元'
    : '${(millions * 100).round()} 萬元';

/// 依我的持股：同一套規則看每一檔。
class _HoldingsView extends StatelessWidget {
  final LtResult r;
  final StrategyResult st;
  const _HoldingsView({required this.r, required this.st});

  /// 持股的收盤和 50 日均線：上市股票用長期資料的含息價（跟回測的停損一樣）；上櫃、ETF 用每日行情。
  (double, double)? _ma50(BuildContext context, String code) {
    final si = r.data.index[code];
    if (si != null) {
      final s = r.data.stocks[si];
      final t = r.data.nd - 1;
      final px = s.trAt(t), m = trMa(s, t, st.cfg.stopMa);
      if (!px.isNaN && !m.isNaN) return (px, m);
    }
    final bars = context.read<HistoryStore>().rawSeriesOf(code);
    if (bars.length < 50) return null;
    final last = bars.sublist(bars.length - 50);
    return (bars.last.close, last.fold(0.0, (a, b) => a + b.close) / 50);
  }

  @override
  Widget build(BuildContext context) {
    final holdings = context.watch<HoldingsStore>().open;
    final codes = <String>{for (final h in holdings) h.code}.toList()..sort();
    if (codes.isEmpty) {
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('「持股」頁還沒有持股。輸入（或從 stock_acc 同步）你手上的股票之後，這裡會照同一套規則逐檔檢查：該續抱、賣出還是換。'),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: () => HomeShell.goTo(context, HomeShell.holdings), child: const Text('到持股頁')),
          ],
        ),
      );
    }
    final pickOf = {for (final p in st.picks) r.data.stocks[p.pick.si].code: p};
    final rows = <(String, String, Color, String)>[]; // code, 動作, 顏色, 理由
    for (final code in codes) {
      if (coreEtfCodes.contains(code)) {
        rows.add(
          st.marketOn
              ? (code, '續抱', const Color(0xFF2E7D32), '穩健部位（0050 類）：大盤在 200 日均線上，持有')
              : (code, '改放現金', const Color(0xFF5B8DB8), '穩健部位（0050 類）：大盤跌破 200 日均線，照規則先放現金'),
        );
        continue;
      }
      final p = pickOf[code];
      final m = _ma50(context, code);
      final below = m != null && m.$1 < m.$2;
      if (p != null) {
        rows.add(
          p.stoppedOn != null || below
              ? (code, '賣出', const Color(0xFFD32F2F), '在進攻名單裡，但收盤跌破 50 日均線：照規則賣出放現金')
              : (code, '續抱', const Color(0xFF2E7D32), '在本月進攻名單裡，還在 50 日均線上'),
        );
        continue;
      }
      rows.add(
        below
            ? (code, '建議賣出', const Color(0xFFD32F2F), '不在名單、收盤也跌破 50 日均線：建議賣出，換成名單裡的股票或放現金')
            : m == null
            ? (code, '觀察', const Color(0xFFC98A00), '不在名單；資料不足 50 天（上櫃或 ETF 請先到「工具」抓每日行情），無法判斷 50 日均線')
            : (code, '觀察', const Color(0xFFC98A00), '不在本月名單、還在 50 日均線上：可以續抱，跌破 50 日均線就賣；新的錢買名單裡的'),
      );
    }
    final held = codes.toSet();
    final cands = [
      for (final p in st.picks)
        if (p.stoppedOn == null && !held.contains(r.data.stocks[p.pick.si].code)) r.data.stocks[p.pick.si],
    ];
    final sell = rows.where((x) => x.$2.contains('賣') || x.$2.contains('現金')).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: sell == 0 ? '目前不用賣' : '建議處理 $sell 檔',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '手上 ${codes.length} 檔，照同一套規則看：0050 類跟著大盤 200 日均線；個股跌破 50 日均線就賣；'
                '不在名單但還在均線上的不急著換。',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              if (cands.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('可以買的（本月名單、還沒持有）：', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in cands)
                      ActionChip(label: Text('${c.code} ${c.name}'), onPressed: () => _openStock(context, c.code)),
                  ],
                ),
              ],
            ],
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, (code, act, color, why)) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                InkWell(
                  onTap: () => _openStock(context, code),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Tag(act, color, filled: true),
                            Text(
                              '$code ${r.data.stock(code)?.name ?? kBuiltinStocksByCode[code]?.name ?? ''}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            CloseText(code),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(why, style: Theme.of(context).textTheme.bodySmall),
                        PriceTrend(code),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
      ),
    );
  }
}
