/// 「選股」：兩份候選名單（強勢成長、穩健存股）由你挑；手上的持股逐檔健檢。
///
/// - 不給比例、不替你配置：名單只是候選，買哪幾檔、買多少自己決定。
/// - 每份名單附上 2014 年以來每月一份名單的真實成績（賺錢機率、贏 0050 的比例、最差一次）。
/// - 持股健檢：趨勢正常／跌破年線／理由破壞，加上六個面向的好、中、差和實際數字。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/factors.dart' show LtScore;
import '../../core/lists.dart';
import '../../core/lt_analysis.dart';
import '../../core/portfolio.dart' show coreEtfCodes, moneyText;
import '../../core/strategy.dart';
import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/longterm_store.dart';
import '../../data/stock_catalog.dart';
import '../../data/stock_industry.dart' show industryOf;
import '../home.dart';
import '../layout.dart';
import '../widgets/common.dart';
import '../widgets/lt_widgets.dart';
import '../widgets/score_widgets.dart';
import 'stock_report_screen.dart';

const _green = Color(0xFF2E7D32);
const _amber = Color(0xFFC98A00);
const _red = Color(0xFFD32F2F);
const _grey = Color(0xFF6B7A8C);

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  int _mode = 0;
  PickList _list = PickList.strong;

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeader(
          icon: Icons.filter_alt_outlined,
          title: '選股',
          subtitle: '候選名單由你挑（不給比例）；手上的持股逐檔健檢',
          trailing: lt.result == null
              ? null
              : Text('資料到 ${lt.result!.date}', style: Theme.of(context).textTheme.bodySmall),
        ),
        PackGate(
          builder: (context, r) {
            if (r.lists.isEmpty) return const _NeedUpdate();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r.strategy != null) _MarketCard(st: r.strategy!),
                Center(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, icon: Icon(Icons.list_alt), label: Text('候選名單')),
                      ButtonSegment(value: 1, icon: Icon(Icons.health_and_safety_outlined), label: Text('我的持股健檢')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                ),
                const SizedBox(height: 8),
                if (_mode == 0)
                  _ListsView(r: r, kind: _list, onKind: (k) => setState(() => _list = k))
                else
                  _HealthView(r: r),
                if (lt.analyzing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '依公開資料、固定規則整理的參考，不是投資建議。過去的成績不代表未來，買什麼、買多少請自己決定，盈虧自行負責。'),
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

/// 大盤狀態：加權報酬指數在不在 200 日均線上（0050 的抱法參考）。
class _MarketCard extends StatelessWidget {
  final StrategyResult st;
  const _MarketCard({required this.st});

  @override
  Widget build(BuildContext context) {
    final on = st.marketGapNow > 0;
    final f = st.full;
    final small = Theme.of(context).textTheme.bodySmall;
    return SectionCard(
      title: '大盤狀態',
      trailing: Tag(on ? '在年線上' : '跌破年線', on ? _green : _amber, filled: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            on
                ? '加權報酬指數比 200 日均線高 ${pc(st.marketGapNow, 1)}：多頭，0050 可以照常抱著。'
                : '加權報酬指數比 200 日均線低 ${pc(-st.marketGapNow, 1)}：保守的人可以先減碼 0050，等站回年線再買回。',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 2),
          Text(
            '這個抱法（在年線上抱 0050、跌破放現金，每月看一次）${f.from.substring(0, 4)} 年以來：'
            '年化 ${sp(f.v[1].$1)}、最大跌幅 ${pc(f.v[1].$2)}；一直抱 0050 是 ${sp(f.v[3].$1)}、${pc(f.v[3].$2)}。'
            '報酬差不多，大跌時少跌很多。',
            style: small,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── 候選名單 ─────────────────────────

class _ListsView extends StatelessWidget {
  final LtResult r;
  final PickList kind;
  final ValueChanged<PickList> onKind;
  const _ListsView({required this.r, required this.kind, required this.onKind});

  @override
  Widget build(BuildContext context) {
    final lr = r.lists[kind]!;
    final small = Theme.of(context).textTheme.bodySmall;
    final held = {for (final h in context.watch<HoldingsStore>().open) h.code};
    final left = <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final k in PickList.values)
            if (r.lists[k] != null)
              ChoiceChip(
                label: Text('${k.label}（${r.lists[k]!.now.length}）'),
                selected: k == kind,
                onSelected: (_) => onKind(k),
              ),
        ],
      ),
      const SizedBox(height: 6),
      SectionCard(
        title: kind.label,
        trailing: Text('同產業最多 $kPerIndustry 檔', style: small),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(kind.oneLine, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 4),
            if (lr.now.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('今天沒有符合條件的股票。', style: TextStyle(fontSize: 13)),
              )
            else
              for (final (i, x) in lr.now.indexed) ...[
                if (i > 0) const Divider(height: 1),
                _ListRow(r: r, x: x, kind: kind, held: held.contains(x.code)),
              ],
            const SizedBox(height: 4),
            Text('名單只是候選：買哪幾檔、買多少由你決定。名單每天依最新資料更新。', style: small),
          ],
        ),
      ),
    ];
    final right = <Widget>[
      SectionCard(
        title: '過去成績（每月一份名單）',
        child: ListStatTable(lr: lr),
      ),
      SectionCard(title: '一句話', child: InfoTable(_verdict(kind), keyWidth: 84)),
      SectionCard(title: '入選條件', child: InfoTable(_rules(kind), keyWidth: 84)),
    ];
    return SplitView(left: left, right: right, leftFlex: 12, rightFlex: 9);
  }

  static List<(String, String)> _verdict(PickList k) => switch (k) {
    PickList.strong => const [
      ('適合', '想抱幾個月、願意看盤的人。'),
      ('表現', '多頭年（2020 以後）抱 3～6 個月平均比 0050 多，賺錢機率約七成；盤整年（2014–2019）輸 0050。'),
      ('不適合', '抱一年以上：大多輸 0050。'),
      ('出場', '收盤跌破 50 日均線就走，不要抱著等；名單上會標「接近 50 日線」。'),
    ],
    PickList.income => const [
      ('適合', '求穩、想長期領股息的人。'),
      ('表現', '抱一年賺錢的機率最高（約 84%），最差一次只跌約 13%。'),
      ('代價', '報酬比 0050 少：多頭時大多跟不上。這份名單不是拿來贏大盤的。'),
      ('出場', '配息中斷、年線下彎或出現地雷時，名單會把它拿掉。'),
    ],
  };

  static List<(String, String)> _rules(PickList k) => switch (k) {
    PickList.strong => const [
      ('趨勢', '股價 > 50 日線 > 150 日線 > 200 日線，200 日線一個月來往上。'),
      ('位置', '離一年高點 25% 以內、比一年低點高 30% 以上。'),
      ('強度', '一年漲幅在全市場前 30%，名單照一年漲幅排。'),
      ('營收', '近 3 個月營收年增 20% 以上。'),
      ('買得到', '每天平均成交 2 億元以上；沒有地雷（虧損、殖利率陷阱、年線下彎又營收衰退）。'),
    ],
    PickList.income => const [
      ('規模', '上市公司市值前 100 大。'),
      ('配息', '近 5 年每年都有配息，殖利率 3% 以上，名單照殖利率排。'),
      ('穩定', '一年波動低於這群大公司的中位數，年線沒有下彎。'),
      ('避雷', '沒有虧損、殖利率陷阱（配的比賺的多）、營收衰退又轉弱。'),
    ],
  };
}

