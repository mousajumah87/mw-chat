// lib/widgets/ui/mw_swipe_back.dart
//
// MW Chat – MW Signature SwipeBack (edge-only gesture)
// ✅ Clean production version (NO logs, NO debug overlay)
// ✅ Works globally with MaterialApp.builder + navigatorKey
// ✅ Edge-only participation (doesn't steal scrolls)
// ✅ RTL/LTR aware
// ✅ MW “signature” gold shimmer + tiny MW bubble hint (optional)

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MwSwipeBack extends StatefulWidget {
  final Widget child;

  /// If provided, runs instead of Navigator.pop.
  final VoidCallback? onExit;

  /// Required when wrapping whole app in MaterialApp.builder.
  final GlobalKey<NavigatorState>? navigatorKey;

  final bool enabled;

  /// Edge width area to arm the gesture.
  final double edgeWidth;

  final double minDistance;
  final double minVelocity;

  final bool goHomeIfCantPop;
  final String fallbackToHomeRoute;

  final bool onlySwipeFromStartToEnd;

  /// Haptic on arm + pop
  final bool hapticOnPop;

  /// Animated parallax + dim
  final bool animatedHint;
  final double hintMaxSlide;
  final double hintMaxDim;

  /// Edge glow
  final double edgeGlowMaxOpacity;

  /// 0..1 progress threshold that can also pop (feels iOS-like).
  final double popProgressThreshold;

  /// Keep true (recommended). If you ever see conflict with Cupertino back, set false.
  final bool allowOnIOS;

  /// ✅ MW Signature “brand moment”
  /// - tiny MW bubble hint + gold shimmer near edge while swiping
  final bool mwSignatureHint;

  /// Customize MW signature intensity
  final double mwSignatureMaxOpacity; // 0..1
  final double mwBubbleMaxScale; // e.g. 1.0..1.15

  const MwSwipeBack({
    super.key,
    required this.child,
    this.onExit,
    this.navigatorKey,
    this.enabled = true,
    this.edgeWidth = 32,
    this.minDistance = 70,
    this.minVelocity = 700,
    this.goHomeIfCantPop = false,
    this.fallbackToHomeRoute = "/home",
    this.onlySwipeFromStartToEnd = true,
    this.hapticOnPop = true,
    this.animatedHint = true,
    this.hintMaxSlide = 30,
    this.hintMaxDim = 0.07,
    this.edgeGlowMaxOpacity = 0.22,
    this.popProgressThreshold = 0.26,
    this.allowOnIOS = true,
    this.mwSignatureHint = true,
    this.mwSignatureMaxOpacity = 0.85,
    this.mwBubbleMaxScale = 1.10,
  });

  @override
  State<MwSwipeBack> createState() => _MwSwipeBackState();
}

/// HorizontalDrag recognizer that ONLY competes if DOWN is near the start edge.
/// This is the key to making it work with scrollables on iOS/Android.
class _EdgeHorizontalDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  _EdgeHorizontalDragGestureRecognizer({
    required this.getBox,
    required this.getIsRtl,
    required this.getEdgeWidth,
    Object? debugOwner,
  }) : super(debugOwner: debugOwner);

  final RenderBox? Function() getBox;
  final bool Function() getIsRtl;
  final double Function() getEdgeWidth;

  @override
  void addPointer(PointerDownEvent event) {
    final box = getBox();
    if (box == null || !box.hasSize) return;

    final local = box.globalToLocal(event.position);
    final w = box.size.width;
    final edge = getEdgeWidth();

    final isRtl = getIsRtl();
    final nearEdge = !isRtl ? (local.dx <= edge) : (local.dx >= (w - edge));

    if (!nearEdge) return; // don't compete
    super.addPointer(event);
  }
}

class _MwSwipeBackState extends State<MwSwipeBack> with SingleTickerProviderStateMixin {
  final GlobalKey _boxKey = GlobalKey();

  double _dx = 0;
  double _dy = 0;
  bool _armed = false;

  double _progress = 0; // 0..1
  double _hintOffset = 0;

  late final AnimationController _settleCtrl;
  late Animation<double> _settleAnim;

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  // small “arm haptic” to make it feel premium (avoid spam)
  bool _didArmHaptic = false;

