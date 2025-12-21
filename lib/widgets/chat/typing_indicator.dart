import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, kDebugMode;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum TypingAvatarGender { male, female, other }

///  supports "typing" and "recording voice"
enum ChatActivityIndicatorMode { typing, recording }

class TypingIndicator extends StatefulWidget {
  final bool isVisible;
  final String text;

  /// Gender of the user who is typing (fallback only).
  final TypingAvatarGender gender;

  /// Avatar type of the user who is typing (PRIMARY selector).
  /// Expected values: "bear", "smurf" (case-insensitive).
  final String? avatarType;

  /// controls indicator animation (dots vs waveform)
  final ChatActivityIndicatorMode mode;

  const TypingIndicator({
    super.key,
    required this.isVisible,
    required this.text,
    this.gender = TypingAvatarGender.other,
    this.avatarType,
    this.mode = ChatActivityIndicatorMode.typing,
  });

  bool get isRecording => mode == ChatActivityIndicatorMode.recording;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _avatarController;
  late final AnimationController _dotsController;

  bool _isFastMode = false;

  static const String _bearAssetPath = 'assets/typing/bear_keyboard.png';
  static const String _smurfAssetPath = 'assets/typing/smurf_keyboard.png';

  String _normalizeAvatarType(String? raw) {
    return (raw ?? '').toString().trim().toLowerCase();
  }

  String get _assetPath {
    // PRIMARY: avatarType (what the user selected)
    final t = _normalizeAvatarType(widget.avatarType);
    if (t == 'smurf') return _smurfAssetPath;
    if (t == 'bear') return _bearAssetPath;

    // FALLBACK: gender mapping
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

    _avatarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat();

    _isFastMode = widget.text.length > 14;

    // _log(
    //   'init gender=${widget.gender} avatarType=${widget.avatarType} mode=${widget.mode} asset=$_assetPath fast=$_isFastMode text="${widget.text}"',
    // );
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldType = _normalizeAvatarType(oldWidget.avatarType);
    final newType = _normalizeAvatarType(widget.avatarType);

    if (oldWidget.gender != widget.gender ||
        oldType != newType ||
        oldWidget.mode != widget.mode) {
      // _log(
      //   'changed gender ${oldWidget.gender} -> ${widget.gender}, avatarType ${oldWidget.avatarType} -> ${widget.avatarType}, mode ${oldWidget.mode} -> ${widget.mode}, asset=$_assetPath',
      // );
    }

    final isNowFast = widget.text.length > 14;
    if (isNowFast != _isFastMode) {
      _isFastMode = isNowFast;

      _avatarController.duration = _isFastMode
          ? const Duration(milliseconds: 520)
          : const Duration(milliseconds: 900);
      _avatarController
        ..reset()
        ..repeat();

      _dotsController.duration = _isFastMode
          ? const Duration(milliseconds: 700)
          : const Duration(milliseconds: 950);
      _dotsController
        ..reset()
        ..repeat();

      // _log('fastMode changed -> $_isFastMode');
    }
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  Widget build(BuildContext context) {
    final assetKey = _assetPath;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: widget.isVisible
          ? LayoutBuilder(
        // IMPORTANT: force rebuild when avatar changes
        key: ValueKey(
          'typing-visible::$assetKey::mode=${widget.mode.name}',
        ),
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final availableW = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : media.size.width;

          final maxBubbleWidth = availableW * 0.88;
          final avatarSize = _clamp(availableW * 0.14, 56, 74);
          final neededHeight = avatarSize + 20;
          double scale = 1.0;
          if (constraints.hasBoundedHeight &&
              constraints.maxHeight > 0 &&
              constraints.maxHeight < neededHeight) {
            scale =
                _clamp(constraints.maxHeight / neededHeight, 0.55, 1.0);
          }

          final enableBlur = !kIsWeb;
          final blurSigma = _isFastMode ? 9.0 : 10.0;

          final bubble = KeyedSubtree(
            // extra safety: rebuild bubble when asset/mode changes
            key: ValueKey(
              'typing-bubble::$assetKey::mode=${widget.mode.name}',
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: enableBlur
                    ? BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: _buildBubble(avatarSize, assetKey),
                )
                    : _buildBubble(avatarSize, assetKey),
              ),
            ),
          );

          final semanticsFallback =
          widget.isRecording ? 'Recording voice' : 'Typing';

          return Semantics(
            label: widget.text.isNotEmpty ? widget.text : semanticsFallback,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 16, 8),
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

  Widget _buildBubble(double avatarSize, String assetPath) {
    // cache-busting key based on the actual asset path
    final cacheKey = ValueKey('typingAsset:$assetPath');

    return DecoratedBox(
      decoration: mwTypingGlassDecoration(radius: 18),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 14, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _avatarController,
              builder: (context, child) {
                final t = _avatarController.value * math.pi * 2;

                final bounceY = -math.sin(t) * (_isFastMode ? 2.2 : 1.6);
                final shakeX = _isFastMode ? math.sin(t * 2) * 0.6 : 0.0;
                final tilt = math.sin(t) * (_isFastMode ? 0.055 : 0.035);
                final scale =
                    1.0 + (math.sin(t) * (_isFastMode ? 0.06 : 0.04));

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
                    width: avatarSize,
                    height: avatarSize,
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
                    assetPath,
                    key: cacheKey,
                    width: avatarSize,
                    height: avatarSize,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint(
                        '❌ TypingIndicator asset failed: $assetPath\n$error',
                      );
                      return Icon(
                        Icons.keyboard,
                        size: _clamp(avatarSize * 0.75, 32, 44),
                        color: kTextSecondary,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // waveform for recording, dots for typing
            widget.isRecording
                ? _RecordingWaves(controller: _dotsController)
                : _TypingDots(controller: _dotsController),
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

///  Recording indicator (audio waveform bars) using same gold neon styling
class _RecordingWaves extends StatelessWidget {
  final AnimationController controller;
  const _RecordingWaves({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value * math.pi * 2;

        Widget bar(double phase) {
          final a = (math.sin(t + phase) * 0.5 + 0.5).clamp(0.0, 1.0);
          final h = 6.0 + (a * 10.0); // 6..16
          final opacity = 0.35 + (a * 0.65);

          return Opacity(
            opacity: opacity,
            child: Container(
              width: 3.2,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.8),
              decoration: BoxDecoration(
                color: kPrimaryGold.withOpacity(0.95),
                borderRadius: BorderRadius.circular(99),
                boxShadow: [
                  BoxShadow(
                    color: kGoldDeep.withOpacity(0.14),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            bar(0.0),
            bar(1.2),
            bar(2.4),
            bar(3.6),
          ],
        );
      },
    );
  }
}
