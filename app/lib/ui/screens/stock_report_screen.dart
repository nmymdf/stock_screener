/// 個股分析報告：推薦理由（為什麼選它／要注意什麼／為什麼被否決）、
/// 交易計畫（進場、停損、目標、張數）、走勢圖、各模組分數逐項拆解、技術指標。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/stock_catalog.dart';
import '../../data/stock_industry.dart';
import '../../logic/engine/analysis.dart';
import '../../logic/engine/industry_engine.dart';
import '../../logic/engine/signals.dart';
import '../../logic/risk.dart';
import '../../logic/ta.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/score_widgets.dart';
import 'risk_settings_screen.dart';

String sizeLabel(RiskSettings r, TradePlan p) {
  final s = sizePosition(r, p);
  if (s.shares == 0) return r.drawdownMultiplier == 0 ? '停止新單（回撤過大）' : '資金不足一股';
  if (s.lots == 0) return '建議 ${s.oddShares} 股（零股）';
  return '建議 ${s.lots} 張${s.oddShares > 0 ? ' ${s.oddShares} 股' : ''}';
}

class StockReportScreen extends StatelessWidget {
  final String code;

  /// 從其他畫面（例如今日雷達）帶進來的額外理由。
  final List<String> extraReasons;
  final String? extraTitle;

  const StockReportScreen({super.key, required this.code, this.extraReasons = const [], this.extraTitle});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final report = store.analysis?.stock(code);
    final bars = store.seriesOf(code);
    final series = bars.length >= 2 ? StockSeries(code, bars) : null;
    final name = kBuiltinStocksByCode[code]?.name ?? '';

