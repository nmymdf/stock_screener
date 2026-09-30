/// 色彩和主題，跟畫面草稿一致：主色是深青綠、台股習慣紅漲綠跌。
library;

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

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 6)),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

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
