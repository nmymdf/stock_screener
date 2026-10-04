/// 色彩和主題，跟畫面草稿一致：主色是深青綠、台股習慣紅漲綠跌。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class AppColors {
  static const accent = Color(0xFF0E6B6B);
  static const accentDark = Color(0xFF43B3A9);
  static const up = Color(0xFFCF3528); // 漲：紅
  static const upDark = Color(0xFFFF6D60);
  static const down = Color(0xFF17824A); // 跌：綠
  static const downDark = Color(0xFF4CC47F);
}

/// 漲跌顏色：n > 0 用紅色（漲），n < 0 用綠色（跌），跟台股習慣一致。
Color changeColor(BuildContext context, num n) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (n > 0.004) return dark ? AppColors.upDark : AppColors.up;
  if (n < -0.004) return dark ? AppColors.downDark : AppColors.down;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

/// 專業看盤軟體風格：淺色是冷灰底＋白卡片，深色是深藍黑底＋藍灰卡片；
/// 數字一律用等寬數字（tabular figures），表格上下對齊。
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: brightness).copyWith(
    surface: dark ? const Color(0xFF141E29) : Colors.white,
    surfaceContainerLowest: dark ? const Color(0xFF0D141C) : const Color(0xFFF2F4F7),
    surfaceContainerLow: dark ? const Color(0xFF17222E) : const Color(0xFFF7F8FA),
    outlineVariant: dark ? const Color(0xFF263545) : const Color(0xFFE1E5EB),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  TextStyle? tab(TextStyle? s) => s?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  final tt = base.textTheme;
  final text = tt.copyWith(
    bodyLarge: tab(tt.bodyLarge),
    bodyMedium: tab(tt.bodyMedium),
    bodySmall: tab(tt.bodySmall),
    titleLarge: tab(tt.titleLarge)?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: tab(tt.titleMedium)?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: tab(tt.titleSmall),
    labelLarge: tab(tt.labelLarge),
    labelMedium: tab(tt.labelMedium),
    labelSmall: tab(tt.labelSmall),
  );
  final ft = _withFont(text);
  return base.copyWith(
    textTheme: ft,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: ft.titleLarge!.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 6)),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: ft.labelLarge!.copyWith(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
      unselectedLabelTextStyle: ft.labelLarge!.copyWith(color: scheme.onSurfaceVariant, fontSize: 13),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      height: 64,
      labelTextStyle: WidgetStatePropertyAll(ft.labelMedium!),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

/// Windows 上明確指定正黑體，避免 Flutter 拿簡體字型（微軟雅黑）畫繁體中文。
String? get _fontFamily => !kIsWeb && Platform.isWindows ? 'Microsoft JhengHei UI' : null;
List<String>? get _fontFallback =>
    !kIsWeb && Platform.isWindows ? const ['Microsoft JhengHei', 'Segoe UI', 'Arial'] : null;

TextTheme _withFont(TextTheme t) =>
    _fontFamily == null ? t : t.apply(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback);

/// 分數的顏色：用主色的深淺表示強弱，不用紅綠（避免跟漲跌色混淆）。
Color scoreColor(BuildContext context, double? score) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (score == null) return Theme.of(context).colorScheme.outline;
  if (score >= 75) return dark ? const Color(0xFF4FD1C5) : const Color(0xFF0B7A6F);
  if (score >= 60) return dark ? const Color(0xFF7FB7E8) : const Color(0xFF2F6FA8);
  if (score >= 45) return dark ? const Color(0xFFE8C170) : const Color(0xFFB7860B);
  return dark ? const Color(0xFFA0A0A0) : const Color(0xFF7A7A7A);
}

/// 策略 A/B/C/D 的標籤顏色。
Color strategyColor(String code) => switch (code) {
  'A' => const Color(0xFF3F51B5),
  'B' => const Color(0xFF00897B),
  'C' => const Color(0xFF8E24AA),
  _ => const Color(0xFF8D6E63),
};
