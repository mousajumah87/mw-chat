// lib/widgets/chat/chat_input_bar.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/voice_recorder_controller.dart';
import '../ui/mw_feedback.dart';
import 'voice_record_bar.dart';

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final ValueChanged<String>? onTextChanged;

  // ✅ Voice
  final VoiceRecorderController? voiceController;
  final Future<void> Function(VoiceDraft draft)? onVoiceSend;

  // ✅ OPTIONAL: let parent update Firestore recording state
  // (e.g., set recording_<uid> true/false)
  final VoidCallback? onVoiceRecordStart;
  final VoidCallback? onVoiceRecordStop;

  // upload progress for media (0..1), null = no upload
  final double? uploadProgress;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.onAttach,
    required this.onSend,
    this.onTextChanged,
    this.voiceController,
    this.onVoiceSend,
    this.onVoiceRecordStart,
    this.onVoiceRecordStop,
    this.uploadProgress,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  bool _hasText = false;
  final FocusNode _messageFocusNode = FocusNode(debugLabel: 'chatInput');

  bool _disposed = false;

  bool get _isUploading =>
      widget.uploadProgress != null && widget.uploadProgress! < 1.0;

  bool get _uiLocked => widget.sending || _isUploading;

  VoiceRecorderController? get _vc => widget.voiceController;

  // ✅ FIX: keep the voice UI visible not only while recording/draft,
  // but ALSO while "preparing" (permissions/init). This prevents flicker/disappear.
  bool get _showVoiceBar {
    final vc = _vc;
    if (vc == null) return false;
    return vc.isRecording || vc.isPreparing || vc.hasDraft;
  }

  Future<void> _toast(String message) async {
    if (!mounted || _disposed) return;
    await MwFeedback.show(context, message: message);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ✅ Voice helpers: ensure onVoiceRecordStart/Stop are always consistent
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _startVoice() async {
    if (_uiLocked) return;
    final vc = _vc;
    if (vc == null) return;

    // guard
    if (vc.isRecording || vc.isPreparing || vc.hasDraft) return;

    // Unfocus text input so the keyboard doesn't fight with recording UI.
    if (_messageFocusNode.hasFocus) _messageFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    // ✅ Show UI immediately (so user sees "recording/preparing" right away)
    if (mounted && !_disposed) setState(() {});

    bool started = false;
    try {
      await vc.start();
      started = vc.isRecording; // only true if start actually succeeded

      if (started) {
        // ✅ Signal parent: recording started (Firestore recording_<uid>=true)
        widget.onVoiceRecordStart?.call();
      } else {
        // start didn't succeed => ensure remote flag is not stuck
        widget.onVoiceRecordStop?.call();
      }
    } catch (_) {
      // start failed => ensure remote flag is not stuck
      widget.onVoiceRecordStop?.call();
    } finally {
      if (!mounted || _disposed) return;
      // voice controller notifies, but keep UI snappy
      setState(() {});
    }
  }

  Future<void> _stopVoiceToPreview() async {
    if (_uiLocked) return;
    final vc = _vc;
    if (vc == null) return;

    if (!vc.isRecording && !vc.isPreparing) {
      // if we somehow reach here while not recording, still ensure remote false
      widget.onVoiceRecordStop?.call();
      return;
    }

    try {
      await vc.stopToPreview();
    } catch (_) {
      // ignore, controller handles reset
    } finally {
      // ✅ ALWAYS clear Firestore recording flag
      widget.onVoiceRecordStop?.call();
      if (!mounted || _disposed) return;
      setState(() {});
    }
  }

  Future<void> _cancelVoice() async {
    final vc = _vc;
    if (vc == null) return;

    try {
      await vc.cancel();
    } catch (_) {
      // ignore
    } finally {
      // ✅ ALWAYS clear Firestore recording flag
      widget.onVoiceRecordStop?.call();
      if (!mounted || _disposed) return;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _syncTextState();
    widget.controller.addListener(_syncTextState);

    // re-render when voice controller changes state
    _vc?.addListener(_onVoiceChanged);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncTextState);
      widget.controller.addListener(_syncTextState);
      _syncTextState();
    }

    if (oldWidget.voiceController != widget.voiceController) {
      oldWidget.voiceController?.removeListener(_onVoiceChanged);
      widget.voiceController?.addListener(_onVoiceChanged);

      // If controller swapped while recording, be safe: clear flag
      if (oldWidget.voiceController?.isRecording == true ||
          oldWidget.voiceController?.isPreparing == true) {
        widget.onVoiceRecordStop?.call();
      }
    }
  }

  void _onVoiceChanged() {
    if (!mounted || _disposed) return;
    setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;

    // ✅ If disposed while recording/preparing, ensure Firestore flag is cleared
    if (widget.voiceController?.isRecording == true ||
        widget.voiceController?.isPreparing == true) {
      widget.onVoiceRecordStop?.call();
    }

    widget.controller.removeListener(_syncTextState);
    widget.voiceController?.removeListener(_onVoiceChanged);
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _syncTextState() {
    if (_disposed) return;
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText && mounted) {
      setState(() => _hasText = hasText);
    }
  }

  void _handleSendPressed() {
    if (_uiLocked) return;

    // If voice preview/recording is active, do not send text.
    if (_showVoiceBar) {
      _toast('Finish or cancel the voice note first.');
      return;
    }

    widget.onSend();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      _messageFocusNode.requestFocus();
    });
  }

  Future<void> _handleAttachPressed() async {
    if (_uiLocked) return;

    // If voice preview/recording is active, do not interrupt.
    if (_showVoiceBar) {
      // ✅ keep simple string to avoid missing l10n key issues
      await _toast('Finish or cancel the voice note first.');
      return;
    }

    if (_messageFocusNode.hasFocus) _messageFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    if (!mounted || _disposed) return;
    widget.onAttach();
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

  Widget _buildMicButton() {
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

    // If no voice controller wired, keep the mic disabled gracefully
    if (_vc == null) {
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: kBorderColor.withOpacity(0.35)),
        ),
        child: Icon(Icons.mic_off, color: Colors.white.withOpacity(0.55)),
      );
    }

    // Web: tap to start/stop to preview
    if (kIsWeb) {
      return GestureDetector(
        onTap: () async {
          if (_uiLocked) return;
          final vc = _vc!;
          if (vc.isRecording || vc.isPreparing) {
            await _stopVoiceToPreview();
          } else if (!vc.hasDraft) {
            await _startVoice();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (_vc!.isRecording || _vc!.isPreparing)
                ? Colors.redAccent.withOpacity(0.22)
                : Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
            border: Border.all(color: kBorderColor.withOpacity(0.35)),
          ),
          child: Icon(
            (_vc!.isRecording || _vc!.isPreparing) ? Icons.stop : Icons.mic_rounded,
            color: Colors.white.withOpacity(0.92),
          ),
        ),
      );
    }

    // Mobile: long-press to record -> release to preview
    return GestureDetector(
      onLongPressStart: (_) async {
        if (_uiLocked) return;
        final vc = _vc!;
        if (vc.isRecording || vc.isPreparing || vc.hasDraft) return;
        await _startVoice();
      },
      onLongPressEnd: (_) async {
        if (_uiLocked) return;
        if (_vc?.isRecording == true || _vc?.isPreparing == true) {
          await _stopVoiceToPreview();
        } else {
          // gesture ended but not recording => ensure remote false
          widget.onVoiceRecordStop?.call();
        }
      },
      // ✅ Critical: if gesture cancels (scroll, route pop, interruption),
      // onLongPressEnd may NOT fire. This is a common “stuck recording” cause.
      onLongPressCancel: () async {
        if (_vc?.isRecording == true || _vc?.isPreparing == true) {
          await _cancelVoice();
        } else {
          widget.onVoiceRecordStop?.call();
        }
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

          // ✅ Voice recording / preview bar (progress + preview + send)
          // ✅ Shows during preparing too (via _showVoiceBar)
          if (_showVoiceBar && _vc != null && widget.onVoiceSend != null)
            VoiceRecordBar(
              controller: _vc!,
              onSend: widget.onVoiceSend!,
              onRecordStart: widget.onVoiceRecordStart,
              onRecordStop: widget.onVoiceRecordStop,
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: kChatInputBarBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kChatInputBarBorder.withOpacity(0.55)),
            ),
            child: Row(
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
