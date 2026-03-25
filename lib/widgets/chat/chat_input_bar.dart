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

  /// ✅ IMPORTANT:
  /// If your parent already applies keyboard bottom inset (recommended), keep this FALSE.
  /// If not, set TRUE to make the bar stick to the keyboard with no jump.
  final bool handleKeyboardInset;

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
    this.handleKeyboardInset = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> with TickerProviderStateMixin {
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
      // avoid timed delays; let one frame settle
      await Future<void>.delayed(Duration.zero);
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
      await Future<void>.delayed(Duration.zero);
    }

    if (mounted && !_disposed) setState(() {});

    try {
      await vc.start();
      if (vc.isRecording) {
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
    if (!mounted) {
      _hasText = hasText;
      return;
    }
    if (hasText != _hasText) {
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

    // 🔴 CRITICAL: DO NOT requestFocus after send.
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
      await Future<void>.delayed(Duration.zero);
    }

    // Close keyboard before opening sheet (prevents flip / weird jump)
    if (_activeFocusNode.hasFocus) _activeFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    // Let the layout settle one frame (no “timed delay” jitter)
    await Future<void>.delayed(Duration.zero);
    if (!mounted || _disposed) return;

    await widget.onAttach();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _circleIconButton({
    required VoidCallback? onTap,
    required IconData icon,
    double size = 44,
    double iconSize = 22,
    Color? bg,
    Color? fg,
    Border? border,
  }) {
    final enabled = onTap != null && !_uiLocked;

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg ??
                  (enabled
                      ? kPrimaryGold.withOpacity(0.95)
                      : kSurfaceAltColor.withOpacity(0.55)),
              border: border ??
                  Border.all(
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
              color: fg ?? (enabled ? Colors.black : Colors.white38),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    if (_uiLocked) {
      return _circleIconButton(
        onTap: null,
        icon: Icons.mic_rounded,
        size: 44,
        iconSize: 22,
        bg: Colors.white.withOpacity(0.06),
        fg: Colors.white38,
        border: Border.all(color: kBorderColor.withOpacity(0.35)),
      );
    }

    if (_vc == null) {
      return _circleIconButton(
        onTap: null,
        icon: Icons.mic_off,
        size: 44,
        iconSize: 22,
        bg: Colors.white.withOpacity(0.06),
        fg: Colors.white.withOpacity(0.55),
        border: Border.all(color: kBorderColor.withOpacity(0.35)),
      );
    }

    final vc = _vc!;
    final bool isRec = vc.isRecording || vc.isPreparing;

    return _circleIconButton(
      onTap: _toggleVoice,
      icon: isRec ? Icons.stop : Icons.mic_rounded,
      size: 44,
      iconSize: 22,
      bg: isRec ? Colors.redAccent.withOpacity(0.22) : Colors.white.withOpacity(0.06),
      fg: Colors.white.withOpacity(0.92),
      border: Border.all(color: kBorderColor.withOpacity(0.35)),
    );
  }

  Widget _fixedIconButton({
    required VoidCallback? onPressed,
    required IconData icon,
    String? tooltip,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: _uiLocked ? null : onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 24,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(icon, color: Colors.white70),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    const double baseFont = 16.0;
    final double scaled = MediaQuery.textScalerOf(context).scale(baseFont);
    final double effectiveFont = scaled < 16.0 ? 16.0 : scaled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isUploading)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: LinearProgressIndicator(value: widget.uploadProgress),
          ),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: (_showVoiceBar && _vc != null && widget.onVoiceSend != null)
              ? KeyedSubtree(
            key: const ValueKey('voice_bar_mode'),
            child: VoiceRecordBar(
              controller: _vc!,
              onSend: widget.onVoiceSend!,
              onRecordStart: widget.onVoiceRecordStart,
              onRecordStop: widget.onVoiceRecordStop,
            ),
          )
              : KeyedSubtree(
            key: const ValueKey('text_input_mode'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: kChatInputBarBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kChatInputBarBorder.withOpacity(0.55)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _fixedIconButton(
                    onPressed: _handleAttachPressed,
                    icon: Icons.add_circle_outline,
                    tooltip: l10n.attachFile,
                  ),
                  _fixedIconButton(
                    onPressed: widget.onTogglePanel,
                    icon: widget.panelVisible
                        ? Icons.keyboard
                        : Icons.emoji_emotions_outlined,
                  ),
                  const SizedBox(width: 6),

                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _activeFocusNode,
                        onTap: () {
                          if (widget.panelVisible) widget.onTogglePanel?.call();
                        },
                        onChanged: widget.onTextChanged,
                        onSubmitted: (_) => _handleSendPressed(),
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        textAlignVertical: TextAlignVertical.center,
                        scrollPadding: EdgeInsets.zero,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.96), // clearer white
                          fontSize: effectiveFont,
                          height: 1.28, // tiny improvement for readability
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.typeMessageHint,
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55), // slightly clearer than 54
                            fontSize: effectiveFont,
                            height: 1.28,
                            fontWeight: FontWeight.w400, // lighter than input text
                            letterSpacing: 0.05,
                          ),
                          filled: false,
                          fillColor: Colors.transparent,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.92, end: 1.0)
                              .animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: (_hasText || widget.sending || _isUploading)
                        ? KeyedSubtree(
                      key: const ValueKey('send_btn'),
                      child: _circleIconButton(
                        onTap: _uiLocked ? null : _handleSendPressed,
                        icon: Icons.send,
                        size: 44,
                        iconSize: 20,
                      ),
                    )
                        : KeyedSubtree(
                      key: const ValueKey('mic_btn'),
                      child: _buildMicButton(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

}
