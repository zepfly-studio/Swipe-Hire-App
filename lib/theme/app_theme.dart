import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// THE ONE PLACE COLOURS LIVE.
//
// Look & feel (per the client brief, docs/SWIPE_HIRE_APP_SPEC.md "How to use
// this document" item 6): professional, flat and calm like LinkedIn / Naukri /
// Indeed. Deep green #1F4D42 on off-white #F0F0EE with white cards, line icons
// and no cartoon art. Font: Plus Jakarta Sans.
//
// To retheme the app change values in [AppColors] only. Widgets must not
// hard-code colours; they read them from here (or from Theme.of(context)).
//
// HOW A DARK PALETTE COULD BE ADDED LATER
//   1. Today every widget reads the static constants on [AppColors], so there
//      is exactly one (light) palette. To support dark mode, turn those
//      constants into a small immutable palette class, e.g.
//      `class AppPalette { final Color bg, surface, primary, ...; }`, with a
//      `light` and a `dark` instance (dark suggestion: bg #0F1714, surface
//      #17211D, primary #5FB39B on dark, text #E8EFEC, danger #FB7185 per the
//      spec's dark danger).
//   2. Expose it through a `ThemeExtension<AppPalette>` and add
//      `AppTheme.darkTheme` built by the same `_build(palette)` helper used for
//      `lightTheme`; wire `darkTheme:` + `themeMode:` in main.dart.
//   3. Replace `AppColors.x` reads with `context.palette.x` (a one-line
//      extension on BuildContext), screen by screen; the semantic names in
//      this file already describe roles (surface, border, textSecondary,
//      statusHired, ...), not hues, so they carry over unchanged.
// =============================================================================

class AppColors {
  AppColors._();

  // ---- Backgrounds & surfaces ----------------------------------------------
  /// App background (off-white).
  static const Color bgTop = Color(0xFFF0F0EE);
  static const Color bgBottom = Color(0xFFF0F0EE);

  /// Cards, sheets, inputs.
  static const Color surface = Color(0xFFFFFFFF);

  /// Chips, disabled tracks, quiet fills.
  static const Color surfaceAlt = Color(0xFFE7E9E6);

  /// Soft green washes (selected rows, highlighted tiles). Legacy member names.
  static const Color glowPink = primarySoft;
  static const Color glowViolet = primaryTint;

  // ---- Brand (deep green family) --------------------------------------------
  static const Color primary = Color(0xFF1F4D42); // deep green
  static const Color accent = Color(0xFF2E6B5B); // lighter green
  static const Color accentAlt = primary; // legacy name: primary actions
  static const Color accentDark = Color(0xFF173B33); // pressed / darkest
  static const Color primaryLight = Color(0xFF6FA593); // on-dark highlights
  static const Color primaryTint = Color(0xFFD7E6DF); // strong tint
  static const Color primarySoft = Color(0xFFE3EEE9); // soft tint
  static const Color onPrimary = Colors.white; // text/icons on filled colour
  static const Color onPrimaryMuted = Color(0xB3FFFFFF); // 70% white
  static const Color onPrimarySubtle = Color(0x4DFFFFFF); // 30% white
  static const Color onPrimaryFaint = Color(0x3DFFFFFF); // 24% white
  static const Color onPrimaryGhost = Color(0x1FFFFFFF); // 12% white

  // ---- Semantic --------------------------------------------------------------
  static const Color like = Color(0xFF059669); // success / shortlist
  static const Color likeText = Color(0xFF047857); // success text on light
  static const Color reject = Color(0xFFDC2626); // danger / pass (spec danger)
  static const Color info = Color(0xFF0284C7); // verified / contacted (sky)
  static const Color infoText = Color(0xFF0369A1);
  static const Color warning = Color(0xFFB45309); // interview / undo (amber)

