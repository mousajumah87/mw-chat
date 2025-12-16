// lib/widgets/chat/chat_input_bar.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../ui/mw_feedback.dart'; // ✅ shared feedback helper (SnackBar/dialog fallback)

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final ValueChanged<String>? onTextChanged;

  // Voice note extras
  final bool isRecording;
  final Duration? recordDuration;
  final VoidCallback? onMicLongPressStart;
  final VoidCallback? onMicLongPressEnd;
  final VoidCallback? onMicCancel;

  // upload progress for media (0..1), null = no upload
  final double? uploadProgress;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.onAttach,
    required this.onSend,
    this.onTextChanged,
    this.isRecording = false,
    this.recordDuration,
    this.onMicLongPressStart,
    this.onMicLongPressEnd,
    this.onMicCancel,
    this.uploadProgress,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  bool _hasText = false;

  final FocusNode _messageFocusNode = FocusNode(debugLabel: 'chatInput');

  double _dragDistance = 0;
  bool _isLocked = false;

  late final AnimationController _waveController;

  bool _disposed = false;

  bool get _isUploading =>
      widget.uploadProgress != null && widget.uploadProgress! < 1.0;

  bool get _uiLocked => widget.sending || _isUploading;

  /// When recording is locked, we still show the full recording bar UI
  bool get _showRecordingBar => widget.isRecording || _isLocked;

  // ✅ Optional: consistent feedback (SnackBar if possible, else dialog).
  // Not used right now (keeps behavior unchanged), but ready if you need it later.
  Future<void> _toast(String message) async {
    if (!mounted || _disposed) return;
    await MwFeedback.show(context, message: message);
  }

  @override
  void initState() {
    super.initState();
    _syncTextState();
    widget.controller.addListener(_syncTextState);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    if (widget.isRecording) {
      _waveController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If recording toggled, manage animation
    if (oldWidget.isRecording != widget.isRecording) {
      if (widget.isRecording) {
        _waveController.repeat(reverse: true);
      } else {
        _waveController.stop();
        // When recording ends, also drop lock state
        if (_isLocked) {
          _isLocked = false;
          _dragDistance = 0;
          if (mounted && !_disposed) setState(() {});
        }
      }
    }

    // Keep text state accurate when controller content changes externally
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncTextState);
      widget.controller.addListener(_syncTextState);
      _syncTextState();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller.removeListener(_syncTextState);
    _messageFocusNode.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _syncTextState() {
    if (_disposed) return;
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText && mounted) {
      setState(() => _hasText = hasText);
    }
  }

  String _formatDuration(Duration? d) {
    final duration = d ?? Duration.zero;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _handleSendPressed() {
    if (_uiLocked) return;
    widget.onSend();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      _messageFocusNode.requestFocus();
    });
  }

  /// ✅ IMPORTANT: hide keyboard before opening attachment UI (iOS/Android safe)
  Future<void> _handleAttachPressed() async {
    if (_uiLocked) return;

    if (_messageFocusNode.hasFocus) _messageFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    if (!mounted || _disposed) return;
    widget.onAttach();
  }

  Widget _buildWaveform() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (_, __) {
        final v = _waveController.value;

        // Softer waveform colors (match MW theme, no neon green)
        final base = kTextSecondary.withOpacity(0.35);
        final active = kPrimaryGold.withOpacity(0.95);

        return Row(
          children: List.generate(7, (i) {
            final h = 10 + (v * 14) * (i.isEven ? 1 : 0.6);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: h,
              decoration: BoxDecoration(
                color: i >= 4 ? base : active,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildGoldCircleButton({
    required VoidCallback? onTap,
    required IconData icon,
    double size = 44,
    double iconSize = 22,
  }) {
    final enabled = onTap != null && !_uiLocked;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? kPrimaryGold.withOpacity(0.95)
              : kSurfaceAltColor.withOpacity(0.55),
          border: Border.all(
            color: enabled
                ? kGoldDeep.withOpacity(0.45)
                : kBorderColor.withOpacity(0.45),
          ),
          boxShadow: [
            if (enabled)
              BoxShadow(
                color: kGoldDeep.withOpacity(0.20),
                blurRadius: 14,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: enabled ? Colors.black : Colors.white38,
        ),
      ),
    );
  }

  Widget _buildFullRecordingBar() {
    // Dark glass bar with subtle red border (like your screenshot)
    final barBg = kSurfaceAltColor.withOpacity(0.78);
    final barBorder = Colors.redAccent.withOpacity(0.40);

    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: barBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: barBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uiLocked
                ? null
                : () {
              widget.onMicCancel?.call();
              _resetRecordingUi();
            },
            child: Icon(Icons.close, color: Colors.white.withOpacity(0.92)),
          ),
          const SizedBox(width: 12),
          Icon(Icons.mic, color: Colors.redAccent.withOpacity(0.90)),
          const SizedBox(width: 10),
          _buildWaveform(),
          const SizedBox(width: 12),
          Text(
            _formatDuration(widget.recordDuration),
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),

          // ✅ Send button: MW gold theme (instead of blue)
          _buildGoldCircleButton(
            onTap: _uiLocked
                ? null
                : () {
              widget.onMicLongPressEnd?.call();
              _resetRecordingUi();
            },
            icon: Icons.send,
            size: 46,
            iconSize: 22,
          ),
        ],
      ),
    );
  }

  void _resetRecordingUi() {
    _dragDistance = 0;
    _isLocked = false;
    if (mounted && !_disposed) setState(() {});
  }

  Widget _buildMicButton() {
    // Disabled UI if uploading/sending
    if (_uiLocked) {
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: kBorderColor.withOpacity(0.35)),
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white38),
      );
    }

    // Web: toggle-style mic
    if (kIsWeb) {
      return GestureDetector(
        onTap: () {
          if (_uiLocked) return;
          if (widget.isRecording) {
            widget.onMicLongPressEnd?.call();
            _resetRecordingUi();
          } else {
            _messageFocusNode.unfocus();
            widget.onMicLongPressStart?.call();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.isRecording
                ? Colors.redAccent.withOpacity(0.22)
                : Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
            border: Border.all(color: kBorderColor.withOpacity(0.35)),
          ),
          child: Icon(
            widget.isRecording ? Icons.stop : Icons.mic_rounded,
            color: Colors.white.withOpacity(0.92),
          ),
        ),
      );
    }

    // Mobile: press/drag behavior
    return Listener(
      onPointerDown: (_) {
        if (_uiLocked) return;
        if (widget.isRecording) return;
        _dragDistance = 0;
        _isLocked = false;
        _messageFocusNode.unfocus();
        widget.onMicLongPressStart?.call();
        if (mounted && !_disposed) setState(() {});
      },
      onPointerMove: (e) {
        if (_uiLocked) return;
        if (!widget.isRecording && !_isLocked) return;

        _dragDistance += e.delta.dx;

        // swipe left to cancel
        if (_dragDistance < -40 && !_isLocked) {
          widget.onMicCancel?.call();
          _resetRecordingUi();
          return;
        }

        // swipe up to lock
        if (e.delta.dy < -8 && !_isLocked) {
          _isLocked = true;
          if (mounted && !_disposed) setState(() {});
        }
      },
      onPointerUp: (_) {
        if (_uiLocked) return;

        // If locked, keep recording until send/cancel
        if (_isLocked) {
          if (mounted && !_disposed) setState(() {});
          return;
        }

        // Normal release sends
        if (widget.isRecording) {
          widget.onMicLongPressEnd?.call();
        }
        _resetRecordingUi();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: kBorderColor.withOpacity(0.35)),
        ),
        child: Icon(Icons.mic_rounded, color: Colors.white.withOpacity(0.92)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool isUploading = _isUploading;

    final textScale = MediaQuery.textScalerOf(context);
    final baseFont = textScale.scale(16);
    final effectiveFont = baseFont < 16 ? 16.0 : baseFont;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUploading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LinearProgressIndicator(value: widget.uploadProgress),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: kChatInputBarBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kChatInputBarBorder.withOpacity(0.55)),
            ),
            child: _showRecordingBar
                ? _buildFullRecordingBar()
                : Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  color: Colors.white70,
                  onPressed: _uiLocked ? null : _handleAttachPressed,
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat_input_textfield'),
                    controller: widget.controller,
                    focusNode: _messageFocusNode,
                    onChanged: widget.onTextChanged,
                    onSubmitted: (_) => _handleSendPressed(),
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: effectiveFont,
                      height: 1.25,
                    ),
                    keyboardAppearance: Brightness.dark,
                    decoration: InputDecoration(
                      hintText: l10n.typeMessageHint,
                      hintStyle: TextStyle(
                        color: Colors.white54,
                        fontSize: effectiveFont - 1,
                      ),
                      filled: true,
                      fillColor: kChatInputFieldBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (_hasText || widget.sending || isUploading)
                  _buildGoldCircleButton(
                    onTap: _uiLocked ? null : _handleSendPressed,
                    icon: Icons.send,
                    size: 44,
                    iconSize: 20,
                  )
                else
                  _buildMicButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
