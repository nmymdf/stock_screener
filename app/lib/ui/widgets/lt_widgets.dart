/// 長期分析的共用元件：資料包下載引導、總分與六大類分數、旗標、市場曝險卡、進場時機提示。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/exposure.dart';
import '../../core/factors.dart';
import '../../core/lt_analysis.dart';
import '../../data/datapack_store.dart';
import '../../data/history_store.dart';
import '../../data/longterm_store.dart';
import '../../logic/engine/analysis.dart';
import '../../logic/engine/horizon.dart';
import '../../logic/engine/signals.dart';
import '../theme.dart';
import 'score_widgets.dart';

/// 比例（0.123）顯示成帶正負號的百分比（+12.3%）。
String sp(double x, [int d = 1]) => x.isNaN ? '—' : '${x >= 0 ? '+' : ''}${(x * 100).toStringAsFixed(d)}%';

/// 比例顯示成百分比（12%）。
String pc(double x, [int d = 0]) => x.isNaN ? '—' : '${(x * 100).toStringAsFixed(d)}%';

Color ltFlagColor(LtFlag f) => switch (f) {
  LtFlag.overheat => const Color(0xFFE8743B),
  LtFlag.downtrend => const Color(0xFF5B8DB8),
  LtFlag.revenueDrop => const Color(0xFF8E44AD),
  LtFlag.loss => const Color(0xFFB71C1C),
  LtFlag.yieldTrap => const Color(0xFFC98A00),
  LtFlag.epsDrop => const Color(0xFF8E44AD),
  LtFlag.illiquid => Colors.grey,
};

class LtFlagTags extends StatelessWidget {
  final Set<LtFlag> flags;
  final bool showIlliquid;
  const LtFlagTags(this.flags, {super.key, this.showIlliquid = false});

  @override
  Widget build(BuildContext context) {
    final l = flags.where((f) => showIlliquid || f != LtFlag.illiquid).toList();
    if (l.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 4, runSpacing: 4, children: [for (final f in l) Tag(f.label, ltFlagColor(f))]);
  }
}

/// 「第 12 名／850・前 2%」。
String rankText(LtScore s, int total) =>
    '第 ${s.rank} 名／$total・前 ${((1 - s.pct) * 100).clamp(0.5, 100).toStringAsFixed(0)}%';

Color pctColor(BuildContext context, double pct) => scoreColor(context, pct * 100);

/// 六大類分數。
class LtGroupBars extends StatelessWidget {
  final LtScore s;
  final bool explain;
  const LtGroupBars(this.s, {super.key, this.explain = true});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final g in FactorGroup.values)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ScoreBar(
            label: g.label,
            score: s.groups[g],
            trailing: '權重 ${(g.weight * 100).round()}%',
            subtitle: explain ? g.explain : null,
          ),
        ),
    ],
  );
}

/// 一句話的亮點（清單上用）：最多三個。
List<String> ltHighlights(LtScore s) {
  final r = s.raw;
  final out = <String>[];
  if (r.revNewHigh) out.add('營收創新高');
  if (!r.revYoy3.isNaN && r.revYoy3 >= 0.15) out.add(r.revYoy3 > 3 ? '營收近3月>300%' : '營收近3月${sp(r.revYoy3, 0)}');
  if (!r.roe.isNaN && r.roe >= 0.15) out.add('ROE ${pc(r.roe)}');
  if (!r.yld.isNaN && r.yld >= 4 && !s.flags.contains(LtFlag.yieldTrap)) out.add('殖利率 ${r.yld.toStringAsFixed(1)}%');
  if (!r.pePct.isNaN && r.pePct <= 0.3) out.add('本益比在5年低檔');
  if (!r.it.isNaN && r.it > 0.02) out.add('投信買超');
  if (!r.fi.isNaN && r.fi > 0.05) out.add('外資買超');
  if (!r.mom12.isNaN && r.mom12 >= 0.3) out.add('一年漲${sp(r.mom12, 0)}');
  if (!r.vol.isNaN && r.vol <= 0.22) out.add('波動低');
  return out.take(3).toList();
}

