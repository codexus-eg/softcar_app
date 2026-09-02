import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Application-wide theming. Provides polished light + dark themes,
/// typography scale and component styling used across the whole app.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.light,
        primary: AppColors.ink,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      brightness: Brightness.light,
    );

    return _build(base, dark: false);
  }

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.dark,
        primary: AppColors.accent,
        surface: AppColors.surfaceDark,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.surfaceDark,
      brightness: Brightness.dark,
    );

    return _build(base, dark: true);
  }

  static ThemeData _build(ThemeData base, {required bool dark}) {
    final bg = dark ? AppColors.surfaceDark : AppColors.surface;
    final divider = dark ? AppColors.dividerDark : AppColors.divider;
    final textPrimary =
        dark ? AppColors.textOnDark : AppColors.textPrimary;
    final textSecondary =
        dark ? AppColors.textTertiary : AppColors.textSecondary;

    return base.copyWith(
      textTheme: _textTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      dividerColor: divider,
      dividerTheme: DividerThemeData(color: divider, thickness: 1),
      splashColor: AppColors.ink.withValues(alpha: 0.04),
      highlightColor: AppColors.ink.withValues(alpha: 0.03),
      canvasColor: bg,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        modalBackgroundColor: bg,
        showDragHandle: false,
      ),
      cardTheme: CardThemeData(
        color: dark ? AppColors.surfaceDarkElevated : AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: divider),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: divider),
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.surfaceDarkElevated : AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? AppColors.surfaceDarkElevated : AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: AppColors.ink,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -1.2,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.35),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.4),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.35,
        color: AppColors.textSecondary,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
