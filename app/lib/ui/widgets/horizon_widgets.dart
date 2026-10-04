/// 短中長交叉分析、持有期間、量價狀態、歷史統計、每日建議的共用小元件。
library;

import 'package:flutter/material.dart';

import '../../logic/engine/horizon.dart';
import '../../logic/engine/scoring.dart';
import '../../logic/holding_eval.dart';
import '../../models/holding.dart';
import '../theme.dart';
import 'score_widgets.dart';

Color opportunityColor(Opportunity o) => switch (o) {
  Opportunity.resonance => const Color(0xFFB71C1C),
  Opportunity.swing => const Color(0xFFE8743B),
  Opportunity.longTurning => const Color(0xFF6A1B9A),
  Opportunity.tactical => const Color(0xFF8D6E63),
  Opportunity.waitEntry => const Color(0xFF1565C0),
  Opportunity.watchlist => const Color(0xFF00838F),
  Opportunity.themeSwing => const Color(0xFFC9A000),
  Opportunity.neutral => Colors.blueGrey,
  Opportunity.avoid => Colors.grey,
};

Color confidenceColor(Confidence c) => switch (c) {
  Confidence.high => const Color(0xFF0B7A6F),
  Confidence.medium => const Color(0xFF2F6FA8),
  Confidence.low => const Color(0xFFB7860B),
};

/// 「D2 2～8 週・信心 中」
class DurationTag extends StatelessWidget {
  final DurationEstimate d;
  const DurationTag(this.d, {super.key});

  @override
  Widget build(BuildContext context) => Tag(
    d.cls == null ? '不建議持有' : 'D${d.cls} ${kDurationRange[d.cls]}・信心${d.confidence.label}',
    d.cls == null ? Colors.grey : confidenceColor(d.confidence),
  );
}

/// 推薦卡片用：短／中／長三個迷你分數條。
class HorizonTriple extends StatelessWidget {
  final HorizonScore short, medium, long;
  const HorizonTriple({super.key, required this.short, required this.medium, required this.long});

  @override
  Widget build(BuildContext context) {
    Widget one(String label, double? v) {
      final c = scoreColor(context, v);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: const TextStyle(fontSize: 11)),
                const Spacer(),
                Text(
                  v == null ? '—' : v.toStringAsFixed(0),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
                ),
              ],
            ),
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (v ?? 0) / 100,
                minHeight: 5,
                color: c,
                backgroundColor: c.withValues(alpha: .12),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        one('短期', short.score),
        const SizedBox(width: 10),
        one('中期', medium.score),
        const SizedBox(width: 10),
        one('長期', long.score),
      ],
    );
  }
}

/// 可以展開看逐項得分的週期分數（跟模組分數同一種樣式）。
class HorizonTile extends StatelessWidget {
  final HorizonScore h;
  const HorizonTile(this.h, {super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: ScoreBar(label: '${h.name}（${h.span}）', score: h.score, subtitle: h.summary),
        children: [
          for (final x in h.items) ScoreItemRow(x),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '失效條件：${h.invalidation}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class ScoreItemRow extends StatelessWidget {
  final ScoreItem x;
  const ScoreItemRow(this.x, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(
          x.points >= x.max * 0.99 ? Icons.check : (x.points > 0 ? Icons.remove : Icons.close),
          size: 14,
          color: x.points >= x.max * 0.99 ? const Color(0xFF0B7A6F) : Colors.grey,
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(x.label, style: const TextStyle(fontSize: 12))),
        Text(
          '${x.points.toStringAsFixed(0)}／${x.max.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    ),
  );
}

Color actionColor(DailyAction a) => switch (a) {
  DailyAction.stopLoss => const Color(0xFFD32F2F),
  DailyAction.overdue => const Color(0xFFB71C1C),
  DailyAction.exit => const Color(0xFF1E6FD9),
  DailyAction.sellHalf => const Color(0xFF6A1B9A),
  DailyAction.addOn => const Color(0xFFCF3528),
  DailyAction.caution => const Color(0xFFC98A00),
  DailyAction.hold => const Color(0xFF2E7D32),
  DailyAction.pending || DailyAction.closed => Colors.grey,
};

IconData actionIcon(DailyAction a) => switch (a) {
  DailyAction.stopLoss => Icons.dangerous,
  DailyAction.overdue => Icons.alarm,
  DailyAction.exit => Icons.logout,
  DailyAction.sellHalf => Icons.call_split,
  DailyAction.addOn => Icons.add_circle,
  DailyAction.caution => Icons.warning_amber_rounded,
  DailyAction.hold => Icons.check_circle,
  DailyAction.pending => Icons.hourglass_empty,
  DailyAction.closed => Icons.inventory_2_outlined,
};

class ActionTag extends StatelessWidget {
  final DailyAction action;
  final bool big;

  /// 持有方式：長期用「健康／觀察／轉弱／考慮減碼」的說法。
  final HoldStyle? style;
  const ActionTag(this.action, {super.key, this.big = false, this.style});

  @override
  Widget build(BuildContext context) {
    final c = actionColor(action);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 10 : 7, vertical: big ? 4 : 2),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(actionIcon(action), size: big ? 18 : 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            style == null ? action.label : actionText(action, style!),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: big ? 15 : 12),
          ),
        ],
      ),
    );
  }
}

Color healthColor(int h) =>
    h >= 70 ? const Color(0xFF2E7D32) : (h >= 50 ? const Color(0xFFC98A00) : const Color(0xFFD32F2F));

/// 健康度小徽章：「健康 82」。
class HealthTag extends StatelessWidget {
  final int health;
  const HealthTag(this.health, {super.key});

  @override
  Widget build(BuildContext context) => Tag('健康度 $health', healthColor(health));
}

/// 健康度走勢的迷你折線。
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double min, max;
  final double height;
  const Sparkline(this.values, {super.key, this.min = 0, this.max = 100, this.height = 36});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _SparkPainter(values, min, max, Theme.of(context).colorScheme.primary)),
  );
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  final double min, max;
  final Color color;
  _SparkPainter(this.v, this.min, this.max, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    double x(int i) => i / (v.length - 1) * size.width;
    double y(double val) => size.height - (val - min) / (max - min) * size.height;
    final guide = Paint()
      ..color = color.withValues(alpha: .25)
      ..strokeWidth = 1;
    for (final g in [50.0, 70.0]) {
      canvas.drawLine(Offset(0, y(g)), Offset(size.width, y(g)), guide);
    }
    final p = Path()..moveTo(x(0), y(v[0]));
    for (var i = 1; i < v.length; i++) {
      p.lineTo(x(i), y(v[i]));
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(Offset(x(v.length - 1), y(v.last)), 3.5, Paint()..color = healthColor(v.last.round()));
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.v != v;
}
