// lib/screens/chat/chat_message_list.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_attachment_utils.dart';
import '../../utils/time_utils.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/mw_reply_to.dart';
import '../../widgets/safety/report_message_dialog.dart';
import '../../widgets/ui/mw_feedback.dart';
import 'chat_screen_deletion.dart';

class ChatMessageList extends StatefulWidget {
  final String roomId;
  final String currentUserId;
  final String? otherUserId;
  final bool isBlocked;

  final double bottomInset;

  /// Reply callback (owned by ChatScreen)
  final ValueChanged<MwReplyTo>? onReply;

  /// Reactions writer (Firestore transaction in parent).
  final Future<void> Function(String messageId, String emoji)? onReactionTapAsync;

  const ChatMessageList({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.otherUserId,
    this.isBlocked = false,
    this.bottomInset = 0,
    this.onReply,
    this.onReactionTapAsync,
  });

  @override
  State<ChatMessageList> createState() => ChatMessageListState();
}

class ChatMessageListState extends State<ChatMessageList> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();

  final Map<String, DocumentSnapshot<Map<String, dynamic>>> _docMap = {};
  final Set<String> _pendingLocalRemovals = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveSub;

  DocumentSnapshot<Map<String, dynamic>>? _oldestDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  static const int _pageSize = 40;
  static const int _liveWindow = 40;

  int _gen = 0;
  String? _flashMessageId;

  bool _jumping = false;

  VoidCallback? _positionsCb;

  @override
  void initState() {
    super.initState();

    _positionsCb = _onPositionsChanged;
    _positionsListener.itemPositions.addListener(_positionsCb!);

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

    if (roomChanged || userChanged || blockedChanged) {
      _resetAllState();

      if (widget.isBlocked) return;

      _startLiveListener();
      _loadMoreOlder();
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();

    final cb = _positionsCb;
    if (cb != null) {
      _positionsListener.itemPositions.removeListener(cb);
    }

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

    _flashMessageId = null;
    _jumping = false;

    if (mounted) setState(() {});
  }

  Timestamp _effectiveTs(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final v = data?['createdAt'];
    if (v is Timestamp) return v;

    final v2 = data?['clientCreatedAt'];
    if (v2 is Timestamp) return v2;

    final v3 = data?['localCreatedAt'];
    if (v3 is Timestamp) return v3;

    return Timestamp.fromMillisecondsSinceEpoch(0);
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

  List<DocumentSnapshot<Map<String, dynamic>>> _computeVisibleDocs() {
    final list = _docMap.values.where(_isVisibleForMe).toList()
      ..sort((a, b) => _effectiveTs(b).compareTo(_effectiveTs(a)));
    return list;
  }

  int _indexOfMessageId(
      List<DocumentSnapshot<Map<String, dynamic>>> docs,
      String messageId,
      ) {
    for (int i = 0; i < docs.length; i++) {
      if (docs[i].id == messageId) return i;
    }
    return -1;
  }

  void _onPositionsChanged() {
    if (!mounted) return;
    if (widget.isBlocked) return;
    if (_isLoadingMore || !_hasMore) return;

    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    int maxVisible = -1;
    for (final p in positions) {
      if (p.index > maxVisible) maxVisible = p.index;
    }

    final visibleDocs = _computeVisibleDocs();
    final itemCount = visibleDocs.length + (_isLoadingMore ? 1 : 0);
    if (itemCount <= 0) return;

    if (maxVisible >= itemCount - 6) {
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
              change.type != DocumentChangeType.removed) {
            continue;
          }

          if (change.type == DocumentChangeType.removed) {
            _pendingLocalRemovals.remove(doc.id);
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

  Future<void> scrollToLatest({bool animated = true}) async {
    if (!mounted) return;
    if (!_itemScrollController.isAttached) return;

    if (!animated) {
      _itemScrollController.jumpTo(index: 0);
      return;
    }

    await _itemScrollController.scrollTo(
      index: 0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    );
  }

  Future<void> _flash(String messageId) async {
    if (!mounted) return;
    setState(() => _flashMessageId = messageId);
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    if (_flashMessageId == messageId) {
      setState(() => _flashMessageId = null);
    }
  }

  Future<void> _jumpToIndex(int index) async {
    if (!_itemScrollController.isAttached) return;

    _itemScrollController.jumpTo(index: index);

    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    if (_itemScrollController.isAttached) {
      await _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _fetchMessageDoc(
      String messageId) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId)
          .collection('messages')
          .doc(messageId);

      final snap = await ref.get();
      if (!snap.exists) return null;
      return snap;
    } catch (_) {
      return null;
    }
  }

  Future<void> _jumpToMessage(String messageId) async {
    final id = messageId.trim();
    if (id.isEmpty) return;
    if (_jumping) return;
    if (widget.isBlocked) return;

    _jumping = true;
    final int myGen = _gen;

    try {
      {
        final visibleDocs = _computeVisibleDocs();
        final idx = _indexOfMessageId(visibleDocs, id);
        if (idx >= 0) {
          await _jumpToIndex(idx);
          await _flash(id);
          return;
        }
      }

      final target = await _fetchMessageDoc(id);
      if (!mounted || myGen != _gen) return;

      if (target == null) {
        final l10n = AppLocalizations.of(context)!;
        await MwFeedback.show(
          context,
          message: l10n.originalMessageNotFound ?? 'Original message not found',
        );
        return;
      }

      final targetTs = _effectiveTs(target);

      const int maxLoads = 10;
      for (int i = 0; i < maxLoads; i++) {
        if (!mounted || myGen != _gen) return;

        final visibleDocs = _computeVisibleDocs();
        final idxNow = _indexOfMessageId(visibleDocs, id);
        if (idxNow >= 0) {
          await _jumpToIndex(idxNow);
          await _flash(id);
          return;
        }

        if (!_hasMore) break;

        final oldest = _oldestDoc;
        final oldestTs = oldest == null ? null : _effectiveTs(oldest);

        final stillNewerThanTarget =
        oldestTs == null ? true : oldestTs.compareTo(targetTs) > 0;

        if (stillNewerThanTarget) {
          await _loadMoreOlder();
          if (!mounted || myGen != _gen) return;
          continue;
        }

        await _loadMoreOlder();
        if (!mounted || myGen != _gen) return;
      }

      final finalDocs = _computeVisibleDocs();
      final finalIdx = _indexOfMessageId(finalDocs, id);
      if (finalIdx >= 0) {
        await _jumpToIndex(finalIdx);
        await _flash(id);
        return;
      }

      final l10n = AppLocalizations.of(context)!;
      await MwFeedback.show(
        context,
        message: l10n.originalMessageNotFound ?? 'Original message not found',
      );
    } finally {
      _jumping = false;
    }
  }

  Future<void> _openActionsMenu(
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
              const SizedBox(height: 10),

              ListTile(
                leading: const Icon(Icons.delete_outline, color: kErrorColor),
                title: Text(l10n.deleteMessageTitle, style: titleStyle),
                onTap: () => Navigator.of(sheetContext).pop(_MessageAction.delete),
              ),
              ListTile(
                leading: Icon(Icons.flag_outlined, color: kPrimaryGold.withOpacity(0.95)),
                title: Text(l10n.reportMessageTitle, style: titleStyle),
                onTap: () => Navigator.of(sheetContext).pop(_MessageAction.report),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );

    if (selected == null) return;

    if (selected == _MessageAction.reply) {
      final data = messageDoc.data() ?? const <String, dynamic>{};
      final fallbackType = (data['type'] ?? 'text').toString();
      final reply =
      MwReplyTo.fromMessageDoc(doc: messageDoc, fallbackType: fallbackType);

      widget.onReply?.call(reply);
      // await MwFeedback.show(
      //   context,
      //   message: l10n.replyingToMessage ?? 'Replying…',
      // );
      return;
    }

    if (selected == _MessageAction.delete) {
      _pendingLocalRemovals.add(messageDoc.id);
      _docMap.remove(messageDoc.id);
      if (mounted) setState(() {});

      try {
        await ChatScreenDeletion.confirmAndDeleteMessage(
          context: context,
          roomId: widget.roomId,
          messageId: messageDoc.id,
          currentUserId: widget.currentUserId,
          otherUserId: widget.otherUserId,
        );
        await _toastSuccess(l10n.messageDeletedSuccess);
      } catch (e, st) {
        debugPrint('[ChatMessageList] confirmAndDeleteMessage failed: $e\n$st');

        _pendingLocalRemovals.remove(messageDoc.id);
        if (mounted) setState(() {});

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

  Widget _buildOverlayMessage(String text) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: kTextPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      shadows: const [
        Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 4),
      ],
    );

    return ListView(
      reverse: true,
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + widget.bottomInset),
      children: [
        const SizedBox(height: 80),
        Center(child: Text(text, textAlign: TextAlign.center, style: style)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.isBlocked) {
      return _buildOverlayMessage(l10n.userBlockedInfo);
    }

    final visibleDocs = _computeVisibleDocs();

    final listPadding =
    EdgeInsets.fromLTRB(12, 12, 12, 12 + widget.bottomInset);

    if (visibleDocs.isEmpty) {
      return ListView(
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

    final bool showLoadingItem = _isLoadingMore;
    final maxWidth = MediaQuery.of(context).size.width * 0.7;
    final int itemCount = visibleDocs.length + (showLoadingItem ? 1 : 0);

    final bool swipeReplyEnabled =
        widget.onReply != null && !widget.isBlocked;

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _positionsListener,
      reverse: true,
      padding: listPadding,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= visibleDocs.length) {
          return Padding(
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
          );
        }

        final doc = visibleDocs[index];
        final data = doc.data() ?? const <String, dynamic>{};

        final senderId = data['senderId'] as String?;
        final isMe = senderId == widget.currentUserId;

        final seenBy =
            (data['seenBy'] as List?)?.cast<String>() ?? const <String>[];

        final att = ChatAttachmentUtils.normalizeAttachment(data);
        final displayText =
        ChatAttachmentUtils.displayTextForMessage(data['text'], att);

        final replyTo = (data['replyTo'] is Map)
            ? (data['replyTo'] as Map).cast<String, dynamic>()
            : null;

        final reactions = (data['reactions'] is Map)
            ? (data['reactions'] as Map).cast<String, dynamic>()
            : null;

        final bool flash = _flashMessageId == doc.id;

        // ✅ Build reply snapshot ONCE per row (used by swipe + menu)
        final fallbackType = (data['type'] ?? 'text').toString();
        final replySnap =
        MwReplyTo.fromMessageDoc(doc: doc, fallbackType: fallbackType);

        void handleSwipeReply() {
          if (!swipeReplyEnabled) return;
          widget.onReply?.call(replySnap);
          // unawaited(
          //   MwFeedback.show(
          //     context,
          //     message: l10n.replyingToMessage ?? 'Replying…',
          //   ),
          // );
        }

        final bubble = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: flash
                  ? [
                BoxShadow(
                  color: kPrimaryGold.withOpacity(0.22),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
                  : const [],
            ),
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
              replyTo: replyTo,
              currentUserId: widget.currentUserId,
              reactions: reactions,
              onReactionTapAsync: widget.onReactionTapAsync == null
                  ? null
                  : (emoji) => widget.onReactionTapAsync!(doc.id, emoji),
              onReplyPreviewTap: (targetId) => _jumpToMessage(targetId),

              // ✅ NEW: swipe-to-reply
              swipeReplyEnabled: swipeReplyEnabled,
              onSwipeReply: handleSwipeReply,
            ),
          ),
        );

        return RepaintBoundary(
          key: ValueKey(doc.id),
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isMe) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    padding: const EdgeInsets.only(right: 4),
                    icon: Icon(
                      Icons.more_horiz,
                      color: Colors.white.withOpacity(0.55),
                    ),
                    onPressed: () => _openActionsMenu(context, doc, isMe),
                    tooltip: l10n.more ?? 'More',
                  ),
                  bubble,
                ] else ...[
                  bubble,
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    padding: const EdgeInsets.only(left: 4),
                    icon: Icon(
                      Icons.more_horiz,
                      color: Colors.white.withOpacity(0.55),
                    ),
                    onPressed: () => _openActionsMenu(context, doc, isMe),
                    tooltip: l10n.more ?? 'More',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _MessageAction {
  reply,
  delete,
  report,
}
