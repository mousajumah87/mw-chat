// lib/widgets/ui/mw_background.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class MwBackground extends StatefulWidget {
  final Widget child;

  const MwBackground({super.key, required this.child});

  @override
  State<MwBackground> createState() => _MwBackgroundState();
}

class _MwBackgroundState extends State<MwBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowShift;

  bool get _isLargeScreen => MediaQuery.of(context).size.width > 800;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);

    _glowShift = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLarge = _isLargeScreen;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _glowShift,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // === Full-screen background image ===
              Positioned.fill(
                child: Image.asset(
                  'assets/images/mw_bg.png',
                  fit: BoxFit.cover,          // <- always fills screen
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.low,
                ),
              ),

              // === Dynamic ambient glow overlay ===
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: const [0.0, 0.5, 1.0],
                        colors: [
                          kPrimaryBlue.withOpacity(
                            0.15 + 0.05 * (1 - _glowShift.value),
                          ),
                          Colors.transparent,
                          kSecondaryAmber.withOpacity(
                            0.15 + 0.05 * _glowShift.value,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // === Dark vignette & fade for contrast ===
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x1A000000),
                          Color(0x4D000000),
                          Color(0x99000000),
                        ],
                        stops: [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // === Subtle radial vignette ===
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
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

              // === Optional adaptive blur (desktop/tablet only) ===
              // if (isLarge)
                // Positioned.fill(
                //   child: BackdropFilter(
                //     filter: ImageFilter.blur(
                //       sigmaX: 1.0 + (0.5 * _glowShift.value),
                //       sigmaY: 1.0 + (0.5 * _glowShift.value),
                //     ),
                //     child: const SizedBox.shrink(),
                //   ),
                // ),

              // === Foreground content (your screen) ===
              Positioned.fill(child: widget.child),
            ],
          );
        },
      ),
    );
  }
}
