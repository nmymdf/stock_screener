/// 共用的小元件（沿用 stock_acc 的樣式）：統計方格、清單列、區塊標題、
/// 非投資建議的提醒卡。
library;

import 'package:flutter/material.dart';

/// 每個選股畫面最上面都要有的提醒：機械化篩選，不是投資建議。
class DisclaimerCard extends StatelessWidget {
  final String text;
  const DisclaimerCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// 小型統計數字方格（例如個股頁「收盤、5 日線、20 日線…」那排）。
class StatGrid extends StatelessWidget {
  final List<(String, String, Color?)> stats;

  /// 已經放在卡片裡的時候設成 true，不要再包一層卡片。
  final bool bare;

  const StatGrid({super.key, required this.stats, this.bare = false});

  @override
  Widget build(BuildContext context) {
    final grid = _grid(context);
    return bare
        ? grid
        : Card(
            child: Padding(padding: const EdgeInsets.all(14), child: grid),
          );
  }

  Widget _grid(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        for (final s in stats)
          SizedBox(
            width: 118,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.$1, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  s.$2,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: s.$3),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 區塊標題列：左邊標題、右邊補充說明。
class SectionHeader extends StatelessWidget {
  final String left;
  final String? right;

  const SectionHeader({super.key, required this.left, this.right});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          if (right != null) Text(right!, style: style),
        ],
      ),
    );
  }
}

/// 一張卡片包住一組 [InfoRow]，中間有分隔線。
class RowList extends StatelessWidget {
  final List<Widget> children;
  final String emptyText;

  const RowList({super.key, required this.children, this.emptyText = '沒有資料'});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(emptyText, style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1), children[i]],
        ],
      ),
    );
  }
}

/// 清單裡的一列：左上標題、左下副標、右上主要數字、右下次要數字。
class InfoRow extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailingTop;
  final Widget? trailingBottom;

  const InfoRow({super.key, this.onTap, required this.title, this.subtitle, this.trailingTop, this.trailingBottom});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    child: title,
                  ),
                  if (subtitle != null)
                    DefaultTextStyle.merge(
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      child: subtitle!,
                    ),
                ],
              ),
            ),
            if (trailingTop != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: trailingTop!),
                    if (trailingBottom != null)
                      DefaultTextStyle.merge(
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        child: trailingBottom!,
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

/// 排名徽章：前幾名特別標記用。
class RankBadge extends StatelessWidget {
  final int rank;
  const RankBadge({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
      child: Text(
        '#$rank',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
