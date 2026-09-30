/// 「推薦」：通過所有否決、依總分排序的候選股，每一檔都寫出推薦理由和
/// 交易計畫。也可以切換看「有訊號但被否決」的股票和否決原因。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../logic/engine/analysis.dart';
import '../../logic/engine/industry_engine.dart';
import '../../logic/engine/market_engine.dart';
import '../../logic/engine/signals.dart';
import '../../logic/risk.dart';
import '../format.dart';
import '../home.dart';
import '../theme.dart';
import '../widgets/analysis_gate.dart';
import '../widgets/common.dart';
import '../widgets/score_widgets.dart';
import 'stock_report_screen.dart';

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  Strategy? _filter;
  bool _showRejected = false;

  bool _match(StockReport s) {
    if (_filter == null) return true;
    if (_showRejected) return s.hits.any((h) => h.hit.strategy == _filter);
    return s.primary?.hit.strategy == _filter;
  }

  @override
  Widget build(BuildContext context) {
    return AnalysisGate(
      builder: (context, a) {
        final recs = a.recommendations;
        final rejected = a.rejected;
        final list = (_showRejected ? rejected : recs).where(_match).toList();
        final today = a.today;
        int count(Strategy s) =>
            (_showRejected
                    ? rejected.where((r) => r.hits.any((h) => h.hit.strategy == s))
                    : recs.where((r) => r.primary?.hit.strategy == s))
                .length;
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
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text('全部 ${_showRejected ? rejected.length : recs.length}'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              for (final s in Strategy.values)
                ChoiceChip(
                  label: Text('${s.label} ${count(s)}'),
                  selected: _filter == s,
                  onSelected: (_) => setState(() => _filter = _filter == s ? null : s),
                ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('改看「有訊號但被否決」的股票', style: TextStyle(fontSize: 13)),
            subtitle: const Text('看系統為什麼不推薦（流動性、停損過寬、報酬風險比不足、分數不夠…）', style: TextStyle(fontSize: 11)),
            value: _showRejected,
            onChanged: (v) => setState(() => _showRejected = v),
          ),
          if (list.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_emptyText(a, today), style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
            ),
          for (var i = 0; i < list.length; i++) _RecCard(rank: i + 1, s: list[i], rejected: _showRejected),
          const SizedBox(height: 10),
          const DisclaimerCard(
            text:
                '機械化篩選，不是投資建議。總分目前由技術面、相對強度、市場和產業組成；'
                '基本面（15%）、籌碼（10%）還沒接資料，不列入計算。每一檔都請自己再確認基本面和新聞。',
          ),
        ];
      },
    );
  }

  String _emptyText(AnalysisResult a, MarketDay? today) {
    if (_showRejected) return '今天沒有「有訊號但被否決」的股票。';
    if (today?.regime == Regime.bear) {
      return '市場處於「空頭／極端風險」（Market Score ${today!.score!.toStringAsFixed(0)}），'
          '依規格書原則停止一般多單，所以今天沒有推薦。這不是系統壞掉，而是風控在運作——'
          '可以切換上面的開關，看哪些股票有訊號但被市場條件否決。';
    }
    if (a.funnel.withSignal == 0) return '今天全市場沒有任何股票出現 A／B／C／D 的進場訊號。';
    return '今天有 ${a.funnel.withSignal} 檔出現訊號，但都沒有通過一票否決或分數門檻。'
        '打開上面的開關可以看每一檔被否決的原因。';
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
    final risk = context.select<HistoryStore, RiskSettings>((st) => st.risk);
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
              Row(
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
                            if (!rejected) RankBadge(rank: rank),
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
                      Text(
                        pctTxt(s.changePct),
                        style: TextStyle(fontSize: 12, color: changeColor(context, s.changePct)),
                      ),
                    ],
                  ),
                ],
              ),
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
              if (p != null && !rejected) ...[
                const Divider(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    Text('買進 ≤ ${f2(p.maxEntry)}', style: small),
                    Text('停損 ${f2(p.stop)}（−${p.riskPct.toStringAsFixed(1)}%）', style: small),
                    Text('目標 ${f2(p.target)}（+${((p.target / p.entry - 1) * 100).toStringAsFixed(1)}%）', style: small),
                    Text('R/R ${p.rr.toStringAsFixed(1)}', style: small),
                    Text(sizeLabel(risk, p), style: small?.copyWith(fontWeight: FontWeight.w600)),
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
