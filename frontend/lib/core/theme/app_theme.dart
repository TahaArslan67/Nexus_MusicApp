import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Spotify-inspired dark theme for Nexus
class NexusTheme {
  // ── Color Palette ──────────────────────────────────────────────────────────
  static const Color primaryGreen = Color(0xFF1DB954);
  static const Color primaryGreenDark = Color(0xFF169C46);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceCard = Color(0xFF1E1E1E);
  static const Color surfaceElevated = Color(0xFF282828);
  static const Color surfaceHover = Color(0xFF333333);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textTertiary = Color(0xFF727272);
  static const Color errorRed = Color(0xFFE55C5C);
  static const Color accentBlue = Color(0xFF4A90D9);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surfaceDark,
      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        secondary: primaryGreenDark,
        surface: surfaceDark,
        error: errorRed,
        onPrimary: Colors.black,
        onSurface: textPrimary,
      ),

      // ── Typography ────────────────────────────────────────────────────────
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 28, fontWeight: FontWeight.w700, color: textPrimary,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary,
        ),
        headlineLarge: GoogleFonts.inter(
          fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w400, color: textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, color: textSecondary,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary,
          letterSpacing: 0.5,
        ),
      ),

      // ── Cards ────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // ── Bottom Navigation ─────────────────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1A1A1A),
        selectedItemColor: primaryGreen,
        unselectedItemColor: textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // ── Input Fields ──────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        hintStyle: const TextStyle(color: textTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),

      // ── Elevated Button ───────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Slider (for player) ──────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryGreen,
        inactiveTrackColor: surfaceHover,
        thumbColor: primaryGreen,
        overlayColor: primaryGreen.withOpacity(0.12),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),

      // ── Divider ──────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: surfaceElevated,
        thickness: 1,
        space: 0,
      ),
    );
  }
}