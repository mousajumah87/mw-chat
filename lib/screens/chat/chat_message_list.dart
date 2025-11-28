import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/chat/message_bubble.dart';
import '../../utils/time_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

class ChatMessageList extends StatefulWidget {
  final String roomId;
  final String currentUserId;
  final String? otherUserId;

  const ChatMessageList({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.otherUserId,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  // Seen batching debounce
  Timer? _debounceTimer;
  final Set<String> _seenMessagesCache = {};

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ================= SEEN HANDLING =================
  void _scheduleMarkMessagesAsSeen(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _markMessagesAsSeen(docs);
    });
  }

  Future<void> _markMessagesAsSeen(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    if (widget.currentUserId.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    bool hasUpdates = false;

    for (final doc in docs) {
      final data = doc.data();
      final senderId = data['senderId'] as String?;
      final seenBy =
          (data['seenBy'] as List?)?.cast<String>() ?? const <String>[];

      if (senderId == null ||
          senderId == widget.currentUserId ||
          _seenMessagesCache.contains(doc.id)) continue;

      if (!seenBy.contains(widget.currentUserId)) {
        batch.update(doc.reference, {
          'seenBy': FieldValue.arrayUnion([widget.currentUserId]),
        });
        hasUpdates = true;
        _seenMessagesCache.add(doc.id);
      }
    }

    if (hasUpdates) {
      await batch.commit();

      // 🔹 Reset unread count for current user in this chat
      try {
        await FirebaseFirestore.instance
            .collection('privateChats')
            .doc(widget.roomId)
            .set({
          'unreadCounts': {widget.currentUserId: 0},
        }, SetOptions(merge: true));
      } on FirebaseException catch (e) {
        debugPrint('⚠️ Failed to reset unread count on seen: ${e.code} ${e.message}');
      }
    }
  }

  // ================= UPDATE UNREAD ON DELETE =================
  Future<void> _decrementUnreadIfNeeded(
      DocumentSnapshot<Map<String, dynamic>> messageDoc,
      ) async {
    if (widget.otherUserId == null) return;

    final data = messageDoc.data();
    if (data == null) return;

    final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? [];

    if (!seenBy.contains(widget.otherUserId)) {
      final roomRef = FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId);

      await roomRef.set({
        'unreadCounts': {
          widget.otherUserId!: FieldValue.increment(-1),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ??
        false;

    if (!confirmed) return;

    final msgRef = FirebaseFirestore.instance
        .collection('privateChats')
        .doc(widget.roomId)
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
          .doc(widget.roomId)
          .collection('messages')
      // Optimization: limit to last 200 messages, still shows all recent
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
              child: Text(
                l10n.noMessagesYet,
                style: const TextStyle(color: kTextSecondary),
              ));
        }

        final docs = snapshot.data!.docs;

        // Schedule seen updates (debounced)
        _scheduleMarkMessagesAsSeen(docs);

        return ListView.builder(
          key: const PageStorageKey<String>('chatMessageList'),
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final senderId = data['senderId'] as String?;
            final isMe = senderId == widget.currentUserId;

            return RepaintBoundary(
              child: Align(
                alignment:
                isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: GestureDetector(
                  onLongPress: isMe
                      ? () => _onMessageLongPress(context, doc.id, isMe)
                      : null,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: MessageBubble(
                      text: data['text'] ?? '',
                      timeLabel: formatTimestamp(data['createdAt']),
                      isMe: isMe,
                      isSeen:
                      (data['seenBy'] ?? []).contains(widget.otherUserId),
                      fileUrl: data['fileUrl'],
                      fileName: data['fileName'],
                      fileType: data['type'],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