class _ListRow extends StatelessWidget {
  final LtResult r;
  final LtScore x;
  final PickList kind;
  final bool held;
  const _ListRow({required this.r, required this.x, required this.kind, required this.held});

  @override
  Widget build(BuildContext context) {
    final s = r.data.stocks[x.si];
    final raw = x.raw;
    final t = r.live.t;
    final px = s.trAt(t), m50 = trMa(s, t, 50);
    final gap50 = px.isNaN || m50.isNaN ? double.nan : px / m50 - 1;
    final (tag, color) = switch (kind) {
      PickList.strong when !gap50.isNaN && gap50 < 0 => ('跌破 50 日線', _grey),
      PickList.strong when !gap50.isNaN && gap50 < 0.03 => ('接近 50 日線', _amber),
      PickList.strong => ('在 50 日線上', _green),
      PickList.income => ('殖利率 ${raw.yld.toStringAsFixed(1)}%', _green),
    };
    final facts = switch (kind) {
      PickList.strong => [
        '營收近 3 月年增 ${sp(raw.revYoy3, 0)}',
        '比 50 日線高 ${sp(gap50, 1)}',
        if (!raw.val60.isNaN) '每天成交約 ${moneyText(raw.val60)}',
      ],
      PickList.income => [
        '近 5 年都配息',
        if (!raw.pe.isNaN && raw.pe > 0) '本益比 ${raw.pe.toStringAsFixed(1)}',
        if (!raw.roe.isNaN) 'ROE ${(raw.roe * 100).round()}%',
        if (!raw.vol.isNaN) '一年波動 ${(raw.vol * 100).round()}%',
        if (!raw.val60.isNaN) '每天成交約 ${moneyText(raw.val60)}',
      ],
    };
    return InkWell(
      onTap: () => _openStock(context, s.code),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${s.code} ${s.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                CloseText(s.code),
                Tag(tag, color, filled: true),
                Tag(industryOf(s.code) ?? '其他', _grey),
                if (held) const Tag('已持有', Color(0xFF5B8DB8)),
              ],
            ),
            const SizedBox(height: 2),
            Text(facts.join('・'), style: Theme.of(context).textTheme.bodySmall),
            PriceTrend(s.code),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── 持股健檢 ─────────────────────────

class _HealthView extends StatelessWidget {
  final LtResult r;
  const _HealthView({required this.r});

  /// 上櫃、ETF：用每日行情看在不在 200 日均線上。
  double? _gap200Bars(BuildContext context, String code) {
    final bars = context.read<HistoryStore>().rawSeriesOf(code);
    if (bars.length < 200) return null;
    final last = bars.sublist(bars.length - 200);
    return bars.last.close / (last.fold(0.0, (a, b) => a + b.close) / 200) - 1;
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
            const Text('「持股」頁還沒有持股。輸入（或從 stock_acc 同步）你手上的股票之後，這裡會逐檔健檢。'),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: () => HomeShell.goTo(context, HomeShell.holdings), child: const Text('到持股頁')),
          ],
        ),
      );
    }
    final scored = <HoldingHealth>[];
    final others = <String>[];
    for (final c in codes) {
      final h = healthOf(r.data, r.live, c, r.lists);
      if (h == null) {
        others.add(c);
      } else {
        scored.add(h);
      }
    }
    scored.sort((a, b) => b.health.index.compareTo(a.health.index));
    final n = {for (final k in Health.values) k: scored.where((h) => h.health == k).length};
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '健檢結果',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in Health.values.reversed)
                    if (n[k]! > 0) Tag('${k.label} ${n[k]} 檔', _healthColor(k), filled: true),
                  if (others.isNotEmpty) Tag('不在評分範圍 ${others.length} 檔', _grey),
                ],
              ),
              const SizedBox(height: 6),
              const InfoTable([
                ('趨勢正常', '站在年線上、長期理由還在（個別警示會另外列出）。'),
                ('跌破年線', '股價在 200 日均線之下。過去這種股票之後 3～6 個月通常比較弱。'),
                ('理由破壞', '趨勢轉弱又營收衰退、虧損又轉弱，或總分掉到全市場後 15%。'),
              ], keyWidth: 84),
              const SizedBox(height: 4),
              Text(
                '檢驗（2014 年以來每月所有上市股票）：之後 6 個月平均，2014–2019 趨勢正常 +3.6%、跌破年線 +1.1%、理由破壞 0.0%；'
                '2020 以後 +14.5%、+5.4%、+8.8%。看一年就差不多，所以這是幾個月內的參考，不是長期預言。',
                style: small,
              ),
            ],
          ),
        ),
        for (final h in scored) _HealthCard(r: r, h: h),
        for (final c in others) _OtherCard(code: c, gap200: _gap200Bars(context, c), market: r.strategy),
      ],
    );
  }
}