/// 原始數值的白話說明。
List<(String, String, String?)> ltFacts(LtScore s) {
  final r = s.raw;
  return [
    if (!r.revYoy3.isNaN) ('近 3 個月營收年增', sp(r.revYoy3), r.revMonth >= 0 ? '到 ${revenueMonthLabel(r.revMonth)}' : null),
    if (!r.revPos12.isNaN) ('近 12 個月營收成長的月數', '${(r.revPos12 * 12).round()} 個月', null),
    if (!r.rev12.isNaN) ('近 12 個月累計營收年增', sp(r.rev12), null),
    if (!r.roe.isNaN) ('股東權益報酬率（ROE，近四季）', pc(r.roe, 1), r.roeStab.isNaN ? null : '近 3 年穩定度（平均減波動）${pc(r.roeStab, 1)}'),
    if (!r.epsGrowth.isNaN) ('每股盈餘一年來', sp(r.epsGrowth), null),
    if (!r.pe.isNaN)
      ('本益比', r.pe.toStringAsFixed(1), r.pePct.isNaN ? null : '比自己過去 5 年 ${pc(r.pePct)} 的時間貴（越低越便宜）')
    else if (!r.pb.isNaN)
      ('本益比', '—（近四季虧損）', null),
    if (!r.yld.isNaN)
      (
        '現金殖利率',
        '${r.yld.toStringAsFixed(2)}%',
        [
          if (!r.payout.isNaN) '配息率 ${pc(r.payout)}',
          if (!r.divYears.isNaN) '近 5 年有 ${r.divYears.round()} 年配息',
          if (s.flags.contains(LtFlag.yieldTrap)) '⚠ 可能是殖利率陷阱',
        ].join('・'),
      ),
    if (!r.fi.isNaN) ('外資近 60 日買賣超／成交量', sp(r.fi), null),
    if (!r.it.isNaN) ('投信近 60 日買賣超／成交量', sp(r.it), null),
    if (!r.dist200.isNaN)
      (
        '股價離年線（含息）',
        sp(r.dist200),
        r.slope200.isNaN ? null : '年線${r.slope200 >= 0 ? '往上' : '往下'}（一個月 ${sp(r.slope200)}）',
      ),
    if (!r.mom12.isNaN) ('近 12 個月含息報酬（不含最近 1 個月）', sp(r.mom12), null),
    if (!r.vol.isNaN) ('近一年波動度', pc(r.vol), r.mdd.isNaN ? null : '一年內最大跌幅 ${pc(r.mdd)}'),
    if (!r.val60.isNaN) ('近 60 日平均每天成交值', '${r.val60.toStringAsFixed(r.val60 >= 100 ? 0 : 1)} 百萬', null),
  ];
}

/// 進場時機（參考短線）：長期挑好股票，什麼時候買可以參考短線狀態，避免買在過熱的時候。
(String, Color)? entryTiming(StockReport? r, LtScore? s) {
  if (s != null && s.flags.contains(LtFlag.overheat)) return ('短期過熱：分批買或等拉回', const Color(0xFFE8743B));
  if (r == null) return null;
  final hot = r.warnings.any((w) => w.contains('乖離過大') || w.contains('過熱'));
  if (hot) return ('短線偏熱：分批買', const Color(0xFFE8743B));
  if (r.recommended) return ('短線有進場訊號：${r.primary!.hit.strategy.label}', AppColors.up);
  if (r.pv.state.bad) return ('量價轉弱：等站穩再買', const Color(0xFF5B8DB8));
  return ('短線中性：可以分批布局', Colors.blueGrey);
}

/// 下次每月檢視日（11 日以後第一個交易日；遇到假日順延）。
String nextReviewText(String today) {
  final d = DateTime.parse(today);
  final target = d.day < 11 ? DateTime(d.year, d.month, 11) : DateTime(d.year, d.month + 1, 11);
  return '${target.month}/11 之後第一個交易日';
}

