// lib/widgets/ui/mw_swipe_back.dart
//
// MW Chat – Premium Snapchat-like swipe back
// - Works globally (even when wrapped in MaterialApp.builder) via navigatorKey
// - Interactive “rubber-band” progress (like iOS native)
// - Subtle MW-glass edge glow + dim + parallax (modern, premium)
// - Safe with vertical scrolling (only arms at edge + direction + dominance check)
// - Web friendly (mouse drag). Trackpad “browser back” is browser-controlled.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MwSwipeBack extends StatefulWidget {
  final Widget child;

  /// If provided, runs instead of Navigator.pop.
  final VoidCallback? onExit;

  /// ✅ Required when wrapping whole app in MaterialApp.builder.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Disable swipe at runtime (e.g., when emoji panel open).
  final bool enabled;

  /// Edge width area to arm the gesture.
  final double edgeWidth;

  /// Distance needed to trigger exit (if velocity not enough).
  final double minDistance;

  /// Velocity needed to trigger exit (fling).
  final double minVelocity;

  /// If true, when navigator cannot pop, navigate to [fallbackToHomeRoute].
  final bool goHomeIfCantPop;

  /// Named route for home (e.g. "/home").
  final String fallbackToHomeRoute;

  /// Only allow back direction:
  /// LTR: left->right, RTL: right->left.
  final bool onlySwipeFromStartToEnd;

  /// Small premium feedback on successful back swipe (mobile only).
  final bool hapticOnPop;

  /// Enable premium visuals (glass glow + dim + parallax).
  final bool animatedHint;

  /// Max pixels content translates while dragging (parallax).
  final double hintMaxSlide;

  /// Max overlay dim while dragging.
  final double hintMaxDim;

  /// Edge glow max opacity.
  final double edgeGlowMaxOpacity;

  /// How much progress needed to pop (0..1 of screen width).
  final double popProgressThreshold;

  /// If true, allow on iOS even when there is the native Cupertino back gesture.
  /// Usually safe. If you ever see conflict on iOS, set false.
  final bool allowOnIOS;

  const MwSwipeBack({
    super.key,
    required this.child,
    this.onExit,
    this.navigatorKey,
    this.enabled = true,
    this.edgeWidth = 22,
    this.minDistance = 70,
    this.minVelocity = 700,
    this.goHomeIfCantPop = false,
    this.fallbackToHomeRoute = "/home",
    this.onlySwipeFromStartToEnd = true,
    this.hapticOnPop = true,
    this.animatedHint = true,
    this.hintMaxSlide = 26,
    this.hintMaxDim = 0.06,
    this.edgeGlowMaxOpacity = 0.22,
    this.popProgressThreshold = 0.28,
    this.allowOnIOS = true,
  });

  @override
  State<MwSwipeBack> createState() => _MwSwipeBackState();
}

class _MwSwipeBackState extends State<MwSwipeBack> with SingleTickerProviderStateMixin {
  // Raw gesture accumulation
  double _dx = 0;
  double _dy = 0;
  bool _armed = false;

  // Track start position to arm reliably (web + mixed pointer devices)
  Offset? _downLocalPos;

  // Progress 0..1 for interactive drag
  double _progress = 0;

  // Parallax offset (signed)
  double _hintOffset = 0;

  late final AnimationController _settleCtrl;
  late Animation<double> _settleAnim;

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  bool get _isIOS {
    // Avoid importing dart:io (web). Use platform enum.
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();

    _settleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    );

