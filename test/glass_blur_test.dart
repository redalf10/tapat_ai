import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapat_ai/const/app_glass.dart';
import 'package:tapat_ai/const/app_theme.dart';

/// Sharp black/white stripes: a blur of this must look soft and grey,
/// while an unfiltered backdrop would show hard edges.
class _StripesPainter extends CustomPainter {
  const _StripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    const width = 28.0;
    for (var x = 0.0; x < size.width; x += width) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, width, size.height),
        paint..color = (x / width).round().isEven ? Colors.black : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}

void main() {
  testWidgets('a glass panel blurs the sharp backdrop behind it',
      (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _StripesPainter())),
          // A mostly transparent panel so the blurred stripes stay visible.
          Center(
            child: GlassSurface(
              radius: 24,
              blur: 20,
              padding: const EdgeInsets.all(30),
              fill: const LinearGradient(
                colors: [Color(0x1AFFFFFF), Color(0x1AFFFFFF)],
              ),
              child: const SizedBox(width: 260, height: 120),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/blur_check.png'));
  });

  testWidgets('glass still blurs the backdrop after a route fade transition',
      (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Mirrors AppRouter: a PageRouteBuilder faded in over the app backdrop.
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) => GlassBackground(child: child!),
      onGenerateRoute: (settings) => PageRouteBuilder(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: [
            const Positioned.fill(child: CustomPaint(painter: _StripesPainter())),
            Center(
              child: GlassSurface(
                radius: 24,
                blur: 20,
                padding: const EdgeInsets.all(30),
                fill: const LinearGradient(
                  colors: [Color(0x1AFFFFFF), Color(0x1AFFFFFF)],
                ),
                child: const SizedBox(width: 260, height: 120),
              ),
            ),
          ]),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/blur_check_route.png'));
  });
}
