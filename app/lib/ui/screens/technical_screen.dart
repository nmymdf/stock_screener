/// 「技術選股」：用本機存好的每日收盤行情，依均線、RSI、量比、新高等條件
/// 篩選全市場。機械化篩選，不是投資建議。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/stock_catalog.dart';
import '../../logic/technical_screen.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sync_status.dart';
import 'stock_detail_screen.dart';

class TechnicalScreen extends StatefulWidget {
  const TechnicalScreen({super.key});

  @override
  State<TechnicalScreen> createState() => _TechnicalScreenState();
}

class _TechnicalScreenState extends State<TechnicalScreen> {
  static const _pageSize = 100;
  int _shown = _pageSize;

  // 篩選是在本機算的，但兩千多檔每次重畫都重算太浪費：條件或資料沒變就沿用。
  ScreenCriteria? _lastCriteria;
  Map<String, dynamic>? _lastSeries;
  ScreenOutcome? _outcome;

  ScreenOutcome _compute(HistoryStore store) {
    final series = store.seriesByCode;
    if (_outcome == null || !identical(_lastCriteria, store.criteria) || !identical(_lastSeries, series)) {
      _outcome = runScreen(series, store.criteria);
      _lastCriteria = store.criteria;
      _lastSeries = series;
    }
    return _outcome!;
  }

  void _update(HistoryStore store, ScreenCriteria c) {
    setState(() => _shown = _pageSize);
    store.setCriteria(c);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final c = store.criteria;
    final hasData = store.tradingDates.isNotEmpty;
    final outcome = hasData ? _compute(store) : null;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const DisclaimerCard(
          text: '這是依技術指標做的機械化篩選（均線、RSI、成交量、新高），不是投資建議、'
              '也不是預測——沒有任何指標組合能保證篩出來的股票之後會賺錢，買賣前務必自己再確認。',
        ),
        const SizedBox(height: 8),
        const SyncStatusCard(),
        const SectionHeader(left: '常用條件（點一下套用，套用後還可以自己調整）'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final p in kScreenPresets)
            Tooltip(
              message: p.description,
              child: ActionChip(label: Text(p.name), onPressed: () => _update(store, p.criteria)),
            ),
        ]),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            title: const Text('篩選條件', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(describeCriteria(c), style: const TextStyle(fontSize: 12)),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            children: [_CriteriaEditor(criteria: c, onChanged: (n) => _update(store, n))],
          ),
        ),
        if (outcome != null) ...[
          SectionHeader(
            left: '符合 ${outcome.results.length} 檔（資料截至 ${store.latestDate} 收盤）',
            right: '依${c.sort.label}排序',
          ),
          if (outcome.skippedShortHistory > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${outcome.skippedShortHistory} 檔歷史天數不足 ${c.requiredBars} 天、無法判斷，已略過'
                '${store.tradingDates.length < c.requiredBars ? '——先到上面補抓更多天的資料' : '（多半是新上市）'}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          RowList(
            emptyText: '沒有符合這組條件的股票，試著放寬一些條件',
            children: [
              for (var i = 0; i < outcome.results.length && i < _shown; i++)
                _ResultRow(rank: i + 1, result: outcome.results[i]),
            ],
          ),
          if (outcome.results.length > _shown)
            TextButton(
              onPressed: () => setState(() => _shown += _pageSize),
              child: Text('再顯示 ${_pageSize < outcome.results.length - _shown ? _pageSize : outcome.results.length - _shown} 檔'),
            ),
        ],
      ],
    );
  }
}

/// 條件的一行文字摘要，收合時顯示在標題下面。
String describeCriteria(ScreenCriteria c) {
  final parts = <String>[
    if (c.bullishAlignment) '多頭排列',
    if (c.aboveMa20) '站上20日線',
    if (c.aboveMa60) '站上60日線',
    if (c.goldenCrossWithin != null) '${c.goldenCrossWithin}天內黃金交叉',
    if (c.rsiMax != null) 'RSI≤${c.rsiMax!.round()}',
    if (c.rsiMin != null) 'RSI≥${c.rsiMin!.round()}',
    if (c.breakoutDays != null) '創${c.breakoutDays}日新高',
    if (c.minVolRatio != null) '量比≥${c.minVolRatio}',
    if (c.minChangePct != null) c.minChangePct! < 0.1 ? '今日上漲' : '今日漲≥${c.minChangePct}%',
    if (c.minAvgVolLots != null) '均量≥${c.minAvgVolLots!.round()}張',
    if (c.minPrice != null) '股價≥${c.minPrice!.round()}',
    if (c.maxPrice != null) '股價≤${c.maxPrice!.round()}',
  ];
  return parts.isEmpty ? '不限（列出全部）' : parts.join('、');
}

