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

  /// ✅ ChatScreen owns attach-sheet + media service. Keep it there.
  /// In ChatInputBar we only: close input states then call onAttach().
  final Future<void> Function() onAttach;

  final VoidCallback onSend;
  final ValueChanged<String>? onTextChanged;

  /// ✅ Parent (ChatScreen) should pass ONE shared focus node.
  final FocusNode? focusNode;

  /// ✅ Emoji/custom panel state is controlled by ChatScreen.
  final bool panelVisible;
  final VoidCallback? onTogglePanel;

  // ✅ Voice
  final VoiceRecorderController? voiceController;
  final Future<void> Function(VoiceDraft draft)? onVoiceSend;

  // ✅ OPTIONAL: let parent update Firestore recording state
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
    this.focusNode,
    this.panelVisible = false,
    this.onTogglePanel,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  bool _hasText = false;

  /// 🔴 IMPORTANT: local fallback focus node only.
  final FocusNode _fallbackFocusNode = FocusNode(debugLabel: 'chatInput');

  bool _disposed = false;

  bool get _isUploading =>
      widget.uploadProgress != null && widget.uploadProgress! < 1.0;

  bool get _uiLocked => widget.sending || _isUploading;

  VoiceRecorderController? get _vc => widget.voiceController;

  /// ✅ The ONLY focus node used by TextField
  FocusNode get _activeFocusNode => widget.focusNode ?? _fallbackFocusNode;

  bool get _showVoiceBar {
    final vc = _vc;
    if (vc == null) return false;
    return vc.isRecording || vc.isPreparing || vc.hasDraft;
  }

  Future<void> _toast(String message) async {
    if (!mounted || _disposed) return;
    await MwFeedback.show(context, message: message);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Voice: tap-to-toggle (start/stop). No long-press anymore.
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _toggleVoice() async {
    if (_uiLocked) return;
    final vc = _vc;
    if (vc == null) return;

    // If emoji/custom panel open, close it (snapchat behavior)
    if (widget.panelVisible) {
      widget.onTogglePanel?.call();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    // If currently recording -> stop to preview
    if (vc.isRecording || vc.isPreparing) {
      await _stopVoiceToPreview();
      return;
    }

    // If a draft already exists -> just keep voice bar visible
    if (vc.hasDraft) {
      if (!mounted || _disposed) return;
      setState(() {});
      return;
    }

    // Start recording
    await _startVoice();
  }

  Future<void> _startVoice() async {
    if (_uiLocked) return;
    final vc = _vc;
    if (vc == null) return;

    if (vc.isRecording || vc.isPreparing || vc.hasDraft) return;

    // ✅ Close keyboard before starting voice
    if (_activeFocusNode.hasFocus) _activeFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    // ✅ Also close emoji panel if open
    if (widget.panelVisible) {
      widget.onTogglePanel?.call();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    if (mounted && !_disposed) setState(() {});

    bool started = false;
    try {
      await vc.start();
      started = vc.isRecording;

      if (started) {
        widget.onVoiceRecordStart?.call();
      } else {
        widget.onVoiceRecordStop?.call();
      }
    } catch (_) {
      widget.onVoiceRecordStop?.call();
    } finally {
      if (!mounted || _disposed) return;
      setState(() {});
    }
  }

  Future<void> _stopVoiceToPreview() async {
    if (_uiLocked) return;
    final vc = _vc;
    if (vc == null) return;

    if (!vc.isRecording && !vc.isPreparing) {
      widget.onVoiceRecordStop?.call();
      return;
    }

    try {
      await vc.stopToPreview();
    } catch (_) {
      // ignore
    } finally {
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
      widget.onVoiceRecordStop?.call();
      if (!mounted || _disposed) return;
      setState(() {});
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _syncTextState();
    widget.controller.addListener(_syncTextState);
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

    if (widget.voiceController?.isRecording == true ||
        widget.voiceController?.isPreparing == true) {
      widget.onVoiceRecordStop?.call();
    }

    widget.controller.removeListener(_syncTextState);
    widget.voiceController?.removeListener(_onVoiceChanged);

    _fallbackFocusNode.dispose();
    super.dispose();
  }

  void _syncTextState() {
    if (_disposed) return;
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText && mounted) {
      setState(() => _hasText = hasText);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Send / Attach / Emoji panel coordination
  // ─────────────────────────────────────────────────────────────────────────────

  void _handleSendPressed() {
    if (_uiLocked) return;

    if (_showVoiceBar) {
      _toast('Finish or cancel the voice note first.');
      return;
    }

    widget.onSend();

    // 🔴 CRITICAL FIX: DO NOT requestFocus after send.
    // Let focus remain naturally; ChatScreen controls layout insets.
  }

  Future<void> _handleAttachPressed() async {
    if (_uiLocked) return;

    if (_showVoiceBar) {
      await _toast('Finish or cancel the voice note first.');
      return;
    }

    // Close emoji panel first so it doesn't eat gestures / overlay sheet
    if (widget.panelVisible) {
      widget.onTogglePanel?.call();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    // Close keyboard before opening sheet (prevents flip / weird jump)
    if (_activeFocusNode.hasFocus) _activeFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || _disposed) return;

    // ✅ IMPORTANT: await to avoid re-entrance glitches
    await widget.onAttach();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────────

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

    final vc = _vc!;
    final bool isRec = vc.isRecording || vc.isPreparing;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleVoice,
      onLongPress: null, // explicitly disable hold behavior
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isRec
              ? Colors.redAccent.withOpacity(0.22)
              : Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: kBorderColor.withOpacity(0.35)),
        ),
        child: Icon(
          isRec ? Icons.stop : Icons.mic_rounded,
          color: Colors.white.withOpacity(0.92),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool isUploading = _isUploading;

    // ✅ Make typing text feel correct on iPhone:
    // Keep a larger minimum font size so it doesn't look tiny inside a tall field.
    final scaler = MediaQuery.textScalerOf(context);
    final scaled = scaler.scale(2); // base target
    final double effectiveFont = scaled < 18 ? 18.0 : scaled;

    // ✅ NO SafeArea here anymore — ChatScreen dock handles it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isUploading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(value: widget.uploadProgress),
          ),

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
              // ✅ LEFT must be ATTACH
              IconButton(
                onPressed: _uiLocked ? null : _handleAttachPressed,
                icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                tooltip: l10n.attachFile,
              ),

              // ✅ Emoji/Keyboard toggle
              IconButton(
                onPressed: widget.onTogglePanel,
                icon: Icon(
                  widget.panelVisible
                      ? Icons.keyboard
                      : Icons.emoji_emotions_outlined,
                  color: Colors.white70,
                ),
              ),

              Expanded(
                child: TextField(
                  key: const ValueKey('chat_input_textfield'),
                  controller: widget.controller,
                  focusNode: _activeFocusNode,
                  onTap: () {
                    // ✅ If panel open, close it when user taps text field
                    if (widget.panelVisible) {
                      widget.onTogglePanel?.call();
                    }
                  },
                  onChanged: widget.onTextChanged,
                  onSubmitted: (_) => _handleSendPressed(),
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.center, // ✅ center text
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: effectiveFont, // ✅ bigger
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                  keyboardAppearance: Brightness.dark,
                  decoration: InputDecoration(
                    hintText: l10n.typeMessageHint,
                    hintStyle: TextStyle(
                      color: Colors.white54,
                      fontSize: effectiveFont, // ✅ same size as typing
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                    filled: true,
                    fillColor: kChatInputFieldBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14, // ✅ slightly taller + balanced
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
    );
  }
}
