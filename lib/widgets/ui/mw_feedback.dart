//lib/widgets/ui/mw_feedback.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';

enum _ToastKind { normal, success, error }

class MwFeedback {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static Future<void> show(
      BuildContext context, {
        required String message,
        Duration duration = const Duration(seconds: 2),
      }) =>
      _showToast(
        context,
        message: message,
        duration: duration,
        kind: _ToastKind.normal,
        haptic: false,
      );

  static Future<void> success(
      BuildContext context, {
        required String message,
        Duration duration = const Duration(seconds: 2),
      }) =>
      _showToast(
        context,
        message: message,
        duration: duration,
        kind: _ToastKind.success,
        haptic: true,
      );

  static Future<void> error(
      BuildContext context, {
        required String message,
        Duration duration = const Duration(seconds: 2),
      }) =>
      _showToast(
        context,
        message: message,
        duration: duration,
        kind: _ToastKind.error,
        haptic: true,
      );

  static Future<void> _showToast(
      BuildContext context, {
        required String message,
        required Duration duration,
        required _ToastKind kind,
        required bool haptic,
      }) async {
    if (!context.mounted) return;

    _remove();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      await _fallbackDialog(context, message);
      return;
    }

    if (haptic) _tryHaptic(kind);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    _entry = OverlayEntry(
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final bottomInset =
            (media.viewInsets.bottom > 0 ? media.viewInsets.bottom : media.padding.bottom) + 16;

        return IgnorePointer(
          ignoring: true,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: bottomInset,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _AnimatedToast(
                          child: _ToastPill(
                            message: message,
                            kind: kind,
                            cs: cs,
                            tt: tt,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(_entry!);
    _timer = Timer(duration, _remove);
  }

  static void _remove() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  static void _tryHaptic(_ToastKind kind) {
    // Safe on iOS/Android; do nothing on web.
    if (kIsWeb) return;
    try {
      if (kind == _ToastKind.error) {
        HapticFeedback.mediumImpact();
      } else if (kind == _ToastKind.success) {
        HapticFeedback.lightImpact();
      } else {
        // No haptic for normal
      }
    } catch (_) {
      // Ignore if platform doesn't support it.
    }
  }

  static Future<void> _fallbackDialog(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: Text(l10n?.ok ?? 'OK'),
          ),
        ],
      ),
    );
  }
}

class _AnimatedToast extends StatefulWidget {
  final Widget child;
  const _AnimatedToast({required this.child});

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _opacity = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

class _ToastPill extends StatelessWidget {
  final String message;
  final _ToastKind kind;
  final ColorScheme cs;
  final TextTheme tt;

  const _ToastPill({
    required this.message,
    required this.kind,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    final accent = switch (kind) {
      _ToastKind.success => cs.primary, // your gold primary
      _ToastKind.error => cs.error,
      _ToastKind.normal => cs.outline,
    };

    final icon = switch (kind) {
      _ToastKind.success => Icons.check_circle_rounded,
      _ToastKind.error => Icons.error_rounded,
      _ToastKind.normal => Icons.info_rounded,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Accent strip
          Container(
            width: 5,
            height: 54,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            ),
          ),
          const SizedBox(width: 10),

          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 10),
          // Replace Expanded with Flexible
          Flexible(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 14, 12),
              child: Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