class _CriteriaEditor extends StatelessWidget {
  final ScreenCriteria criteria;
  final ValueChanged<ScreenCriteria> onChanged;
  const _CriteriaEditor({required this.criteria, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = criteria;
    Widget sw(String title, bool v, ScreenCriteria Function(bool) f) => SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(fontSize: 13)),
          value: v,
          onChanged: (x) => onChanged(f(x)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sw('多頭排列（收盤 > 5日 > 20日 > 60日線）', c.bullishAlignment, (x) => c.copyWith(bullishAlignment: x)),
      sw('收盤站上 20 日線（月線）', c.aboveMa20, (x) => c.copyWith(aboveMa20: x)),
      sw('收盤站上 60 日線（季線）', c.aboveMa60, (x) => c.copyWith(aboveMa60: x)),
      _Option<int?>(
        label: '5 日線黃金交叉 20 日線',
        value: c.goldenCrossWithin,
        options: const [(null, '不限'), (1, '今天'), (3, '3 天內'), (5, '5 天內'), (10, '10 天內')],
        onChanged: (v) => onChanged(c.copyWith(goldenCrossWithin: v)),
      ),
      _Option<(double?, double?)>(
        label: 'RSI(14)',
        value: (c.rsiMin, c.rsiMax),
        options: const [
          ((null, null), '不限'),
          ((null, 30.0), '≤ 30（超賣）'),
          ((null, 40.0), '≤ 40'),
          ((40.0, 60.0), '40 ～ 60'),
          ((60.0, null), '≥ 60'),
          ((70.0, null), '≥ 70（過熱）'),
        ],
        onChanged: (v) => onChanged(c.copyWith(rsiMin: v.$1, rsiMax: v.$2)),
      ),
      _Option<int?>(
        label: '收盤創新高',
        value: c.breakoutDays,
        options: const [(null, '不限'), (5, '5 日新高'), (10, '10 日新高'), (20, '20 日新高'), (60, '60 日新高')],
        onChanged: (v) => onChanged(c.copyWith(breakoutDays: v)),
      ),
      _Option<double?>(
        label: '量比（今天量 ÷ 前 20 日均量）',
        value: c.minVolRatio,
        options: const [(null, '不限'), (1.2, '≥ 1.2 倍'), (1.5, '≥ 1.5 倍'), (2.0, '≥ 2 倍'), (3.0, '≥ 3 倍')],
        onChanged: (v) => onChanged(c.copyWith(minVolRatio: v)),
      ),
      _Option<double?>(
        label: '今日漲跌',
        value: c.minChangePct,
        options: const [(null, '不限'), (0.01, '上漲'), (2.0, '漲 ≥ 2%'), (5.0, '漲 ≥ 5%'), (9.0, '漲 ≥ 9%（接近漲停）')],
        onChanged: (v) => onChanged(c.copyWith(minChangePct: v)),
      ),
      _Option<double?>(
        label: '20 日均量（過濾冷門股）',
        value: c.minAvgVolLots,
        options: const [(null, '不限'), (100.0, '≥ 100 張'), (500.0, '≥ 500 張'), (1000.0, '≥ 1,000 張'), (5000.0, '≥ 5,000 張')],
        onChanged: (v) => onChanged(c.copyWith(minAvgVolLots: v)),
      ),
      _Option<(double?, double?)>(
        label: '股價',
        value: (c.minPrice, c.maxPrice),
        options: const [
          ((null, null), '不限'),
          ((null, 50.0), '≤ 50 元'),
          ((null, 100.0), '≤ 100 元'),
          ((50.0, 300.0), '50 ～ 300 元'),
          ((100.0, null), '≥ 100 元'),
          ((500.0, null), '≥ 500 元'),
        ],
        onChanged: (v) => onChanged(c.copyWith(minPrice: v.$1, maxPrice: v.$2)),
      ),
      _Option<ScreenSort>(
        label: '排序',
        value: c.sort,
        options: [for (final s in ScreenSort.values) (s, s.label)],
        onChanged: (v) => onChanged(c.copyWith(sort: v)),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => onChanged(const ScreenCriteria()),
          child: const Text('全部清除'),
        ),
      ),
    ]);
  }
}

/// 一行「標題 ＋ 下拉選單」。目前的值不在選項裡（例如舊版存的設定）時，
/// 會額外顯示成「自訂」，不會讓下拉選單出錯。
class _Option<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _Option({required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final known = options.any((o) => o.$1 == value);
    final items = [
      ...options,
      if (!known) (value, '自訂'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        DropdownButton<int>(
          value: items.indexWhere((o) => o.$1 == value),
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (var i = 0; i < items.length; i++)
              DropdownMenuItem(value: i, child: Text(items[i].$2, style: const TextStyle(fontSize: 13))),
          ],
          onChanged: (i) {
            if (i != null) onChanged(items[i].$1);
          },
        ),
      ]),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final int rank;
  final ScreenResult result;
  const _ResultRow({required this.rank, required this.result});

  @override
  Widget build(BuildContext context) {
    final ind = result.ind;
    final name = kBuiltinStocksByCode[ind.code]?.name ?? '';
    return InfoRow(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StockDetailScreen(code: ind.code, reasons: result.reasons),
      )),
      title: Row(children: [
        if (rank <= 5) RankBadge(rank: rank),
        Flexible(child: Text('${ind.code} $name', overflow: TextOverflow.ellipsis)),
      ]),
      subtitle: Text(result.reasons.join(' · ')),
      trailingTop: Text(f2(ind.close)),
      trailingBottom: Text(pctTxt(ind.changePct), style: TextStyle(color: changeColor(context, ind.changePct ?? 0))),
    );
  }
}
