import 'package:flutter/material.dart';

/// ✅ DEFAULTS (Back to the original look like your screenshot)
const _kEnglishFont = 'Poppins';
const _kArabicFont = 'NotoSansArabic';

bool _isArabicFamily(String family) {
  final f = family.trim();
  return f == 'Noto Sans Arabic' ||
      f == 'NotoSansArabic' || // backward compatibility
      f == 'Cairo' ||
      f == 'Tajawal' ||
      f == 'Almarai' ||
      f == 'Reem Kufi' ||
      f == 'Amiri';
}

String resolveMwFontFamily({
  required bool isArabic,
  String? override,
}) {
  final o = (override ?? '').trim();
  if (o.isNotEmpty) return o;
  return isArabic ? _kArabicFont : _kEnglishFont;
}

TextTheme buildMwTextTheme({
  required bool isArabic,
  double fontScale = 1.0,
  String? fontFamilyOverride,
}) {
  final base = ThemeData.dark().textTheme;

  final resolvedFamily = resolveMwFontFamily(
    isArabic: isArabic,
    override: fontFamilyOverride,
  );

  final bool familyIsArabic = _isArabicFamily(resolvedFamily);

  // ✅ Letter spacing:
  // - Arabic locale should not use positive letterSpacing
  // - Also: Arabic font selected while locale is English → still avoid spacing
  double ls(double value) => (isArabic || familyIsArabic) ? 0.0 : value;

  // ✅ Arabic fonts typically need slightly more line height
  double h(double value) => familyIsArabic ? (value + 0.06) : value;

  // Scale helper
  double s(double v) => (v * fontScale).clamp(11.0, 72.0);

  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(40),
      fontWeight: FontWeight.w700,
      height: h(1.18),
      letterSpacing: ls(0.2),
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(34),
      fontWeight: FontWeight.w700,
      height: h(1.2),
      letterSpacing: ls(0.15),
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(30),
      fontWeight: FontWeight.w600,
      height: h(1.2),
      letterSpacing: ls(0.1),
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(26),
      fontWeight: FontWeight.w700,
      height: h(1.25),
      letterSpacing: ls(0.1),
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(22),
      fontWeight: FontWeight.w600,
      height: h(1.25),
      letterSpacing: ls(0.05),
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(20),
      fontWeight: FontWeight.w600,
      height: h(1.25),
      letterSpacing: ls(0.0),
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(18),
      fontWeight: FontWeight.w600,
      height: h(1.3),
      letterSpacing: ls(0.0),
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(16),
      fontWeight: FontWeight.w500,
      height: h(1.35),
      letterSpacing: ls(0.05),
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(14),
      fontWeight: FontWeight.w500,
      height: h(1.35),
      letterSpacing: ls(0.05),
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(16),
      fontWeight: FontWeight.w400,
      height: h(1.45),
      letterSpacing: ls(0.05),
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(14),
      fontWeight: FontWeight.w400,
      height: h(1.45),
      letterSpacing: ls(0.03),
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(12),
      fontWeight: FontWeight.w400,
      height: h(1.4),
      letterSpacing: ls(0.02),
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(13),
      fontWeight: FontWeight.w600,
      height: h(1.3),
      letterSpacing: ls(0.1),
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(12),
      fontWeight: FontWeight.w500,
      height: h(1.3),
      letterSpacing: ls(0.05),
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontFamily: resolvedFamily,
      fontSize: s(11),
      fontWeight: FontWeight.w500,
      height: h(1.2),
      letterSpacing: ls(0.03),
    ),
  );
}
