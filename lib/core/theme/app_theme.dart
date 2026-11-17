import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

abstract final class AppFonts {
  /// Heavy retro serif for titles.
  static const display = 'AbrilFatface';

  /// Typewriter face for body text and labels.
  static const body = 'SpecialElite';
}

abstract final class AppTheme {
  /// The theme for the version of [AppColors] in use now (day or night).
  static ThemeData get current {
    final night = AppColors.night;
    final paper = AppColors.paper;
    final card = AppColors.card;
    final ink = AppColors.ink;
    final border = BorderSide(color: ink, width: 2);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.terracotta,
          brightness: night ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: AppColors.terracotta,
          onPrimary: AppColors.onDark,
          secondary: AppColors.mustard,
          onSecondary: AppColors.onLight,
          tertiary: AppColors.teal,
          onTertiary: AppColors.onDark,
          surface: paper,
          onSurface: ink,
          surfaceContainerHighest: AppColors.paperDark,
          outline: ink,
        );

    final base = ThemeData(colorScheme: scheme, fontFamily: AppFonts.body);
    final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);

    TextStyle display(TextStyle? style, double size) =>
        (style ?? const TextStyle()).copyWith(
          fontFamily: AppFonts.display,
          fontSize: size,
          fontWeight: FontWeight.w400,
        );

    // The bars are drawn in the paper color right up to the screen edges,
    // so the system bars are see-through and only their icons change.
    final icons = night ? Brightness.light : Brightness.dark;
    final systemBars = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: night ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: paper,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    return base.copyWith(
      scaffoldBackgroundColor: paper,
      textTheme: text.copyWith(
        headlineSmall: display(text.headlineSmall, 26),
        titleLarge: display(text.titleLarge, 22),
        titleMedium: display(text.titleMedium, 17),
        titleSmall: display(text.titleSmall, 15),
      ),
      iconTheme: IconThemeData(color: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        systemOverlayStyle: systemBars,
        titleTextStyle: display(text.headlineSmall, 26).copyWith(color: ink),
        shape: Border(bottom: border),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            letterSpacing: 1,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: display(text.titleLarge, 22).copyWith(color: ink),
        contentTextStyle: text.bodyMedium?.copyWith(color: ink),
      ),
      // Set here and not where a sheet is opened: a sheet that is open
      // while the theme changes (the settings sheet) then changes with it.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        modalBackgroundColor: card,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: ink.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          side: border,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontFamily: AppFonts.body, color: paper),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(fontFamily: AppFonts.body, color: ink),
        shape: RoundedRectangleBorder(
          side: border,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
