/// 每個畫面最上面的抬頭（像看盤軟體的頂端列）：標誌、版本、作者、加權指數、
/// 市場分數、資料日期與自動更新狀態、字體大小（整個 App）、深淺色切換。
///
/// 這一列放在 Navigator 之上（MaterialApp.builder），所以不能用 Tooltip、
/// 選單這類需要 Overlay 的元件。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_build_info.dart';
import '../../core/exposure.dart';
import '../../data/history_store.dart';
import '../../data/longterm_store.dart';
import '../../logic/engine/market_engine.dart';
import '../format.dart';
import '../layout.dart';
import 'lt_widgets.dart';
import 'score_widgets.dart';

class AppBanner extends StatelessWidget {
  const AppBanner({super.key});

  static const gold = Color(0xFFD4AF37);
  static const bg1 = Color(0xFF0B1E33);
  static const bg2 = Color(0xFF14395A);
  static const muted = Color(0xFF9FB3C8);
  static const up = Color(0xFFFF6D60);
  static const down = Color(0xFF4CC47F);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final store = context.watch<HistoryStore>();
    const author = Text(
      '作者: ArchieKUO',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: gold),
    );
    return Material(
      color: bg1,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [bg1, bg2], begin: Alignment.centerLeft, end: Alignment.centerRight),
          border: Border(bottom: BorderSide(color: gold, width: 1.2)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: w >= 760 ? 18 : 12, vertical: 6),
            child: Row(
              children: [
                const _Logo(),
                const SizedBox(width: 8),
                const Text(
                  '台股選股',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: gold.withValues(alpha: .7)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    kAppVersion,
                    style: TextStyle(fontSize: 11, color: gold, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                if (w >= 760) author else Flexible(child: author),
                if (w >= kWideBreakpoint) ...[const SizedBox(width: 18), Expanded(child: _Ticker(store: store))],
                if (w >= 760 && w < kWideBreakpoint) const Spacer(),
                if (w >= 760) ...[
                  const SizedBox(width: 10),
                  _FontControl(store: store, width: w),
                  const SizedBox(width: 6),
                  _ThemeToggle(store: store),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 加權指數、市場分數、資料日期、更新狀態。
class _Ticker extends StatelessWidget {
  final HistoryStore store;
  const _Ticker({required this.store});

  @override
  Widget build(BuildContext context) {
    final dates = store.tradingDates;
    final taiex = store.taiexByDate;
    final withIdx = [
      for (final d in dates)
        if (taiex[d] != null) d,
    ];
    double? last, chg;
    if (withIdx.isNotEmpty) {
      last = taiex[withIdx.last];
      if (withIdx.length >= 2) chg = (last! / taiex[withIdx[withIdx.length - 2]]! - 1) * 100;
    }
    final today = store.analysis?.today;
    final exposure = context.select<LongTermStore, ExposureState?>((s) => s.result?.exposure);
    final missing = store.missingDates().length;
    final (statusText, statusColor) = store.syncing
        ? ('更新中 ${store.syncDone}/${store.syncTotal}', const Color(0xFFFFC857))
        : (dates.isEmpty
              ? ('尚未下載資料', AppBanner.muted)
              : (missing == 0 ? ('資料已是最新', AppBanner.down) : ('$missing 天待更新', const Color(0xFFFFC857))));
    Widget sep() =>
        Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 12), color: Colors.white24);
    const label = TextStyle(fontSize: 12, color: AppBanner.muted);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (last != null) ...[
            const Text('加權指數 ', style: label),
            Text(
              f2(last),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            if (chg != null) ...[
              const SizedBox(width: 6),
              Text(
                '${chg >= 0 ? '▲' : '▼'} ${chg.abs().toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: chg >= 0 ? AppBanner.up : AppBanner.down,
                ),
              ),
            ],
            sep(),
          ],
          if (exposure != null) ...[
            const Text('長期 ', style: label),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: exposureColor(exposure.level), borderRadius: BorderRadius.circular(4)),
              child: Text(
                exposure.label,
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            sep(),
          ] else if (today?.score != null) ...[
            const Text('市場分數 ', style: label),
            Text(
              today!.score!.toStringAsFixed(0),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: regimeColor(today.regime), borderRadius: BorderRadius.circular(4)),
              child: Text(
                today.regime?.label ?? '—',
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            sep(),
          ],
          if (store.latestDate != null) ...[
            const Text('資料 ', style: label),
            Text('${store.latestDate} 收盤', style: const TextStyle(fontSize: 13, color: Colors.white)),
            sep(),
          ],
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(statusText, style: TextStyle(fontSize: 12, color: statusColor)),
        ],
      ),
    );
  }
}

/// 字體大小：A− ／目前倍率（點一下回到自動）／A＋。
class _FontControl extends StatelessWidget {
  final HistoryStore store;
  final double width;
  const _FontControl({required this.store, required this.width});

  @override
  Widget build(BuildContext context) {
    final cur = store.fontScale ?? autoFontScale(width);
    double? step(int dir) {
      final i = kFontScales.indexWhere((s) => (s - cur).abs() < 0.01);
      final idx = i < 0 ? kFontScales.indexWhere((s) => s > cur) - (dir > 0 ? 0 : 1) : i + dir;
      if (idx < 0 || idx >= kFontScales.length) return null;
      return kFontScales[idx];
    }

    Widget btn(String t, double? v, {double size = 13}) => InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: v == null ? null : () => store.setFontScale(v),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          t,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: v == null ? Colors.white30 : Colors.white,
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn('A−', step(-1), size: 12),
          InkWell(
            onTap: store.fontScale == null ? null : () => store.setFontScale(null),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${(cur * 100).round()}%${store.fontScale == null ? ' 自動' : ''}',
                style: const TextStyle(fontSize: 11, color: AppBanner.muted),
              ),
            ),
          ),
          btn('A＋', step(1), size: 15),
        ],
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final HistoryStore store;
  const _ThemeToggle({required this.store});

  @override
  Widget build(BuildContext context) {
    final (icon, next, text) = switch (store.themeMode) {
      ThemeMode.system => (Icons.brightness_auto, ThemeMode.light, '跟系統'),
      ThemeMode.light => (Icons.light_mode, ThemeMode.dark, '淺色'),
      ThemeMode.dark => (Icons.dark_mode, ThemeMode.system, '深色'),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => store.setThemeMode(next),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(fontSize: 11, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// 標誌：圓角方塊裡三根 K 棒。
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF14A39A), Color(0xFF0E6B6B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppBanner.gold, width: 1),
    ),
    child: CustomPaint(painter: _CandlePainter()),
  );
}

class _CandlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void candle(double x, double top, double bottom, double wickTop, double wickBottom, Color c) {
      final p = Paint()
        ..color = c
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(x, h * wickTop), Offset(x, h * wickBottom), p);
      canvas.drawRect(Rect.fromLTRB(x - w * .08, h * top, x + w * .08, h * bottom), p);
    }

    candle(w * .28, .55, .78, .45, .86, Colors.white);
    candle(w * .5, .38, .66, .28, .74, AppBanner.gold);
    candle(w * .72, .2, .5, .12, .58, Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