Color _healthColor(Health h) => switch (h) {
  Health.ok => _green,
  Health.belowYear => _amber,
  Health.broken => _red,
};

class _HealthCard extends StatelessWidget {
  final LtResult r;
  final HoldingHealth h;
  const _HealthCard({required this.r, required this.h});

  @override
  Widget build(BuildContext context) {
    final s = r.data.stock(h.code)!;
    final small = Theme.of(context).textTheme.bodySmall;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openStock(context, h.code),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tag(h.health.label, _healthColor(h.health), filled: true),
                  Text('${s.code} ${s.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  CloseText(s.code),
                  for (final k in h.inLists) Tag('在${k.label}名單', const Color(0xFF5B8DB8)),
                ],
              ),
              const SizedBox(height: 2),
              Text(h.health.advice, style: const TextStyle(fontSize: 13, height: 1.4)),
              Text(
                [
                  '離年線 ${sp(h.gap200, 1)}',
                  '離 50 日線 ${sp(h.gap50, 1)}',
                  if (h.flags.isNotEmpty) '警示：${h.flags.join('、')}',
                ].join('・'),
                style: small,
              ),
              const SizedBox(height: 6),
              Table(
                columnWidths: const {0: IntrinsicColumnWidth(), 1: IntrinsicColumnWidth(), 2: FlexColumnWidth()},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(horizontalInside: BorderSide(color: scheme.outlineVariant)),
                children: [
                  for (final d in h.dims)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Text(d.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                          child: _Grade(d.grade),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Text(d.detail.isEmpty ? '—' : d.detail, style: small),
                        ),
                      ],
                    ),
                ],
              ),
              PriceTrend(s.code),
            ],
          ),
        ),
      ),
    );
  }
}

