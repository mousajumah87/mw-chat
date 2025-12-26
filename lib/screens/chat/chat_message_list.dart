import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/chat/message_bubble.dart';
import '../../utils/time_utils.dart';
import '../../utils/chat_attachment_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

import '../../widgets/safety/report_message_dialog.dart';
import '../../widgets/ui/mw_feedback.dart';

import 'chat_friendship_service.dart';
import 'chat_screen_deletion.dart';

class ChatMessageList extends StatefulWidget {
  final String roomId;
  final String currentUserId;
  final String? otherUserId;
  final bool isBlocked;

  /// ✅ extra padding to reserve space at the bottom (TypingIndicator + composer)
  final double bottomInset;

  const ChatMessageList({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.otherUserId,
    this.isBlocked = false,
    this.bottomInset = 0,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  Timer? _debounceTimer;
  final Set<String> _seenMessagesCache = {};
  String? _lastSeenScheduleKey;

  String? _friendStatus;

  StreamSubscription<String?>? _friendSub;
  final ChatFriendshipService _friendship = ChatFriendshipService();

  final ScrollController _scrollController = ScrollController();

  final Map<String, DocumentSnapshot<Map<String, dynamic>>> _docMap = {};
  final Set<String> _pendingLocalRemovals = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveSub;

  DocumentSnapshot<Map<String, dynamic>>? _oldestDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  static const int _pageSize = 40;
  static const int _liveWindow = 40;

  int _gen = 0;

  @override
  void initState() {
    super.initState();

    _listenFriendStatus();
    _scrollController.addListener(_onScroll);

    if (!widget.isBlocked) {
      _startLiveListener();
      _loadMoreOlder();
    }
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final roomChanged = oldWidget.roomId != widget.roomId;
    final userChanged = oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.otherUserId != widget.otherUserId;
    final blockedChanged = oldWidget.isBlocked != widget.isBlocked;

    if (userChanged) _listenFriendStatus();

    if (roomChanged || blockedChanged) {
      _resetAllState();

      if (widget.isBlocked) return;

      _startLiveListener();
      _loadMoreOlder();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _friendSub?.cancel();
    _liveSub?.cancel();
    _scrollController.dispose();
    _friendship.dispose();
    super.dispose();
  }

  Future<void> _toastSuccess(String message) async {
    if (!mounted) return;
    await MwFeedback.success(context, message: message);
  }

  Future<void> _toastError(String message) async {
    if (!mounted) return;
    await MwFeedback.error(context, message: message);
  }

  void _resetAllState() {
    _gen++;
    _liveSub?.cancel();
    _liveSub = null;

    _pendingLocalRemovals.clear();
    _docMap.clear();

    _oldestDoc = null;
    _isLoadingMore = false;
    _hasMore = true;

    _seenMessagesCache.clear();
    _lastSeenScheduleKey = null;

    if (mounted) setState(() {});
  }

  // ================= FRIEND STATUS LISTENER =================

  void _listenFriendStatus() {
    _friendSub?.cancel();

    final myId = widget.currentUserId;
    final otherId = widget.otherUserId;

    if (myId.isEmpty || otherId == null || otherId.isEmpty) {
      if (mounted) setState(() => _friendStatus = null);
      return;
    }

    _friendSub = _friendship
        .friendshipStatusStream(me: myId, other: otherId)
        .listen(
          (status) {
        if (!mounted) return;
        setState(() => _friendStatus = status);
      },
      onError: (e, st) {
        debugPrint('[ChatMessageList] _listenFriendStatus error: $e\n$st');
        if (mounted) setState(() => _friendStatus = null);
      },
    );
  }

  // ================= TIMESTAMP HELPERS =================

  Timestamp _effectiveTs(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final v = data?['createdAt'];
    if (v is Timestamp) return v;

    final v2 = data?['clientCreatedAt'];
    if (v2 is Timestamp) return v2;

    final v3 = data?['localCreatedAt'];
    if (v3 is Timestamp) return v3;

    return Timestamp.now();
  }

  String _formatDocTime(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final ts =
        data?['createdAt'] ?? data?['clientCreatedAt'] ?? data?['localCreatedAt'];
    return formatTimestamp(ts);
  }

  bool _isVisibleForMe(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final hiddenFor =
        (data['hiddenFor'] as List?)?.cast<String>() ?? const <String>[];
    return !hiddenFor.contains(widget.currentUserId);
  }

  // ================= SEEN HANDLING =================

  void _scheduleMarkMessagesAsSeen(
      List<DocumentSnapshot<Map<String, dynamic>>> docs) {
    if (widget.isBlocked) return;
    if (widget.currentUserId.isEmpty) return;
    if (widget.otherUserId == null || widget.otherUserId!.isEmpty) return;

    final ids = docs.take(25).map((d) => d.id).join('|');
    final key = '${widget.roomId}:${widget.currentUserId}:$ids';
    if (_lastSeenScheduleKey == key) return;
    _lastSeenScheduleKey = key;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _markMessagesAsSeen(docs);
    });
  }

  Future<void> _markMessagesAsSeen(
      List<DocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (widget.isBlocked) return;
    if (widget.currentUserId.isEmpty) return;
    if (widget.otherUserId == null || widget.otherUserId!.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    bool hasUpdates = false;

    for (final doc in docs) {
      final data = doc.data() ?? const <String, dynamic>{};
      final senderId = data['senderId'] as String?;
      final seenBy =
          (data['seenBy'] as List?)?.cast<String>() ?? const <String>[];

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
      try {
        await batch.commit();
      } catch (e, st) {
        debugPrint('[ChatMessageList] seenBy batch commit error: $e\n$st');
      }
    }

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
          '⚠️ Failed to reset unread count on seen: ${e.code} ${e.message}');
    }
  }