  @override
  void initState() {
    super.initState();

    _settleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
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

  void _resetGesture() {
    _dx = 0;
    _dy = 0;
    _armed = false;
    _didArmHaptic = false;
  }

  RenderBox? _getRootBox() {
    final ctx = _boxKey.currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is RenderBox && ro.hasSize) return ro;
    return null;
  }

  double _progressToHintOffset(double p) {
    if (!widget.animatedHint) return 0;
    final maxSlide = widget.hintMaxSlide <= 0 ? 1.0 : widget.hintMaxSlide;
    final sign = _isRtl ? -1.0 : 1.0;
    final eased = Curves.easeOutCubic.transform(p.clamp(0.0, 1.0));
    return sign * (maxSlide * eased).clamp(0.0, maxSlide);
  }

  bool _isBackDirection(double dx) => _isRtl ? dx < 0 : dx > 0;

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

  void _cancel({bool animate = true}) {
    if (animate) {
      _animateTo(0);
    } else {
      _settleCtrl.stop();
      _progress = 0;
      _hintOffset = 0;
    }
    _resetGesture();
  }

  @override
  Widget build(BuildContext context) {
    if (_isIOS && !widget.allowOnIOS) return widget.child;

    final minDistance = kIsWeb ? widget.minDistance * 0.75 : widget.minDistance;
    final minVelocity = kIsWeb ? widget.minVelocity * 0.55 : widget.minVelocity;

    final supportedDevices = <PointerDeviceKind>{
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.stylus,
      PointerDeviceKind.unknown,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;

        final p = _progress.clamp(0.0, 1.0);
        final overlayOpacity =
        widget.animatedHint ? (widget.hintMaxDim.clamp(0.0, 0.25) * p) : 0.0;
        final glowOpacity =
        widget.animatedHint ? (widget.edgeGlowMaxOpacity.clamp(0.0, 0.45) * p) : 0.0;

        final sign = _isRtl ? -1.0 : 1.0;
        final glowWidth =
        (widget.edgeWidth + 26 * Curves.easeOut.transform(p)).clamp(
          widget.edgeWidth,
          widget.edgeWidth + 30,
        );

        // MW signature intensity (gold shimmer + bubble)
        final mwSigOn = widget.mwSignatureHint;
        final mwSigOpacity = (mwSigOn ? widget.mwSignatureMaxOpacity : 0.0).clamp(0.0, 1.0);
        final mwShimmerOpacity = (mwSigOpacity * Curves.easeOut.transform((p * 1.05).clamp(0.0, 1.0)))
            .clamp(0.0, mwSigOpacity);
        final mwBubbleOpacity = (mwSigOpacity * Curves.easeOut.transform((p * 1.2).clamp(0.0, 1.0)))
            .clamp(0.0, mwSigOpacity);
        final mwBubbleScale = (1.0 + (widget.mwBubbleMaxScale - 1.0) * Curves.easeOut.transform(p))
            .clamp(1.0, widget.mwBubbleMaxScale);

        Widget content = KeyedSubtree(
          key: _boxKey,
          child: widget.child,
        );

        if (widget.animatedHint) {
          content = Stack(
            fit: StackFit.passthrough,
            children: [
              Transform.translate(
                offset: Offset(_hintOffset, 0),
                child: content,
              ),
              if (overlayOpacity > 0)
                IgnorePointer(
                  child: Container(color: Colors.black.withOpacity(overlayOpacity)),
                ),

              // Base white edge glow
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

              // ✅ MW Signature gold shimmer (subtle, premium)
              if (mwSigOn && mwShimmerOpacity > 0.0)
                IgnorePointer(
                  child: Align(
                    alignment: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: (glowWidth + 14).clamp(glowWidth, glowWidth + 22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
                          end: _isRtl ? Alignment.centerLeft : Alignment.centerRight,
                          colors: [
                            const Color(0xFFFFD54A).withOpacity(mwShimmerOpacity * 0.55),
                            const Color(0xFFFFB300).withOpacity(mwShimmerOpacity * 0.35),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Chevron (direction aware)
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
                          child: Icon(
                            _isRtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                            size: 26,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ✅ MW tiny bubble hint (brand moment)
              if (mwSigOn && mwBubbleOpacity > 0.0)
                IgnorePointer(
                  child: Align(
                    alignment: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: _isRtl ? 0 : 10,
                        right: _isRtl ? 10 : 0,
                      ),
                      child: Transform.translate(
                        offset: Offset(sign * (6 + 18 * p), -22),
                        child: Opacity(
                          opacity: mwBubbleOpacity,
                          child: Transform.scale(
                            scale: mwBubbleScale,
                            child: _MwSignatureBubble(rtl: _isRtl),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        return RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: <Type, GestureRecognizerFactory>{
            _EdgeHorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_EdgeHorizontalDragGestureRecognizer>(
                  () => _EdgeHorizontalDragGestureRecognizer(
                debugOwner: this,
                getBox: _getRootBox,
                getIsRtl: () => _isRtl,
                getEdgeWidth: () => widget.enabled ? widget.edgeWidth : 0,
              ),
                  (_EdgeHorizontalDragGestureRecognizer instance) {
                instance
                  ..supportedDevices = supportedDevices
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = (_) {
                    if (!widget.enabled) return;

                    _settleCtrl.stop();
                    _resetGesture();

                    _armed = true;
                    _progress = 0;
                    _hintOffset = 0;

                    // Premium: tiny haptic once when gesture arms
                    if (widget.hapticOnPop && !kIsWeb && !_didArmHaptic) {
                      _didArmHaptic = true;
                      HapticFeedback.lightImpact();
                    }
                  }
                  ..onUpdate = (d) {
                    if (!_armed) return;

                    _dx += d.delta.dx;
                    _dy += d.delta.dy;

                    // Direction guard
                    if (widget.onlySwipeFromStartToEnd && !_isBackDirection(_dx)) {
                      _cancel(animate: true);
                      return;
                    }

                    // Vertical dominance guard (don’t break scrolling)
                    final absDx = _dx.abs();
                    final absDy = _dy.abs();
                    if (absDy > absDx * 0.90 && absDy > 6) {
                      _cancel(animate: true);
                      return;
                    }

                    // Compute progress
                    final next = (absDx / width).clamp(0.0, 1.0);

                    if (next != _progress && mounted) {
                      setState(() {
                        _progress = next;
                        _hintOffset = _progressToHintOffset(_progress);
                      });
                    }
                  }
                  ..onEnd = (d) async {
                    if (!_armed) return;
                    _armed = false;

                    final absDx = _dx.abs();
                    final absDy = _dy.abs();

                    if (absDy > absDx * 0.85) {
                      _cancel(animate: true);
                      return;
                    }

                    final vx = d.velocity.pixelsPerSecond.dx;
                    final vxIsBack = _isBackDirection(vx);

                    final enoughDistance = absDx >= minDistance;
                    final enoughVelocity = vxIsBack && vx.abs() >= minVelocity;
                    final enoughProgress = _progress >= widget.popProgressThreshold;

                    if (!(enoughDistance || enoughVelocity || enoughProgress)) {
                      _cancel(animate: true);
                      return;
                    }

                    if (widget.animatedHint) {
                      _settleCtrl.duration = const Duration(milliseconds: 110);
                      _animateTo(1);
                      _settleCtrl.duration = const Duration(milliseconds: 180);
                    }

                    await _performExit();

                    if (mounted) _cancel(animate: false);
                  }
                  ..onCancel = () {
                    _cancel(animate: true);
                  };
              },
            ),
          },
          child: content,
        );
      },
    );
  }
}

class _MwSignatureBubble extends StatelessWidget {
  final bool rtl;
  const _MwSignatureBubble({required this.rtl});

  @override
  Widget build(BuildContext context) {
    // Tiny “MW” bubble — feels like a signature without being loud.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.40),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            blurRadius: 16,
            spreadRadius: 0,
            color: const Color(0xFFFFD54A).withOpacity(0.12),
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            rtl ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_new_rounded,
            size: 12,
            color: Colors.white.withOpacity(0.85),
          ),
          const SizedBox(width: 6),
          Text(
            'MW',
            style: TextStyle(
              color: const Color(0xFFFFD54A).withOpacity(0.95),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
