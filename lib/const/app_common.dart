import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_glass.dart';
import 'package:tapat_ai/const/app_theme.dart';
import 'package:tapat_ai/domain/models/topic_model.dart';

const topicIcons = <IconData>[
  Icons.wifi, Icons.school, Icons.settings_suggest, Icons.eco,
  Icons.flutter_dash, Icons.account_balance, Icons.favorite, Icons.menu_book,
];
const topicColors = <Color>[
  AppColors.blue, Color(0xFFF59E0B), Color(0xFF14B8A6), Color(0xFF22C55E),
  Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF6366F1),
];

String fmtDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => AppColors.gradient.createShader(r),
        child: Text(text, textAlign: TextAlign.center,
            style: (style ?? const TextStyle()).copyWith(color: Colors.white)),
      );
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 90});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.asset('assets/logo.png', width: size, height: size),
      );
}

/// The brand mark resting on a frosted glass disc.
class BrandGlassMark extends StatelessWidget {
  const BrandGlassMark({super.key, this.size = 110});
  final double size;
  @override
  Widget build(BuildContext context) => GlassSurface(
        radius: size * .32,
        blur: 22,
        padding: EdgeInsets.all(size * .18),
        child: BrandLogo(size: size * .5),
      );
}

/// Primary call to action: a frosted accent button.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon, this.loading = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: GlassSurface(
        radius: 16,
        blur: Glass.blurSoft,
        rim: Colors.white.withValues(alpha: dark ? .3 : .55),
        fill: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xA62563EB), Color(0xA67C3AED)]
              : const [Color(0xD12563EB), Color(0xD17C3AED)],
        ),
        onTap: enabled ? onPressed : null,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: .3),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            SizedBox(
              height: 50,
              child: Center(
                child: loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
                        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary action: a plain frosted glass button.
class SoftButton extends StatelessWidget {
  const SoftButton({super.key, required this.label, required this.onPressed, this.icon, this.dark = false});
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool dark;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = dark ? Colors.white : cs.onSurface;
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: GlassSurface(
        radius: 16,
        blur: Glass.blurSoft,
        rim: dark ? Colors.white.withValues(alpha: .32) : null,
        fill: dark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x26FFFFFF), Color(0x0DFFFFFF)],
              )
            : null,
        onTap: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: foreground), const SizedBox(width: 8)],
            Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// A frosted card used for grouped content.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => GlassSurface(
        radius: 18,
        blur: Glass.blurSoft,
        padding: padding,
        onTap: onTap,
        child: child,
      );
}

/// A glossy rounded tile carrying the colour of a knowledge base.
class TopicIcon extends StatelessWidget {
  const TopicIcon(this.index, {super.key, this.size = 44});
  final int index;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = topicColors[index % topicColors.length];
    final radius = BorderRadius.circular(size * .28);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: .95), c.withValues(alpha: .62)],
        ),
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: .38)),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 5)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: .38),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
                borderRadius: radius,
              ),
            ),
          ),
          Center(
            child: Icon(topicIcons[index % topicIcons.length],
                color: Colors.white, size: size * .55),
          ),
        ],
      ),
    );
  }
}

class TopicTile extends StatelessWidget {
  const TopicTile(this.topic, {super.key, required this.onTap});
  final Topic topic;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          onTap: onTap,
          child: Row(children: [
            TopicIcon(topic.iconIndex),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(topic.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(topic.stats, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ]),
        ),
      );
}

/// Pulsing concentric rings, used on NFC screens.
class Ripple extends StatefulWidget {
  const Ripple({super.key, required this.child, this.size = 220, this.color = AppColors.blue});
  final Widget child;
  final double size;
  final Color color;
  @override
  State<Ripple> createState() => _RippleState();
}

class _RippleState extends State<Ripple> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size, height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) => CustomPaint(
              painter: _RipplePainter(_c.value, widget.color), child: Center(child: child)),
          child: widget.child,
        ),
      );
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t, this.color);
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - p) * .7);
      canvas.drawCircle(s.center(Offset.zero), s.width / 2 * (.35 + .65 * p), paint);
    }
    canvas.drawCircle(s.center(Offset.zero), s.width * .22,
        Paint()..color = color.withValues(alpha: .12 + .08 * math.sin(t * 2 * math.pi)));
  }
  @override
  bool shouldRepaint(_RipplePainter o) => o.t != t;
}

/// A scaffold on the dark glass palette, used by the NFC flows.
class DarkScaffold extends StatelessWidget {
  const DarkScaffold({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.dark,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: GlassBackground(
            dark: true,
            child: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: child)),
          ),
        ),
      );
}
