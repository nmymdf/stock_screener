/// 「比較」：輸入一檔股票看白話的現況總覽；輸入多檔（最多 6 檔）互相比較——
/// 綜合排名、誰在哪方面最強、相對走勢圖、逐項比較表。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/factors.dart';
import '../../data/longterm_store.dart';

import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/stock_catalog.dart';
import '../../logic/engine/analysis.dart';
import '../../logic/engine/horizon.dart';
import '../../logic/engine/industry_engine.dart';
import '../../logic/engine/signals.dart';
import '../../logic/ta.dart';
import '../format.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/analysis_gate.dart';
import '../widgets/charts.dart';
import '../widgets/horizon_widgets.dart';
import '../widgets/score_widgets.dart';
import 'stock_report_screen.dart';

const kCompareMax = 6;
const kCompareColors = [
  Color(0xFF2F6FA8),
  Color(0xFFE8743B),
  Color(0xFF0B9A8D),
  Color(0xFF8E24AA),
  Color(0xFFC9A000),
  Color(0xFFC2185B),
];

/// 把「2330 2317、聯發科」這種輸入拆成股票代號；認不得的放進 [unknown]。
List<String> parseStockInput(String text, {List<String>? unknown}) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'[\s,，、;；/]+'))) {
    final tok = raw.trim();
    if (tok.isEmpty) continue;
    if (kBuiltinStocksByCode.containsKey(tok.toUpperCase())) {
      out.add(tok.toUpperCase());
      continue;
    }
    final hit = searchStocks(tok);
    final exact = hit.where((s) => s.name == tok).toList();
    if (exact.isNotEmpty) {
      out.add(exact.first.code);
    } else if (hit.isNotEmpty) {
      out.add(hit.first.code);
    } else {
      unknown?.add(tok);
    }
  }
  return out;
}

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  int _period = 60;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(List<String> codes) {
    final store = context.read<HistoryStore>();
    final cur = [...store.compareCodes];
    for (final c in codes) {
      if (!cur.contains(c)) cur.add(c);
    }
    final over = cur.length > kCompareMax;
    store.setCompareCodes(cur.take(kCompareMax).toList());
    if (over) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('最多同時比較 $kCompareMax 檔，多的先不加入')));
    }
  }

  void _submit(String text) {
    final unknown = <String>[];
    final codes = parseStockInput(text, unknown: unknown);
    _add(codes);
    _ctrl.clear();
    if (unknown.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('找不到：${unknown.join('、')}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnalysisGate(
      builder: (context, a) {
        final store = context.watch<HistoryStore>();
        final codes = store.compareCodes;
        final reports = <StockReport>[];
        final missing = <String>[];
        for (final c in codes) {
          final r = a.stock(c);
          r == null ? missing.add(c) : reports.add(r);
        }
        final series = {for (final r in reports) r.code: StockSeries(r.code, store.seriesOf(r.code))};
        final colorOf = {for (var i = 0; i < codes.length; i++) codes[i]: kCompareColors[i % kCompareColors.length]};
        return [
          PageHeader(
            icon: Icons.compare_arrows,
            title: '個股查詢與比較',
            subtitle: '輸入一檔看白話現況；輸入多檔（最多 $kCompareMax 檔）互相比較。代號、名稱都可以，用空白或逗號分開。',
            trailing: Text('資料截至 ${a.latestDate}', style: Theme.of(context).textTheme.bodySmall),
          ),
          _inputCard(context, a, codes, colorOf),
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${missing.map((c) => '$c ${kBuiltinStocksByCode[c]?.name ?? ''}').join('、')}：今天沒有交易或本機沒有資料，無法分析。',
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          if (reports.isEmpty) const _Help(),
          if (reports.length == 1) _SingleView(r: reports.single, s: series[reports.single.code]!),
          if (reports.length >= 2) ...[
            _Conclusion(reports: reports, series: series, colorOf: colorOf),
            _RelativeChart(
              reports: reports,
              series: series,
              colorOf: colorOf,
              period: _period,
              onPeriod: (p) => setState(() => _period = p),
            ),
            _CompareTable(reports: reports, series: series, colorOf: colorOf),
          ],
        ];
      },
    );
  }

  Widget _inputCard(BuildContext context, AnalysisResult a, List<String> codes, Map<String, Color> colorOf) {
    final holdings = context.watch<HoldingsStore>().open.map((h) => h.code).toSet().toList();
    final ideal = context.select<LongTermStore, List<String>>((s) {
      final r = s.result;
      if (r == null) return const [];
      final l = r.sim.holdings.entries.toList()..sort((x, y) => y.value.$1.compareTo(x.value.$1));
      return [for (final e in l) r.data.stocks[e.key].code];
    });
    final store = context.read<HistoryStore>();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RawAutocomplete<StockInfo>(
                  textEditingController: _ctrl,
                  focusNode: _focus,
                  optionsBuilder: (v) {
                    final parts = v.text.split(RegExp(r'[\s,，、;；/]+'));
                    final last = parts.isEmpty ? '' : parts.last.trim();
                    if (last.isEmpty) return const Iterable<StockInfo>.empty();
                    return searchStocks(last).take(12);
                  },
                  displayStringForOption: (s) => '${s.code} ${s.name}',
                  onSelected: (s) {
                    _add([s.code]);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.clear());
                  },
                  fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                    controller: controller,
                    focusNode: focus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _submit,
                    decoration: const InputDecoration(hintText: '例如：2330 2317 聯發科', prefixIcon: Icon(Icons.search)),
                  ),
                  optionsViewBuilder: (context, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 420),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          children: [
                            for (final s in options)
                              ListTile(
                                dense: true,
                                title: Text('${s.code} ${s.name}'),
                                subtitle: Text(s.market),
                                onTap: () => onSelected(s),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _submit(_ctrl.text), child: const Text('加入')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final c in codes)
                InputChip(
                  avatar: CircleAvatar(backgroundColor: colorOf[c], radius: 6),
                  label: Text('$c ${kBuiltinStocksByCode[c]?.name ?? ''}'),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: c))),
                  onDeleted: () => store.setCompareCodes([...codes]..remove(c)),
                ),
              if (codes.isNotEmpty)
                TextButton.icon(
                  onPressed: () => store.setCompareCodes(const []),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('清除'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Text('快速加入：', style: Theme.of(context).textTheme.bodySmall),
              if (holdings.isNotEmpty)
                ActionChip(label: const Text('我的持股'), onPressed: () => _add(holdings.take(kCompareMax).toList())),
              if (ideal.isNotEmpty)
                ActionChip(label: const Text('理想組合前 5'), onPressed: () => _add(ideal.take(5).toList())),
              if (a.recommendations.isNotEmpty)
                ActionChip(
                  label: const Text('短線訊號前 5'),
                  onPressed: () => _add([for (final r in a.recommendations.take(5)) r.code]),
                ),
              if (a.watchlist.isNotEmpty)
                ActionChip(
                  label: const Text('觀察池前 5'),
                  onPressed: () => _add([for (final r in a.watchlist.take(5)) r.code]),
                ),
              if (codes.isNotEmpty && a.stock(codes.first)?.industry != null)
                ActionChip(
                  label: Text('${a.stock(codes.first)!.industry} 同業前 4'),
                  onPressed: () {
                    final ind = a.stock(codes.first)!.industry;
                    final peers = a.stocks.where((s) => s.industry == ind && s.liquid && s.code != codes.first).toList()
                      ..sort((x, y) => y.total.compareTo(x.total));
                    _add([for (final p in peers.take(4)) p.code]);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) => const SectionCard(
    title: '怎麼用',
    child: Bullets([
      '輸入一檔（例如 2330）：看白話的現況總覽——趨勢、位置、動能、量價、相對強度、產業與市場、關鍵價位、現在適不適合買。',
      '輸入多檔（例如 2330 2317 2454）：系統排出綜合順序，說明誰短線最強、誰中長期最好、誰波動最小、誰有進場訊號，並畫出相對走勢、列出逐項比較表（每一列最好的會標出來）。',
      '可以一次輸入多檔，用空白、逗號分開；也可以用「快速加入」把持股、理想組合、短線訊號、同業一次加進來。',
      '比較清單會記住，下次打開還在。點股票標籤可以看完整的個股報告。',
    ], BulletKind.info),
  );
}

// ───────── 單檔：現況總覽 ─────────

String _f(double v) => v >= 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(2);

/// 把一檔股票的現況寫成白話。
List<String> statusSummary(StockReport r, StockSeries s) {
  final i = s.length - 1;
  final out = <String>[];
  if (i < 1) return out;
  final c = s.close[i];
  final above = <String>[], below = <String>[];
  for (final (n, v) in [('20 日線', s.ema20[i]), ('50 日線', s.ema50[i]), ('200 日線', s.ema200[i])]) {
    if (!ok(v)) continue;
    (c >= v ? above : below).add('$n ${_f(v)}');
  }
  if (below.isEmpty && above.isNotEmpty) {
    out.add('趨勢：收盤 ${_f(c)} 站在 ${above.join('、')} 之上，屬於多頭結構。');
  } else if (above.isEmpty && below.isNotEmpty) {
    out.add('趨勢：收盤 ${_f(c)} 在 ${below.join('、')} 之下，屬於空頭結構，先不要急著接。');
  } else if (below.isNotEmpty) {
    out.add('趨勢：收盤 ${_f(c)} 在 ${above.join('、')} 之上，但還在 ${below.join('、')} 之下，方向還不一致。');
  }
  final look = math.min(250, i);
  if (look >= 60) {
    final top = maxIn(s.high, i - look, i);
    final dist = (top - c) / top * 100;
    out.add(
      dist <= 1
          ? '位置：就在 $look 日高點附近（${_f(top)}），上方沒有套牢壓力，但也要小心追高。'
          : '位置：離 $look 日高點 ${_f(top)} 還有 ${dist.toStringAsFixed(1)}%。',
    );
  }
  if (ok(s.rsi[i])) {
    final v = s.rsi[i];
    out.add(
      'RSI ${v.toStringAsFixed(0)}：${v > 80
          ? '過熱，短線容易拉回'
          : v >= 50
          ? '在多頭區，動能健康'
          : v >= 40
          ? '動能轉弱，還沒到超賣'
          : '弱勢區，等止跌訊號'}。',
    );
  }
  out.add('量價：${r.pv.state.label}——${r.pv.detail}。');
  if (r.rsRank != null && r.rsPct != null) {
    out.add('相對強度：全市場第 ${r.rsRank} 名（前 ${((1 - r.rsPct!) * 100).clamp(1, 100).toStringAsFixed(0)}%）。');
  }
  if (r.industry != null) {
    out.add('產業：${r.industry}${r.industryClass == null ? '' : '目前「${r.industryClass!.label}」'}。');
  }
  out.add('判斷：${r.opportunity.label}——${r.opportunity.strategy}');
  final p = r.primary;
  if (p != null) {
    out.add(
      '今天有「${p.hit.strategy.label}」進場訊號，通過所有檢查：明天開盤 ≤ ${_f(p.plan.maxEntry)} 可以買，'
      '停損 ${_f(p.plan.stop)}、目標 ${_f(p.plan.target)}。',
    );
  } else if (r.hits.isNotEmpty) {
    out.add('今天有訊號但被否決：${r.allVetoes.first}');
  } else if (r.triggers.isNotEmpty) {
    out.add('今天沒有進場訊號。可以等：${r.triggers.first}');
  }
  return out;
}

/// 關鍵價位：上方壓力、下方支撐。
List<(String, double, bool)> keyLevels(StockSeries s) {
  final i = s.length - 1;
  final out = <(String, double, bool)>[];
  if (i < 21) return out;
  final c = s.close[i];
  final hh20 = maxIn(s.high, i - 19, i), ll20 = minIn(s.low, i - 19, i);
  final look = math.min(250, i);
  final top = maxIn(s.high, i - look, i);
  if (top > c * 1.001) out.add(('$look 日高點', top, true));
  if (hh20 > c * 1.001 && (hh20 - top).abs() > 0.01) out.add(('20 日高點', hh20, true));
  for (final (n, v) in [('20 日線', s.ema20[i]), ('50 日線', s.ema50[i]), ('200 日線', s.ema200[i])]) {
    if (ok(v)) out.add((n, v, v > c));
  }
  out.add(('20 日低點', ll20, false));
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}

class _SingleView extends StatelessWidget {
  final StockReport r;
  final StockSeries s;
  const _SingleView({required this.r, required this.s});

  @override
  Widget build(BuildContext context) {
    final n = s.length;
    final from = math.max(0, n - 120);
    List<double?> tail(List<double> v) => [for (var i = from; i < n; i++) v[i].isNaN ? null : v[i]];
    final levels = keyLevels(s);
    final scheme = Theme.of(context).colorScheme;
    return SplitView(
      left: [
        SectionCard(
          title: '${r.code} ${r.name}・現況總覽',
          trailing: TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: r.code))),
            child: const Text('完整報告 ›'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ScoreBadge(score: r.total, size: 56, caption: '總分'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(f2(r.close), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            Text(
                              pctTxt(r.changePct),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: changeColor(context, r.changePct),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: [
                            Tag(r.opportunity.label, opportunityColor(r.opportunity), filled: true),
                            DurationTag(r.duration),
                            if (r.recommended)
                              Tag('今日推薦：${r.primary!.hit.strategy.label}', const Color(0xFF0B7A6F), filled: true),
                            if (r.industry != null) Tag(r.industry!, industryClassColor(r.industryClass)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              HorizonTriple(short: r.short, medium: r.medium, long: r.long),
              const SizedBox(height: 10),
              Bullets(statusSummary(r, s), BulletKind.info),
              if (r.warnings.isNotEmpty) ...[const SizedBox(height: 4), Bullets(r.warnings, BulletKind.warn)],
            ],
          ),
        ),
      ],
      right: [
        SectionCard(
          title: '走勢（最近 ${n - from} 個交易日）',
          child: SimpleChart(
            height: 260,
            series: [
              ChartSeries('收盤', tail(s.close), scheme.primary, width: 2),
              ChartSeries('20 日線', tail(s.ema20), Colors.orange),
              ChartSeries('50 日線', tail(s.ema50), Colors.purple),
            ],
            lines: [
              if (r.primary != null) ChartLine('停損', r.primary!.plan.stop, AppColors.down),
              if (r.primary != null) ChartLine('目標', r.primary!.plan.target, AppColors.up),
            ],
            volumes: [for (var i = from; i < n; i++) s.vol[i]],
            volumeUp: [for (var i = from; i < n; i++) i == 0 || s.close[i] >= s.close[i - 1]],
            startLabel: s.bars[from].date,
            endLabel: s.bars[n - 1].date,
          ),
        ),
        if (levels.isNotEmpty)
          SectionCard(
            title: '關鍵價位',
            child: Column(
              children: [
                for (final (name, v, above) in levels)
                  KvRow(
                    '${above ? '壓力' : '支撐'}・$name',
                    '${f2(v)}（${((v / r.close - 1) * 100) >= 0 ? '+' : ''}${((v / r.close - 1) * 100).toStringAsFixed(1)}%）',
                    color: above ? AppColors.up : AppColors.down,
                  ),
                Text('在現價之上的是壓力（漲到那裡容易遇到賣壓），之下的是支撐（跌到那裡容易有買盤）。', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

// ───────── 多檔：綜合結論、相對走勢、比較表 ─────────

double? _atrPct(StockSeries s) {
  final i = s.length - 1;
  return i >= 0 && ok(s.atr[i]) ? s.atr[i] / s.close[i] * 100 : null;
}

double? _distHigh(StockSeries s) {
  final i = s.length - 1;
  final look = math.min(250, i);
  if (look < 60) return null;
  final top = maxIn(s.high, i - look, i);
  return (top - s.close[i]) / top * 100;
}

double? _roc(StockSeries s, int n) {
  final v = s.roc(s.length - 1, n);
  return ok(v) ? v : null;
}

int _sortKey(StockReport r) => (r.recommended ? 0 : 100) + r.opportunity.rank * 10;

class _Conclusion extends StatelessWidget {
  final List<StockReport> reports;
  final Map<String, StockSeries> series;
  final Map<String, Color> colorOf;
  const _Conclusion({required this.reports, required this.series, required this.colorOf});

  @override
  Widget build(BuildContext context) {
    final ranked = [...reports]
      ..sort((a, b) {
        final k = _sortKey(a).compareTo(_sortKey(b));
        return k != 0 ? k : b.total.compareTo(a.total);
      });
    String name(StockReport r) => '${r.code} ${r.name}';
    StockReport? best(double? Function(StockReport) f, {bool lower = false}) {
      StockReport? b;
      double? bv;
      for (final r in reports) {
        final v = f(r);
        if (v == null) continue;
        if (bv == null || (lower ? v < bv : v > bv)) {
          bv = v;
          b = r;
        }
      }
      return b;
    }

    final lines = <String>[];
    void add(String label, StockReport? r, String Function(StockReport) v) {
      if (r != null) lines.add('$label：${name(r)}（${v(r)}）');
    }

    add('短期最強', best((r) => r.short.score), (r) => '${r.short.score!.toStringAsFixed(0)} 分');
    add('中期最強', best((r) => r.medium.score), (r) => '${r.medium.score!.toStringAsFixed(0)} 分');
    add('長期結構最好', best((r) => r.long.score), (r) => '${r.long.score!.toStringAsFixed(0)} 分');
    add('相對強度最強', best((r) => r.rsRank?.toDouble(), lower: true), (r) => '全市場第 ${r.rsRank} 名');
    add(
      '波動最小（最穩）',
      best((r) => _atrPct(series[r.code]!), lower: true),
      (r) => '每日約 ${_atrPct(series[r.code]!)!.toStringAsFixed(1)}%',
    );
    add(
      '離高點最近',
      best((r) => _distHigh(series[r.code]!), lower: true),
      (r) => '差 ${_distHigh(series[r.code]!)!.toStringAsFixed(1)}%',
    );
    final sig = reports.where((r) => r.recommended).toList();
    lines.add(
      sig.isEmpty
          ? '今天都沒有通過檢查的進場訊號。'
          : '今天有進場訊號：${sig.map((r) => '${name(r)}（${r.primary!.hit.strategy.label}）').join('、')}',
    );
    final warn = reports.where((r) => r.pv.state.bad).toList();
    if (warn.isNotEmpty) lines.add('量價有警訊：${warn.map((r) => '${name(r)}（${r.pv.state.label}）').join('、')}');

    return SectionCard(
      title: '綜合結論',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, r) in ranked.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: r.code))),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colorOf[r.code]),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name(r), style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 4,
                            runSpacing: 3,
                            children: [
                              Tag(r.opportunity.label, opportunityColor(r.opportunity), filled: true),
                              DurationTag(r.duration),
                              if (r.recommended) Tag('有進場訊號', const Color(0xFF0B7A6F)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ScoreBadge(score: r.total, size: 42),
                  ],
                ),
              ),
            ),
          const Divider(height: 18),
          Bullets(lines, BulletKind.good),
          const SizedBox(height: 4),
          Text('排序方式：有通過檢查的進場訊號優先，其次看機會類型（三週期共振 > 波段機會 > …），同類再比總分。', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RelativeChart extends StatelessWidget {
  final List<StockReport> reports;
  final Map<String, StockSeries> series;
  final Map<String, Color> colorOf;
  final int period;
  final ValueChanged<int> onPeriod;
  const _RelativeChart({
    required this.reports,
    required this.series,
    required this.colorOf,
    required this.period,
    required this.onPeriod,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final dates = store.tradingDates;
    final from = math.max(0, dates.length - period - 1);
    final window = dates.sublist(from);
    final lines = <ChartSeries>[];
    final rets = <(StockReport, double)>[];
    for (final r in reports) {
      final s = series[r.code]!;
      final byDate = {for (var i = 0; i < s.length; i++) s.bars[i].date: s.close[i]};
      double? base;
      final vals = <double?>[];
      for (final d in window) {
        final v = byDate[d];
        if (v != null) base ??= v;
        vals.add(v == null || base == null ? null : v / base * 100);
      }
      final lastV = vals.lastWhere((v) => v != null, orElse: () => null);
      if (lastV != null) rets.add((r, lastV - 100));
      lines.add(ChartSeries('${r.code} ${r.name}', vals, colorOf[r.code]!, width: 2));
    }
    final taiex = store.taiexByDate;
    double? tb;
    final tv = <double?>[];
    for (final d in window) {
      final v = taiex[d];
      if (v != null) tb ??= v;
      tv.add(v == null || tb == null ? null : v / tb * 100);
    }
    if (tv.any((v) => v != null)) lines.add(ChartSeries('加權指數', tv, Colors.grey, width: 1.4));
    rets.sort((a, b) => b.$2.compareTo(a.$2));
    return SectionCard(
      title: '相對走勢（起點 = 100）',
      trailing: Wrap(
        spacing: 4,
        children: [
          for (final p in const [20, 60, 120, 250])
            ChoiceChip(
              label: Text(p == 250 ? '1 年' : '$p 天'),
              selected: period == p,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onPeriod(p),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SimpleChart(
            height: 260,
            yFormat: (v) => v.toStringAsFixed(0),
            series: lines,
            lines: const [ChartLine('起點', 100, Colors.grey)],
            startLabel: window.isEmpty ? null : window.first,
            endLabel: window.isEmpty ? null : window.last,
          ),
          const SizedBox(height: 6),
          Text(
            '這段期間漲跌：${rets.map((x) => '${x.$1.code} ${x.$2 >= 0 ? '+' : ''}${x.$2.toStringAsFixed(1)}%').join('　')}',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

enum _Better { higher, lower, none }

class _Metric {
  final String name;
  final _Better better;
  final double? Function(StockReport r, StockSeries s)? value;
  final String Function(StockReport r, StockSeries s) text;
  const _Metric(this.name, this.text, {this.value, this.better = _Better.none});
}

class _CompareTable extends StatelessWidget {
  final List<StockReport> reports;
  final Map<String, StockSeries> series;
  final Map<String, Color> colorOf;
  const _CompareTable({required this.reports, required this.series, required this.colorOf});

  static String _p(double? v) => v == null ? '—' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';
  static String _s(double? v) => v == null ? '—' : v.toStringAsFixed(0);

  static final _metrics = <_Metric>[
    _Metric('收盤', (r, s) => f2(r.close)),
    _Metric('今日漲跌', (r, s) => _p(r.changePct), value: (r, s) => r.changePct, better: _Better.higher),
    _Metric('短線總分', (r, s) => _s(r.total), value: (r, s) => r.total, better: _Better.higher),
    _Metric('短期分數', (r, s) => _s(r.short.score), value: (r, s) => r.short.score, better: _Better.higher),
    _Metric('中期分數', (r, s) => _s(r.medium.score), value: (r, s) => r.medium.score, better: _Better.higher),
    _Metric('長期技術分數', (r, s) => _s(r.long.score), value: (r, s) => r.long.score, better: _Better.higher),
    _Metric('機會類型', (r, s) => r.opportunity.label),
    _Metric('預估持有', (r, s) => r.duration.cls == null ? '不建議' : 'D${r.duration.cls} ${kDurationRange[r.duration.cls]}'),
    _Metric('信心度', (r, s) => r.duration.confidence.label),
    _Metric('今日訊號', (r, s) => r.recommended ? '✓ ${r.primary!.hit.strategy.label}' : (r.hits.isEmpty ? '—' : '被否決')),
    _Metric(
      'RS 排名',
      (r, s) => r.rsRank == null ? '—' : '第 ${r.rsRank} 名',
      value: (r, s) => r.rsRank?.toDouble(),
      better: _Better.lower,
    ),
    _Metric(
      '產業',
      (r, s) =>
          r.industry == null ? '—' : '${r.industry}${r.industryClass == null ? '' : '・${r.industryClass!.label}'}',
    ),
    _Metric('量價狀態', (r, s) => r.pv.state.label),
    _Metric('價量持續性', (r, s) => _s(r.pv.persistence), value: (r, s) => r.pv.persistence, better: _Better.higher),
    _Metric(
      '趨勢分數',
      (r, s) => _s(r.module('trend').score),
      value: (r, s) => r.module('trend').score,
      better: _Better.higher,
    ),
    _Metric(
      '動能分數',
      (r, s) => _s(r.module('momentum').score),
      value: (r, s) => r.module('momentum').score,
      better: _Better.higher,
    ),
    _Metric('20 日報酬', (r, s) => _p(_roc(s, 20)), value: (r, s) => _roc(s, 20), better: _Better.higher),
    _Metric('60 日報酬', (r, s) => _p(_roc(s, 60)), value: (r, s) => _roc(s, 60), better: _Better.higher),
    _Metric('120 日報酬', (r, s) => _p(_roc(s, 120)), value: (r, s) => _roc(s, 120), better: _Better.higher),
    _Metric('250 日報酬', (r, s) => _p(_roc(s, 250)), value: (r, s) => _roc(s, 250), better: _Better.higher),
    _Metric(
      '離一年高點',
      (r, s) => _distHigh(s) == null ? '—' : '−${_distHigh(s)!.toStringAsFixed(1)}%',
      value: (r, s) => _distHigh(s),
      better: _Better.lower,
    ),
    _Metric('RSI', (r, s) => ok(s.rsi[s.length - 1]) ? s.rsi[s.length - 1].toStringAsFixed(0) : '—'),
    _Metric(
      '每日波動 ATR%',
      (r, s) => _atrPct(s) == null ? '—' : '${_atrPct(s)!.toStringAsFixed(1)}%',
      value: (r, s) => _atrPct(s),
      better: _Better.lower,
    ),
    _Metric('20 日均成交值', (r, s) => valueTxt(r.avgValue20), value: (r, s) => r.avgValue20, better: _Better.higher),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const nameW = 120.0, colW = 150.0;
    Widget cell(String t, {bool best = false, bool head = false, Color? color, bool first = false}) => Container(
      width: first ? nameW : colW,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: best ? scheme.primaryContainer.withValues(alpha: .7) : null,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: head ? 13 : 12.5,
          fontWeight: head || best ? FontWeight.w700 : (first ? FontWeight.w600 : FontWeight.normal),
          color: color ?? (first ? scheme.onSurfaceVariant : null),
        ),
      ),
    );

    final rows = <Widget>[
      Row(
        children: [
          cell('項目', head: true, first: true),
          for (final r in reports) cell('${r.code} ${r.name}', head: true, color: colorOf[r.code]),
        ],
      ),
    ];
    // 長期評分（資料包）放最前面
    final lt = context.watch<LongTermStore>().result;
    final lts = [for (final r in reports) lt?.scoreOf(r.code)];
    void ltRow(String name, String Function(LtScore s) text, [double? Function(LtScore s)? value]) {
      int? bestIdx;
      double? bv;
      for (var k = 0; k < reports.length; k++) {
        final s = lts[k];
        final v = s == null || value == null ? null : value(s);
        if (v == null || v.isNaN) continue;
        if (bv == null || v > bv) {
          bv = v;
          bestIdx = k;
        }
      }
      rows.add(
        Row(
          children: [
            cell(name, first: true),
            for (var k = 0; k < reports.length; k++) cell(lts[k] == null ? '—' : text(lts[k]!), best: k == bestIdx),
          ],
        ),
      );
    }

    if (lts.any((s) => s != null)) {
      ltRow('長期總分', (s) => s.composite.toStringAsFixed(0), (s) => s.composite);
      ltRow('長期排名', (s) => '第 ${s.rank} 名（前 ${((1 - s.pct) * 100).clamp(1, 100).toStringAsFixed(0)}%）', (s) => s.pct);
      for (final g in FactorGroup.values) {
        ltRow('・${g.label}', (s) => s.groups[g]?.toStringAsFixed(0) ?? '—', (s) => s.groups[g]);
      }
      ltRow('長期警示', (s) => s.flags.isEmpty ? '—' : s.flags.map((f) => f.label).join('、'));
    }
    for (final m in _metrics) {
      int? bestIdx;
      if (m.better != _Better.none && m.value != null) {
        double? bv;
        for (var k = 0; k < reports.length; k++) {
          final v = m.value!(reports[k], series[reports[k].code]!);
          if (v == null) continue;
          if (bv == null || (m.better == _Better.higher ? v > bv : v < bv)) {
            bv = v;
            bestIdx = k;
          }
        }
      }
      rows.add(
        Row(
          children: [
            cell(m.name, first: true),
            for (var k = 0; k < reports.length; k++)
              cell(m.text(reports[k], series[reports[k].code]!), best: k == bestIdx),
          ],
        ),
      );
    }
    return SectionCard(
      title: '逐項比較',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
          ),
          const SizedBox(height: 6),
          Text('底色標出的是那一列最好的（分數、報酬越高越好；排名、波動、離高點越小越好）。', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
