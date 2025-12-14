// lib/widgets/chat/typing_indicator.dart

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class TypingIndicator extends StatefulWidget {
  final bool isVisible;
  final String text;

  const TypingIndicator({
    super.key,
    required this.isVisible,
    required this.text,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _bearController;
  late final AnimationController _dotsController;

  bool _isFastMode = false;

  static const String _bearAssetPath = 'assets/typing/bear_keyboard.png';

  @override
  void initState() {
    super.initState();

    _bearController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    final isNowFast = widget.text.length > 14;

    if (isNowFast != _isFastMode) {
      _isFastMode = isNowFast;

      _bearController.duration =
      _isFastMode ? const Duration(milliseconds: 520) : const Duration(milliseconds: 900);
      _bearController
        ..reset()
        ..repeat();

      _dotsController.duration =
      _isFastMode ? const Duration(milliseconds: 700) : const Duration(milliseconds: 950);
      _dotsController
        ..reset()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _bearController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  Widget build(BuildContext context) {
    // If parent hides it, keep size stable when invisible to avoid layout jump
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: widget.isVisible
          ? LayoutBuilder(
        key: const ValueKey('typing-visible'),
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final availableW = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : media.size.width;

          final maxBubbleWidth = availableW * 0.88;

          // Bear size based on available width
          final bearSize = _clamp(availableW * 0.13, 50, 66);

          // Bubble padding totals (vertical) = 10(top) + 10(bottom)
          // But bear also has its own size → needed height roughly:
          final neededHeight = bearSize + 20;

          // If parent gives tiny height (your Web bug), scale bubble down instead of clipping
          double scale = 1.0;
          if (constraints.hasBoundedHeight &&
              constraints.maxHeight > 0 &&
              constraints.maxHeight < neededHeight) {
            scale = _clamp(constraints.maxHeight / neededHeight, 0.55, 1.0);
          }

          final enableBlur = !kIsWeb; // blur only on mobile by default
          final blurSigma = _isFastMode ? 9.0 : 10.0;

          final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            color: kTextSecondary,
            height: 1.15,
          ) ??
              const TextStyle(fontSize: 12.5, color: kTextSecondary, height: 1.15);

          final bubble = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: enableBlur
                  ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: _buildBubble(bearSize, textStyle),
              )
                  : _buildBubble(bearSize, textStyle),
            ),
          );

          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Transform.scale(
                  scale: scale,
                  alignment: AlignmentDirectional.centerStart,
                  child: bubble,
                ),
              ),
            ),
          );
        },
      )
          : const SizedBox(
        key: ValueKey('typing-hidden'),
        height: 0,
        width: 0,
      ),
    );
  }

  Widget _buildBubble(double bearSize, TextStyle textStyle) {
    return DecoratedBox(
      decoration: mwTypingGlassDecoration(radius: 18),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 14, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _bearController,
              builder: (context, child) {
                final t = _bearController.value * math.pi * 2;

                final bounceY = -math.sin(t) * (_isFastMode ? 2.2 : 1.6);
                final shakeX = _isFastMode ? math.sin(t * 3) * 1.8 : 0.0;
                final tilt = math.sin(t) * (_isFastMode ? 0.055 : 0.035);
                final scale = 1.0 + (math.sin(t) * (_isFastMode ? 0.06 : 0.04));

                return Transform.translate(
                  offset: Offset(shakeX, bounceY),
                  child: Transform.rotate(
                    angle: tilt,
                    child: Transform.scale(scale: scale, child: child),
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: bearSize,
                    height: bearSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kGoldDeep.withOpacity(0.22),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  Image.asset(
                    _bearAssetPath,
                    width: bearSize,
                    height: bearSize,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('❌ TypingIndicator asset failed: $_bearAssetPath\n$error');
                      return Icon(
                        Icons.keyboard,
                        size: _clamp(bearSize * 0.75, 32, 44),
                        color: kTextSecondary,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.text,
                      style: textStyle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _TypingDots(controller: _dotsController),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatelessWidget {
  final AnimationController controller;
  const _TypingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final v = controller.value;

        double dotPhase(int i) {
          final p = (v + (i * 0.18)) % 1.0;
          return (math.sin(p * math.pi)).clamp(0.0, 1.0);
        }

        Widget dot(int i) {
          final a = dotPhase(i);
          final opacity = 0.28 + (a * 0.72);
          final scale = 0.85 + (a * 0.35);

          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 4.6,
                height: 4.6,
                margin: const EdgeInsets.symmetric(horizontal: 1.6),
                decoration: BoxDecoration(
                  color: kPrimaryGold.withOpacity(0.95),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kGoldDeep.withOpacity(0.14),
                      blurRadius: 8,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [dot(0), dot(1), dot(2)],
        );
      },
    );
  }
}
