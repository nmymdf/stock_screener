/// 個股分析報告：短中長交叉分析與機會類型、預估持有期間（D1～D3＋信心度＋
/// 升降級條件）、推薦理由、交易計畫（進場、停損、目標、加碼時機、明天怎麼做）、
/// 歷史上同類訊號的結果、量價狀態、走勢圖、各模組分數逐項拆解、技術指標。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/stock_catalog.dart';
import '../../data/stock_industry.dart';
import '../../logic/engine/analysis.dart';
import '../../logic/engine/horizon.dart';
import '../../logic/engine/industry_engine.dart';
import '../../logic/engine/signals.dart';
import '../../logic/ta.dart';
import '../format.dart';
import '../theme.dart';
import '../layout.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/horizon_widgets.dart';
import '../widgets/score_widgets.dart';
import 'holding_detail_screen.dart';
import 'holding_forms.dart';

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

    final plan = report?.primary?.plan ?? (report?.hits.isEmpty ?? true ? null : report!.hits.first.plan);
    final left = <Widget>[
      if (extraReasons.isNotEmpty)
        SectionCard(title: extraTitle ?? '上榜理由', child: Bullets(extraReasons, BulletKind.good)),
      if (report != null) ...[
        _Header(r: report),
        _HoldingAction(code: code, report: report),
        _HorizonCard(r: report),
        _DurationCard(r: report),
        _Reasons(r: report),
        for (final h in report.hits) _PlanCard(r: report, h: h, primary: identical(h, report.primary)),
      ] else
        const SectionCard(
          child: Text(
            '這檔股票今天不在分析範圍（今天沒有交易，或本機還沒有它的歷史資料）。'
            '到「工具 → 資料管理」補抓資料後就會有完整分析。',
          ),
        ),
    ];
    final right = <Widget>[
      if (series != null) _ChartCard(s: series, plan: plan),
      if (report != null) ...[
        if (report.calibration != null) SectionCard(title: '歷史上同類訊號的結果', child: CalibrationView(report.calibration!)),
        if (!report.recommended && report.triggers.isNotEmpty)
          SectionCard(
            title: '什麼情況會變成可以買',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bullets(report.triggers, BulletKind.info),
                const SizedBox(height: 4),
                Text('條件出現的那天收盤後，這檔就會出現在「推薦」裡，並附上完整的停損和目標。', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        _PvCard(r: report),
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
      ],
      if (series != null) _IndicatorCard(s: series),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('$code $name')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: ListView(
            padding: pagePadding(context),
            children: [
              SplitView(left: left, right: right),
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
                      Tag(r.opportunity.label, opportunityColor(r.opportunity), filled: true),
                      DurationTag(r.duration),
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
    final p = h.plan;
    return SectionCard(
      title: '交易計畫 · ${h.hit.strategy.label}${h.passed ? '' : '（被否決，僅供參考）'}',
      trailing: StrategyTag(code: h.hit.strategy.code, label: h.hit.strategy.code, dimmed: !h.passed),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KvRow('參考進場價', f2(p.entry), note: '今天收盤價；訊號是收盤後才確認的，實際在明天開盤後進場'),
          KvRow('可接受最高買價', f2(p.maxEntry), note: '收盤 + 0.5 ATR。明天開盤超過這個價就不追（避免追價，§13）'),
          KvRow(
            '停損',
            '${f2(p.stop)}（−${p.riskPct.toStringAsFixed(1)}%）',
            color: AppColors.down,
            note: '${p.stopBasis}。每股風險 ${f2(p.risk)} 元（1R）。',
          ),
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
          const Text('明天怎麼做', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Bullets([
            '開盤 ≤ ${f2(p.maxEntry)}：可以進場',
            '開盤 > ${f2(p.maxEntry)}：不追，等回檔或下一個訊號',
            '開盤就 ≤ ${f2(p.stop)}（跌破停損）：訊號失效，不買',
          ], BulletKind.info),
          const SizedBox(height: 8),
          const Text('可能的加碼時機（只加贏家）', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Bullets(addOnPlanFor(p, r), BulletKind.good),
          const SizedBox(height: 4),
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

/// 「我已進場」：把這檔加入我的持股（有訊號的話帶入停損、目標和推薦理由）；
/// 已經持有就顯示持股狀態的捷徑。
class _HoldingAction extends StatelessWidget {
  final String code;
  final StockReport report;
  const _HoldingAction({required this.code, required this.report});

  @override
  Widget build(BuildContext context) {
    final holding = context.watch<HoldingsStore>().openFor(code);
    final h = report.primary ?? (report.hits.isEmpty ? null : report.hits.first);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (holding == null)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddHoldingPage(
                    code: code,
                    plan: h == null
                        ? null
                        : PlanPrefill(
                            strategy: h.hit.strategy,
                            entry: h.plan.entry,
                            stop: h.plan.stop,
                            target: h.plan.target,
                            reason: h.hit.headline,
                            opportunity: report.opportunity.label,
                            duration: report.duration.cls,
                            confidence: report.duration.confidence.label,
                            thesis: [h.hit.headline, ...report.duration.why.take(4)],
                          ),
                  ),
                ),
              ),
              icon: const Icon(Icons.add_task, size: 18),
              label: const Text('我已進場（加入持股追蹤）'),
            )
          else
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => HoldingDetailScreen(id: holding.id))),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: Text('已持有 ${holding.shares} 股，看持股追蹤'),
            ),
        ],
      ),
    );
  }
}