  // ---- Text -------------------------------------------------------------------
  static const Color textPrimary = Color(0xFF14201C);
  static const Color textSecondary = Color(0x9914201C); // 60%
  static const Color textTertiary = Color(0x6614201C); // 40%
  static const Color border = Color(0x1F14201C); // 12%
  static const Color borderStrong = Color(0x3314201C); // 20%

  /// Legacy alias (same value as textTertiary).
  static const Color textHint = textTertiary;

  // ---- Status tokens (pills, badges, rings) -----------------------------------
  // Pipeline stages (spec B: grey, sky, violet, amber, green, red; "task" uses a
  // muted teal-green from the palette family instead of violet).
  static const Color statusNeutral = Color(0xFF6B7570); // solid grey
  static const Color stageShortlisted = statusNeutral;
  static const Color stageContacted = info;
  static const Color stageTask = Color(0xFF3F7F6D);
  static const Color stageInterview = warning;
  static const Color stageHired = like;
  static const Color stageRejected = reject;

  // Task status pills: Waiting amber / Submitted green / Deadline passed red /
  // Cancelled grey.
  static const Color taskWaiting = warning;
  static const Color taskSubmitted = like;
  static const Color taskOverdue = reject;
  static const Color taskCancelled = statusNeutral;

  // Match badge: >= 75 green, >= 45 amber, otherwise grey.
  static const Color matchHigh = like;
  static const Color matchHighText = likeText;
  static const Color matchMid = warning;
  static const Color matchLow = statusNeutral;

  /// Verified company badge (blue check).
  static const Color verified = info;

  /// Wishlist / "save for later" action.
  static const Color wishlist = info;

  // ---- Media / overlays ---------------------------------------------------------
  /// Backdrop behind videos and full-bleed photos.
  static const Color mediaBg = Color(0xFF101614);

  /// Pure black base for shadows / overlays (always used with an alpha).
  static const Color scrim = Color(0xFF000000);

  /// Black scrims used only to keep white text legible on photos / video.
  static const Color scrimLight = Color(0x61000000); // ~38%
  static const Color scrimMedium = Color(0x73000000); // ~45%
  static const Color scrimStrong = Color(0x8A000000); // ~54%

  /// Recording indicator.
  static const Color recording = reject;

  // ---- Third-party brand colours (must stay as the provider specifies) --------
  /// Google "G" mark blue.
  static const Color googleBlue = Color(0xFF4285F4);

  // ---- Avatar fallbacks -----------------------------------------------------------
  /// Initials avatar fills: tonal greens only.
  static const List<List<Color>> avatarPalettes = [
    [accent, primary],
    [stageTask, primaryLight],
    [like, likeText],
    [primary, accentDark],
    [primaryLight, accent],
  ];

  // ---- Gradients (kept flat: solid clean surfaces) ------------------------------
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
  );

  /// Primary filled surfaces (buttons, own chat bubbles). Flat on purpose.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primary],
  );

  static const LinearGradient likeGradient = LinearGradient(colors: [like, like]);

  static const LinearGradient rejectGradient = LinearGradient(colors: [reject, reject]);

  /// Soft elevation for cards/tiles: a hairline-tight layer and a faint,
  /// wider one. Neutral (no coloured glow).
  static List<BoxShadow> cardShadow({double opacity = 1}) => [
        BoxShadow(color: textPrimary.withValues(alpha: 0.05 * opacity), blurRadius: 8, offset: const Offset(0, 1)),
        BoxShadow(color: textPrimary.withValues(alpha: 0.03 * opacity), blurRadius: 18, offset: const Offset(0, 6)),
      ];
}

/// Font sizes / weights used by the text theme (kept in one place too).
class AppText {
  AppText._();
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}

class AppTheme {
  AppTheme._();

