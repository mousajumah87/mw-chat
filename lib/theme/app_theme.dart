// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'mw_text_theme.dart';

// === MW Chat Enhanced Neon Glass Theme (Warm Gold Edition) ===

// Core background colors
const kBgColor = Color(0xFF0B0B0B);
const kSurfaceColor = Color(0xFF141414);
const kSurfaceAltColor = Color(0xFF1C1C1C);
const kBorderColor = Color(0xFF2C2C2C);

// Text
const kTextPrimary = Colors.white;
const kTextSecondary = Color(0xFF9CA3AF);

// Brand accents (warm gold theme)
const kPrimaryGold = Color(0xFFFFD166);
const kGoldDeep = Color(0xFFFFC107);
const kOffWhite = Color(0xFFF8FAFC);

const kAccentColor = Color(0xFF22C55E);
const kErrorColor = Colors.redAccent;

// Chat bubbles
const kBubbleMeColor = kGoldDeep;
const kBubbleOtherColor = Color(0xFF1E1E1E);

// === Typing Indicator (NEW) ===
const kTypingBg = Color(0xFF121212);
const kTypingBorder = Color(0xFF2C2C2C);
const kTypingGlow = kGoldDeep;

// === Chat Input Bar (NEW shared tokens) ===
const Color kChatInputBarBg = Color(0xFF0B0B0B);
const Color kChatInputBarBorder = Color(0xFF2C2C2C);
const Color kChatInputFieldBg = Color(0xFF141414);

// === Gradient and Glow ===
final LinearGradient mwGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    kPrimaryGold.withOpacity(0.95),
    kGoldDeep.withOpacity(0.85),
  ],
);

BoxDecoration mwGlowDecoration = BoxDecoration(
  gradient: mwGradient,
  boxShadow: [
    BoxShadow(
      color: kGoldDeep.withOpacity(0.28),
      blurRadius: 20,
      spreadRadius: 3,
      offset: const Offset(0, 4),
    ),
  ],
  borderRadius: BorderRadius.circular(16),
);

