// lib/widgets/chat/typing_indicator.dart
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

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: 4),
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: kTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