class _Grade extends StatelessWidget {
  final int g;
  const _Grade(this.g);

  @override
  Widget build(BuildContext context) {
    final (t, c) = switch (g) {
      2 => ('好', _green),
      1 => ('中', _grey),
      0 => ('差', _red),
      _ => ('—', _grey),
    };
    return Tag(t, c, filled: g == 2 || g == 0);
  }
}

/// 上櫃、ETF：沒有評分，只看價格在不在年線上；0050 類看大盤。
class _OtherCard extends StatelessWidget {
  final String code;
  final double? gap200;
  final StrategyResult? market;
  const _OtherCard({required this.code, required this.gap200, required this.market});

  @override
  Widget build(BuildContext context) {
    final name = kBuiltinStocksByCode[code]?.name ?? '';
    final etf = coreEtfCodes.contains(code);
    final mk = market;
    final String text;
    final (String, Color) tag;
    if (etf && mk != null) {
      final on = mk.marketGapNow > 0;
      tag = on ? ('大盤在年線上', _green) : ('大盤跌破年線', _amber);
      text = on ? '市值型 ETF：大盤在年線上，照常抱著。' : '市值型 ETF：大盤跌破年線，保守的人可以先減碼，等站回去再買回。';
    } else if (gap200 == null) {
      tag = ('不在評分範圍', _grey);
      text = '上櫃股票或 ETF 沒有長期評分；到「工具」抓每日行情後，這裡會顯示在不在年線上。';
    } else {
      final on = gap200! >= 0;
      tag = on ? ('在年線上', _green) : ('跌破年線', _amber);
      text = '上櫃股票或 ETF 沒有長期評分，只看價格：離年線 ${sp(gap200!, 1)}。';
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openStock(context, code),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tag(tag.$1, tag.$2, filled: true),
                  Text('$code $name', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  CloseText(code),
                ],
              ),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
              PriceTrend(code),
            ],
          ),
        ),
      ),
    );
  }
}
