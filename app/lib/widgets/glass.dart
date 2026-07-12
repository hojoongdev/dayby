import 'dart:ui';

import 'package:flutter/material.dart';

/// A frosted-glass surface (iOS style): a blurred, translucent panel with a
/// hairline highlight border. Sits over [GlassBackground] so the blur reads.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.blur = 18,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = DecoratedBox(
      // Frost alone does not lift a panel off the page; the shadow is what says
      // the glass is above the background rather than painted onto it. Two of
      // them: a close one for the edge, a wide soft one for the lift.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.22 : 0.05),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: dark ? 0.10 : 0.55),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.16 : 0.65),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// What the glass floats on. The gradient alone is too smooth for frost to show
/// against — the blur needs something to smear — so a few soft colour blooms sit
/// under it, out of focus, the way a wallpaper does behind iOS glass.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF1B2430), Color(0xFF2A3442), Color(0xFF20291F)]
                    : const [Color(0xFFDCE7F5), Color(0xFFEDE5F4), Color(0xFFE4F1EA)],
              ),
            ),
          ),
        ),
        Positioned(
          top: -90,
          left: -70,
          child: _Bloom(
            const Color(0xFF7BA7DD),
            size: 320,
            opacity: dark ? 0.22 : 0.38,
          ),
        ),
        Positioned(
          top: 220,
          right: -110,
          child: _Bloom(
            const Color(0xFFB79FDD),
            size: 300,
            opacity: dark ? 0.20 : 0.32,
          ),
        ),
        Positioned(
          bottom: -80,
          left: 20,
          child: _Bloom(
            const Color(0xFF86CDB2),
            size: 340,
            opacity: dark ? 0.18 : 0.30,
          ),
        ),
      ],
    );
  }
}

class _Bloom extends StatelessWidget {
  const _Bloom(this.color, {required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
