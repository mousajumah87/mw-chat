// lib/widgets/chat/message_reply.dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'mw_reply_to.dart';

class MessageReply extends StatelessWidget {
  final MwReplyTo replyTo;
  final VoidCallback onCancel;

  const MessageReply({
    super.key,
    required this.replyTo,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: kChatInputFieldBg.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kChatInputBarBorder.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: kGoldDeep.withOpacity(0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 18, color: kPrimaryGold.withOpacity(0.95)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.replying, // add this key if you don't have it
                  style: TextStyle(
                    fontSize: 11,
                    color: kTextSecondary.withOpacity(0.92),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyTo.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.close_rounded, color: kTextSecondary.withOpacity(0.85)),
            onPressed: onCancel,
            tooltip: l10n.cancelLabel,
          ),
        ],
      ),
    );
  }
}
