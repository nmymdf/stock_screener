/// 版面工具：電腦寬螢幕用雙欄、卡片格狀排列，手機自動變回單欄。
library;

import 'package:flutter/material.dart';

/// 內容最寬多少（再寬就置中，兩邊留白）。
const double kMaxContentWidth = 1600;

/// 多寬以上算「寬螢幕」，改用雙欄。
const double kWideBreakpoint = 1100;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= kWideBreakpoint;

/// 頁面四周的留白：電腦寬一點，手機窄一點。
EdgeInsets pagePadding(BuildContext context) =>
    isWide(context) ? const EdgeInsets.fromLTRB(24, 18, 24, 32) : const EdgeInsets.fromLTRB(14, 14, 14, 24);

/// 依「視窗寬度」自動決定的字體倍率：越寬的螢幕字越大。
double autoFontScale(double width) => width >= 1700 ? 1.25 : (width >= 1100 ? 1.15 : 1.0);

const kFontScales = [1.0, 1.15, 1.3, 1.45];

/// 卡片格狀排列：寬度夠就排成好幾欄（每欄至少 [minItemWidth]），不夠就一欄。
class CardGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  const CardGrid({super.key, required this.children, this.minItemWidth = 560, this.spacing = 12});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final cols = ((c.maxWidth + spacing) / (minItemWidth + spacing)).floor().clamp(1, 3);
        if (cols == 1) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < cols; k++) ...[
                  if (k > 0) SizedBox(width: spacing),
                  Expanded(child: i + k < children.length ? children[i + k] : const SizedBox.shrink()),
                ],
              ],
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}

/// 雙欄：寬螢幕左右並排，窄螢幕上下接續。
class SplitView extends StatelessWidget {
  final List<Widget> left, right;
  final int leftFlex, rightFlex;
  const SplitView({super.key, required this.left, required this.right, this.leftFlex = 11, this.rightFlex = 9});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < kWideBreakpoint - 60) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, ...right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: leftFlex,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: rightFlex,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
            ),
          ],
        );
      },
    );
  }
}

/// 每個分頁最上面的標題列：圖示、標題、說明、右邊的補充（例如資料日期）。
class PageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const PageHeader({super.key, required this.icon, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, Color.lerp(scheme.primary, const Color(0xFF1F4E79), .6)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: .5)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
