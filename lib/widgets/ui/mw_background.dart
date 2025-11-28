import 'dart:ui';
import 'package:flutter/material.dart';

class MwBackground extends StatelessWidget {
  final Widget child;

  const MwBackground({super.key, required this.child});

  bool _isLargeScreen(BuildContext context) =>
      MediaQuery.of(context).size.width > 800;

  @override
  Widget build(BuildContext context) {
    final isLarge = _isLargeScreen(context);

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // === Background Image (cached, static, low GPU load) ===
          Positioned.fill(
            child: Image.asset(
              'assets/images/mw_bg.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low, // less GPU work
              isAntiAlias: false,
            ),
          ),

          // === Soft gradient overlay (single layer only) ===
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x1A000000), // very faint at top
                      Color(0x4D000000), // mid-level tint
                      Color(0x80000000), // stronger at bottom
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // === Subtle vignette (merged with bottom fade for contrast) ===
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      Colors.transparent,
                      Color(0x66000000),
                    ],
                    stops: [0.8, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // === Optional blur only for tablets/desktops ===
          if (isLarge)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
                child: const SizedBox.shrink(),
              ),
            ),

          // === Foreground Content ===
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
