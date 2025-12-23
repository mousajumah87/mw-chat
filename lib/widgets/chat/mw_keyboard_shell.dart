import 'package:flutter/material.dart';

typedef OnBoolChanged = void Function(bool value);

class MeasureSize extends StatefulWidget {
  const MeasureSize({
    super.key,
    required this.onChange,
    required this.child,
  });

  final void Function(Size size) onChange;
  final Widget child;

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? _old;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ro = context.findRenderObject();
      if (ro is RenderBox) {
        final s = ro.size;
        if (_old == s) return;
        _old = s;
        widget.onChange(s);
      }
    });
    return widget.child;
  }
}

class MwKeyboardShell extends StatelessWidget {
  const MwKeyboardShell({
    super.key,
    required this.focusNode,
    required this.panelVisible,
    required this.panelHeight,
    required this.panel,
    required this.composer,
    required this.onPanelVisibilityChanged,
    this.above,
    this.duration = const Duration(milliseconds: 160),
    this.curve = Curves.easeOut,
  });

  final FocusNode focusNode;

  final bool panelVisible;
  final double panelHeight;
  final Widget panel;
  final Widget composer;

  final OnBoolChanged onPanelVisibilityChanged;

  final Widget? above;

  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final bool keyboardOpen = keyboard > 0;

    // If panel is visible, treat it like keyboard height
    final double raiseBy = panelVisible ? panelHeight : keyboard;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: duration,
        curve: curve,
        padding: EdgeInsets.only(bottom: raiseBy),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (above != null) above!,

            // SafeArea only when both keyboard + panel are closed (prevents gap)
            SafeArea(
              top: false,
              bottom: (!keyboardOpen && !panelVisible),
              child: composer,
            ),

            AnimatedContainer(
              duration: duration,
              curve: curve,
              height: panelVisible ? panelHeight : 0,
              child: panelVisible
                  ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: panel,
              )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
