/// 簡單的圖表：多條折線、水平參考線（進場／停損／目標）、背景色帶（市場
/// 狀態區間）、成交量柱。不另外裝圖表套件，用 CustomPaint 畫。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';

class ChartSeries {
  final String label;
  final List<double?> values;
  final Color color;
  final double width;
  const ChartSeries(this.label, this.values, this.color, {this.width = 1.4});
}

class ChartLine {
  final String label;
  final double y;
  final Color color;
  const ChartLine(this.label, this.y, this.color);
}

class ChartBand {
  final double from, to;
  final Color color;
  const ChartBand(this.from, this.to, this.color);
}

class SimpleChart extends StatelessWidget {
  final List<ChartSeries> series;
  final List<ChartLine> lines;
  final List<ChartBand> bands;
  final List<double>? volumes;
  final List<bool>? volumeUp;
  final double? minY, maxY;
  final String? startLabel, endLabel;
  final double height;
  final String Function(double)? yFormat;

  const SimpleChart({
    super.key,
    required this.series,
    this.lines = const [],
    this.bands = const [],
    this.volumes,
    this.volumeUp,
    this.minY,
    this.maxY,
    this.startLabel,
    this.endLabel,
    this.height = 220,
    this.yFormat,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 10, color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _Painter(
              series: series,
              lines: lines,
              bands: bands,
              volumes: volumes,
              volumeUp: volumeUp,
              minY: minY,
              maxY: maxY,
              grid: scheme.outlineVariant,
              label: small,
              upColor: const Color(0xFFCF3528).withValues(alpha: .35),
              downColor: const Color(0xFF17824A).withValues(alpha: .35),
              yFormat: yFormat ?? (v) => v.abs() >= 1000 ? f0(v) : f2(v),
            ),
          ),
        ),
        if (startLabel != null || endLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 52),
            child: Row(
              children: [
                Text(startLabel ?? '', style: small),
                const Spacer(),
                Text(endLabel ?? '', style: small),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final s in series) _Legend(color: s.color, label: s.label),
            for (final l in lines) _Legend(color: l.color, label: '${l.label} ${f2(l.y)}', dashed: true),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _Legend({required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      dashed
          ? Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(width: 4, height: 2, margin: const EdgeInsets.only(right: 2), color: color),
              ],
            )
          : Container(width: 14, height: 3, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class _Painter extends CustomPainter {
  final List<ChartSeries> series;
  final List<ChartLine> lines;
  final List<ChartBand> bands;
  final List<double>? volumes;
  final List<bool>? volumeUp;
  final double? minY, maxY;
  final Color grid, upColor, downColor;
  final TextStyle label;
  final String Function(double) yFormat;

  _Painter({
    required this.series,
    required this.lines,
    required this.bands,
    required this.volumes,
    required this.volumeUp,
    required this.minY,
    required this.maxY,
    required this.grid,
    required this.label,
    required this.upColor,
    required this.downColor,
    required this.yFormat,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = series.isEmpty ? 0 : series.map((s) => s.values.length).reduce(math.max);
    if (n < 2) return;
    const labelW = 50.0;
    final w = size.width - labelW;
    final volH = volumes == null ? 0.0 : size.height * 0.2;
    final h = size.height - volH - (volumes == null ? 0 : 4);

    final all = <double>[for (final s in series) ...s.values.whereType<double>(), for (final l in lines) l.y];
    if (all.isEmpty) return;
    var lo = minY ?? all.reduce(math.min);
    var hi = maxY ?? all.reduce(math.max);
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    if (minY == null || maxY == null) {
      final pad = (hi - lo) * 0.05;
      if (minY == null) lo -= pad;
      if (maxY == null) hi += pad;
    }
    double x(int i) => i / (n - 1) * w;
    double y(double v) => h - (v - lo) / (hi - lo) * h;

    for (final b in bands) {
      final top = y(math.min(b.to, hi)), bottom = y(math.max(b.from, lo));
      if (bottom > top) canvas.drawRect(Rect.fromLTRB(0, top, w, bottom), Paint()..color = b.color);
    }

    final gp = Paint()
      ..color = grid
      ..strokeWidth = 0.8;
    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      canvas.drawLine(Offset(0, y(v)), Offset(w, y(v)), gp);
      final tp = TextPainter(
        text: TextSpan(text: yFormat(v), style: label),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: labelW - 4);
      tp.paint(canvas, Offset(w + 4, y(v) - tp.height / 2));
    }

    if (volumes != null && volumes!.isNotEmpty) {
      final vmax = volumes!.reduce(math.max);
      final bw = math.max(1.0, w / n * 0.7);
      for (var i = 0; i < volumes!.length && i < n; i++) {
        if (vmax <= 0) break;
        final bh = volumes![i] / vmax * volH;
        final up = volumeUp == null || volumeUp![i];
        canvas.drawRect(
          Rect.fromLTWH(x(i) - bw / 2, size.height - bh, bw, bh),
          Paint()..color = up ? upColor : downColor,
        );
      }
    }

    for (final l in lines) {
      final p = Paint()
        ..color = l.color
        ..strokeWidth = 1.2;
      final yy = y(l.y);
      for (var sx = 0.0; sx < w; sx += 8) {
        canvas.drawLine(Offset(sx, yy), Offset(math.min(sx + 4, w), yy), p);
      }
    }

    for (final s in series) {
      final path = Path();
      var started = false;
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null || v.isNaN) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(x(i), y(v));
          started = true;
        } else {
          path.lineTo(x(i), y(v));
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
