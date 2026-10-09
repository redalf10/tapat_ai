import 'package:flutter/material.dart';

class AppColors {
  static const blue = Color(0xFF2563EB);
  static const purple = Color(0xFF7C3AED);
  static const navy = Color(0xFF070B1A);
  static const navy2 = Color(0xFF111A3A);
  static const gradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const darkGradient = LinearGradient(
    colors: [navy, navy2],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}