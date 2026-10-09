import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/app_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  static const _pages = [
    (
      title1: 'Your Documents,',
      title2: 'Your AI',
      desc: 'Upload your own documents and create a private knowledge base that works offline.',
    ),
    (
      title1: 'Ask Anything',
      title2: 'From Your Knowledge',
      desc: 'Get accurate answers from your uploaded documents using local AI. No internet required.',
    ),
    (
      title1: 'Tap an Object.',
      title2: 'Open Its Knowledge.',
      desc: 'Use NFC tags to instantly open the right knowledge base. Perfect for equipment, books, classrooms, and more.',
    ),
  ];

  void _finish() {
    AppState.read(context).completeOnboarding();
    Navigator.pushReplacementNamed(context, Routes.shell);
  }

  void _next() {
    if (_currentIndex == 2) {
      _finish();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Skip Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ),
            ),

            // Page Content Carousel
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: 3,
                onPageChanged: (v) => setState(() => _currentIndex = v),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          p.title1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            height: 1.25,
                            letterSpacing: -0.5,
                          ),
                        ),
                        GradientText(
                          p.title2,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            p.desc,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14.5,
                              color: Color(0xFF64748B),
                              height: 1.45,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Custom Center Graphic
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: switch (i) {
                            0 => const _UploadIllustration(),
                            1 => const _AskAnythingIllustration(),
                            _ => const _NfcTapIllustration(),
                          },
                        ),
                        const Spacer(),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Navigation Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: _currentIndex == 2
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Dots Centered
                        _buildDotsIndicator(),
                        const SizedBox(height: 20),
                        // Full-width Get Started Button
                        Container(
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x552563EB),
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _finish,
                              borderRadius: BorderRadius.circular(16),
                              child: const Center(
                                child: Text(
                                  'Get Started',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        // Dots on the left
                        _buildDotsIndicator(),
                        const Spacer(),
                        // Floating Next Squircle Button
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x552563EB),
                                blurRadius: 14,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _next,
                              borderRadius: BorderRadius.circular(16),
                              child: const Center(
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDotsIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (dotIndex) {
        final isActive = dotIndex == _currentIndex;
        return GestureDetector(
          onTap: () => _goTo(dotIndex),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 8 : 6,
            height: isActive ? 8 : 6,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}

// ============================================================================
// SCREEN 1 ILLUSTRATION: Upload Documents & Dock
// ============================================================================
class _UploadIllustration extends StatelessWidget {
  const _UploadIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      width: 320,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Base Dock (Scanner Bed)
          Positioned(
            bottom: 4,
            child: Container(
              width: 220,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 170,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFF334155), width: 1),
                  ),
                ),
              ),
            ),
          ),

          // Glowing Upward Arrow
          Positioned(
            bottom: 48,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                color: Color(0xFF3B82F6),
                size: 38,
              ),
            ),
          ),

          // Document Cards (Left PDF, Center TXT, Right DOCX)
          // 1. Red PDF Card (Left, tilted -11 deg)
          Positioned(
            left: 28,
            top: 26,
            child: Transform.rotate(
              angle: -0.18,
              child: const _FoldedFileCard(
                width: 74,
                height: 104,
                cardColor: Color(0xFFEF4444),
                foldColor: Color(0xFFDC2626),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PdfRibbonIcon(size: 26),
                    SizedBox(height: 6),
                    Text(
                      'PDF',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Light Blue TXT Card (Center, elevated)
          Positioned(
            top: 10,
            child: const _FoldedFileCard(
              width: 74,
              height: 104,
              cardColor: Color(0xFFDBEAFE),
              foldColor: Color(0xFFBFDBFE),
              child: Center(
                child: Text(
                  'TXT',
                  style: TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),

          // 3. Blue DOCX Card (Right, tilted +11 deg)
          Positioned(
            right: 28,
            top: 26,
            child: Transform.rotate(
              angle: 0.18,
              child: const _FoldedFileCard(
                width: 74,
                height: 104,
                cardColor: Color(0xFF2563EB),
                foldColor: Color(0xFF1D4ED8),
                child: Center(
                  child: Text(
                    'DOCX',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Dog-eared folded file card widget
class _FoldedFileCard extends StatelessWidget {
  const _FoldedFileCard({
    required this.width,
    required this.height,
    required this.cardColor,
    required this.foldColor,
    required this.child,
  });

  final double width;
  final double height;
  final Color cardColor;
  final Color foldColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const foldSize = 18.0;
    const radius = 12.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Stack(
        children: [
          // Card Body with folded corner cutout
          ClipPath(
            clipper: _FoldedCardClipper(foldSize: foldSize, radius: radius),
            child: Container(
              color: cardColor,
              width: width,
              height: height,
              child: child,
            ),
          ),
          // Folded corner flap
          Positioned(
            top: 0,
            right: 0,
            child: ClipPath(
              clipper: _CornerFlapClipper(foldSize: foldSize),
              child: Container(
                width: foldSize,
                height: foldSize,
                color: foldColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoldedCardClipper extends CustomClipper<Path> {
  const _FoldedCardClipper({required this.foldSize, required this.radius});
  final double foldSize;
  final double radius;

  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    // Start at top-left with border radius
    path.moveTo(radius, 0);
    // Line to start of fold
    path.lineTo(w - foldSize, 0);
    // Diagonal to fold end on right edge
    path.lineTo(w, foldSize);
    // Line down to bottom-right corner
    path.lineTo(w, h - radius);
    path.quadraticBezierTo(w, h, w - radius, h);
    // Line to bottom-left corner
    path.lineTo(radius, h);
    path.quadraticBezierTo(0, h, 0, h - radius);
    // Line to top-left corner
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_FoldedCardClipper oldClipper) =>
      oldClipper.foldSize != foldSize || oldClipper.radius != radius;
}

class _CornerFlapClipper extends CustomClipper<Path> {
  const _CornerFlapClipper({required this.foldSize});
  final double foldSize;

  @override
  Path getClip(Size size) {
    final path = Path();
    // Triangle: (0, 0) -> (0, foldSize) -> (foldSize, foldSize)
    path.moveTo(0, 0);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_CornerFlapClipper oldClipper) =>
      oldClipper.foldSize != foldSize;
}

// Stylized PDF emblem icon
class _PdfRibbonIcon extends StatelessWidget {
  const _PdfRibbonIcon({this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PdfRibbonPainter(),
    );
  }
}

class _PdfRibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final path = Path();
    // Elegant stylized PDF curly ribbon loop
    path.moveTo(w * 0.2, h * 0.75);
    path.cubicTo(w * 0.05, h * 0.6, w * 0.2, h * 0.4, w * 0.5, h * 0.15);
    path.cubicTo(w * 0.58, h * 0.1, w * 0.65, h * 0.2, w * 0.5, h * 0.5);
    path.cubicTo(w * 0.4, h * 0.7, w * 0.7, h * 0.8, w * 0.85, h * 0.65);

    canvas.drawPath(path, paint);

    // Inner loop accent
    final smallPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.52, h * 0.28), 1.6, smallPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// SCREEN 2 ILLUSTRATION: Ask Anything & Source Citation
// ============================================================================
class _AskAnythingIllustration extends StatelessWidget {
  const _AskAnythingIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      width: 330,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User Question Bubble (Aligned Right)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFE0F2FE),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'What is TCP?',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // AI Response Row (Avatar + Response Card)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x332563EB),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.all_inclusive_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // AI Response Bubble Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0E000000),
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TCP is a connection-oriented protocol that provides reliable and ordered delivery...',
                        style: TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Citation Mini-Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.article_outlined,
                                color: Color(0xFF64748B),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Source',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 1),
                                  Text(
                                    'Networking Basics.pdf',
                                    style: TextStyle(
                                      color: Color(0xFF1E293B),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 1),
                                  Text(
                                    'Page 18',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 10.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SCREEN 3 ILLUSTRATION: NFC Object & Knowledge Card
// ============================================================================
class _NfcTapIllustration extends StatelessWidget {
  const _NfcTapIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      width: 320,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Concentric Radiating NFC Waves
          Positioned(
            left: 10,
            top: 20,
            child: CustomPaint(
              size: const Size(180, 180),
              painter: _NfcWaveRingsPainter(),
            ),
          ),

          // NFC Disc / Tag (3D metallic disc on left)
          Positioned(
            left: 55,
            top: 65,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFFFFF), Color(0xFFCBD5E1)],
                ),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
                    ),
                    border: Border.all(color: const Color(0xFF93C5FD), width: 1.5),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.wifi_rounded,
                      color: Color(0xFF0F172A),
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Standing Smartphone Mockup (Right)
          Positioned(
            right: 20,
            top: 15,
            child: Container(
              width: 105,
              height: 175,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF334155), width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x35000000),
                    blurRadius: 24,
                    offset: Offset(4, 12),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  // Camera / Dynamic Island Pill
                  Positioned(
                    top: 6,
                    child: Container(
                      width: 24,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF020617),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // Screen glass
                  Positioned.fill(
                    top: 14,
                    bottom: 6,
                    left: 4,
                    right: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1E293B),
                            border: Border.all(color: const Color(0xFF334155), width: 1.5),
                          ),
                          child: const Icon(
                            Icons.contactless_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Floating NFC Tag Card (In front, bottom-left)
          Positioned(
            left: 20,
            bottom: 15,
            child: Container(
              width: 215,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF2563EB),
                    ),
                    child: const Icon(
                      Icons.contactless_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'NFC Tag',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'RAG: networking-001',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Open Knowledge',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Concentric cyan/light blue wave rings painter
class _NfcWaveRingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final rings = [
      (radius: 48.0, color: const Color(0xFF38BDF8).withValues(alpha: 0.6), stroke: 2.2),
      (radius: 68.0, color: const Color(0xFF60A5FA).withValues(alpha: 0.4), stroke: 2.0),
      (radius: 88.0, color: const Color(0xFF93C5FD).withValues(alpha: 0.25), stroke: 1.8),
    ];

    for (final r in rings) {
      final paint = Paint()
        ..color = r.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.stroke;
      canvas.drawCircle(center, r.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
