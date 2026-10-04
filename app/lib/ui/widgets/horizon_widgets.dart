/// 短中長交叉分析、持有期間、量價狀態、歷史統計、每日建議的共用小元件。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../logic/engine/backtest.dart';
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

/// 歷史上同類訊號的結果：賺錢比例、先到目標、先停損、平均 R、典型走勢區間。
class CalibrationView extends StatelessWidget {
  final CalStat c;
  final bool compact;
  const CalibrationView(this.c, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    String pc(double v) => '${(v * 100).toStringAsFixed(0)}%';
    final rel = c.reliable;
    final line =
        '過去 ${c.n} 次：賺錢 ${pc(c.winRate)}｜先到目標 ${pc(c.targetRate)}｜先停損 ${pc(c.stopRate)}｜'
        '平均 ${c.avgR >= 0 ? '+' : ''}${c.avgR.toStringAsFixed(2)}R｜平均 ${c.avgDays.toStringAsFixed(0)} 天';
    if (compact) {
      return Text(
        '📊 $line',
        style: small?.copyWith(
          color: rel == false ? Theme.of(context).colorScheme.error : null,
          fontWeight: rel == true ? FontWeight.w600 : null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            Tag(c.title, Colors.blueGrey),
            Tag(
              rel == true ? '歷史上可靠' : (rel == false ? '歷史上平均虧損' : (c.n < 15 ? '樣本少，僅供參考' : '歷史上普通')),
              rel == true ? const Color(0xFF0B7A6F) : (rel == false ? AppColors.up : Colors.grey),
              filled: rel != null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(line, style: const TextStyle(fontSize: 13, height: 1.4)),
        if (c.from != null) Text('統計期間：${c.from} ～ ${c.to}（只用本機資料，條件跟推薦完全一樣，隔天開盤進場）', style: small),
        if (c.cone.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('買進後的典型走勢（R）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ConeChart(cone: c.cone),
          Text('中間線是中位數，色帶是一半的情況會落在的範圍（25%～75%）。持股如果掉到色帶下方，就是比同類訊號弱。', style: small),
        ],
      ],
    );
  }
}

/// 典型走勢區間的小圖。
class ConeChart extends StatelessWidget {
  final List<ConePoint> cone;
  final double? mark; // 目前持股的 R
  final int? markDay;
  const ConeChart({super.key, required this.cone, this.mark, this.markDay});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    width: double.infinity,
    child: CustomPaint(
      painter: _ConePainter(
        cone,
        mark,
        markDay,
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.onSurfaceVariant,
        Theme.of(context).textTheme.bodySmall!,
      ),
    ),
  );
}

class _ConePainter extends CustomPainter {
  final List<ConePoint> cone;
  final double? mark;
  final int? markDay;
  final Color color, text;
  final TextStyle base;
  _ConePainter(this.cone, this.mark, this.markDay, this.color, this.text, this.base);

  @override
  void paint(Canvas canvas, Size size) {
    if (cone.isEmpty) return;
    var lo = cone.map((c) => c.p25).reduce(math.min);
    var hi = cone.map((c) => c.p75).reduce(math.max);
    if (mark != null) {
      lo = math.min(lo, mark!);
      hi = math.max(hi, mark!);
    }
    lo = math.min(lo, -0.5);
    hi = math.max(hi, 0.5);
    const left = 34.0, bottom = 16.0;
    final w = size.width - left - 6, h = size.height - bottom - 4;
    final maxDay = cone.last.day.toDouble();
    double x(num d) => left + (d - 1) / math.max(1, maxDay - 1) * w;
    double y(double v) => 4 + (hi - v) / (hi - lo) * h;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String s, Offset o) {
      tp.text = TextSpan(
        text: s,
        style: base.copyWith(fontSize: 10, color: text),
      );
      tp.layout();
      tp.paint(canvas, o);
    }

    final zero = Paint()
      ..color = text.withValues(alpha: .4)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, y(0)), Offset(left + w, y(0)), zero);
    label('0R', Offset(4, y(0) - 6));
    label('${hi.toStringAsFixed(1)}R', const Offset(0, 0));
    label('${lo.toStringAsFixed(1)}R', Offset(0, 4 + h - 10));
    final band = Path()..moveTo(x(cone.first.day), y(cone.first.p75));
    for (final c in cone) {
      band.lineTo(x(c.day), y(c.p75));
    }
    for (final c in cone.reversed) {
      band.lineTo(x(c.day), y(c.p25));
    }
    band.close();
    canvas.drawPath(band, Paint()..color = color.withValues(alpha: .15));
    final mid = Path()..moveTo(x(cone.first.day), y(cone.first.p50));
    for (final c in cone) {
      mid.lineTo(x(c.day), y(c.p50));
    }
    canvas.drawPath(
      mid,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    for (final c in cone) {
      label('第${c.day}天', Offset(x(c.day) - 12, size.height - 13));
    }
    if (mark != null && markDay != null && markDay! >= 1) {
      final d = math.min(markDay!, cone.last.day);
      canvas.drawCircle(Offset(x(d), y(mark!)), 5, Paint()..color = AppColors.up);
    }
  }

  @override
  bool shouldRepaint(covariant _ConePainter old) => old.cone != cone || old.mark != mark;
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
