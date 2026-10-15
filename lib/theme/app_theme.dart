import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The one place colours live. Deep green + white, flat and professional --
/// no pink/violet, no cartoon art. Member names are historical (the app used
/// to be pink/violet), so `accentAlt` is the PRIMARY brand green and
/// `accent` its lighter companion.
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color bgTop = Color(0xFFF0F0EE);
  static const Color bgBottom = Color(0xFFF0F0EE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFE7E9E6);
  static const Color glowPink = Color(0xFFE3EEE9); // legacy name, soft green
  static const Color glowViolet = Color(0xFFD7E6DF); // legacy name, soft green

  // Brand
  static const Color primary = Color(0xFF1F4D42); // deep green
  static const Color accent = Color(0xFF2E6B5B); // lighter green
  static const Color accentAlt = primary; // primary actions / highlights
  static const Color accentDark = Color(0xFF173B33); // pressed

  // Semantic
  static const Color like = Color(0xFF059669); // success / shortlist
  static const Color likeText = Color(0xFF047857);
  static const Color reject = Color(0xFFDC2626); // danger / pass
  static const Color info = Color(0xFF0284C7); // verified / contacted
  static const Color infoText = Color(0xFF0369A1);
  static const Color warning = Color(0xFFB45309); // interview / undo

  // Text
  static const Color textPrimary = Color(0xFF14201C);
  static const Color textSecondary = Color(0x9914201C); // 60%
  static const Color textTertiary = Color(0x6614201C); // 40%
  static const Color border = Color(0x1F14201C); // 12%

  // Legacy alias (same opacity/value as textSecondary)
  static const Color textHint = textTertiary;

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
  );

  /// The signature brand gradient: two greens, very subtle.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accent],
  );

  static const LinearGradient likeGradient = LinearGradient(
    colors: [Color(0xFF10B981), like],
  );

  static const LinearGradient rejectGradient = LinearGradient(
    colors: [Color(0xFFEF4444), reject],
  );

  /// Soft elevation for cards/tiles: one tight layer and one wider layer.
  static List<BoxShadow> cardShadow({double opacity = 1}) => [
        BoxShadow(color: textPrimary.withValues(alpha: 0.05 * opacity), blurRadius: 10, offset: const Offset(0, 2)),
        BoxShadow(color: primary.withValues(alpha: 0.05 * opacity), blurRadius: 20, offset: const Offset(0, 8)),
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
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.reject,
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
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceAlt,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
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
          foregroundColor: AppColors.primary,
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
        fillColor: AppColors.surface,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.reject),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.reject, width: 1.5),
        ),
      ),
    );
  }
}
