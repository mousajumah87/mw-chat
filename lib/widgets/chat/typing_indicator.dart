import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum TypingAvatarGender { male, female, other }

/// Supports "typing" and "recording voice".
enum ChatActivityIndicatorMode { typing, recording }

class TypingIndicator extends StatefulWidget {
  final bool isVisible;
  final String text;

  /// Fallback only if avatarType is missing.
  final TypingAvatarGender gender;

  /// Expected values: "bear", "smurf" (case-insensitive).
  final String? avatarType;

  /// Controls indicator animation (dots vs waveform).
  final ChatActivityIndicatorMode mode;

  /// Fixed reserved height to avoid layout jumping.
  final double height;

  /// Horizontal padding for the activity bar.
  final EdgeInsetsGeometry padding;

  /// Whether to draw a subtle top divider.
  final bool showTopDivider;

  const TypingIndicator({
    super.key,
    required this.isVisible,
    required this.text,
    this.gender = TypingAvatarGender.other,
    this.avatarType,
    this.mode = ChatActivityIndicatorMode.typing,
    this.height = 34,
    this.padding = const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 4),
    this.showTopDivider = false,
  });

  bool get isRecording => mode == ChatActivityIndicatorMode.recording;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _presenceController;
  late final AnimationController _activityController;

  static const String _bearAssetPath = 'assets/typing/bear_keyboard.png';
  static const String _smurfAssetPath = 'assets/typing/smurf_keyboard.png';

  String _normalizeAvatarType(String? raw) {
    return (raw ?? '').trim().toLowerCase();
  }

  String get _assetPath {
    final t = _normalizeAvatarType(widget.avatarType);
    if (t == 'smurf') return _smurfAssetPath;
    if (t == 'bear') return _bearAssetPath;

    switch (widget.gender) {
      case TypingAvatarGender.female:
        return _smurfAssetPath;
      case TypingAvatarGender.male:
      case TypingAvatarGender.other:
        return _bearAssetPath;
    }
  }

  void _log(String msg) {
    if (!kDebugMode) return;
    debugPrint('[TypingIndicator] $msg');
  }

  @override
  void initState() {
    super.initState();

    _presenceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.isVisible ? 1 : 0,
    );

    _activityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _presenceController.forward();
      } else {
        _presenceController.reverse();
      }
    }

    if (oldWidget.mode != widget.mode) {
      _activityController
        ..reset()
        ..repeat();
    }

    final oldType = _normalizeAvatarType(oldWidget.avatarType);
    final newType = _normalizeAvatarType(widget.avatarType);
    if (oldType != newType || oldWidget.gender != widget.gender) {
      _log('avatar changed: $_assetPath');
    }
  }

  @override
  void dispose() {
    _presenceController.dispose();
    _activityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semanticsFallback =
    widget.isRecording ? 'Recording voice' : 'Typing';

    return Semantics(
      label: widget.text.isNotEmpty ? widget.text : semanticsFallback,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: widget.showTopDivider
                ? Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.05),
                width: 0.8,
              ),
            )
                : null,
          ),
          child: FadeTransition(
            opacity: _presenceController,
            child: AnimatedBuilder(
              animation: _presenceController,
              builder: (context, child) {
                final slideY = (1 - _presenceController.value) * 5.0;

                return Transform.translate(
                  offset: Offset(0, slideY),
                  child: IgnorePointer(
                    ignoring: !widget.isVisible,
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: widget.padding,
                child: Row(
                  children: [
                    _CompactAvatar(
                      assetPath: _assetPath,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.96),
                          fontSize: 13.4,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 2.5,
                              offset: const Offset(0, 0.6),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    RepaintBoundary(
                      child: widget.isRecording
                          ? _RecordingWaves(controller: _activityController)
                          : _TypingDots(controller: _activityController),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactAvatar extends StatelessWidget {
  final String assetPath;

  const _CompactAvatar({
    required this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 18;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.12),
        border: Border.all(
          color: kPrimaryGold.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      child: ClipOval(
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('❌ TypingIndicator asset failed: $assetPath\n$error');
            return Icon(
              Icons.more_horiz_rounded,
              size: 13,
              color: kTextSecondary,
            );
          },
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
    return SizedBox(
      width: 24,
      height: 12,
      child: AnimatedBuilder(
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
            final scale = 0.82 + (a * 0.28);

            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: kPrimaryGold.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kGoldDeep.withValues(alpha: 0.10),
                        blurRadius: 5,
                        spreadRadius: 0.2,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [dot(0), dot(1), dot(2)],
          );
        },
      ),
    );
  }
}

class _RecordingWaves extends StatelessWidget {
  final AnimationController controller;

  const _RecordingWaves({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 14,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value * math.pi * 2;

          Widget bar(double phase) {
            final a = (math.sin(t + phase) * 0.5 + 0.5).clamp(0.0, 1.0);
            final h = 4.0 + (a * 7.0);
            final opacity = 0.35 + (a * 0.65);

            return Align(
              alignment: Alignment.bottomCenter,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 2.6,
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: kPrimaryGold.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: kGoldDeep.withValues(alpha: 0.10),
                        blurRadius: 5,
                        spreadRadius: 0.2,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              bar(0.0),
              bar(1.0),
              bar(2.0),
              bar(3.0),
            ],
          );
        },
      ),
    );
  }
}