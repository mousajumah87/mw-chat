// lib/screens/chat/chat_message_list.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../widgets/chat/message_bubble.dart';
import '../../utils/time_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

class ChatMessageList extends StatefulWidget {
  final String roomId;
  final String currentUserId;
  final String? otherUserId;

  /// If true, we show a “blocked” info state instead of streaming messages.
  /// This means there is a block relationship (you blocked them or they blocked you).
  final bool isBlocked;

  const ChatMessageList({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.otherUserId,
    this.isBlocked = false,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  // Seen batching debounce
  Timer? _debounceTimer;
  final Set<String> _seenMessagesCache = {};

  // Friend status for this chat:
  // null, "accepted", "requested", "request_received", ...
  String? _friendStatus;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _friendSub;

  @override
  void initState() {
    super.initState();
    _listenFriendStatus();
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.otherUserId != widget.otherUserId) {
      _listenFriendStatus();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _friendSub?.cancel();
    super.dispose();
  }

  // ================= FRIEND STATUS LISTENER =================

  void _listenFriendStatus() {
    _friendSub?.cancel();

    final myId = widget.currentUserId;
    final otherId = widget.otherUserId;

    if (myId.isEmpty || otherId == null || otherId.isEmpty) {
      setState(() {
        _friendStatus = null;
      });
      return;
    }

    _friendSub = FirebaseFirestore.instance
        .collection('users')
        .doc(myId)
        .collection('friends')
        .doc(otherId)
        .snapshots()
        .listen(
          (snap) {
        final data = snap.data();
        final status = data?['status'] as String?;
        if (mounted) {
          setState(() {
            _friendStatus = status;
          });
        }
      },
      onError: (e, st) {
        debugPrint('[ChatMessageList] _listenFriendStatus error: $e\n$st');
        if (mounted) {
          setState(() {
            _friendStatus = null;
          });
        }
      },
    );
  }

  // ================= FRIEND REQUEST ACTIONS =================

  Future<void> _acceptFriendRequest() async {
    final myId = widget.currentUserId;
    final otherId = widget.otherUserId;
    if (myId.isEmpty || otherId == null || otherId.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(myId)
        .collection('friends')
        .doc(otherId);
    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(otherId)
        .collection('friends')
        .doc(myId);

    final now = FieldValue.serverTimestamp();

    batch.set(
      myRef,
      {
        'status': 'accepted',
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
    batch.set(
      theirRef,
      {
        'status': 'accepted',
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    try {
      await batch.commit();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestAccepted)),
      );
    } catch (e, st) {
      debugPrint('[ChatMessageList] _acceptFriendRequest error: $e\n$st');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestAcceptFailed)),
      );
    }
  }

  Future<void> _declineFriendRequest() async {
    final myId = widget.currentUserId;
    final otherId = widget.otherUserId;
    if (myId.isEmpty || otherId == null || otherId.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(myId)
        .collection('friends')
        .doc(otherId);
    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(otherId)
        .collection('friends')
        .doc(myId);

    batch.delete(myRef);
    batch.delete(theirRef);

    try {
      await batch.commit();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestDeclined)),
      );
    } catch (e, st) {
      debugPrint('[ChatMessageList] _declineFriendRequest error: $e\n$st');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestDeclineFailed)),
      );
    }
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

      // Only mark messages from the other user, and only once per message.
      if (senderId == null ||
          senderId == widget.currentUserId ||
          _seenMessagesCache.contains(doc.id)) {
        continue;
      }

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

      // Also reset unread count for the current user in this chat.
      try {
        await FirebaseFirestore.instance
            .collection('privateChats')
            .doc(widget.roomId)
            .set(
          {
            'unreadCounts': {widget.currentUserId: 0},
          },
          SetOptions(merge: true),
        );
      } on FirebaseException catch (e) {
        debugPrint(
          '⚠️ Failed to reset unread count on seen: ${e.code} ${e.message}',
        );
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

    // If the other user has not seen this message yet, and I delete it,
    // decrement their unread counter.
    if (!seenBy.contains(widget.otherUserId)) {
      final roomRef = FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId);

      await roomRef.set(
        {
          'unreadCounts': {
            widget.otherUserId!: FieldValue.increment(-1),
          },
        },
        SetOptions(merge: true),
      );
    }
  }

  // ================= REPORT MESSAGE =================

  Future<void> _reportMessage(
      BuildContext context,
      DocumentSnapshot<Map<String, dynamic>> messageDoc, {
        required String reasonCategory,
        String? reasonDetails,
      }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = messageDoc.data() ?? {};
    final type = data['type'] ?? 'text';

    try {
      await FirebaseFirestore.instance.collection('contentReports').add({
        'type': type,
        'roomId': widget.roomId,
        'messageId': messageDoc.id,
        'senderId': data['senderId'],
        'senderEmail': data['senderEmail'],
        'reporterId': user.uid,

        // New structured fields
        'reasonCategory': reasonCategory,
        'reasonDetails':
        (reasonDetails == null || reasonDetails.trim().isEmpty)
            ? null
            : reasonDetails.trim(),

        // Backward-compatible combined reason string
        'reason': (reasonDetails == null || reasonDetails.trim().isEmpty)
            ? reasonCategory
            : '$reasonCategory – ${reasonDetails.trim()}',

        'text': data['text'] ?? '',
        'fileUrl': data['fileUrl'],
        'fileName': data['fileName'],
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });

      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reportSubmitted)),
        );
      }
    } catch (e, st) {
      debugPrint('[ChatMessageList] _reportMessage error: $e\n$st');
    }
  }

  Future<void> _showReportDialog(
      BuildContext context,
      DocumentSnapshot<Map<String, dynamic>> messageDoc,
      ) async {
    final l10n = AppLocalizations.of(context)!;
    final reasonController = TextEditingController();

    final List<String> reasonCategories = <String>[
      l10n.reasonHarassment,
      l10n.reasonSpam,
      l10n.reasonHate,
      l10n.reasonSexual,
      l10n.reasonOther,
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? selectedCategory;

        return StatefulBuilder(
          builder: (context, setState) {
            final bool canSave = selectedCategory != null;

            return AlertDialog(
              title: Text(l10n.reportMessageTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.reportUserReasonLabel,
                      border: const OutlineInputBorder(),
                    ),
                    items: reasonCategories
                        .map(
                          (r) => DropdownMenuItem<String>(
                        value: r,
                        child: Text(r),
                      ),
                    )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedCategory = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: l10n.reportMessageHint, // optional details
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: !canSave
                      ? null
                      : () async {
                    final details = reasonController.text.trim();
                    await _reportMessage(
                      context,
                      messageDoc,
                      reasonCategory: selectedCategory!,
                      reasonDetails:
                      details.isEmpty ? null : details,
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: Text(
                    l10n.save,
                    style: TextStyle(
                      color: canSave
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.4),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================= DELETE / REPORT MENU =================

  Future<void> _onMessageLongPress(
      BuildContext context,
      DocumentSnapshot<Map<String, dynamic>> messageDoc,
      bool isMe,
      ) async {
    final l10n = AppLocalizations.of(context)!;

    // Build options: always "Report", and "Delete" only if it's my message.
    final options = <_MessageAction>[
      if (isMe) _MessageAction.delete,
      _MessageAction.report,
    ];

    final selected = await showModalBottomSheet<_MessageAction>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              if (isMe)
                ListTile(
                  leading:
                  const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    l10n.deleteMessageTitle,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_MessageAction.delete),
                ),
              ListTile(
                leading:
                const Icon(Icons.flag_outlined, color: Colors.orange),
                title: Text(
                  l10n.reportMessageTitle,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.of(sheetContext)
                    .pop(_MessageAction.report),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );

    if (selected == null) return;

    if (selected == _MessageAction.delete && isMe) {
      // Confirm delete
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.deleteMessageTitle),
          content: Text(l10n.deleteMessageConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                l10n.delete,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ) ??
          false;

      if (!confirmed) return;

      final msgRef = messageDoc.reference;
      await _decrementUnreadIfNeeded(messageDoc);
      await msgRef.delete();
    } else if (selected == _MessageAction.report) {
      await _showReportDialog(context, messageDoc);
    }
  }

  // ================= FRIEND REQUEST BANNER =================

  Widget _buildFriendBanner(BuildContext context) {
    final status = _friendStatus;
    if (status == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;

    if (status == 'request_received') {
      // Incoming request → Accept / Decline.
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Card(
          color: Colors.white.withOpacity(0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.18)),
          ),
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.person_add, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.friendRequestIncomingBanner,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _acceptFriendRequest,
                  child: Text(
                    l10n.friendAcceptTooltip,
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
                ),
                TextButton(
                  onPressed: _declineFriendRequest,
                  child: Text(
                    l10n.friendDeclineTooltip,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (status == 'requested') {
      // Outgoing request → info only (design kept as-is, empty card).
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Card(
          color: Colors.white.withOpacity(0.04),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.14)),
          ),
        ),
      );
    }

    // For "accepted" or any other status, no banner.
    return const SizedBox.shrink();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.7;
    final l10n = AppLocalizations.of(context)!;

    // If this chat is blocked from either side, do NOT stream messages.
    // We show only the blocked info, and do not mark new messages as seen.
    if (widget.isBlocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.userBlockedInfo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kTextSecondary,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId)
          .collection('messages')
      // Optimization: limit to last 200 messages, still shows all recent.
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          // If no messages but there is a pending friend request, still show the banner.
          if (_friendStatus == 'request_received' ||
              _friendStatus == 'requested') {
            return ListView(
              key: const PageStorageKey<String>('chatMessageList'),
              reverse: true,
              padding: const EdgeInsets.all(12),
              children: [
                _buildFriendBanner(context),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      l10n.noMessagesYet,
                      style: const TextStyle(color: kTextSecondary),
                    ),
                  ),
                ),
              ],
            );
          }

          return Center(
            child: Text(
              l10n.noMessagesYet,
              style: const TextStyle(color: kTextSecondary),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        // Schedule seen updates (debounced).
        _scheduleMarkMessagesAsSeen(docs);

        final bool showBanner =
            _friendStatus == 'request_received' ||
                _friendStatus == 'requested';
        final int itemCount = docs.length + (showBanner ? 1 : 0);

        return ListView.builder(
          key: const PageStorageKey<String>('chatMessageList'),
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: itemCount,
          itemBuilder: (context, i) {
            // With reverse: true, the last index appears at the top.
            if (showBanner && i == itemCount - 1) {
              return _buildFriendBanner(context);
            }

            // Normal message row.
            final doc = docs[i];
            final data = doc.data();
            final senderId = data['senderId'] as String?;
            final isMe = senderId == widget.currentUserId;

            return RepaintBoundary(
              child: Align(
                alignment:
                isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: GestureDetector(
                  onLongPress: () =>
                      _onMessageLongPress(context, doc, isMe),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: MessageBubble(
                      text: data['text'] ?? '',
                      timeLabel: formatTimestamp(data['createdAt']),
                      isMe: isMe,
                      // "Seen" dot logic: did the *other* user see this?
                      isSeen: (data['seenBy'] ?? [])
                          .contains(widget.otherUserId),
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

enum _MessageAction {
  delete,
  report,
}
