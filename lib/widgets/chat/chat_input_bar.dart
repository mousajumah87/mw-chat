import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final ValueChanged<String> onTextChanged;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.onAttach,
    required this.onSend,
    required this.onTextChanged,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sendController;
  late final Animation<double> _scaleAnim;

  // Keep our own focus node so we can control focus if needed
  final FocusNode _inputFocusNode = FocusNode();

  static const _sendGradient = LinearGradient(
    colors: [Color(0xFF0057FF), Color(0xFFFFB300)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  void initState() {
    super.initState();
    _sendController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.05).animate(
      CurvedAnimation(parent: _sendController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _sendController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _triggerSend() async {
    if (widget.sending) return;

    final text = widget.controller.text.trim();
    if (text.isEmpty) return;

    await _sendController.forward();
    await _sendController.reverse();
    widget.onSend();

    // Keep focus so keyboard stays open after sending (WhatsApp-like)
    _inputFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: RepaintBoundary(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // === Input bubble ===
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 44,
                  maxHeight: 120, // allow a few lines, similar to WhatsApp
                ),
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: kSurfaceAltColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: kBorderColor.withOpacity(0.8),
                      width: 0.7,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.attach_file,
                          size: 20,
                          color: kTextSecondary,
                        ),
                        splashRadius: 22,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        tooltip: l10n.attachFile,
                        onPressed: widget.onAttach,
                      ),

                      const SizedBox(width: 6),

                      // === Text input (WhatsApp-like multiline) ===
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _inputFocusNode,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          minLines: 1,
                          maxLines: 5, // auto-expand up to 5 lines
                          onChanged: widget.onTextChanged,
                          // No onSubmitted -> Enter just creates a new line,
                          // sending is done via the send button only.
                          textAlignVertical: TextAlignVertical.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          cursorColor: Colors.white70,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            isDense: true,
                            hintText: l10n.typeMessageHint,
                            hintStyle: const TextStyle(
                              color: kTextSecondary,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // === Send button ===
            ScaleTransition(
              scale: _scaleAnim,
              child: GestureDetector(
                onTap: widget.sending ? null : _triggerSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.sending
                        ? const LinearGradient(
                      colors: [kSurfaceAltColor, kSurfaceAltColor],
                    )
                        : _sendGradient,
                    boxShadow: widget.sending
                        ? const []
                        : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: widget.sending
                          ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(
                        key: ValueKey('send'),
                        Icons.send_rounded,
                        size: 20,
                        color: Colors.white,
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
  }
}
