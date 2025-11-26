// lib/widgets/chat/chat_input_bar.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

class ChatInputBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        // input bubble with attach icon inside
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: kSurfaceColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kBorderColor),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.attach_file,
                    size: 20,
                  ),
                  splashRadius: 20,
                  onPressed: onAttach,
                  tooltip: l10n.attachFile,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: onTextChanged,
                    decoration: InputDecoration(
                      hintText: l10n.typeMessageHint,
                      isDense: true,
                      border: InputBorder.none,
                      hintStyle: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8),

        // round send button
        InkWell(
          onTap: sending ? null : onSend,
          borderRadius: BorderRadius.circular(999),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: sending ? kSurfaceAltColor : Colors.white,
            child: sending
                ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(
              Icons.send,
              size: 20,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}