/// 沒有資料包時的引導、下載進度、第一次分析的進度；都好了才顯示 [builder]。
class PackGate extends StatelessWidget {
  final Widget Function(BuildContext context, LtResult r) builder;
  const PackGate({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final pack = context.watch<DataPackStore>();
    final lt = context.watch<LongTermStore>();
    final r = lt.result;
    if (r != null) return builder(context, r);
    if (!pack.loaded || !lt.loaded) return const Center(child: CircularProgressIndicator());
    if (!pack.hasPack) return const PackIntro();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lt.analyzing || pack.updating) ...[
              Text(pack.updating ? '更新資料包中…' : '長期分析中…（十幾年的資料，第一次約需 10～30 秒）'),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: pack.updating && pack.totalBytes > 0 ? pack.doneBytes / pack.totalBytes : null,
              ),
            ] else ...[
              Text(lt.error ?? '還沒有分析結果', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: lt.refresh, child: const Text('重新分析')),
            ],
          ],
        ),
      ),
    );
  }
}

/// 第一次使用：說明要下載什麼，按一下開始。
class PackIntro extends StatelessWidget {
  const PackIntro({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = context.watch<DataPackStore>();
    final lt = context.read<LongTermStore>();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download_outlined, color: scheme.primary, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('先下載長期資料', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '長期選股要看好幾年的資料：2013 年以來每天的收盤（含除權息）、本益比、殖利率、三大法人，'
              '每月營收、歷年配息，以及費半、Nasdaq、美元匯率等國際指標。\n\n'
              '這些資料由 GitHub 每個交易日晚上自動整理好，第一次下載約 30 MB，之後每天只下載約 1 MB 的更新。'
              '下載的只有公開的市場資料，你的持股不會上傳。',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 14),
            if (pack.updating) ...[
              LinearProgressIndicator(value: pack.totalBytes > 0 ? pack.doneBytes / pack.totalBytes : null),
              const SizedBox(height: 6),
              Text(
                pack.totalBytes > 0
                    ? '下載中… ${(pack.doneBytes / 1e6).toStringAsFixed(1)} / ${(pack.totalBytes / 1e6).toStringAsFixed(1)} MB'
                    : '連線中…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              FilledButton.icon(
                onPressed: lt.updatePack,
                icon: const Icon(Icons.download),
                label: const Text('下載長期資料（約 30 MB）'),
              ),
            if (pack.error != null) ...[
              const SizedBox(height: 8),
              Text(pack.error!, style: TextStyle(color: scheme.error, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

Color exposureColor(double level) =>
    level >= 0.999 ? AppColors.up : (level >= 0.749 ? const Color(0xFFC9A000) : const Color(0xFF5B8DB8));

/// 市場環境：建議股票比例、理由、國際指標。
class ExposureCard extends StatelessWidget {
  final ExposureState e;
  final ExposureMode mode;
  final bool compact;
  final VoidCallback? onTap;
  const ExposureCard(this.e, {super.key, required this.mode, this.compact = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = exposureColor(e.level);
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c, width: 5)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.speed, color: c),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '市場環境：${e.label}',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c),
                    ),
                  ),
                  if (onTap != null) const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 6),
              Text(e.reasons.join('；'), style: const TextStyle(fontSize: 13, height: 1.4)),
              if (mode == ExposureMode.none)
                Text('（你選的是「一直滿倉」，不依環境調整；以上僅供參考）', style: small)
              else if (mode == ExposureMode.local && e.intlLevel < e.localLevel)
                Text('國際指標偏弱：如果也看國際環境，會建議 ${ExposureState.levelLabel(e.intlLevel)}', style: small),
              if (!compact && e.intl.isNotEmpty) ...[
                const Divider(height: 18),
                for (final x in e.intl)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          x.risk ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                          size: 16,
                          color: x.risk ? const Color(0xFFC98A00) : const Color(0xFF0B7A6F),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(x.note, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text('國際資料用台股前一天以前的美國收盤（美國收盤在台灣開盤之前），只用來調整股票比例，不用來挑股票。', style: small),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 短線分析（每日行情）的單檔報告，給進場時機提示用。
StockReport? shortReportOf(BuildContext context, String code) =>
    context.select<HistoryStore, StockReport?>((s) => s.analysis?.stock(code));
