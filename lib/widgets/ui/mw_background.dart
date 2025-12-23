// lib/widgets/ui/mw_background.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class MwBackground extends StatefulWidget {
  final Widget child;

  /// ✅ When true: pauses glow animation (better performance during typing)
  final bool reduceEffects;

  const MwBackground({
    super.key,
    required this.child,
    this.reduceEffects = false,
  });

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
    );

    _glowShift = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );

    // Start animation only if effects enabled
    if (!widget.reduceEffects) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant MwBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.reduceEffects != widget.reduceEffects) {
      if (widget.reduceEffects) {
        // ✅ pause + reset to stable state
        _controller.stop();
        _controller.value = 0.0;
      } else {
        _controller.repeat(reverse: true);
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLarge = _isLargeScreen;

    // If reduced effects, don’t rebuild on animation ticks
    final animated = widget.reduceEffects ? null : _glowShift;

    Widget buildStack(double glowValue) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/mw_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.low,
            ),
          ),

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
                      kPrimaryGold.withOpacity(0.12 + 0.06 * (1 - glowValue)),
                      Colors.transparent,
                      kGoldDeep.withOpacity(0.12 + 0.06 * glowValue),
                    ],
                  ),
                ),
              ),
            ),
          ),

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

          // Keep blur disabled on mobile for performance (yours already commented)
          // if (isLarge) ...

          Positioned.fill(child: widget.child),
        ],
      );
    }

    return RepaintBoundary(
      child: animated == null
          ? buildStack(0.0)
          : AnimatedBuilder(
        animation: animated,
        builder: (context, _) => buildStack(_glowShift.value),
      ),
    );
  }
}
