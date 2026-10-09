import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';

class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);
 
  static ThemeData _build(Brightness b) {
    final d = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
        seedColor: AppColors.blue, brightness: b, secondary: AppColors.purple);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          d ? const Color(0xFF0E1224) : const Color(0xFFF6F8FC),
      cardColor: d ? const Color(0xFF1A2038) : Colors.white,
      dividerColor: d ? Colors.white12 : Colors.black12,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: d ? const Color(0xFF1A2038) : const Color(0xFFEEF2F9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}