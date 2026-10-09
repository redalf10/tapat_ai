import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/app_provider.dart';

export 'package:tapat_ai/presentation/onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        final done = AppState.read(context).onboarded;
        Navigator.pushReplacementNamed(context, done ? Routes.shell : Routes.onboarding);
      }
    });
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.darkGradient),
          child: SafeArea(
            child: Column(children: [
              const Spacer(flex: 3),
              const BrandLogo(size: 110),
              const SizedBox(height: 16),
              const Text('Tapat AI',
                  style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Local RAG AI with NFC', style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 40),
              const Text('Your knowledge.\nOn your device.\nOne tap away.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.5)),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: _c.value, minHeight: 4,
                        backgroundColor: Colors.white12, color: AppColors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ]),
          ),
        ),
      );
}