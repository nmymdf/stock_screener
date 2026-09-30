/// 個股頁：收盤價走勢（含 20/60 日線）、各項指標數字、符合篩選的理由。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/stock_catalog.dart';
import '../../logic/indicators.dart';
import '../../models/daily_bar.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

class StockDetailScreen extends StatelessWidget {
  final String code;
  final List<String> reasons;
  const StockDetailScreen({super.key, required this.code, this.reasons = const []});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final info = kBuiltinStocksByCode[code];
    final series = store.seriesOf(code);
    final ind = IndicatorSnapshot.compute(code, series);

    return Scaffold(
      appBar: AppBar(title: Text('$code ${info?.name ?? ''}')),
      body: ind == null
          ? ListView(padding: const EdgeInsets.all(14), children: [
              if (reasons.isNotEmpty) ...[
                const SectionHeader(left: '上榜理由'),
                RowList(children: [for (final r in reasons) InfoRow(title: Text(r, style: const TextStyle(fontSize: 13)))]),
              ],
              const SizedBox(height: 12),
              const Text('本機還沒有這檔股票的歷史資料，到「技術選股」或「資料」頁抓歷史資料後，這裡就會有走勢和指標。',
                  style: TextStyle(fontSize: 12)),
            ])
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text(
                  '${info?.market ?? ''} · 資料截至 ${ind.date} 收盤 · ${ind.bars} 個交易日',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                StatGrid(stats: [
                  ('收盤', f2(ind.close), null),
                  ('漲跌', pctTxt(ind.changePct), changeColor(context, ind.changePct ?? 0)),
                  ('成交量', '${f0(ind.volumeLots)} 張', null),
                  ('5 日線', optF2(ind.ma5), null),
                  ('20 日線', optF2(ind.ma20), null),
                  ('60 日線', optF2(ind.ma60), null),
                  ('RSI(14)', ind.rsi14?.toStringAsFixed(1) ?? '—', null),
                  ('量比', ind.volRatio == null ? '—' : '${ind.volRatio!.toStringAsFixed(2)} 倍', null),
                  ('20 日均量', ind.avgVol20 == null ? '—' : '${f0(ind.avgVol20!)} 張', null),
                  ('近 20 日', pctTxt(ind.return20Pct), changeColor(context, ind.return20Pct ?? 0)),
                ]),
                if (reasons.isNotEmpty) ...[
                  const SectionHeader(left: '上榜理由'),
                  RowList(children: [for (final r in reasons) InfoRow(title: Text(r, style: const TextStyle(fontSize: 13)))]),
                ],
                const SectionHeader(left: '收盤價走勢'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: Column(children: [
                      SizedBox(height: 220, child: PriceChart(series: series)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 14, children: [
                        _Legend(color: Theme.of(context).colorScheme.primary, label: '收盤'),
                        const _Legend(color: Colors.orange, label: '20 日線'),
                        const _Legend(color: Colors.purple, label: '60 日線'),
                      ]),
                    ]),
                  ),
                ),
                const SectionHeader(left: '最近 10 個交易日'),
                RowList(children: [
                  for (var i = series.length - 1; i >= 0 && i >= series.length - 10; i--)
                    _BarRow(bar: series[i], prevClose: i > 0 ? series[i - 1].close : null),
                ]),
              ],
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}

class _BarRow extends StatelessWidget {
  final DailyBar bar;
  final double? prevClose;
  const _BarRow({required this.bar, required this.prevClose});

  @override
  Widget build(BuildContext context) {
    final ch = prevClose == null || prevClose == 0 ? null : (bar.close - prevClose!) / prevClose! * 100;
    return InfoRow(
      title: Text(bar.date, style: const TextStyle(fontSize: 13)),
      subtitle: Text('開 ${f2(bar.open)} · 高 ${f2(bar.high)} · 低 ${f2(bar.low)} · ${f0(bar.volumeLots)} 張'),
      trailingTop: Text(f2(bar.close)),
      trailingBottom: Text(pctTxt(ch), style: TextStyle(color: changeColor(context, ch ?? 0))),
    );
  }
}

/// 簡單的折線圖：收盤價、20 日線、60 日線。不另外裝圖表套件，用 CustomPaint 畫。
class PriceChart extends StatelessWidget {
  final List<DailyBar> series;
  const PriceChart({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.infinite,
      painter: _ChartPainter(
        closes: [for (final b in series) b.close],
        priceColor: scheme.primary,
        ma20Color: Colors.orange,
        ma60Color: Colors.purple,
        gridColor: scheme.outlineVariant,
        labelStyle: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> closes;
  final Color priceColor, ma20Color, ma60Color, gridColor;
  final TextStyle labelStyle;

  _ChartPainter({
    required this.closes,
    required this.priceColor,
    required this.ma20Color,
    required this.ma60Color,
    required this.gridColor,
    required this.labelStyle,
  });

  List<double?> _maSeries(int n) => [
        for (var i = 0; i < closes.length; i++) i + 1 < n ? null : sma(closes.sublist(0, i + 1), n),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    if (closes.length < 2) return;
    const labelW = 48.0;
    final w = size.width - labelW;
    final h = size.height;
    final ma20 = _maSeries(20);
    final ma60 = _maSeries(60);
    final all = [...closes, ...ma20.whereType<double>(), ...ma60.whereType<double>()];
    var lo = all.reduce(math.min);
    var hi = all.reduce(math.max);
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    double x(int i) => i / (closes.length - 1) * w;
    double y(double v) => h - (v - lo) / (hi - lo) * (h - 8) - 4;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final v = lo + (hi - lo) * k / 3;
      canvas.drawLine(Offset(0, y(v)), Offset(w, y(v)), grid);
      final tp = TextPainter(text: TextSpan(text: f2(v), style: labelStyle), textDirection: TextDirection.ltr)
        ..layout(maxWidth: labelW - 4);
      tp.paint(canvas, Offset(w + 4, y(v) - tp.height / 2));
    }

    void line(List<double?> vals, Color color, double width) {
      final path = Path();
      var started = false;
      for (var i = 0; i < vals.length; i++) {
        final v = vals[i];
        if (v == null) continue;
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
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }

    line(ma60, ma60Color, 1.2);
    line(ma20, ma20Color, 1.2);
    line(closes, priceColor, 2);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.closes != closes || old.priceColor != priceColor;
}