    _settleAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _settleCtrl, curve: Curves.easeOutCubic),
    )..addListener(() {
      if (!mounted) return;
      setState(() {
        _progress = _settleAnim.value;
        _hintOffset = _progressToHintOffset(_progress);
      });
    });
  }

  @override
  void dispose() {
    _settleCtrl.dispose();
    super.dispose();
  }

  void _reset() {
    _dx = 0;
    _dy = 0;
    _armed = false;
    _downLocalPos = null;
  }

  double _progressToHintOffset(double p) {
    if (!widget.animatedHint) return 0;
    final maxSlide = widget.hintMaxSlide <= 0 ? 1.0 : widget.hintMaxSlide;
    final sign = _isRtl ? -1.0 : 1.0;

    // Rubber-band feel: fast at first, slower later
    final eased = Curves.easeOutCubic.transform(p.clamp(0.0, 1.0));
    return sign * (maxSlide * eased).clamp(0.0, maxSlide);
  }

  double _applyRubberBand(double raw, double dimension) {
    // Rubber-band formula inspired by iOS scroll feel.
    // raw: absolute drag distance
    // dimension: typically screen width
    final d = dimension <= 0 ? 1.0 : dimension;
    final x = raw / d;
    // Softer resistance as it grows
    final r = (1 - (1 / (x * 6 + 1)));
    return r.clamp(0.0, 1.0) * d;
  }

  bool _isNearStartEdge(Offset localPosition, double width) {
    if (!widget.enabled) return false;

    if (!_isRtl) {
      return localPosition.dx <= widget.edgeWidth;
    }
    return localPosition.dx >= (width - widget.edgeWidth);
  }

  bool _isBackDirection(double dx) {
    // LTR back: +dx. RTL back: -dx.
    if (!_isRtl) return dx > 0;
    return dx < 0;
  }

  NavigatorState? _resolveNavigator() {
    final keyed = widget.navigatorKey?.currentState;
    if (keyed != null) return keyed;

    return Navigator.maybeOf(context) ?? Navigator.maybeOf(context, rootNavigator: true);
  }

  Future<void> _performExit() async {
    if (widget.onExit != null) {
      widget.onExit!.call();
      return;
    }

    final nav = _resolveNavigator();
    if (nav == null) return;

    if (nav.canPop()) {
      if (widget.hapticOnPop && !kIsWeb) {
        HapticFeedback.selectionClick();
      }
      await nav.maybePop();
      return;
    }

    if (widget.goHomeIfCantPop) {
      nav.pushNamedAndRemoveUntil(widget.fallbackToHomeRoute, (r) => false);
    }
  }

  void _animateTo(double target) {
    _settleCtrl.stop();
    _settleAnim = Tween<double>(begin: _progress, end: target).animate(
      CurvedAnimation(parent: _settleCtrl, curve: Curves.easeOutCubic),
    );
    _settleCtrl
      ..value = 0
      ..forward();
  }

  void _cancelGesture({bool animate = true}) {
    if (animate) {
      _animateTo(0);
    } else {
      _settleCtrl.stop();
      _progress = 0;
      _hintOffset = 0;
    }
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    // Optional: if you ever see iOS conflict with native back swipe, flip allowOnIOS=false.
    if (_isIOS && !widget.allowOnIOS) return widget.child;

    final supportedDevices = <PointerDeviceKind>{
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.stylus,
      PointerDeviceKind.unknown,
    };

    // Web: often lower fling velocity
    final minDistance = kIsWeb ? (widget.minDistance * 0.75) : widget.minDistance;
    final minVelocity = kIsWeb ? (widget.minVelocity * 0.55) : widget.minVelocity;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Derived visuals
        final p = _progress.clamp(0.0, 1.0);
        final overlayOpacity = widget.animatedHint ? (widget.hintMaxDim.clamp(0.0, 0.25) * p) : 0.0;
        final glowOpacity = widget.animatedHint ? (widget.edgeGlowMaxOpacity.clamp(0.0, 0.45) * p) : 0.0;

        final sign = _isRtl ? -1.0 : 1.0;

        // Edge glow strip width grows slightly with progress (premium)
        final glowWidth = (widget.edgeWidth + 26 * Curves.easeOut.transform(p)).clamp(widget.edgeWidth, widget.edgeWidth + 28);

        Widget content = widget.child;

        if (widget.animatedHint) {
          content = Stack(
            fit: StackFit.passthrough,
            children: [
              // Parallax translate
              Transform.translate(
                offset: Offset(_hintOffset, 0),
                child: widget.child,
              ),

              // Subtle dim
              if (overlayOpacity > 0)
                IgnorePointer(
                  child: Container(color: Colors.black.withOpacity(overlayOpacity)),
                ),

              // Edge glow (gold-ish by using white with opacity, it will pick up theme behind glass)
              if (glowOpacity > 0)
                IgnorePointer(
                  child: Align(
                    alignment: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: glowWidth,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
                          end: _isRtl ? Alignment.centerLeft : Alignment.centerRight,
                          colors: [
                            Colors.white.withOpacity(glowOpacity),
                            Colors.white.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Tiny chevron hint (only when user started the gesture)
              if (p > 0.02)
                IgnorePointer(
                  child: Align(
                    alignment: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: _isRtl ? 0 : 10,
                        right: _isRtl ? 10 : 0,
                      ),
                      child: Opacity(
                        opacity: (p * 1.2).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(sign * (6 + 10 * p), 0),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            size: 26,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            _downLocalPos = e.localPosition;
          },
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: <Type, GestureRecognizerFactory>{
              HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
                    () => HorizontalDragGestureRecognizer(debugOwner: this),
                    (HorizontalDragGestureRecognizer instance) {
                  instance
                    ..supportedDevices = supportedDevices
                    ..dragStartBehavior = DragStartBehavior.down
                    ..onStart = (d) {
                      _settleCtrl.stop();
                      _reset();

                      final startPos = _downLocalPos ?? d.localPosition;
                      if (!_isNearStartEdge(startPos, width)) return;

                      _armed = true;
                      _progress = 0;
                      _hintOffset = 0;
                    }
                    ..onUpdate = (d) {
                      if (!_armed) return;

                      _dx += d.delta.dx;
                      _dy += d.delta.dy;

                      // Direction guard (ignore wrong direction early)
                      if (widget.onlySwipeFromStartToEnd && !_isBackDirection(_dx)) {
                        // If they swiped opposite direction, cancel quickly
                        _cancelGesture(animate: true);
                        return;
                      }

                      // Vertical scroll guard: if user is mostly vertical, cancel to avoid conflicts
                      final absDx = _dx.abs();
                      final absDy = _dy.abs();
                      if (absDy > absDx * 0.90 && absDy > 6) {
                        _cancelGesture(animate: true);
                        return;
                      }

                      // Compute interactive progress with rubber band
                      final raw = absDx;
                      final resisted = _applyRubberBand(raw, width);
                      final nextProgress = (resisted / width).clamp(0.0, 1.0);

                      if (nextProgress != _progress && mounted) {
                        setState(() {
                          _progress = nextProgress;
                          _hintOffset = _progressToHintOffset(_progress);
                        });
                      }
                    }
                    ..onEnd = (d) async {
                      if (!_armed) return;
                      _armed = false;

                      final absDx = _dx.abs();
                      final absDy = _dy.abs();

                      // If vertical dominated near the end, cancel
                      if (absDy > absDx * 0.85) {
                        _cancelGesture(animate: true);
                        return;
                      }

                      // Velocity + distance checks
                      final vx = d.velocity.pixelsPerSecond.dx;
                      final vxIsBack = _isBackDirection(vx);

                      final enoughDistance = absDx >= minDistance;
                      final enoughVelocity = vxIsBack && vx.abs() >= minVelocity;

                      // Also use progress threshold for “iOS-like” feel
                      final enoughProgress = _progress >= widget.popProgressThreshold;

                      if (!(enoughDistance || enoughVelocity || enoughProgress)) {
                        _cancelGesture(animate: true);
                        return;
                      }

                      // Snap visuals to 1 quickly before pop (feels crisp)
                      if (widget.animatedHint) {
                        // fast settle to 1
                        _settleCtrl.duration = const Duration(milliseconds: 120);
                        _animateTo(1);
                        // restore duration
                        _settleCtrl.duration = const Duration(milliseconds: 190);
                      }

                      await _performExit();

                      // Reset visuals (in case route didn’t pop)
                      if (mounted) {
                        _cancelGesture(animate: false);
                      }
                    }
                    ..onCancel = () {
                      _cancelGesture(animate: true);
                    };
                },
              ),
            },
            child: content,
          ),
        );
      },
    );
  }
}
