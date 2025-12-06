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

  // Voice note extras (all optional so old code doesn't break)
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

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
  }

  String _formatDuration(Duration? d) {
    final duration = d ?? Duration.zero;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _handleTextChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
    widget.onTextChanged?.call(value);
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

          // Text field – now full pill, not a small box with its own border
          Expanded(
            child: TextField(
              controller: widget.controller,
              enabled: !widget.sending && !widget.isRecording,
              onChanged: _handleTextChanged,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
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
                // One big rounded pill; remove the default blue outline look.
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

          // Right side: send / mic / recording pill
          if (widget.isRecording)
            _buildRecordingPill(theme)
          else
            _buildSendOrMic(theme),
        ],
      ),
    );
  }

  Widget _buildRecordingPill(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          const SizedBox(width: 6),
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
    // If there is text or we are currently sending, show SEND button.
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
        onPressed: widget.sending ? null : widget.onSend,
      );
    }

    // Otherwise show mic with long-press actions.
    return GestureDetector(
      onLongPressStart: (_) => widget.onMicLongPressStart?.call(),
      onLongPressEnd: (_) => widget.onMicLongPressEnd?.call(),
      onTap: () {
        // Simple hint; no localization required, safe default.
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
