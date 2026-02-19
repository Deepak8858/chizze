import 'package:flutter/material.dart';

/// Chizze brand color palette — Dark theme with orange accents
class AppColors {
  AppColors._();

  // ─── Primary Brand ───
  static const Color primary = Color(0xFFF49D25);
  static const Color primaryDark = Color(0xFFE8751A);
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  // ─── Background (Dark Theme) ───
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceElevated = Color(0xFF252525);
  static const Color surfaceGlass = Color(0x0FFFFFFF); // 6% white

  // ─── Text ───
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA0A0A0);
  static const Color textTertiary = Color(0xFF666666);

  // ─── Semantic ───
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFFACC15);
  static const Color info = Color(0xFF3B82F6);
  static const Color ratingStar = Color(0xFFFBBF24);

  // ─── Food Indicators ───
  static const Color veg = Color(0xFF22C55E);
  static const Color nonVeg = Color(0xFFEF4444);

  // ─── Glass Effect ───
  static const Color glassBorder = Color(0x1AFFFFFF); // 10% white
  static const Color glassBackground = Color(0x0FFFFFFF); // 6% white

  // ─── Misc ───
  static const Color divider = Color(0xFF2A2A2A);
  static const Color shimmerBase = Color(0xFF1A1A1A);
  static const Color shimmerHighlight = Color(0xFF2A2A2A);
  static const Color overlay = Color(0x80000000); // 50% black
  static const Color scrim = Color(0xCC000000); // 80% black
}
