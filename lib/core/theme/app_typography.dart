import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Chizze typography — Plus Jakarta Sans throughout
class AppTypography {
  AppTypography._();

  static String get _fontFamily => 'PlusJakartaSans';

  // ─── Headings ───
  static TextStyle get h1 => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w800,
    fontSize: 28,
    height: 1.2,
    letterSpacing: -0.5,
    color: Colors.white,
  );

  static TextStyle get h2 => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    height: 1.3,
    letterSpacing: -0.3,
    color: Colors.white,
  );

  static TextStyle get h3 => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w600,
    fontSize: 18,
    height: 1.3,
    color: Colors.white,
  );

  // ─── Body ───
  static TextStyle get body1 => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 1.5,
    color: Colors.white,
  );

  static TextStyle get body2 => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.5,
    color: const Color(0xFFA0A0A0),
  );

  // ─── Caption & Labels ───
  static TextStyle get caption => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.4,
    color: const Color(0xFFA0A0A0),
  );

  static TextStyle get overline => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w600,
    fontSize: 10,
    height: 1.4,
    letterSpacing: 1.2,
    color: const Color(0xFF666666),
  );

  // ─── Buttons & Actions ───
  static TextStyle get button => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    height: 1.0,
    letterSpacing: 0.3,
    color: Colors.white,
  );

  static TextStyle get buttonSmall => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.0,
    letterSpacing: 0.3,
    color: Colors.white,
  );

  // ─── Special ───
  static TextStyle get price => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    height: 1.2,
    color: Colors.white,
  );

  static TextStyle get priceLarge => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w800,
    fontSize: 24,
    height: 1.2,
    color: Colors.white,
  );

  static TextStyle get badge => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    height: 1.0,
    color: Colors.white,
  );

  /// Get Google Fonts fallback text theme for the full app
  static TextTheme get textTheme => GoogleFonts.plusJakartaSansTextTheme(
    const TextTheme(
      displayLarge: TextStyle(color: Colors.white),
      displayMedium: TextStyle(color: Colors.white),
      displaySmall: TextStyle(color: Colors.white),
      headlineLarge: TextStyle(color: Colors.white),
      headlineMedium: TextStyle(color: Colors.white),
      headlineSmall: TextStyle(color: Colors.white),
      titleLarge: TextStyle(color: Colors.white),
      titleMedium: TextStyle(color: Colors.white),
      titleSmall: TextStyle(color: Colors.white),
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Color(0xFFA0A0A0)),
      bodySmall: TextStyle(color: Color(0xFF666666)),
      labelLarge: TextStyle(color: Colors.white),
      labelMedium: TextStyle(color: Color(0xFFA0A0A0)),
      labelSmall: TextStyle(color: Color(0xFF666666)),
    ),
  );
}
