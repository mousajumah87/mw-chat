import 'package:flutter/material.dart';

/// Reusable "Snapchat-like" swipe-to-exit wrapper.
/// - Triggers ONLY when swipe starts near left/right edge (avoids scroll conflicts)
/// - Pops current route by default, or runs [onExit] if provided
class MwSwipeBack extends StatefulWidget {
  final Widget child;

  /// If provided, this runs instead of Navigator.pop.
  final VoidCallback? onExit;

  /// Disable swipe at runtime (e.g., when keyboard/panel open).
  final bool enabled;

  /// Edge width area to arm the gesture.
  final double edgeWidth;

  /// Distance needed to trigger exit.
  final double minDistance;

  /// Velocity needed to trigger exit (fling).
  final double minVelocity;

  /// Horizontal/vertical dominance factor. Higher = stricter horizontal.
  final double horizontalDominance;

  const MwSwipeBack({
    super.key,
    required this.child,
    this.onExit,
    this.enabled = true,
    this.edgeWidth = 22,
    this.minDistance = 70,
    this.minVelocity = 700,
    this.horizontalDominance = 1.2,
  });

  @override
  State<MwSwipeBack> createState() => _MwSwipeBackState();
}

class _MwSwipeBackState extends State<MwSwipeBack> {
  double _dx = 0;
  double _dy = 0;
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,

      onPanStart: (d) {
        _dx = 0;
        _dy = 0;
        _armed = false;

        if (!widget.enabled) return;

        final x = d.localPosition.dx;
        final w = MediaQuery.of(context).size.width;

        if (x <= widget.edgeWidth || x >= (w - widget.edgeWidth)) {
          _armed = true;
        }
      },

      onPanUpdate: (d) {
        if (!_armed) return;
        _dx += d.delta.dx;
        _dy += d.delta.dy;
      },

      onPanEnd: (d) {
        if (!_armed) return;
        _armed = false;

        final absDx = _dx.abs();
        final absDy = _dy.abs();
        final vx = d.velocity.pixelsPerSecond.dx.abs();

        // must be mainly horizontal
        if (absDx <= absDy * widget.horizontalDominance) return;

        final bool enoughDistance = absDx >= widget.minDistance;
        final bool enoughVelocity = vx >= widget.minVelocity;

        if (!(enoughDistance || enoughVelocity)) return;

        if (widget.onExit != null) {
          widget.onExit!.call();
          return;
        }

        final nav = Navigator.of(context);
        if (nav.canPop()) nav.maybePop();
      },

      child: widget.child,
    );
  }
}