  static const double _radius = 12;

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);

    final sized = base.textTheme.copyWith(
          displayLarge: const TextStyle(fontSize: 36, fontWeight: AppText.bold, height: 1.15),
          displayMedium: const TextStyle(fontSize: 30, fontWeight: AppText.bold, height: 1.2),
          displaySmall: const TextStyle(fontSize: 26, fontWeight: AppText.bold, height: 1.2),
          headlineLarge: const TextStyle(fontSize: 24, fontWeight: AppText.bold, height: 1.25),
          headlineMedium: const TextStyle(fontSize: 22, fontWeight: AppText.bold, height: 1.25),
          headlineSmall: const TextStyle(fontSize: 20, fontWeight: AppText.bold, height: 1.3),
          titleLarge: const TextStyle(fontSize: 18, fontWeight: AppText.bold, height: 1.3),
          titleMedium: const TextStyle(fontSize: 16, fontWeight: AppText.semibold, height: 1.35),
          titleSmall: const TextStyle(fontSize: 14, fontWeight: AppText.semibold, height: 1.35),
          bodyLarge: const TextStyle(fontSize: 16, fontWeight: AppText.regular, height: 1.45),
          bodyMedium: const TextStyle(fontSize: 14, fontWeight: AppText.regular, height: 1.45),
          bodySmall: const TextStyle(fontSize: 12, fontWeight: AppText.regular, height: 1.4),
          labelLarge: const TextStyle(fontSize: 14, fontWeight: AppText.semibold),
          labelMedium: const TextStyle(fontSize: 12, fontWeight: AppText.semibold),
          labelSmall: const TextStyle(fontSize: 11, fontWeight: AppText.medium, letterSpacing: 0.2),
    );
    final themedText = GoogleFonts.plusJakartaSansTextTheme(sized).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radius),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgTop,
      canvasColor: AppColors.surface,
      textTheme: themedText,
      primaryTextTheme: themedText,
      splashFactory: InkRipple.splashFactory,
      dividerColor: AppColors.border,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primarySoft,
        onPrimaryContainer: AppColors.accentDark,
        secondary: AppColors.accent,
        onSecondary: AppColors.onPrimary,
        secondaryContainer: AppColors.primaryTint,
        onSecondaryContainer: AppColors.accentDark,
        tertiary: AppColors.info,
        onTertiary: AppColors.onPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: AppColors.surface,
        surfaceContainerLow: AppColors.surface,
        surfaceContainer: AppColors.surface,
        surfaceContainerHigh: AppColors.surface,
        surfaceContainerHighest: AppColors.surfaceAlt,
        outline: AppColors.borderStrong,
        outlineVariant: AppColors.border,
        error: AppColors.reject,
        onError: AppColors.onPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      primaryIconTheme: const IconThemeData(color: AppColors.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.textPrimary,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actionsIconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: themedText.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: AppColors.textPrimary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primarySoft,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? AppText.bold : AppText.medium,
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.border,
        labelStyle: const TextStyle(fontWeight: AppText.bold, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: AppText.medium, fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: AppColors.onPrimary,
          shape: shape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: AppColors.onPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: shape,
          textStyle: themedText.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.borderStrong),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: shape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.textPrimary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: AppColors.primarySoft,
        disabledColor: AppColors.surfaceAlt,
        checkmarkColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: AppText.semibold, fontSize: 13),
        secondaryLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: AppText.semibold, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: themedText.titleLarge?.copyWith(color: AppColors.textPrimary),
        contentTextStyle: themedText.bodyMedium?.copyWith(color: AppColors.textSecondary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        showDragHandle: false,
        dragHandleColor: AppColors.borderStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: themedText.bodyMedium?.copyWith(color: AppColors.onPrimary),
        actionTextColor: AppColors.primaryLight,
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceAlt,
        circularTrackColor: AppColors.surfaceAlt,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(AppColors.onPrimary),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textTertiary,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceAlt,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.12),
        valueIndicatorColor: AppColors.primary,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: themedText.bodyMedium?.copyWith(color: AppColors.textPrimary),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(color: AppColors.onPrimary, fontSize: 12),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.2),
        selectionHandleColor: AppColors.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: AppColors.primary),
        errorStyle: const TextStyle(color: AppColors.reject),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.reject),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.reject, width: 1.5),
        ),
      ),
    );
  }
}
