import 'package:flutter/material.dart';

// === MW Optimized Theme (Performance-First) ===

// Core background colors
const kBgColor = Color(0xFF0B0B0B);
const kSurfaceColor = Color(0xFF141414);
const kSurfaceAltColor = Color(0xFF1C1C1C);
const kBorderColor = Color(0xFF2C2C2C);

// Text
const kTextPrimary = Colors.white;
const kTextSecondary = Color(0xFF9CA3AF);

// Brand accents
const kPrimaryBlue = Color(0xFF0057FF);
const kSecondaryAmber = Color(0xFFFFB300);
const kAccentColor = Color(0xFF22C55E);
const kErrorColor = Colors.redAccent;

// Chat bubbles
const kBubbleMeColor = Colors.white;
const kBubbleOtherColor = Color(0xFF1E1E1E);

// Lightweight gradient (used in headers/buttons)
final LinearGradient mwGradient = const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kPrimaryBlue, kSecondaryAmber],
);

// === THEME DATA ===
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBgColor,
    colorScheme: const ColorScheme.dark(
      primary: kPrimaryBlue,
      secondary: kSecondaryAmber,
      surface: kSurfaceColor,
      background: kBgColor,
      error: kErrorColor,
    ),
  );

  final textTheme = base.textTheme.copyWith(
    headlineLarge: const TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: kTextPrimary,
    ),
    headlineSmall: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: kTextPrimary,
    ),
    titleMedium: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: kTextPrimary,
    ),
    bodyMedium: const TextStyle(
      fontSize: 14,
      color: kTextPrimary,
    ),
    bodySmall: const TextStyle(
      fontSize: 12,
      color: kTextSecondary,
    ),
    labelLarge: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
  );

  return base.copyWith(
    textTheme: textTheme,

    // === APP BAR ===
    appBarTheme: AppBarTheme(
      backgroundColor: kSurfaceColor,
      elevation: 0,
      centerTitle: true,
      foregroundColor: kTextPrimary,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: const IconThemeData(color: kTextPrimary),
    ),

    // === BUTTONS ===
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        textStyle: textTheme.labelLarge,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kPrimaryBlue,
        textStyle: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    ),

    // === INPUT FIELDS ===
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceAltColor,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      hintStyle: const TextStyle(color: kTextSecondary),
      labelStyle: const TextStyle(color: kTextSecondary),
      prefixIconColor: kTextSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kBorderColor.withOpacity(0.8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kBorderColor.withOpacity(0.8)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: kPrimaryBlue, width: 1.3),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: kErrorColor, width: 1.2),
      ),
    ),

    // === FLOATING BUTTON ===
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPrimaryBlue,
      foregroundColor: Colors.white,
      elevation: 4,
    ),

    // === SCROLLBAR ===
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: MaterialStateProperty.all(kTextSecondary.withOpacity(0.3)),
      radius: const Radius.circular(10),
      thickness: MaterialStateProperty.all(4),
    ),

    // === ICONS ===
    iconTheme: const IconThemeData(color: Colors.white70, size: 22),

    // === TOOLTIP ===
    tooltipTheme: TooltipThemeData(
      textStyle: textTheme.bodySmall?.copyWith(color: Colors.black),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
    ),

    // === SNACKBAR ===
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kSurfaceAltColor,
      contentTextStyle: textTheme.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
