import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color bgTop = Color(0xFFF9F8FF);
  static const Color bgBottom = Color(0xFFEFEDFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF3F1FC);
  static const Color accent = Color(0xFF6C4CF1);
  static const Color accentAlt = Color(0xFF0EA5A3);
  static const Color like = Color(0xFF16A34A);
  static const Color reject = Color(0xFFE11D48);
  static const Color textPrimary = Color(0xFF15162B);
  static const Color textSecondary = Color(0xFF6E7191);
  static const Color border = Color(0xFFE6E2F7);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, Color(0xFF9478FF)],
  );

  static const LinearGradient likeGradient = LinearGradient(
    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
  );

  static const LinearGradient rejectGradient = LinearGradient(
    colors: [Color(0xFFFB7185), Color(0xFFE11D48)],
  );

  /// Soft, modern elevation for light-theme cards/tiles -- a two-layer
  /// shadow (a tight dark layer + a wider accent-tinted layer) instead of
  /// the single hard shadow a plain `BoxShadow` tends to look like.
  static List<BoxShadow> cardShadow({double opacity = 1}) => [
        BoxShadow(color: const Color(0xFF15162B).withValues(alpha: 0.05 * opacity), blurRadius: 10, offset: const Offset(0, 2)),
        BoxShadow(color: accent.withValues(alpha: 0.05 * opacity), blurRadius: 20, offset: const Offset(0, 8)),
      ];
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgTop,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.light,
        primary: AppColors.accent,
        secondary: AppColors.accentAlt,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: AppColors.textPrimary,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
