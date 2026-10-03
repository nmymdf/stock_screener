/// 「推薦」：通過所有否決、依總分排序的候選股，每一檔都寫出機會類型（短中長
/// 交叉）、預估持有期間、推薦理由、歷史勝率和交易計畫。另外有「觀察池」
/// （中長期好、等進場點）和「被否決」（看否決原因）。
library;

import 'package:flutter/material.dart';

import '../../logic/engine/analysis.dart';
import '../../logic/engine/horizon.dart';
import '../../logic/engine/industry_engine.dart';
import '../../logic/engine/market_engine.dart';
import '../../logic/engine/signals.dart';
import '../format.dart';
import '../home.dart';
import '../theme.dart';
import '../widgets/analysis_gate.dart';
import '../widgets/common.dart';
import '../widgets/horizon_widgets.dart';
import '../widgets/score_widgets.dart';
import 'stock_report_screen.dart';

enum _Mode { recommend, watch, rejected }

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  _Mode _mode = _Mode.recommend;
  int? _horizon; // null = 全部；1／2／3 = D1／D2／D3

  bool _match(StockReport s) => _horizon == null || s.duration.cls == _horizon;

  @override
  Widget build(BuildContext context) {
    return AnalysisGate(
      builder: (context, a) {
        final recs = a.recommendations;
        final rejected = a.rejected;
        final watch = a.watchlist;
        final base = switch (_mode) {
          _Mode.recommend => recs,
          _Mode.watch => watch,
          _Mode.rejected => rejected,
        };
        final list = base.where(_match).toList();
        final today = a.today;
        int count(int d) => base.where((s) => s.duration.cls == d).length;
        return [
          Row(
            children: [
              const Expanded(
                child: Text('今日推薦', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              Text('資料截至 ${a.latestDate} 收盤', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          if (today != null) _MarketBanner(day: today),
          const SizedBox(height: 6),
          _FunnelCard(f: a.funnel),
          const SizedBox(height: 8),
          SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _Mode.recommend, label: Text('推薦 ${recs.length}')),
              ButtonSegment(value: _Mode.watch, label: Text('觀察池 ${watch.length}')),
              ButtonSegment(value: _Mode.rejected, label: Text('被否決 ${rejected.length}')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 6),
          Text(switch (_mode) {
            _Mode.recommend => '今天出現進場訊號、通過所有否決的股票。依預估持有期間分成短線、波段、中長期。',
            _Mode.watch => '中長期條件好、但今天沒有進場點的股票。每一檔都寫出「什麼情況會變成可以買」，先放著等。',
            _Mode.rejected => '有訊號但被一票否決（流動性、停損過寬、報酬風險比不足、分數不夠…），看系統為什麼不推薦。',
          }, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: Text('全部 ${base.length}'),
                selected: _horizon == null,
                onSelected: (_) => setState(() => _horizon = null),
              ),
              for (final (d, name) in [(1, '短線'), (2, '波段'), (3, '中長期')])
                ChoiceChip(
                  label: Text('$name D$d ${count(d)}'),
                  tooltip: kDurationRange[d],
                  selected: _horizon == d,
                  onSelected: (_) => setState(() => _horizon = _horizon == d ? null : d),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (list.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_emptyText(a, today), style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
            ),
          for (var i = 0; i < list.length; i++)
            _mode == _Mode.watch
                ? _WatchCard(s: list[i])
                : _RecCard(rank: i + 1, s: list[i], rejected: _mode == _Mode.rejected),
          const SizedBox(height: 10),
          const DisclaimerCard(
            text:
                '機械化篩選，不是投資建議。分數目前由技術面、相對強度、量價、市場和產業組成；'
                '基本面、籌碼還沒接資料，所以長期分數只看技術面、持有期間最多估到 D3。'
                '歷史勝率是用本機資料、跟推薦完全相同的條件回算的，過去不代表未來。',
          ),
        ];
      },
    );
  }

  String _emptyText(AnalysisResult a, MarketDay? today) {
    if (_horizon != null) return '這個持有期間（D$_horizon）今天沒有股票，可以點「全部」看其他期間。';
    if (_mode == _Mode.rejected) return '今天沒有「有訊號但被否決」的股票。';
    if (_mode == _Mode.watch) return '觀察池是空的：今天沒有「中長期條件好、但還沒進場點」的股票。';
    if (today?.regime == Regime.bear) {
      return '市場處於「空頭／極端風險」（Market Score ${today!.score!.toStringAsFixed(0)}），'
          '依規格書原則停止一般多單，所以今天沒有推薦。這不是系統壞掉，而是風控在運作——'
          '可以切到「被否決」看哪些股票有訊號但被市場條件否決，或看「觀察池」先準備名單。';
    }
    if (a.funnel.withSignal == 0) return '今天全市場沒有任何股票出現 A／B／C／D 的進場訊號。可以看「觀察池」裡等待進場點的股票。';
    return '今天有 ${a.funnel.withSignal} 檔出現訊號，但都沒有通過一票否決或分數門檻。'
        '切到「被否決」可以看每一檔被否決的原因。';
  }
}

class _MarketBanner extends StatelessWidget {
  final MarketDay day;
  const _MarketBanner({required this.day});

  @override
  Widget build(BuildContext context) {
    final r = day.regime;
    final c = regimeColor(r);
    return Card(
      color: c.withValues(alpha: .08),
      child: InkWell(
        onTap: () => HomeShell.goTo(context, HomeShell.market),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ScoreBadge(score: day.score, size: 50, caption: '市場'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Tag(r?.label ?? '資料不足', c, filled: true),
                        if (r != null)
                          Text(
                            '建議最大總曝險 ${r.exposure}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(r?.attitude ?? '市場資料還不夠算分數（需要約 20 個交易日以上）。', style: const TextStyle(fontSize: 12)),
                    if (day.warnings.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '⚠ ${day.warnings.first}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFB7860B)),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _FunnelCard extends StatelessWidget {
  final Funnel f;
  const _FunnelCard({required this.f});

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String label, {bool last = false}) => Expanded(
      child: Column(
        children: [
          Text(
            n,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: last ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
    const arrow = Icon(Icons.arrow_forward_ios, size: 11, color: Colors.grey);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            step(f0(f.traded), '今日有交易'),
            arrow,
            step(f0(f.liquid), '流動性合格'),
            arrow,
            step(f0(f.withSignal), '出現進場訊號'),
            arrow,
            step(f0(f.recommended), '通過否決＝推薦', last: true),
          ],
        ),
      ),
    );
  }
}

class _RecCard extends StatelessWidget {
  final int rank;
  final StockReport s;
  final bool rejected;
  const _RecCard({required this.rank, required this.s, required this.rejected});

  @override
  Widget build(BuildContext context) {
    final h = s.primary ?? (s.hits.isEmpty ? null : s.hits.first);
    final p = h?.plan;
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: s.code))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StockHead(s: s, rank: rejected ? null : rank),
              const SizedBox(height: 8),
              HorizonTriple(short: s.short, medium: s.medium, long: s.long),
              if (h != null) ...[
                const SizedBox(height: 8),
                Text(h.hit.headline, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
              if (!rejected && s.positives.isNotEmpty) ...[
                const SizedBox(height: 4),
                Bullets(s.positives.take(2).toList(), BulletKind.good),
              ],
              if (rejected) ...[const SizedBox(height: 4), Bullets(s.allVetoes.take(2).toList(), BulletKind.bad)],
              if (!rejected && s.warnings.isNotEmpty) Bullets([s.warnings.first], BulletKind.warn),
              if (!rejected && s.calibration != null) ...[
                const SizedBox(height: 4),
                CalibrationView(s.calibration!, compact: true),
              ],
              if (p != null && !rejected) ...[
                const Divider(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    Text('買進 ≤ ${f2(p.maxEntry)}', style: small?.copyWith(fontWeight: FontWeight.w600)),
                    Text('停損 ${f2(p.stop)}（−${p.riskPct.toStringAsFixed(1)}%）', style: small),
                    Text('目標 ${f2(p.target)}（+${((p.target / p.entry - 1) * 100).toStringAsFixed(1)}%）', style: small),
                    Text('R/R ${p.rr.toStringAsFixed(1)}', style: small),
                    if (p.strategy != Strategy.meanReversion) Text('+1R 後可加碼 ${f2(p.entry + p.risk)}', style: small),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片最上面：分數、代號名稱、機會類型、持有期間、策略、產業、價格。
class _StockHead extends StatelessWidget {
  final StockReport s;
  final int? rank;
  const _StockHead({required this.s, this.rank});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScoreBadge(score: s.total, caption: '總分'),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (rank != null) RankBadge(rank: rank!),
                  Flexible(
                    child: Text(
                      '${s.code} ${s.name}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 4,
                runSpacing: 3,
                children: [
                  Tag(s.opportunity.label, opportunityColor(s.opportunity), filled: true),
                  DurationTag(s.duration),
                  for (final x in s.hits)
                    StrategyTag(code: x.hit.strategy.code, label: x.hit.strategy.label, dimmed: !x.passed),
                  if (s.industry != null)
                    Tag(
                      '${s.industry}${s.industryClass == null ? '' : '・${s.industryClass!.label}'}',
                      industryClassColor(s.industryClass),
                    ),
                  if (s.rsRank != null) Tag('RS 第 ${s.rsRank} 名', Colors.blueGrey),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(f2(s.close), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text(pctTxt(s.changePct), style: TextStyle(fontSize: 12, color: changeColor(context, s.changePct))),
          ],
        ),
      ],
    );
  }
}

/// 觀察池：中長期好、等進場點。寫出什麼情況會變成可以買。
class _WatchCard extends StatelessWidget {
  final StockReport s;
  const _WatchCard({required this.s});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: s.code))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StockHead(s: s),
              const SizedBox(height: 8),
              HorizonTriple(short: s.short, medium: s.medium, long: s.long),
              const SizedBox(height: 6),
              Text(s.opportunity.strategy, style: const TextStyle(fontSize: 12, height: 1.4)),
              if (s.triggers.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('什麼情況會變成可以買', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Bullets(s.triggers, BulletKind.info),
              ],
              if (s.warnings.isNotEmpty) Bullets([s.warnings.first], BulletKind.warn),
            ],
          ),
        ),
      ),
    );
  }
}
