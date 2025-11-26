// lib/widgets/mw_background.dart
import 'dart:ui';
import 'package:flutter/material.dart';

class MwBackground extends StatelessWidget {
  final Widget child;

  const MwBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background mascot (brighter and sharper)
        Positioned.fill(
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.white.withOpacity(0.15), // boosts brightness subtly
              BlendMode.srcATop,
            ),
            child: Image.asset(
              'assets/images/mw_bg.png',
              fit: BoxFit.contain, // keeps full mascot visible
              alignment: Alignment.center,
            ),
          ),
        ),

        // Light gradient overlay for readability (much lighter now)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.15), // top minimal shade
                  Colors.black.withOpacity(0.25),
                  Colors.black.withOpacity(0.45), // bottom a bit darker for text
                ],
              ),
            ),
          ),
        ),

        // Soft vignette effect for focus
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.25),
                ],
                stops: const [0.8, 1.0],
              ),
            ),
          ),
        ),

        // Foreground content
        child,
      ],
    );
  }
}