/// 交易計畫的加碼時機（含價格）。
List<String> addOnPlanFor(TradePlan p, StockReport r) {
  if (p.strategy == Strategy.meanReversion) {
    return ['均值回歸型的目標就是 20 日線、空間有限，不加碼；到目標全部出場。'];
  }
  final one = p.entry + p.risk;
  return [
    '① 收盤站上 +1R（${f2(one)}），停損拉到成本 ${f2(p.entry)} 之後，第一次加碼（≤ 原始股數的一半）',
    if (p.strategy == Strategy.pullback)
      '② 之後回測 20 日線量縮、再收盤站上前一天高點，第二次加碼（≤ 四分之一）'
    else
      '② 創高後回檔整理、守住 20 日線，再放量突破前高時，第二次加碼（≤ 四分之一）',
    '加碼後整筆停損至少拉到新的平均成本；虧損中一律不加碼（禁止向下攤平）',
  ];
}

/// 短中長交叉：三個分數、各自的失效條件、這是哪一種機會。
class _HorizonCard extends StatelessWidget {
  final StockReport r;
  const _HorizonCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final o = r.opportunity;
    return SectionCard(
      title: '短中長交叉分析',
      trailing: Tag(o.label, opportunityColor(o), filled: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '短期 ${r.short.level.label}・中期 ${r.medium.level.label}・長期 ${r.long.level.label} → ${o.label}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(o.strategy, style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 6),
          HorizonTile(r.short),
          HorizonTile(r.medium),
          HorizonTile(r.long),
          Text(
            '三個週期各有自己的失效條件，不會互相拿來合理化：短線失效就照短線處理，不會因為長期分數高就改成長抱。（點開看每一分怎麼來）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 預估持有期間：D 等級、信心度、為什麼、為什麼還不是更長、升降級條件、失效條件、證據來源。
class _DurationCard extends StatelessWidget {
  final StockReport r;
  const _DurationCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final d = r.duration;
    final small = Theme.of(context).textTheme.bodySmall;
    return SectionCard(
      title: '預估持有期間',
      trailing: DurationTag(d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text('信心度 ${d.confidence.label}：${d.confidence.meaning}', style: small),
          const SizedBox(height: 8),
          if (d.why.isNotEmpty) ...[
            const Text('為什麼是這個期間', style: TextStyle(fontWeight: FontWeight.w600)),
            Bullets(d.why, BulletKind.good),
          ],
          if (d.capped.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('被往下調的原因', style: TextStyle(fontWeight: FontWeight.w600)),
            Bullets(d.capped, BulletKind.warn),
          ],
          const SizedBox(height: 4),
          Text(d.whyNotHigher, style: const TextStyle(fontSize: 13, height: 1.4)),
          if (d.upgradeIf.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('升級條件（可以抱更久）', style: TextStyle(fontWeight: FontWeight.w600)),
            Bullets(d.upgradeIf, BulletKind.info),
          ],
          if (d.downgradeIf.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('降級條件（要縮短）', style: TextStyle(fontWeight: FontWeight.w600)),
            Bullets(d.downgradeIf, BulletKind.warn),
          ],
          const SizedBox(height: 6),
          KvRow('理由失效（立刻檢討出場）', '', note: d.hardInvalidation),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('證據來源（持續性分數 ${d.durationScore.toStringAsFixed(0)}）', style: const TextStyle(fontSize: 13)),
              children: [
                for (final e in d.evidence)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 34, child: Text('${e.weight.toStringAsFixed(0)}%', style: small)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(e.detail, style: small),
                            ],
                          ),
                        ),
                        Text(
                          e.score == null ? '尚無資料' : e.score!.toStringAsFixed(0),
                          style: TextStyle(fontWeight: FontWeight.w700, color: scoreColor(context, e.score)),
                        ),
                      ],
                    ),
                  ),
                Text('沒有資料的來源不列入，權重重新分配。基本面、事件資料接上後，持有期間才可能估到 D4／D5。', style: small),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 量價狀態、價量持續性、突破品質。
class _PvCard extends StatelessWidget {
  final StockReport r;
  const _PvCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final pv = r.pv;
    return SectionCard(
      title: '量價：${pv.state.label}',
      trailing: Tag('持續性 ${pv.persistence.toStringAsFixed(0)}', scoreColor(context, pv.persistence)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${pv.detail}。${pv.state.meaning}。', style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 6),
          const Text('價量持續性（中長期是累積還是分配）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          for (final x in pv.persistenceItems) ScoreItemRow(x),
          if (pv.breakoutQuality != null) ...[
            const SizedBox(height: 8),
            Text(
              '突破品質 ${pv.breakoutQuality!.toStringAsFixed(0)} 分',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            for (final x in pv.breakoutItems) ScoreItemRow(x),
          ],
        ],
      ),
    );
  }
}