    return Scaffold(
      appBar: AppBar(title: Text('$code $name')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            children: [
              if (extraReasons.isNotEmpty)
                SectionCard(title: extraTitle ?? '上榜理由', child: Bullets(extraReasons, BulletKind.good)),
              if (report != null) ...[
                _Header(r: report),
                _Reasons(r: report),
                for (final h in report.hits) _PlanCard(r: report, h: h, primary: identical(h, report.primary)),
              ] else
                const SectionCard(
                  child: Text(
                    '這檔股票今天不在分析範圍（今天沒有交易，或本機還沒有它的歷史資料）。'
                    '到「工具 → 資料管理」補抓資料後就會有完整分析。',
                  ),
                ),
              if (series != null)
                _ChartCard(
                  s: series,
                  plan: report?.primary?.plan ?? (report?.hits.isEmpty ?? true ? null : report!.hits.first.plan),
                ),
              if (report != null)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 14, 14, 4),
                        child: Text('分數拆解（點開看每一分怎麼來）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          '總分 = 各模組分數依權重加權平均（規格書 §10.1），沒有資料的模組不列入、權重重新分配。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      for (final m in report.modules) ModuleScoreTile(m: m),
                    ],
                  ),
                ),
              if (series != null) _IndicatorCard(s: series),
              const SizedBox(height: 8),
              const DisclaimerCard(text: '機械化分析，不是投資建議。交易計畫是依規則算出來的參考值，實際下單前請自己再確認。'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final StockReport r;
  const _Header({required this.r});

  @override
  Widget build(BuildContext context) {
    final rec = r.recommended;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ScoreBadge(score: r.total, size: 64, caption: '總分'),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Tag(
                        rec ? '推薦：${r.primary!.hit.strategy.label}' : (r.hits.isEmpty ? '今天沒有進場訊號' : '有訊號但被否決'),
                        rec ? const Color(0xFF0B7A6F) : Colors.grey,
                        filled: rec,
                      ),
                      if (r.industry != null)
                        Tag(
                          '${r.industry}${r.industryClass == null ? '' : '・${r.industryClass!.label}'}',
                          industryClassColor(r.industryClass),
                        ),
                      Tag(r.market, Colors.blueGrey),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(f2(r.close), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text(
                        pctTxt(r.changePct),
                        style: TextStyle(color: changeColor(context, r.changePct), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Text(
                    '成交 ${f0(r.volumeLots)} 張 · 20 日均成交值 ${valueTxt(r.avgValue20)}'
                    '${r.rsRank == null ? '' : ' · RS 第 ${r.rsRank} 名'}',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _Reasons extends StatelessWidget {
  final StockReport r;
  const _Reasons({required this.r});

  @override
  Widget build(BuildContext context) {
    final h = r.primary ?? (r.hits.isEmpty ? null : r.hits.first);
    final why = <String>[if (h != null) ...h.hit.details, ...r.positives];
    return SectionCard(
      title: r.recommended ? '推薦理由' : '分析結論',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (h != null) ...[
            Text(h.hit.headline, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${h.hit.strategy.label}：${h.hit.strategy.idea}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          if (why.isNotEmpty) ...[
            const Text('為什麼選它', style: TextStyle(fontWeight: FontWeight.w600)),
            Bullets(why, BulletKind.good),
          ],
          if (r.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('要注意', style: TextStyle(fontWeight: FontWeight.w600)),
            Bullets(r.warnings, BulletKind.warn),
          ],
          if (!r.recommended && r.allVetoes.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('為什麼沒有推薦（一票否決）', style: TextStyle(fontWeight: FontWeight.w600)),
            Bullets(r.allVetoes, BulletKind.bad),
          ],
          if (r.hits.isEmpty)
            const Text(
              '今天沒有出現 A 突破、B 回檔、C 趨勢延續、D 均值回歸任何一種進場訊號，所以沒有交易計畫。'
              '下面的分數拆解可以看它目前的體質。',
              style: TextStyle(fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final StockReport r;
  final HitResult h;
  final bool primary;
  const _PlanCard({required this.r, required this.h, required this.primary});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final p = h.plan;
    final sz = sizePosition(store.risk, p);
    final pctOf = store.risk.capital == 0 ? 0 : sz.riskAmount / store.risk.capital * 100;
    return SectionCard(
      title: '交易計畫 · ${h.hit.strategy.label}${h.passed ? '' : '（被否決，僅供參考）'}',
      trailing: StrategyTag(code: h.hit.strategy.code, label: h.hit.strategy.code, dimmed: !h.passed),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KvRow('參考進場價', f2(p.entry), note: '今天收盤價；訊號是收盤後才確認的，實際在明天開盤後進場'),
          KvRow('可接受最高買價', f2(p.maxEntry), note: '收盤 + 0.5 ATR。明天開盤超過這個價就不追（避免追價，§13）'),
          KvRow('停損', '${f2(p.stop)}（−${p.riskPct.toStringAsFixed(1)}%）', color: AppColors.down, note: p.stopBasis),
          KvRow(
            '目標',
            '${f2(p.target)}（+${((p.target / p.entry - 1) * 100).toStringAsFixed(1)}%）',
            color: AppColors.up,
            note: p.targetBasis,
          ),
          KvRow(
            '報酬風險比',
            p.rr.toStringAsFixed(2),
            note: p.resistance == null ? '上方一年內沒有前高壓力（已在新高區）' : '上方前高壓力 ${f2(p.resistance!)}',
          ),
          if (h.hit.strategy != Strategy.meanReversion)
            KvRow(
              '之後的出場規則',
              '保本 → 移動停利',
              note:
                  '漲到 +1R（${f2(p.entry + p.risk)}）後停損拉到成本；到 2R 出一半後，剩下用「22 日最高 − 3 ATR」移動停利'
                  '（今天算出來是 ${f2(p.trailing)}，移動停利只會往上調、不會低於當時的停損）；'
                  '${p.timeStopDays} 個交易日還沒有 +1R 就出場（時間停損）。',
            ),
          const Divider(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text('建議部位', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RiskSettingsScreen())),
                child: const Text('調整資金／風險設定'),
              ),
            ],
          ),
          KvRow(
            sizeLabel(store.risk, p),
            '${f0(sz.amount)} 元',
            note:
                '總資金 ${f0(store.risk.capital)} 元、單筆風險 ${store.risk.riskPct}%、單檔上限 ${store.risk.maxPositionPct.toStringAsFixed(0)}%。${sz.note}',
          ),
          KvRow(
            '碰到停損的虧損',
            '${f0(sz.riskAmount)} 元（${pctOf.toStringAsFixed(2)}% 資金）',
            note: '部位大小由「可以承受的損失」決定，不是固定買多少錢（§11.1）。${store.risk.drawdownNote}',
          ),
          if (tickSize(p.entry, r.type) > 0)
            Text(
              '價格都已對齊台股跳動單位（這個價位 tick = ${tickSize(p.entry, r.type)}${r.type == SecurityType.stock ? '' : '，ETF 規則'}）。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final StockSeries s;
  final TradePlan? plan;
  const _ChartCard({required this.s, required this.plan});

  @override
  Widget build(BuildContext context) {
    final n = s.length;
    final from = math.max(0, n - 120);
    List<double?> tail(List<double> v) => [for (var i = from; i < n; i++) v[i].isNaN ? null : v[i]];
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '走勢（最近 ${n - from} 個交易日，已還原權息）',
      child: SimpleChart(
        height: 240,
        series: [
          ChartSeries('收盤', tail(s.close), scheme.primary, width: 2),
          ChartSeries('EMA20', tail(s.ema20), Colors.orange),
          ChartSeries('EMA50', tail(s.ema50), Colors.purple),
          if (s.ema200.any(ok)) ChartSeries('EMA200', tail(s.ema200), Colors.brown),
        ],
        lines: plan == null
            ? const []
            : [ChartLine('停損', plan!.stop, AppColors.down), ChartLine('目標', plan!.target, AppColors.up)],
        volumes: [for (var i = from; i < n; i++) s.vol[i]],
        volumeUp: [for (var i = from; i < n; i++) i == 0 || s.close[i] >= s.close[i - 1]],
        startLabel: s.bars[from].date,
        endLabel: s.bars[n - 1].date,
      ),
    );
  }
}

class _IndicatorCard extends StatelessWidget {
  final StockSeries s;
  const _IndicatorCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final i = s.length - 1;
    String v(double x, [int d = 1]) => ok(x) ? x.toStringAsFixed(d) : '—';
    final avg = s.avgVolBefore(i, 20);
    final bbp = s.percentileOf(s.bbw, i, 120);
    return SectionCard(
      title: '技術指標（最新一天）',
      child: StatGrid(
        bare: true,
        stats: [
          ('RSI(14)', v(s.rsi[i]), null),
          ('ADX', v(s.adx.adx[i]), null),
          ('+DI／−DI', '${v(s.adx.diPlus[i], 0)}／${v(s.adx.diMinus[i], 0)}', null),
          ('MACD 柱', v(s.macd.hist[i], 2), null),
          ('K／D', '${v(s.kd.k[i], 0)}／${v(s.kd.d[i], 0)}', null),
          (
            'ATR(14)',
            '${v(s.atr[i], 2)}（${ok(s.atr[i]) ? (s.atr[i] / s.close[i] * 100).toStringAsFixed(1) : '—'}%）',
            null,
          ),
          ('EMA20', v(s.ema20[i], 2), null),
          ('EMA50', v(s.ema50[i], 2), null),
          ('EMA200', v(s.ema200[i], 2), null),
          ('量比', avg > 0 ? '${(s.vol[i] / avg).toStringAsFixed(2)} 倍' : '—', null),
          ('布林帶寬分位', ok(bbp) ? '${(bbp * 100).toStringAsFixed(0)}%' : '—', null),
          ('60 日報酬', ok(s.roc(i, 60)) ? pctTxt(s.roc(i, 60)) : '—', null),
        ],
      ),
    );
  }
}
