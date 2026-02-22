import 'package:flutter/material.dart';

/// Chizze brand color palette — supports Dark + Light themes
class AppColors {
  AppColors._();

  // ─── Primary Brand (shared) ───
  static const Color primary = Color(0xFFF49D25);
  static const Color primaryDark = Color(0xFFE8751A);
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  // ─── Semantic (shared) ───
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFFACC15);
  static const Color info = Color(0xFF3B82F6);
  static const Color ratingStar = Color(0xFFFBBF24);
  static const Color gold = Color(0xFFFFD700);

  // ─── Food Indicators (shared) ───
  static const Color veg = Color(0xFF22C55E);
  static const Color nonVeg = Color(0xFFEF4444);

  // ════════════════════════════════════════
  // DARK THEME COLORS
  // ════════════════════════════════════════
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceElevated = Color(0xFF252525);
  static const Color surfaceGlass = Color(0x0FFFFFFF); // 6% white
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA0A0A0);
  static const Color textTertiary = Color(0xFF666666);
  static const Color glassBorder = Color(0x1AFFFFFF); // 10% white
  static const Color glassBackground = Color(0x0FFFFFFF); // 6% white
  static const Color divider = Color(0xFF2A2A2A);
  static const Color shimmerBase = Color(0xFF1A1A1A);
  static const Color shimmerHighlight = Color(0xFF2A2A2A);
  static const Color overlay = Color(0x80000000); // 50% black
  static const Color scrim = Color(0xCC000000); // 80% black

  // ════════════════════════════════════════
  // LIGHT THEME COLORS
  // ════════════════════════════════════════
  static const Color lightBackground = Color(0xFFF8F8F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF0F0F0);
  static const Color lightSurfaceGlass = Color(0x0F000000); // 6% black
  static const Color lightTextPrimary = Color(0xFF1A1A1A);
  static const Color lightTextSecondary = Color(0xFF666666);
  static const Color lightTextTertiary = Color(0xFFA0A0A0);
  static const Color lightGlassBorder = Color(0x1A000000); // 10% black
  static const Color lightGlassBackground = Color(0x0F000000); // 6% black
  static const Color lightDivider = Color(0xFFE0E0E0);
  static const Color lightShimmerBase = Color(0xFFE8E8E8);
  static const Color lightShimmerHighlight = Color(0xFFF5F5F5);
  static const Color lightOverlay = Color(0x40000000); // 25% black
  static const Color lightScrim = Color(0x80000000); // 50% black
}
