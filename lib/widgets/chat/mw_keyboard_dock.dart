// lib/widgets/chat/mw_keyboard_dock.dart
import 'package:flutter/material.dart';

typedef OnSizeChanged = void Function(Size size);

/// ✅ Measures its child's size and reports it when it changes.
class MeasureSize extends StatefulWidget {
  const MeasureSize({
    super.key,
    required this.onChange,
    required this.child,
  });

  final OnSizeChanged onChange;
  final Widget child;

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox) {
        final newSize = renderObject.size;
        if (_oldSize == newSize) return;
        _oldSize = newSize;
        widget.onChange(newSize);
      }
    });

    return widget.child;
  }
}

/// ✅ Snapchat-like dock:
/// - Pins content to bottom
/// - Moves it exactly with the system keyboard (viewInsets.bottom)
/// - Applies SafeArea ONLY when keyboard is closed (no extra gap)
class MwKeyboardDock extends StatelessWidget {
  const MwKeyboardDock({
    super.key,
    required this.child,
    this.above,
    this.duration = const Duration(milliseconds: 160),
    this.curve = Curves.easeOut,
  });

  /// Optional widget shown above the dock (ex: TypingIndicator).
  final Widget? above;

  /// The pinned bottom content (your composer).
  final Widget child;

  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: duration,
        curve: curve,
        // ✅ Move whole dock up by keyboard height (system keyboard)
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (above != null) above!,
            // ✅ IMPORTANT:
            // Only apply bottom SafeArea when keyboard is CLOSED.
            // When keyboard is OPEN, SafeArea creates the unwanted gap.
            SafeArea(
              top: false,
              bottom: keyboard == 0,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
