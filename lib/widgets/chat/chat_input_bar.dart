// lib/widgets/chat/chat_input_bar.dart

import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

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

  late AnimationController _waveController;

  bool get _isUploading =>
      widget.uploadProgress != null && widget.uploadProgress! < 1.0;

  bool get _uiLocked => widget.sending || _isUploading;

  @override
  void initState() {
    super.initState();
    _syncTextState();
    widget.controller.addListener(_syncTextState);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // ✅ only animate when recording (less CPU / smoother web)
    if (widget.isRecording) {
      _waveController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isRecording != widget.isRecording) {
      if (widget.isRecording) {
        _waveController.repeat(reverse: true);
      } else {
        _waveController.stop();
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncTextState);
    _messageFocusNode.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _syncTextState() {
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
      if (mounted) _messageFocusNode.requestFocus();
    });
  }

  /// ✅ IMPORTANT: hide keyboard before opening attachment UI (iOS/Android safe)
  Future<void> _handleAttachPressed() async {
    if (_uiLocked) return;

    if (_messageFocusNode.hasFocus) _messageFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    if (!mounted) return;
    widget.onAttach();
  }

  Widget _buildWaveform() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (_, __) {
        final v = _waveController.value;
        return Row(
          children: List.generate(7, (i) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: 10 + (v * 14) * (i.isEven ? 1 : 0.6),
              decoration: BoxDecoration(
                color: Colors.greenAccent,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildFullRecordingBar() {
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.15),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.redAccent.withOpacity(.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uiLocked ? null : widget.onMicCancel,
            child: const Icon(Icons.close, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.mic, color: Colors.redAccent),
          const SizedBox(width: 6),
          _buildWaveform(),
          const SizedBox(width: 10),
          Text(
            _formatDuration(widget.recordDuration),
            style: const TextStyle(color: Colors.white),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _uiLocked ? null : widget.onMicLongPressEnd,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent,
              ),
              child: const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    if (_uiLocked) {
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white38),
      );
    }

    if (kIsWeb) {
      return GestureDetector(
        onTap: () {
          if (widget.isRecording) {
            widget.onMicLongPressEnd?.call();
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
                ? Colors.redAccent.withOpacity(0.3)
                : Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.isRecording ? Icons.stop : Icons.mic_rounded,
            color: Colors.white,
          ),
        ),
      );
    }

    return Listener(
      onPointerDown: (_) {
        _dragDistance = 0;
        _isLocked = false;
        _messageFocusNode.unfocus();
        widget.onMicLongPressStart?.call();
        setState(() {});
      },
      onPointerMove: (e) {
        _dragDistance += e.delta.dx;

        if (_dragDistance < -40 && !_isLocked) {
          widget.onMicCancel?.call();
          _resetRecording();
          return;
        }

        if (e.delta.dy < -8 && !_isLocked) {
          _isLocked = true;
          setState(() {});
        }
      },
      onPointerUp: (_) {
        if (!_isLocked) {
          widget.onMicLongPressEnd?.call();
          _resetRecording();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white),
      ),
    );
  }

  void _resetRecording() {
    _dragDistance = 0;
    _isLocked = false;
    setState(() {});
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
              child: LinearProgressIndicator(
                value: widget.uploadProgress,
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111119),
              borderRadius: BorderRadius.circular(24),
            ),
            child: widget.isRecording
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
                      fillColor: Colors.white.withOpacity(0.04),
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
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: _uiLocked ? null : _handleSendPressed,
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
