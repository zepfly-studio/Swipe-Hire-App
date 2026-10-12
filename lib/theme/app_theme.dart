import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color bgTop = Color(0xFF0B0E17);
  static const Color bgBottom = Color(0xFF141A2B);
  static const Color surface = Color(0xFF1B2133);
  static const Color surfaceAlt = Color(0xFF232B42);
  static const Color accent = Color(0xFF7C5CFF);
  static const Color accentAlt = Color(0xFF3DDAD7);
  static const Color like = Color(0xFF34D399);
  static const Color reject = Color(0xFFFF5C72);
  static const Color textPrimary = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xFFA6ADC3);
  static const Color border = Color(0x33FFFFFF);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, Color(0xFF9D7CFF)],
  );

  static const LinearGradient likeGradient = LinearGradient(
    colors: [Color(0xFF34D399), Color(0xFF22C55E)],
  );

  static const LinearGradient rejectGradient = LinearGradient(
    colors: [Color(0xFFFF5C72), Color(0xFFE11D48)],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgTop,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        secondary: AppColors.accentAlt,
        surface: AppColors.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
