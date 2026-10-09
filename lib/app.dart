import 'package:flutter/material.dart';
import 'package:tapat_ai/presentation/home/home_screen.dart';

class TapatApp extends StatelessWidget {
  const TapatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomeScreen(),
    );
  }
}