import 'package:flutter/material.dart';

const _kEnglishFont = 'Poppins';
const _kArabicFont = 'NotoSansArabic';

TextTheme buildMwTextTheme({required bool isArabic}) {
  final base = ThemeData.dark().textTheme;
  final fontFamily = isArabic ? _kArabicFont : _kEnglishFont;

  // For Arabic, avoid big positive letterSpacing – keep it neutral/tight.
  double ls(double value) => isArabic ? 0.0 : value;

  return base.copyWith(
    // Big hero headings (e.g., onboarding title, main brand headers)
    displayLarge: base.displayLarge?.copyWith(
      fontFamily: fontFamily,
      fontSize: 40,
      fontWeight: FontWeight.w700,
      height: 1.18,
      letterSpacing: ls(0.2),
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontFamily: fontFamily,
      fontSize: 34,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: ls(0.15),
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontFamily: fontFamily,
      fontSize: 30,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: ls(0.1),
    ),

    // Section titles / screen titles (e.g., "Profile", "Friends", "Settings")
    headlineLarge: base.headlineLarge?.copyWith(
      fontFamily: fontFamily,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: ls(0.1),
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontFamily: fontFamily,
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: ls(0.05),
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontFamily: fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: ls(0.0),
    ),

    // AppBar titles / section subtitles
    titleLarge: base.titleLarge?.copyWith(
      fontFamily: fontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: ls(0.0),
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontFamily: fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.35,
      letterSpacing: ls(0.05),
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontFamily: fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.35,
      letterSpacing: ls(0.05),
    ),

    // Main body text (chat bubbles, descriptions, settings text)
    bodyLarge: base.bodyLarge?.copyWith(
      fontFamily: fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.45,
      letterSpacing: ls(0.05),
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontFamily: fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
      letterSpacing: ls(0.03),
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontFamily: fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
      letterSpacing: ls(0.02),
    ),

    // Buttons, chips, small labels
    labelLarge: base.labelLarge?.copyWith(
      fontFamily: fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: ls(0.1),
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontFamily: fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.3,
      letterSpacing: ls(0.05),
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontFamily: fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.2,
      letterSpacing: ls(0.03),
    ),
  );
}
