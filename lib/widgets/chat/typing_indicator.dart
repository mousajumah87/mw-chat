// lib/widgets/chat/typing_indicator.dart

import 'dart:math';
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
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _shake;

  bool _isFastMode = false;

  // Correct PNG asset path
  static const String _bearAssetPath =
      'assets/typing/bear_keyboard.png';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _shake = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ Auto-detect fast typing
    final isNowFast = widget.text.length > 14;

    if (isNowFast != _isFastMode) {
      _isFastMode = isNowFast;

      _controller.duration = _isFastMode
          ? const Duration(milliseconds: 420) // ⚡ FAST
          : const Duration(milliseconds: 900); // 🐻 NORMAL

      _controller
        ..reset()
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final maxWidth = MediaQuery.of(context).size.width * 0.8;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(left: 18, right: 16, bottom: 8, top: 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 🐻 Typing Bear (Safe + Fast Mode)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(
                      _isFastMode
                          ? _shake.value * Random().nextDouble()
                          : 0,
                      0,
                    ),
                    child: Transform.scale(
                      scale: _scale.value,
                      child: child,
                    ),
                  );
                },
                child: Image.asset(
                  _bearAssetPath,
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,

                  // Final safety net (no red errors ever)
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint(
                      '❌ TypingIndicator asset failed to load: $_bearAssetPath\n$error',
                    );
                    return const Icon(
                      Icons.keyboard,
                      size: 32,
                      color: kTextSecondary,
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Your existing typing text (unchanged)
              Flexible(
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: kTextSecondary,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
