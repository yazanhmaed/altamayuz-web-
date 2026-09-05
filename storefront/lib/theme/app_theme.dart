import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFFF6F3EC);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1E1B16);
  static const textSecondary = Color(0xFF6B6459);
  static const accent = Color(0xFF1F3A3D);
  static const accentSoft = Color(0xFFDCE6E5);
  static const danger = Color(0xFFB23A2E);
  static const border = Color(0xFFE4E0D6);
}

class AppTheme {
  static ThemeData get theme {
    final base = ThemeData(useMaterial3: true, fontFamily: 'Tajawal');
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      textTheme: GoogleFonts.tajawalTextTheme(base.textTheme).copyWith(
        headlineSmall: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        titleMedium: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.tajawal(fontSize: 14, color: AppColors.textPrimary),
        bodySmall: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.accent),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
    );
  }
}
