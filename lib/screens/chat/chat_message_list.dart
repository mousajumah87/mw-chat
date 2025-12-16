// lib/screens/chat/chat_message_list.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../widgets/chat/message_bubble.dart';
import '../../utils/time_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

// reuse shared dialogs/helpers
import '../../widgets/safety/report_message_dialog.dart';
import '../../widgets/ui/mw_feedback.dart';

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
  String? _lastSeenScheduleKey;

  // Friend status
  String? _friendStatus;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _friendSub;

  // Pagination + realtime
  final ScrollController _scrollController = ScrollController();

  /// Single source of truth: all loaded docs in a map to prevent duplicates
  final Map<String, DocumentSnapshot<Map<String, dynamic>>> _docMap = {};

  /// For delete race hardening
  final Set<String> _pendingLocalRemovals = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveSub;

  DocumentSnapshot<Map<String, dynamic>>? _oldestDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  static const int _pageSize = 40;
  static const int _liveWindow = 40;

  int _gen = 0; // ignore late callbacks after room change

  @override
  void initState() {
    super.initState();

    _listenFriendStatus();
    _scrollController.addListener(_onScroll);

    if (!widget.isBlocked) {
      _startLiveListener();
      _loadMoreOlder(); // initial older page
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
        if (mounted) setState(() => _friendStatus = status);
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

  bool _isVisibleForMe(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final hiddenFor = (data['hiddenFor'] as List?)?.cast<String>() ?? const <String>[];
    return !hiddenFor.contains(widget.currentUserId);
  }

  // ================= SEEN HANDLING =================

  void _scheduleMarkMessagesAsSeen(List<DocumentSnapshot<Map<String, dynamic>>> docs) {
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

  Future<void> _markMessagesAsSeen(List<DocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (widget.isBlocked) return;
    if (widget.currentUserId.isEmpty) return;
    if (widget.otherUserId == null || widget.otherUserId!.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    bool hasUpdates = false;

    for (final doc in docs) {
      final data = doc.data() ?? const <String, dynamic>{};
      final senderId = data['senderId'] as String?;
      final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? const <String>[];

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
      debugPrint('⚠️ Failed to reset unread count on seen: ${e.code} ${e.message}');
    }
  }

  // ================= UNREAD CONSISTENCY =================

  Future<void> _decrementUnreadIfNeeded(DocumentSnapshot<Map<String, dynamic>> messageDoc) async {
    if (widget.otherUserId == null) return;

    final data = messageDoc.data();
    if (data == null) return;

    final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? [];
    if (seenBy.contains(widget.otherUserId)) return;

    final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(roomRef);
        final data = snap.data() as Map<String, dynamic>?;

        final unreadCounts = (data?['unreadCounts'] as Map?)?.cast<String, dynamic>() ?? {};
        final cur = (unreadCounts[widget.otherUserId!] as num?)?.toInt() ?? 0;
        final next = cur - 1;

        tx.set(
          roomRef,
          {
            'unreadCounts': {widget.otherUserId!: next < 0 ? 0 : next},
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint('[ChatMessageList] decrement unread txn failed: $e');
    }
  }

  // ================= PAGINATION =================

  void _onScroll() {
    // reverse:true means "older side" is maxScrollExtent.
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || !_hasMore) return;
    if (widget.isBlocked) return;

    final max = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;

    if (offset >= (max - 300)) {
      _loadMoreOlder();
    }
  }

  void _recomputeOldest() {
    if (_docMap.isEmpty) {
      _oldestDoc = null;
      return;
    }
    DocumentSnapshot<Map<String, dynamic>>? oldest;
    Timestamp? oldestTs;

    for (final d in _docMap.values) {
      final ts = _effectiveTs(d);
      if (oldest == null) {
        oldest = d;
        oldestTs = ts;
        continue;
      }
      if (ts.compareTo(oldestTs!) < 0) {
        oldest = d;
        oldestTs = ts;
      }
    }
    _oldestDoc = oldest;
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

      final oldest = _oldestDoc;
      if (oldest != null) {
        q = q.startAfterDocument(oldest);
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

      _recomputeOldest();

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

          // If we removed locally already, ignore redundant events
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

          // added / modified
          _docMap[doc.id] = doc;
        }

        _recomputeOldest();
        setState(() {});
      },
      onError: (e, st) {
        debugPrint('[ChatMessageList] live listener error: $e\n$st');
      },
    );
  }

  // ================= STORAGE HELPERS (for deleting message attachments) =================

  Set<String> _extractStoragePathsFromMessage(Map<String, dynamic> data) {
    final paths = <String>{};

    void add(dynamic v) {
      if (v is String && v.trim().isNotEmpty) paths.add(v.trim());
    }

    add(data['storagePath']);
    add(data['thumbStoragePath']);
    add(data['thumbnailStoragePath']);

    final attachments = data['attachments'];
    if (attachments is List) {
      for (final item in attachments) {
        if (item is Map) {
          add(item['storagePath']);
          add(item['thumbStoragePath']);
          add(item['thumbnailStoragePath']);
        }
      }
    }

    final media = data['media'];
    if (media is Map) {
      add(media['storagePath']);
      add(media['thumbStoragePath']);
      add(media['thumbnailStoragePath']);
    }

    // Back-compat: try parse URLs too
    final urlFields = [
      data['fileUrl'],
      data['mediaUrl'],
      data['imageUrl'],
      data['videoUrl'],
      data['audioUrl'],
      data['voiceUrl'],
      data['thumbnailUrl'],
      data['thumbUrl'],
      data['url'],
    ];

    for (final v in urlFields) {
      if (v is String && v.trim().isNotEmpty) {
        final p = _storagePathFromUrl(v.trim());
        if (p != null && p.isNotEmpty) paths.add(p);
      }
    }

    return paths;
  }

  String? _storagePathFromUrl(String url) {
    try {
      final u = Uri.parse(url);

      // gs://bucket/path/to/object
      if (u.scheme == 'gs') {
        final p = u.path;
        if (p.isEmpty) return null;
        return p.startsWith('/') ? p.substring(1) : p;
      }

      // https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<encodedPath>
      if (u.host.contains('firebasestorage.googleapis.com')) {
        final seg = u.pathSegments;
        final oIndex = seg.indexOf('o');
        if (oIndex != -1 && oIndex + 1 < seg.length) {
          return Uri.decodeComponent(seg[oIndex + 1]);
        }
      }

      // https://storage.googleapis.com/download/storage/v1/b/<bucket>/o/<encodedPath>
      if (u.host.contains('storage.googleapis.com')) {
        final seg = u.pathSegments;
        final oIndex = seg.indexOf('o');
        if (oIndex != -1 && oIndex + 1 < seg.length) {
          return Uri.decodeComponent(seg[oIndex + 1]);
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _purgeStorageForMessagePaths(Set<String> paths) async {
    if (paths.isEmpty) return;

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('purgeChatRoom');

      await fn.call({
        'roomId': widget.roomId,
        'paths': paths.toList(growable: false),
      });
    } catch (e) {
      // Non-fatal: message delete should still proceed
      debugPrint('[ChatMessageList] purgeChatRoom failed (non-fatal): $e');
    }
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
              if (isMe) ...[
                ListTile(
                  leading: Icon(Icons.visibility_off_outlined,
                      color: kTextSecondary.withOpacity(0.95)),
                  title: Text(l10n.deleteChatForMe, style: titleStyle),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_MessageAction.deleteForMe),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: kErrorColor),
                  title: Text(l10n.deleteMessageTitle, style: titleStyle),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_MessageAction.deleteForBoth),
                ),
              ],
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

    void removeLocalNow(String id) {
      _pendingLocalRemovals.add(id);
      _docMap.remove(id);
      if (mounted) setState(() {});
    }

    void restoreLocalNow(DocumentSnapshot<Map<String, dynamic>> doc) {
      _pendingLocalRemovals.remove(doc.id);
      _docMap[doc.id] = doc;
      if (mounted) setState(() {});
    }

    // -------- Delete for me (hide) --------
    if (selected == _MessageAction.deleteForMe && isMe) {
      try {
        await messageDoc.reference.update({
          'hiddenFor': FieldValue.arrayUnion([widget.currentUserId]),
        });
        removeLocalNow(messageDoc.id);
        await _toastSuccess(l10n.deletedForMe);
      } on FirebaseException catch (e, st) {
        debugPrint('[ChatMessageList] deleteForMe failed: ${e.code} ${e.message}\n$st');
        await _toastError(l10n.chatHistoryDeleteFailed);
      } catch (e, st) {
        debugPrint('[ChatMessageList] deleteForMe failed: $e\n$st');
        await _toastError(l10n.chatHistoryDeleteFailed);
      }
      return;
    }

    // -------- Delete for both (real delete) --------
    if (selected == _MessageAction.deleteForBoth && isMe) {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: kSurfaceAltColor,
          surfaceTintColor: Colors.transparent,
          title: Text(
            l10n.deleteMessageTitle,
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
              color: kTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            l10n.deleteMessageConfirm,
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
              color: kTextSecondary.withOpacity(0.95),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                l10n.delete,
                style: const TextStyle(color: kErrorColor),
              ),
            ),
          ],
        ),
      ) ??
          false;

      if (!confirmed) return;

      // Optimistic UI removal
      removeLocalNow(messageDoc.id);

      try {
        // 1) best effort unread decrement
        try {
          await _decrementUnreadIfNeeded(messageDoc);
        } catch (_) {}

        // 2) delete storage files for this message (server-side, secure)
        final data = messageDoc.data() ?? const <String, dynamic>{};
        final paths = _extractStoragePathsFromMessage(Map<String, dynamic>.from(data));
        await _purgeStorageForMessagePaths(paths);

        // 3) delete message doc (source of truth)
        await messageDoc.reference.delete();

        await _toastSuccess(l10n.deleteMessageSuccess);
      } on FirebaseException catch (e, st) {
        debugPrint('[ChatMessageList] deleteForBoth failed: ${e.code} ${e.message}\n$st');
        restoreLocalNow(messageDoc);
        await _toastError(l10n.deleteMessageFailed);
      } catch (e, st) {
        debugPrint('[ChatMessageList] deleteForBoth failed: $e\n$st');
        restoreLocalNow(messageDoc);
        await _toastError(l10n.deleteMessageFailed);
      }

      return;
    }

    // -------- Report --------
    if (selected == _MessageAction.report) {
      await ReportMessageDialog.open(
        context,
        roomId: widget.roomId,
        messageDoc: messageDoc,
      );
    }
  }

  // ================= UI =================

  Widget _buildOverlayMessage(String text) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: kTextPrimary,
      fontSize: 14,
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
      padding: const EdgeInsets.all(24),
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
      _scheduleMarkMessagesAsSeen(visibleDocs);
    }

    if (visibleDocs.isEmpty) {
      return ListView(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.all(12),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Text(
              l10n.noMessagesYet,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: kTextPrimary,
                fontSize: 14,
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
      padding: const EdgeInsets.all(12),
      itemCount: visibleDocs.length + extraItems.length,
      itemBuilder: (context, index) {
        if (index < visibleDocs.length) {
          final doc = visibleDocs[index];
          final data = doc.data() ?? const <String, dynamic>{};

          final senderId = data['senderId'] as String?;
          final isMe = senderId == widget.currentUserId;

          final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? const <String>[];

          return RepaintBoundary(
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: () => _onMessageLongPress(context, doc, isMe),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: MessageBubble(
                    key: ValueKey(doc.id),
                    text: (data['text'] ?? '').toString(),
                    timeLabel: formatTimestamp(data['createdAt']),
                    isMe: isMe,
                    isSeen: widget.otherUserId != null &&
                        widget.otherUserId!.isNotEmpty &&
                        seenBy.contains(widget.otherUserId),
                    fileUrl: data['fileUrl'] as String?,
                    fileName: data['fileName'] as String?,
                    fileType: data['type']?.toString(),
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
  deleteForMe,
  deleteForBoth,
  report,
}
