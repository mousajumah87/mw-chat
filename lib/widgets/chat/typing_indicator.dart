import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class TypingIndicator extends StatelessWidget {
  final bool isVisible;
  final String text;

  const TypingIndicator({
    super.key,
    required this.isVisible,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

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
              const _AnimatedDot(delay: 0),
              const SizedBox(width: 3),
              const _AnimatedDot(delay: 200),
              const SizedBox(width: 3),
              const _AnimatedDot(delay: 400),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
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

class _AnimatedDot extends StatefulWidget {
  final int delay;
  const _AnimatedDot({required this.delay});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Apply offset for staggered animation
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward(from: 0.3);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const CircleAvatar(
        radius: 2.8,
        backgroundColor: kTextSecondary,
      ),
    );
  }
}
