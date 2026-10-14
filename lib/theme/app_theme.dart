import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Backgrounds
  static const Color bgTop = Color(0xFFF5F5FA);
  static const Color bgBottom = Color(0xFFF5F5FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFEBEBF0);
  static const Color glowPink = Color(0xFFFBE3EA);
  static const Color glowViolet = Color(0xFFE6E0FF);

  // Brand
  static const Color accent = Color(0xFF6D4AFF); // violet
  static const Color accentAlt = Color(0xFFEC3D64); // pink
  static const Color accentDark = Color(0xFFD42A52); // pink pressed

  // Semantic
  static const Color like = Color(0xFF059669); // success / shortlist
  static const Color likeText = Color(0xFF047857);
  static const Color reject = Color(0xFFEC3D64); // danger / pass
  static const Color info = Color(0xFF0284C7); // verified / contacted
  static const Color infoText = Color(0xFF0369A1);
  static const Color warning = Color(0xFFB45309); // interview / undo

  // Text
  static const Color textPrimary = Color(0xFF15151F);
  static const Color textSecondary = Color(0x8C15151F); // 55%
  static const Color textTertiary = Color(0x6615151F); // 40%
  static const Color border = Color(0x1A15151F); // 10%

  // Legacy alias (same opacity/value as textSecondary)
  static const Color textHint = textTertiary;

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
  );

  /// The one signature brand gradient: pink -> violet.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentAlt, accent],
  );

  static const LinearGradient likeGradient = LinearGradient(
    colors: [Color(0xFF10B981), like],
  );

  static const LinearGradient rejectGradient = LinearGradient(
    colors: [Color(0xFFFF6090), reject],
  );

  /// Soft, modern elevation for light-theme cards/tiles -- a two-layer
  /// shadow (a tight dark layer + a wider brand-tinted layer) instead of
  /// the single hard shadow a plain `BoxShadow` tends to look like.
  static List<BoxShadow> cardShadow({double opacity = 1}) => [
        BoxShadow(color: textPrimary.withValues(alpha: 0.05 * opacity), blurRadius: 10, offset: const Offset(0, 2)),
        BoxShadow(color: accentAlt.withValues(alpha: 0.05 * opacity), blurRadius: 20, offset: const Offset(0, 8)),
      ];
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgTop,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.light,
        primary: AppColors.accentAlt,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: AppColors.textPrimary,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      splashFactory: InkRipple.splashFactory,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentAlt,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentAlt,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        hintStyle: TextStyle(color: AppColors.textTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accentAlt.withValues(alpha: 0.6), width: 1.5),
        ),
      ),
    );
  }
}
