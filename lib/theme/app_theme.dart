// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

// === MW Chat Enhanced Neon Glass Theme ===

// Core background colors
const kBgColor = Color(0xFF0B0B0B);
const kSurfaceColor = Color(0xFF141414);
const kSurfaceAltColor = Color(0xFF1C1C1C);
const kBorderColor = Color(0xFF2C2C2C);

// Text
const kTextPrimary = Colors.white;
const kTextSecondary = Color(0xFF9CA3AF);

// Brand accents
const kPrimaryBlue = Color(0xFF0066FF);
const kSecondaryAmber = Color(0xFFFFC107);
const kAccentColor = Color(0xFF22C55E);
const kErrorColor = Colors.redAccent;

// Chat bubbles
const kBubbleMeColor = Color(0xFFFFC107);
const kBubbleOtherColor = Color(0xFF1E1E1E);

// === Gradient and Glow ===
final LinearGradient mwGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    kPrimaryBlue.withOpacity(0.9),
    kSecondaryAmber.withOpacity(0.9),
  ],
);

// Reusable glow decoration
BoxDecoration mwGlowDecoration = BoxDecoration(
  gradient: mwGradient,
  boxShadow: [
    BoxShadow(
      color: kSecondaryAmber.withOpacity(0.35),
      blurRadius: 20,
      spreadRadius: 3,
      offset: const Offset(0, 4),
    ),
  ],
  borderRadius: BorderRadius.circular(16),
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
    fontFamily: 'Poppins',
  );

  final textTheme = base.textTheme.copyWith(
    headlineLarge: const TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
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
      fontSize: 15,
      color: kTextPrimary,
      letterSpacing: 0.2,
    ),
    bodySmall: const TextStyle(
      fontSize: 13,
      color: kTextSecondary,
      letterSpacing: 0.2,
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
      backgroundColor: kSurfaceAltColor.withOpacity(0.6),
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
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith<Color>(
              (states) {
            if (states.contains(MaterialState.hovered)) {
              return kPrimaryBlue.withOpacity(0.9);
            }
            if (states.contains(MaterialState.pressed)) {
              return kSecondaryAmber.withOpacity(0.8);
            }
            return kPrimaryBlue;
          },
        ),
        foregroundColor: MaterialStateProperty.all(Colors.white),
        shadowColor:
        MaterialStateProperty.all(kSecondaryAmber.withOpacity(0.3)),
        elevation: MaterialStateProperty.all(4),
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        padding: MaterialStateProperty.all(
          const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
        ),
        textStyle: MaterialStateProperty.all(
          textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
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
      fillColor: kSurfaceAltColor.withOpacity(0.8),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      hintStyle: const TextStyle(color: kTextSecondary),
      labelStyle: const TextStyle(color: kTextSecondary),
      prefixIconColor: kTextSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kBorderColor.withOpacity(0.7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kBorderColor.withOpacity(0.6)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: kPrimaryBlue, width: 1.3),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: kErrorColor, width: 1.2),
      ),
    ),

    // === FLOATING BUTTON ===
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPrimaryBlue,
      foregroundColor: Colors.white,
      elevation: 6,
    ),

    // === SCROLLBAR ===
    scrollbarTheme: ScrollbarThemeData(
      thumbColor:
      MaterialStateProperty.all(kTextSecondary.withOpacity(0.35)),
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
