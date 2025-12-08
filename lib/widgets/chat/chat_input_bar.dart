// lib/widgets/chat/chat_input_bar.dart

import 'dart:ui';
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
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _hasText = false;

  // ✅ KEYBOARD FOCUS FIX
  final FocusNode _messageFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _syncTextState();
    widget.controller.addListener(_syncTextState);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncTextState);
      widget.controller.addListener(_syncTextState);
      _syncTextState();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncTextState);
    _messageFocusNode.dispose(); // ✅ CLEANUP
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

  void _handleTextChanged(String value) {
    widget.onTextChanged?.call(value);
  }

  // ✅ ✅ ✅ SEND HANDLER THAT KEEPS KEYBOARD OPEN
  void _handleSendPressed() {
    if (widget.sending) return;

    widget.onSend();

    // ✅ KEEP KEYBOARD OPEN AFTER SEND
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _messageFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111119),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          // Attach
          IconButton(
            icon: const Icon(Icons.attach_file),
            color: Colors.white70,
            onPressed:
            widget.sending || widget.isRecording ? null : widget.onAttach,
          ),

          // ✅ TEXT FIELD WITH FOCUS FIX
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _messageFocusNode, // ✅ FIX HERE
              enabled: !widget.sending && !widget.isRecording,
              onChanged: _handleTextChanged,
              onSubmitted: (_) => _handleSendPressed(), // ✅ SEND FROM KEYBOARD
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.typeMessageHint,
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.25),
                    width: 1.3,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 4),

          // Right side
          if (widget.isRecording)
            _buildRecordingPill(theme)
          else
            _buildSendOrMic(theme),
        ],
      ),
    );
  }

  // NOW HAS SEND + CANCEL
  Widget _buildRecordingPill(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic, color: Colors.redAccent, size: 18),
          const SizedBox(width: 6),
          Text(
            _formatDuration(widget.recordDuration),
            style: const TextStyle(
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),

          // SEND VOICE BUTTON
          GestureDetector(
            onTap: widget.onMicLongPressEnd,
            child: const Icon(
              Icons.send_rounded,
              color: Colors.greenAccent,
              size: 18,
            ),
          ),

          const SizedBox(width: 10),

          // CANCEL
          GestureDetector(
            onTap: widget.onMicCancel,
            child: const Icon(
              Icons.close,
              color: Colors.white70,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendOrMic(ThemeData theme) {
    if (_hasText || widget.sending) {
      return IconButton(
        icon: widget.sending
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Icon(Icons.send_rounded),
        color: theme.colorScheme.primary,
        onPressed: widget.sending ? null : _handleSendPressed, // ✅ FIX
      );
    }

    // ✅ Mic when empty
    return GestureDetector(
      onLongPressStart: (_) => widget.onMicLongPressStart?.call(),
      onLongPressEnd: (_) => widget.onMicLongPressEnd?.call(),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hold the mic to record a voice message'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.mic_rounded,
          color: Colors.white,
        ),
      ),
    );
  }
}
