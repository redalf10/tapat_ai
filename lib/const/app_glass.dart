import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';

/// Design tokens for the app's glassmorphism language.
///
/// Every frosted panel shares the same blur strength, rim light and shadow so
/// the whole UI reads as one continuous sheet of glass.
class Glass {
  const Glass._();

  /// Corner radius of a standard frosted panel.
  static const double radius = 22;

  /// Corner radius used by bars, sheets and dialogs.
  static const double largeRadius = 26;

  /// Backdrop blur sigma for prominent surfaces.
  static const double blur = 16;

  /// Backdrop blur sigma for small surfaces that are rendered many times.
  static const double blurSoft = 9;

  /// Translucent fill of a frosted panel.
  static LinearGradient fill(bool dark) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0x2BFFFFFF), Color(0x0DFFFFFF)]
            : const [Color(0xCCFFFFFF), Color(0x7AFFFFFF)],
      );

  /// Hairline rim light that gives a panel its lit edge.
  static Color rim(bool dark) =>
      dark ? Colors.white.withValues(alpha: .18) : Colors.white.withValues(alpha: .92);

  /// Soft drop shadow underneath a panel.
  static List<BoxShadow> shadow(bool dark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? .42 : .08),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ];
}

/// A soft mesh-gradient backdrop. The glass panels refract this so the blur
/// always has colour to work with.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, this.child, this.dark});

  final Widget? child;

  /// Forces the dark palette; defaults to the ambient theme brightness.
  final bool? dark;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: CustomPaint(painter: _MeshPainter(isDark))),
        ?child,
      ],
    );
  }
}

const _lightBlobs = <(Color, double, double, double)>[
  (Color(0xFF93C5FD), -0.15, -0.12, 0.95),
  (Color(0xFFC4B5FD), 1.05, 0.02, 0.85),
  (Color(0xFF67E8F9), 0.30, 0.95, 0.80),
  (Color(0xFFFBCFE8), 0.88, 0.88, 0.60),
  (Color(0xFFA5B4FC), 0.02, 0.55, 0.70),
];

const _darkBlobs = <(Color, double, double, double)>[
  (Color(0xFF1D4ED8), -0.12, -0.16, 0.95),
  (Color(0xFF7C3AED), 1.05, 0.04, 0.85),
  (Color(0xFF0E7490), 0.28, 1.00, 0.80),
  (Color(0xFFBE185D), 0.92, 0.86, 0.55),
  (Color(0xFF3730A3), 0.02, 0.55, 0.75),
];

class _MeshPainter extends CustomPainter {
  const _MeshPainter(this.dark);

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xFF060917) : const Color(0xFFF1F3FB),
    );
    final blobs = dark ? _darkBlobs : _lightBlobs;
    for (final blob in blobs) {
      final center = Offset(blob.$2 * size.width, blob.$3 * size.height);
      final radius = blob.$4 * size.longestSide * .55;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              blob.$1.withValues(alpha: dark ? .55 : .9),
              blob.$1.withValues(alpha: 0),
            ],
            stops: const [0, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.dark != dark;
}

/// A frosted-glass panel: blurred backdrop, translucent tint, rim light and a
/// soft drop shadow. Optionally tappable, in which case it gets an ink ripple.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.radius = Glass.radius,
    this.blur = Glass.blur,
    this.fill,
    this.rim,
    this.shadow = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  /// Backdrop blur sigma.
  final double blur;

  /// Overrides the default translucent fill.
  final Gradient? fill;

  /// Overrides the default rim light colour.
  final Color? rim;

  /// Whether the panel casts a drop shadow.
  final bool shadow;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    final decoration = BoxDecoration(
      gradient: fill ?? Glass.fill(dark),
      borderRadius: shape,
      border: Border.all(color: rim ?? Glass.rim(dark)),
      boxShadow: shadow ? Glass.shadow(dark) : null,
    );

    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);

    Widget body = Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: decoration,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: shape,
                splashColor: (dark ? Colors.white : AppColors.blue).withValues(alpha: .14),
                highlightColor: Colors.white.withValues(alpha: .06),
                child: content,
              ),
      ),
    );

    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: body,
      ),
    );
  }
}

/// A frosted app bar. Wraps a regular [AppBar] so the back button, actions
/// and title behaviour stay untouched.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, required this.appBar});

  final AppBar appBar;

  @override
  Size get preferredSize => appBar.preferredSize;

  @override
  Widget build(BuildContext context) => GlassSurface(
        radius: 0,
        blur: Glass.blur,
        shadow: false,
        rim: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: .12)
            : Colors.white.withValues(alpha: .8),
        child: appBar,
      );
}

/// A frosted text field. The blur lives in the panel, the field itself paints
/// no background so the glass shows through.
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.maxLines = 1,
    this.textInputAction,
    this.prefixIcon,
    this.suffix,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final int maxLines;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;
  final Widget? suffix;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => GlassSurface(
        radius: 16,
        blur: Glass.blurSoft,
        shadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          obscureText: obscureText,
          maxLines: maxLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon,
            suffixIcon: suffix,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
}

/// A frosted pill used for filters and short options.
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassSurface(
      radius: 12,
      blur: Glass.blurSoft,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      fill: selected
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withValues(alpha: .92),
                cs.primary.withValues(alpha: .72),
              ],
            )
          : null,
      rim: selected
          ? Colors.white.withValues(alpha: .35)
          : (dark ? Colors.white24 : Colors.white),
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : cs.onSurface,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// A single entry of the glass navigation bar.
class GlassNavDestination {  const GlassNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// A floating frosted navigation bar that replaces Material's [NavigationBar].
class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: GlassSurface(
        radius: Glass.largeRadius,
        blur: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _GlassNavItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  dark: dark,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  const _GlassNavItem({
    required this.destination,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final GlassNavDestination destination;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inactive = cs.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  gradient: selected
                      ? LinearGradient(colors: [
                          cs.primary.withValues(alpha: .26),
                          cs.secondary.withValues(alpha: .26),
                        ])
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? (dark ? Colors.white24 : Colors.white)
                        : Colors.transparent,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: .28),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 21,
                  color: selected ? cs.primary : inactive,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.primary : inactive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A frosted circular action button.
class GlassFab extends StatelessWidget {
  const GlassFab({super.key, required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GlassSurface(
      radius: 28,
      blur: 20,
      padding: EdgeInsets.zero,
      onTap: onPressed,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);
  }
}

/// A frosted modal dialog.
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 20),
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(),
      clipBehavior: Clip.none,
      child: GlassSurface(
        radius: Glass.largeRadius,
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
            ],
            child,
            if (actions != null) ...[
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions!),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small grab handle used on top of glass sheets.
class GlassDragHandle extends StatelessWidget {
  const GlassDragHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Shows a bottom sheet made of frosted glass.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: .32),
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * .86),
        child: SafeArea(
          top: false,
          child: GlassSurface(
            radius: Glass.largeRadius,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GlassDragHandle(),
                const SizedBox(height: 14),
                builder(sheetContext),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shows a floating glass snack bar.
void glassSnack(BuildContext context, String message, {IconData? icon}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: Colors.transparent,
      duration: const Duration(seconds: 3),
      content: GlassSurface(
        radius: 16,
        blur: Glass.blurSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                message,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
