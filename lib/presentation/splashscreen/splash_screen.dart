import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/app_provider.dart';

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

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingScreen> {
  final _p = PageController();
  int _i = 0;

  static const _pages = [
    ('Your Documents,', 'Your AI',
        'Upload your own documents and create a private knowledge base that works offline.',
        [Icons.picture_as_pdf, Icons.description, Icons.upload_file]),
    ('Ask Anything', 'From Your Knowledge',
        'Get accurate answers from your uploaded documents using local AI. No internet required.',
        [Icons.chat_bubble_outline, Icons.psychology_outlined, Icons.source_outlined]),
    ('Tap an Object.', 'Open Its Knowledge.',
        'Use NFC tags to instantly open the right knowledge base. Perfect for equipment, books, classrooms, and more.',
        [Icons.nfc, Icons.phone_android, Icons.menu_book]),
  ];

  void _finish() {
    AppState.read(context).completeOnboarding();
    Navigator.pushReplacementNamed(context, Routes.shell);
  }

  void _next() => _i == 2
      ? _finish()
      : _p.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _finish, child: Text('Skip', style: TextStyle(color: hint))),
          ),
          Expanded(
            child: PageView.builder(
              controller: _p,
              itemCount: 3,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (_, i) {
                final p = _pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(children: [
                    const SizedBox(height: 24),
                    Text(p.$1, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    GradientText(p.$2, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    Text(p.$3, textAlign: TextAlign.center, style: TextStyle(color: hint, height: 1.4)),
                    const Spacer(),
                    Ripple(
                      size: 240,
                      child: Container(
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                            gradient: AppColors.gradient, borderRadius: BorderRadius.circular(32)),
                        child: Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
                            children: [for (final ic in p.$4) Icon(ic, color: Colors.white, size: 34)]),
                      ),
                    ),
                    const Spacer(),
                  ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _i == 2
                ? GradientButton(label: 'Get Started', onPressed: _next)
                : Row(children: [
                    for (var d = 0; d < 3; d++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        width: d == _i ? 18 : 6, height: 6,
                        decoration: BoxDecoration(
                            color: d == _i ? AppColors.blue : hint.withValues(alpha: .4),
                            borderRadius: BorderRadius.circular(3)),
                      ),
                    const Spacer(),
                    SizedBox(
                      width: 52,
                      child: GradientButton(label: '', icon: Icons.arrow_forward, onPressed: _next),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}