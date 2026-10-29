import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tapat_ai/const/app_color.dart';

class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final d = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
        seedColor: AppColors.blue, brightness: b, secondary: AppColors.purple);
    final rim = d ? Colors.white.withValues(alpha: .16) : Colors.white.withValues(alpha: .85);
    final fieldFill = d ? Colors.white.withValues(alpha: .07) : Colors.white.withValues(alpha: .55);
    final surface = d ? const Color(0xF00B1024) : const Color(0xF7FFFFFF);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // The mesh backdrop lives behind every scaffold, so the scaffold itself
      // must stay transparent for the glass panels to refract it.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      cardColor: Colors.transparent,
      dividerColor: d ? Colors.white.withValues(alpha: .12) : Colors.black.withValues(alpha: .08),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface),
        systemOverlayStyle:
            d ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: .75)),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: rim)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: rim)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: .85), width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: fieldFill,
        selectedColor: scheme.primary.withValues(alpha: .88),
        side: BorderSide(color: rim),
        labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
        titleTextStyle: TextStyle(
            fontSize: 19, fontWeight: FontWeight.w700, color: scheme.onSurface),
        contentTextStyle: TextStyle(fontSize: 14, color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: .45),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        contentTextStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 14,
        shadowColor: Colors.black.withValues(alpha: .25),
        textStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: rim),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        foregroundColor: scheme.primary,
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: fieldFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        contentTextStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: TextStyle(color: scheme.onSurface, fontSize: 15),
        subtitleTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      dividerTheme: DividerThemeData(
        color: d ? Colors.white.withValues(alpha: .12) : Colors.black.withValues(alpha: .08),
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor:
            d ? Colors.white.withValues(alpha: .12) : Colors.white.withValues(alpha: .55),
        circularTrackColor:
            d ? Colors.white.withValues(alpha: .12) : Colors.white.withValues(alpha: .55),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: rim),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
