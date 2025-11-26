// lib/widgets/chat_message_list.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/chat/message_bubble.dart';
import '../../utils/time_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

class ChatMessageList extends StatelessWidget {
  final String roomId;
  final String currentUserId;
  final String? otherUserId;

  const ChatMessageList({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.otherUserId,
  });

  // ================= SEEN HANDLING =================

  Future<void> _markMessagesAsSeen(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    if (currentUserId.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in docs) {
      final data = doc.data();
      final senderId = data['senderId'] as String?;
      if (senderId == null || senderId == currentUserId) continue;

      final seenBy =
          (data['seenBy'] as List?)?.cast<String>() ?? const <String>[];

      if (!seenBy.contains(currentUserId)) {
        batch.update(doc.reference, {
          'seenBy': FieldValue.arrayUnion([currentUserId]),
        });
      }
    }

    await batch.commit();
  }

  // ================= UPDATE UNREAD ON DELETE =================

  Future<void> _decrementUnreadIfNeeded(
      DocumentSnapshot<Map<String, dynamic>> messageDoc,
      ) async {
    if (otherUserId == null) return;

    final data = messageDoc.data();
    if (data == null) return;

    final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? [];

    // Only reduce unread if the other user hadn't seen it yet
    if (!seenBy.contains(otherUserId)) {
      final roomRef =
      FirebaseFirestore.instance.collection('privateChats').doc(roomId);

      await roomRef.set({
        'unreadCounts': {
          otherUserId!: FieldValue.increment(-1),
        }
      }, SetOptions(merge: true));
    }
  }

  // ================= DELETE MESSAGE =================

  Future<void> _onMessageLongPress(
      BuildContext context,
      String messageId,
      bool isMe,
      ) async {
    if (!isMe) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('Delete this message for everyone?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed) return;

    final msgRef = FirebaseFirestore.instance
        .collection('privateChats')
        .doc(roomId)
        .collection('messages')
        .doc(messageId);

    final messageSnap = await msgRef.get();

    await _decrementUnreadIfNeeded(messageSnap);
    await msgRef.delete();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.7;
    final l10n = AppLocalizations.of(context)!;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('privateChats')
          .doc(roomId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(l10n.noMessagesYet, style: const TextStyle(color: kTextSecondary)));
        }

        final docs = snapshot.data!.docs;
        _markMessagesAsSeen(docs);

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final senderId = data['senderId'] as String?;
            final isMe = senderId == currentUserId;

            final bubble = ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: MessageBubble(
                text: data['text'] ?? '',
                timeLabel: formatTimestamp(data['createdAt']),
                isMe: isMe,
                isSeen: (data['seenBy'] ?? []).contains(otherUserId),
                fileUrl: data['fileUrl'],
                fileName: data['fileName'],
                fileType: data['type'],
              ),
            );

            return GestureDetector(
              onLongPress: isMe ? () => _onMessageLongPress(context, doc.id, isMe) : null,
              child: Row(
                mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [bubble],
              ),
            );
          },
        );
      },
    );
  }
}