BoxDecoration mwTypingGlassDecoration({double radius = 18}) {
  return BoxDecoration(
    color: kTypingBg.withOpacity(0.62),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: kTypingBorder.withOpacity(0.65),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: kTypingGlow.withOpacity(0.18),
        blurRadius: 18,
        spreadRadius: 1,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

/// ✅ Apply a Google Font safely by family name.
///
/// IMPORTANT:
/// - We only allow real GoogleFonts families in the app-wide theme.
/// - We map known families to their real GoogleFonts methods.
/// - Unknowns fall back to base.apply(fontFamily: family) (assets/platform fonts).
TextTheme _applyGoogleFontToTheme(TextTheme base, String family) {
  final f = family.trim();
  if (f.isEmpty) return base;

  TextTheme apply(TextTheme Function(TextTheme) fn) {
    try {
      return fn(base);
    } catch (_) {
      return base.apply(fontFamily: f);
    }
  }

  switch (f) {
  // ===== Latin / English =====
    case 'Poppins':
      return apply(GoogleFonts.poppinsTextTheme);
    case 'Inter':
      return apply(GoogleFonts.interTextTheme);
    case 'Roboto':
      return apply(GoogleFonts.robotoTextTheme);

  // ===== Serif / Fancy =====
    case 'DM Serif Display':
      return apply(GoogleFonts.dmSerifDisplayTextTheme);
    case 'Playfair Display':
      return apply(GoogleFonts.playfairDisplayTextTheme);

  // ===== Cool / modern (youth) =====
    case 'Rubik':
      return apply(GoogleFonts.rubikTextTheme);
    case 'Space Grotesk':
      return apply(GoogleFonts.spaceGroteskTextTheme);
    case 'Montserrat':
      return apply(GoogleFonts.montserratTextTheme);
    case 'Nunito':
      return apply(GoogleFonts.nunitoTextTheme);

  // ===== Love / Romantic =====
    case 'Dancing Script':
      return apply(GoogleFonts.dancingScriptTextTheme);

  // ===== Arabic =====
    case 'Cairo':
      return apply(GoogleFonts.cairoTextTheme);
    case 'Reem Kufi':
      return apply(GoogleFonts.reemKufiTextTheme);
    case 'Tajawal':
      return apply(GoogleFonts.tajawalTextTheme);
    case 'Almarai':
      return apply(GoogleFonts.almaraiTextTheme);
    case 'Amiri':
      return apply(GoogleFonts.amiriTextTheme);

  // Backward compatibility (older stored values)
    case 'NotoSansArabic':
    case 'Noto Sans Arabic':
      return apply(GoogleFonts.notoSansArabicTextTheme);

    default:
    // Fallback: If you bundled as assets or the platform has it, it will work.
      return base.apply(fontFamily: f);
  }
}

/// === THEME DATA ===
///
/// ✅ Defaults (from mw_text_theme.dart):
/// - English default: Poppins
/// - Arabic default: Noto Sans Arabic
ThemeData buildAppTheme({
  bool isArabic = false,
  double fontScale = 1.0,
  String? fontFamily,
}) {
  // Resolve the desired family (uses defaults based on locale)
  final resolvedFamily = resolveMwFontFamily(
    isArabic: isArabic,
    override: fontFamily,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBgColor,
    colorScheme: const ColorScheme.dark(
      primary: kPrimaryGold,
      secondary: kGoldDeep,
      surface: kSurfaceColor,
      background: kBgColor,
      error: kErrorColor,
    ),
    // Keep ThemeData.fontFamily set for widgets that rely on it.
    fontFamily: resolvedFamily,
  );

  // MW sizing + Arabic letterSpacing rules
  var textTheme = buildMwTextTheme(
    isArabic: isArabic,
    fontScale: fontScale,
    fontFamilyOverride: resolvedFamily,
  );

  // Ensure actual font is loaded/rendered via google_fonts where possible
  textTheme = _applyGoogleFontToTheme(textTheme, resolvedFamily);

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,

    // === APP BAR ===
    appBarTheme: AppBarTheme(
      backgroundColor: kSurfaceAltColor.withOpacity(0.6),
      elevation: 0,
      centerTitle: true,
      foregroundColor: kTextPrimary,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontSize: (20 * fontScale).clamp(12.0, 28.0),
        fontWeight: FontWeight.w600,
        color: kTextPrimary,
      ),
      iconTheme: const IconThemeData(color: kTextPrimary),
    ),

    // === BUTTONS (Gold / Warm) ===
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.disabled)) {
            return kPrimaryGold.withOpacity(0.35);
          }
          if (states.contains(MaterialState.pressed)) {
            return kGoldDeep.withOpacity(0.95);
          }
          if (states.contains(MaterialState.hovered)) {
            return kPrimaryGold.withOpacity(0.95);
          }
          return kPrimaryGold;
        }),
        foregroundColor: MaterialStateProperty.all(Colors.black),
        shadowColor: MaterialStateProperty.all(kGoldDeep.withOpacity(0.35)),
        elevation: MaterialStateProperty.all(3),
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        padding: MaterialStateProperty.all(
          const EdgeInsets.symmetric(vertical: 14, horizontal: 26),
        ),
        textStyle: MaterialStateProperty.all(
          TextStyle(
            fontSize: (15 * fontScale).clamp(12.0, 22.0),
            fontWeight: FontWeight.w700,
            letterSpacing: isArabic ? 0.0 : 0.4,
            color: Colors.black,
          ),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kPrimaryGold,
        textStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),

    // === INPUT FIELDS ===
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceAltColor.withOpacity(0.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      hintStyle: const TextStyle(color: kTextSecondary),
      labelStyle: const TextStyle(color: kTextSecondary),
      prefixIconColor: kTextSecondary,
      suffixIconColor: kTextSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kBorderColor.withOpacity(0.7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kBorderColor.withOpacity(0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(
          color: kPrimaryGold.withOpacity(0.95),
          width: 1.3,
        ),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: kErrorColor, width: 1.2),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: kErrorColor, width: 1.2),
      ),
    ),

    // === FLOATING BUTTON ===
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kPrimaryGold,
      foregroundColor: Colors.black,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    // === SCROLLBAR ===
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: MaterialStateProperty.all(kTextSecondary.withOpacity(0.35)),
      radius: const Radius.circular(10),
      thickness: MaterialStateProperty.all(4),
    ),

    // === ICONS ===
    iconTheme: const IconThemeData(color: Colors.white70, size: 22),

    // === TOOLTIP ===
    tooltipTheme: TooltipThemeData(
      textStyle: textTheme.bodySmall?.copyWith(color: Colors.black),
      decoration: BoxDecoration(
        color: kOffWhite,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    ),

    // === SNACKBAR ===
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kSurfaceAltColor,
      contentTextStyle: textTheme.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
