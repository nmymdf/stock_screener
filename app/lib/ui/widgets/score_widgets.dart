/// 分數、策略、市場狀態、產業分類的小元件，讓各畫面長得一致。
library;

import 'package:flutter/material.dart';

import '../../logic/engine/industry_engine.dart';
import '../../logic/engine/market_engine.dart';
import '../../logic/engine/scoring.dart';
import '../theme.dart';

Color regimeColor(Regime? r) => switch (r) {
  Regime.strongBull => AppColors.up,
  Regime.bull => const Color(0xFFE8743B),
  Regime.range => const Color(0xFFC9A000),
  Regime.weak => const Color(0xFF5B8DB8),
  Regime.bear => AppColors.down,
  null => Colors.grey,
};

Color industryClassColor(IndustryClass? c) => switch (c) {
  IndustryClass.leading => AppColors.up,
  IndustryClass.improving => const Color(0xFFE8743B),
  IndustryClass.neutral => Colors.blueGrey,
  IndustryClass.weakening => const Color(0xFF5B8DB8),
  IndustryClass.lagging => AppColors.down,
  null => Colors.grey,
};

/// 圓形分數徽章。
class ScoreBadge extends StatelessWidget {
  final double? score;
  final double size;
  final String? caption;
  const ScoreBadge({super.key, required this.score, this.size = 46, this.caption});

  @override
  Widget build(BuildContext context) {
    final c = scoreColor(context, score);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: (score ?? 0) / 100,
              strokeWidth: size / 12,
              color: c,
              backgroundColor: c.withValues(alpha: .15),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score == null ? '—' : score!.toStringAsFixed(0),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.34, color: c, height: 1),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: TextStyle(fontSize: size * 0.16, color: c, height: 1.1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 小標籤（策略、市場狀態、產業分類共用）。
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const Tag(this.text, this.color, {super.key, this.filled = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(color: filled ? Colors.white : color, fontWeight: FontWeight.w700, fontSize: 11),
    ),
  );
}

class StrategyTag extends StatelessWidget {
  final String code;
  final String label;
  final bool dimmed;
  const StrategyTag({super.key, required this.code, required this.label, this.dimmed = false});

  @override
  Widget build(BuildContext context) => Opacity(opacity: dimmed ? .45 : 1, child: Tag(label, strategyColor(code)));
}

/// 橫條分數：模組名稱、權重、分數。
class ScoreBar extends StatelessWidget {
  final String label;
  final double? score; // 0～100
  final String? trailing;
  final String? subtitle;
  const ScoreBar({super.key, required this.label, required this.score, this.trailing, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = scoreColor(context, score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 8),
            SizedBox(
              width: 42,
              child: Text(
                score == null ? '—' : score!.toStringAsFixed(0),
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700, color: c),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score == null ? 0 : score! / 100,
            minHeight: 6,
            color: c,
            backgroundColor: c.withValues(alpha: .12),
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

enum BulletKind { good, warn, bad, info }

/// 條列：✓ 理由、⚠ 注意、✕ 否決、• 說明。
class Bullets extends StatelessWidget {
  final List<String> items;
  final BulletKind kind;
  const Bullets(this.items, this.kind, {super.key});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      BulletKind.good => (Icons.check_circle, const Color(0xFF0B7A6F)),
      BulletKind.warn => (Icons.warning_amber_rounded, const Color(0xFFB7860B)),
      BulletKind.bad => (Icons.cancel, Theme.of(context).colorScheme.error),
      BulletKind.info => (Icons.circle, Theme.of(context).colorScheme.outline),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: Icon(icon, size: kind == BulletKind.info ? 6 : 15, color: color),
                ),
                Expanded(child: Text(t, style: const TextStyle(fontSize: 13, height: 1.35))),
              ],
            ),
          ),
      ],
    );
  }
}

/// 可以展開看逐項得分的模組分數。
class ModuleScoreTile extends StatelessWidget {
  final ModuleScore m;
  const ModuleScoreTile({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    final scored = m.items.where((x) => x.max > 0).toList();
    final info = m.items.where((x) => x.max == 0).toList();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        title: ScoreBar(
          label: m.name,
          score: m.score,
          trailing: '權重 ${m.weight.toStringAsFixed(0)}',
          subtitle: m.summary,
        ),
        children: [
          if (m.items.isEmpty) Text(m.summary, style: const TextStyle(fontSize: 12)),
          for (final x in scored)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    x.points >= x.max ? Icons.check : (x.points > 0 ? Icons.remove : Icons.close),
                    size: 14,
                    color: x.points >= x.max ? const Color(0xFF0B7A6F) : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(x.label, style: const TextStyle(fontSize: 12))),
                  Text(
                    '${x.points.toStringAsFixed(0)}／${x.max.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          if (info.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              children: [for (final x in info) Text(x.label, style: const TextStyle(fontSize: 11, color: Colors.grey))],
            ),
          ],
        ],
      ),
    );
  }
}

/// 帶標題的卡片區塊。
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  ?trailing,
                ],
              ),
            ),
          child,
        ],
      ),
    ),
  );
}

/// 兩欄的「名稱：數值」表格列。
class KvRow extends StatelessWidget {
  final String k;
  final String v;
  final String? note;
  final Color? color;
  const KvRow(this.k, this.v, {super.key, this.note, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                v,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
        if (note != null) Text(note!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
      ],
    ),
  );
}