  // ================= PAGINATION =================

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || !_hasMore) return;
    if (widget.isBlocked) return;

    final max = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;

    if (offset >= (max - 300)) {
      _loadMoreOlder();
    }
  }

  Future<void> _loadMoreOlder() async {
    if (_isLoadingMore || !_hasMore) return;
    if (widget.isBlocked) return;

    setState(() => _isLoadingMore = true);
    final int myGen = _gen;

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      final cursor = _oldestDoc;
      if (cursor != null) {
        q = q.startAfterDocument(cursor);
      }

      final snap = await q.get();
      if (!mounted) return;
      if (myGen != _gen) return;

      if (snap.docs.isEmpty) {
        _hasMore = false;
        return;
      }

      for (final d in snap.docs) {
        _docMap.putIfAbsent(d.id, () => d);
      }

      _oldestDoc = snap.docs.last;

      if (snap.docs.length < _pageSize) {
        _hasMore = false;
      }

      setState(() {});
    } catch (e, st) {
      debugPrint('[ChatMessageList] _loadMoreOlder error: $e\n$st');
    } finally {
      if (mounted && myGen == _gen) setState(() => _isLoadingMore = false);
    }
  }

  // ================= LIVE LISTENER =================

  void _startLiveListener() {
    _liveSub?.cancel();
    final int myGen = _gen;

    _liveSub = FirebaseFirestore.instance
        .collection('privateChats')
        .doc(widget.roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(_liveWindow)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        if (myGen != _gen) return;
        if (widget.isBlocked) return;

        if (snap.docs.isEmpty) {
          _docMap.clear();
          _pendingLocalRemovals.clear();
          _oldestDoc = null;
          _hasMore = false;
          _isLoadingMore = false;
          setState(() {});
          return;
        }

        for (final change in snap.docChanges) {
          final doc = change.doc;

          if (_pendingLocalRemovals.contains(doc.id) &&
              change.type != DocumentChangeType.added) {
            if (change.type == DocumentChangeType.removed) {
              _pendingLocalRemovals.remove(doc.id);
            }
            continue;
          }

          if (change.type == DocumentChangeType.removed) {
            _docMap.remove(doc.id);
            continue;
          }

          _docMap[doc.id] = doc;
        }

        setState(() {});
      },
      onError: (e, st) {
        debugPrint('[ChatMessageList] live listener error: $e\n$st');
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

    final selected = await showModalBottomSheet<_MessageAction>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: kSurfaceAltColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final titleStyle = Theme.of(sheetContext).textTheme.bodyLarge?.copyWith(
          color: kTextPrimary,
          fontWeight: FontWeight.w700,
        );

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kTextSecondary.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: kErrorColor),
                title: Text(l10n.deleteMessageTitle, style: titleStyle),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_MessageAction.delete),
              ),
              ListTile(
                leading: Icon(Icons.flag_outlined,
                    color: kPrimaryGold.withOpacity(0.95)),
                title: Text(l10n.reportMessageTitle, style: titleStyle),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_MessageAction.report),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );

    if (selected == null) return;

    if (selected == _MessageAction.delete) {
      try {
        await ChatScreenDeletion.confirmAndDeleteMessage(
          context: context,
          roomId: widget.roomId,
          messageId: messageDoc.id,
          currentUserId: widget.currentUserId,
          otherUserId: widget.otherUserId,
        );
      } catch (e, st) {
        debugPrint('[ChatMessageList] confirmAndDeleteMessage failed: $e\n$st');
        await _toastError(l10n.deleteMessageFailed);
      }
      return;
    }

    if (selected == _MessageAction.report) {
      await ReportMessageDialog.open(
        context,
        roomId: widget.roomId,
        messageDoc: messageDoc,
      );
      return;
    }
  }

  // ================= UI =================

  Widget _buildOverlayMessage(String text) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: kTextPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      shadows: [
        const Shadow(
          color: Colors.black54,
          offset: Offset(0, 1),
          blurRadius: 4,
        ),
      ],
    );

    return ListView(
      reverse: true,
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + widget.bottomInset),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.isBlocked) {
      return _buildOverlayMessage(l10n.userBlockedInfo);
    }

    final visibleDocs = _docMap.values.where(_isVisibleForMe).toList()
      ..sort((a, b) => _effectiveTs(b).compareTo(_effectiveTs(a)));

    if (visibleDocs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scheduleMarkMessagesAsSeen(visibleDocs);
      });
    }

    final listPadding =
    EdgeInsets.fromLTRB(12, 12, 12, 12 + widget.bottomInset);

    if (visibleDocs.isEmpty) {
      return ListView(
        controller: _scrollController,
        reverse: true,
        padding: listPadding,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Text(
              l10n.noMessagesYet,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: kTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(
                    color: Colors.black54,
                    offset: Offset(0, 1),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final extraItems = <Widget>[];
    if (_isLoadingMore) {
      extraItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    }

    final maxWidth = MediaQuery.of(context).size.width * 0.7;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: listPadding,
      itemCount: visibleDocs.length + extraItems.length,
      itemBuilder: (context, index) {
        if (index < visibleDocs.length) {
          final doc = visibleDocs[index];
          final data = doc.data() ?? const <String, dynamic>{};

          final senderId = data['senderId'] as String?;
          final isMe = senderId == widget.currentUserId;

          final seenBy =
              (data['seenBy'] as List?)?.cast<String>() ?? const <String>[];

          final att = ChatAttachmentUtils.normalizeAttachment(data);
          final displayText =
          ChatAttachmentUtils.displayTextForMessage(data['text'], att);

          return RepaintBoundary(
            key: ValueKey(doc.id),
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: () => _onMessageLongPress(context, doc, isMe),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: MessageBubble(
                    text: displayText,
                    timeLabel: _formatDocTime(doc),
                    isMe: isMe,
                    isSeen: widget.otherUserId != null &&
                        widget.otherUserId!.isNotEmpty &&
                        seenBy.contains(widget.otherUserId),
                    fileUrl: att.url,
                    fileName: ChatAttachmentUtils.uiFileNameForAttachment(att),
                    fileType: att.type,
                  ),
                ),
              ),
            ),
          );
        }

        final extraIndex = index - visibleDocs.length;
        return extraItems[extraIndex];
      },
    );
  }
}

enum _MessageAction {
  delete,
  report,
}
