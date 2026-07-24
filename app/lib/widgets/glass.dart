import 'dart:ui';

import 'package:flutter/material.dart';

/// A frosted-glass surface (iOS style): a translucent panel with a hairline highlight
/// border. Over scrolling content the blur reads as glass; over the flat background it
/// reads as a panel lifted a little off the page.
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
      // The shadow is what lifts the glass off the page. Two: a close one for the
      // edge, a wide soft one for the lift.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.30 : 0.06),
            blurRadius: 28,
            offset: const Offset(0, 12),
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
              // On black the fill is a faint white lift; on white a soft milky panel.
              color: Colors.white.withValues(alpha: dark ? 0.07 : 0.62),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.10 : 0.70),
                width: 0.6,
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

/// What the glass floats on. No wallpaper blooms — those read as AI stock art. Dark is
/// true black for OLED, with a whisper of lift at the very top so it is not a dead void;
/// light is a clean, cool off-white. Both are flat and quiet, so the content is the thing.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0C0F14), Color(0xFF000000)]
              : const [Color(0xFFF5F7FB), Color(0xFFEBEEF3)],
          stops: const [0.0, 0.55],
        ),
      ),
    );
  }
}
