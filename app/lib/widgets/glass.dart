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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
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
    );
  }
}

/// The soft gradient the glass surfaces float on.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF1B2430), Color(0xFF2A3442), Color(0xFF20291F)]
              : const [Color(0xFFDCE7F5), Color(0xFFEDE5F4), Color(0xFFE4F1EA)],
        ),
      ),
    );
  }
}
