import 'package:flutter/material.dart';

// === MW Unified Theme System ===

// Core colors (Glassmorphic base)
const kBgColor = Color(0xFF050505);
const kSurfaceColor = Color(0xFF111111);
const kSurfaceAltColor = Color(0xFF181818);
const kBorderColor = Color(0xFF2A2A2A);

const kTextPrimary = Colors.white;
const kTextSecondary = Color(0xFF9CA3AF);

// === MW Gradient Brand Accents ===
const kPrimaryBlue = Color(0xFF0057FF);
const kSecondaryAmber = Color(0xFFFFB300);
const kGradientStart = Color(0xCC0057FF);
const kGradientEnd = Color(0xCCFFB300);
const kGlassSurface = Color(0x73000000);

// Chat bubbles
const kBubbleMeColor = Colors.white;
const kBubbleOtherColor = Color(0xFF1E1E1E);

// === Accent Elements ===
const kAccentColor = Color(0xFF22C55E);
const kErrorColor = Colors.redAccent;

final LinearGradient mwGradient = const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kGradientStart, kGradientEnd],
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
      error: Colors.redAccent,
    ),
  );

  final textTheme = base.textTheme.copyWith(
    headlineLarge: const TextStyle(
      fontSize: 28,
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
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: kTextPrimary,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: const IconThemeData(color: kTextPrimary),
    ),

    // === MW Glassmorphic Buttons ===
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 10,
        shadowColor: Colors.black.withOpacity(0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
        textStyle: textTheme.labelLarge,
      ),
    ),

    // === MW Secondary Buttons ===
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white70,
        textStyle: textTheme.bodyMedium?.copyWith(
          decoration: TextDecoration.underline,
        ),
      ),
    ),

    // === MW Input Field Styling ===
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(0.1),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      hintStyle: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIconColor: Colors.white70,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: kPrimaryBlue, width: 1.4),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    ),

    // === MW Floating Button ===
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 8,
    ),

    // === Cards / Containers ===
    cardTheme: const CardThemeData(
      color: kGlassSurface,
      elevation: 10,
      margin: EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
        side: BorderSide(color: Colors.white12),
      ),
      shadowColor: Colors.black54,
    ),



  // === Scrollbar ===
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: MaterialStateProperty.all(
        Colors.white.withOpacity(0.2),
      ),
      radius: const Radius.circular(12),
      thickness: MaterialStateProperty.all(4),
    ),
  );
}
