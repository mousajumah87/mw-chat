// lib/screens/chat/chat_message_list.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_attachment_utils.dart';
import '../../utils/time_utils.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_reactions.dart'; // ✅ MwReactionOverlay.hide()
import '../../widgets/chat/mw_reply_to.dart';
import '../../widgets/ui/mw_feedback.dart';

class ChatMessageList extends StatefulWidget {
  final String roomId;
  final String currentUserId;
  final String? otherUserId;
  final bool isBlocked;

  /// Extra padding to reserve space at the bottom (TypingIndicator + composer)
  final double bottomInset;

  /// Reply tap callback (owned by ChatScreen)
  final ValueChanged<MwReplyTo>? onReply;

  /// Reactions writer (Firestore transaction in parent).
  final Future<void> Function(String messageId, String emoji)? onReactionTapAsync;

  /// Back-compat: single selected id
  final String? selectedMessageId;

  /// Preferred: multi-select ids (WhatsApp-style)
  final Set<String>? selectedMessageIds;

  /// Called on long-press to select/toggle a message (ChatScreen should update header)
  final void Function(
      DocumentSnapshot<Map<String, dynamic>> messageDoc,
      bool isMe,
      )? onMessageLongPress;

  /// Called on tap (usually clears selection / closes keyboard / overlays)
  final VoidCallback? onMessageTap;

  /// Optional: tap callback with message doc (lets ChatScreen toggle selection on tap)
  final void Function(
      DocumentSnapshot<Map<String, dynamic>> messageDoc,
      bool isMe,
      )? onMessageTapWithDoc;

  const ChatMessageList({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.otherUserId,
    this.isBlocked = false,
    this.bottomInset = 0,
    this.onReply,
    this.onReactionTapAsync,
    this.selectedMessageId,
    this.selectedMessageIds,
    this.onMessageLongPress,
    this.onMessageTap,
    this.onMessageTapWithDoc,
  });

  @override
  State<ChatMessageList> createState() => ChatMessageListState();
}

class ChatMessageListState extends State<ChatMessageList> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();

  final Map<String, DocumentSnapshot<Map<String, dynamic>>> _docMap = {};
  final Set<String> _pendingLocalRemovals = <String>{};

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

  /// ✅ "at latest" is now based on whether newest message is VISIBLE at all.
  bool _atLatest = true;

  bool _showNewIndicator = false;
  int _newCount = 0;

  // ✅ DEBUG: trace badge lifecycle
  int _dbgSeq = 0;

  // ✅ Prevent one-frame "atLatest" glitches from instantly hiding New badge
  DateTime? _newBadgeShownAt;
  static const Duration _newBadgeMinVisible = Duration(milliseconds: 350);

  // ✅ track newest message id reliably
  String? _latestMessageId;

  // ✅ debounced auto-scroll (avoid double jump)
  bool _pendingAutoScroll = false;
  bool _hasPositions = false;

  // ✅ IMPORTANT: keep the last list used to build UI (so positions indices match)
  List<DocumentSnapshot<Map<String, dynamic>>> _lastBuiltDocs = const [];

  // ✅ NEW: when user chooses "Reply" on an older message, we want to jump to latest
  bool _pendingReplyJumpToLatest = false;

  void _log(String msg) {
    // keep it very cheap + only in debug
    assert(() {
      debugPrint('[ChatMessageList][${++_dbgSeq}] $msg');
      return true;
    }());
  }

  String _posSummary() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return 'pos=EMPTY';

    // show a compact view: min/max visible index + whether idx0 is visible/pinned-ish
    int minI = 1 << 30;
    int maxI = -1;
    ItemPosition? p0;
    for (final p in positions) {
      minI = math.min(minI, p.index);
      maxI = math.max(maxI, p.index);
      if (p.index == 0) p0 = p;
    }

    final z = p0 == null
        ? 'idx0=NA'
        : 'idx0=[L=${p0.itemLeadingEdge.toStringAsFixed(2)},T=${p0.itemTrailingEdge.toStringAsFixed(2)}]';
    return 'pos=min=$minI max=$maxI $z';
  }

  @override
  void initState() {
    super.initState();

    _positionsCb = _onPositionsChanged;
    _positionsListener.itemPositions.addListener(_positionsCb!);

    if (!widget.isBlocked) {
      _startLiveListener();
      unawaited(_loadMoreOlder());
    }
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final roomChanged = oldWidget.roomId != widget.roomId;
    final userChanged = oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.otherUserId != widget.otherUserId;
    final blockedChanged = oldWidget.isBlocked != widget.isBlocked;

    if (!roomChanged && !userChanged && !blockedChanged) return;

    _resetAllState();

    if (widget.isBlocked) return;

    _startLiveListener();
    unawaited(_loadMoreOlder());
  }

  @override
  void dispose() {
    try {
      MwReactionOverlay.hide();
    } catch (_) {}

    _liveSub?.cancel();

    final cb = _positionsCb;
    if (cb != null) {
      _positionsListener.itemPositions.removeListener(cb);
    }

    super.dispose();
  }

  void _resetAllState() {
    try {
      MwReactionOverlay.hide();
    } catch (_) {}

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

    _atLatest = true;
    _showNewIndicator = false;
    _newCount = 0;

    _latestMessageId = null;

    _pendingAutoScroll = false;
    _lastBuiltDocs = const [];

    _pendingReplyJumpToLatest = false;

    if (mounted) setState(() {});
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

    return Timestamp.fromMillisecondsSinceEpoch(0);
  }

  String _formatDocTime(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final ts = data?['createdAt'] ?? data?['clientCreatedAt'] ?? data?['localCreatedAt'];
    return formatTimestamp(ts);
  }

  bool _isVisibleForMe(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final hiddenFor = (data['hiddenFor'] as List?)?.cast<String>() ?? const <String>[];
    return !hiddenFor.contains(widget.currentUserId);
  }

  bool _isSelected(String messageId) {
    final ids = widget.selectedMessageIds;
    if (ids != null) return ids.contains(messageId);
    return (widget.selectedMessageId ?? '') == messageId;
  }

  bool _isSelectionMode() {
    final ids = widget.selectedMessageIds;
    if (ids != null) return ids.isNotEmpty;
    return (widget.selectedMessageId ?? '').isNotEmpty;
  }

  // ================= COMPUTE SORTED VISIBLE DOCS =================

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

  // ================= SCROLL / POSITION HELPERS =================

  bool _isLatestVisibleFromPositions() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return false; // ✅ unknown, don’t assume atLatest

    for (final p in positions) {
      if (p.index == 0) {
        return p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1;
      }
    }
    return false;
  }

  bool _isLatestPinnedFromPositions() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return false;

    for (final p in positions) {
      if (p.index == 0) {
        final visible = p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1;
        if (!visible) return false;
        return p.itemTrailingEdge >= 0.98;
      }
    }
    return false;
  }

  _ScrollAnchor? _captureAnchorIfNeeded() {
    if (!_itemScrollController.isAttached) return null;
    if (_atLatest) return null;

    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return null;

    ItemPosition? best;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0) continue;
      if (p.itemLeadingEdge >= 1) continue;
      if (best == null || p.itemLeadingEdge < best!.itemLeadingEdge) {
        best = p;
      }
    }
    if (best == null) return null;

    final docs = _lastBuiltDocs;
    if (best.index < 0 || best.index >= docs.length) return null;

    return _ScrollAnchor(
      messageId: docs[best.index].id,
      alignment: best.itemLeadingEdge.clamp(0.0, 1.0),
    );
  }

  void _restoreAnchorNextFrame(_ScrollAnchor? anchor) {
    if (anchor == null) return;
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_itemScrollController.isAttached) return;

      final docs = _lastBuiltDocs;
      final idx = _indexOfMessageId(docs, anchor.messageId);
      if (idx < 0) return;

      try {
        _itemScrollController.jumpTo(index: idx, alignment: anchor.alignment);
      } catch (_) {}
    });
  }

  void _scheduleAutoScrollToLatest() {
    if (_pendingAutoScroll) return;
    if (!_hasPositions) return;
    _pendingAutoScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _pendingAutoScroll = false;
      if (!mounted) return;
      if (!_itemScrollController.isAttached) return;

      // ✅ Only auto-scroll when truly pinned (prevents jumping while typing)
      if (!_isLatestPinnedFromPositions()) return;

      // ✅ no “landing on previous newest”
      await _scrollToLatestExact(animated: false);
    });
  }

  // ✅ NEW: used when user chooses Reply while reading older messages.
  // Always jump to latest so the input bar / reply composer is visible at the bottom.
  void _requestJumpToLatestForReply() {
    if (!mounted) return;

    // Clear "New" badge immediately (reply action implies user is going to the bottom)
    if (_showNewIndicator || _newCount != 0) {
      setState(() {
        _showNewIndicator = false;
        _newCount = 0;
        _newBadgeShownAt = null;
      });
    }

    // If controller/positions not ready yet, defer until we get positions.
    if (!_itemScrollController.isAttached || !_hasPositions) {
      _pendingReplyJumpToLatest = true;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_itemScrollController.isAttached) {
        _pendingReplyJumpToLatest = true;
        return;
      }
      await _scrollToLatestExact(animated: false);

      if (!mounted) return;
      // Best-effort update state so indicator won't pop again right away.
      if (_atLatest == false) {
        setState(() => _atLatest = true);
      }
    });
  }

  // ================= POSITIONS LISTENER =================
  void _onPositionsChanged() {
    if (!mounted) return;

    final positions = _positionsListener.itemPositions.value;

    // ✅ mark positions ready once we get any layout positions
    if (positions.isNotEmpty && !_hasPositions) {
      _hasPositions = true;
    }

    // ✅ If we were waiting to jump to bottom for Reply, do it as soon as we can.
    if (_pendingReplyJumpToLatest && _hasPositions && _itemScrollController.isAttached) {
      _pendingReplyJumpToLatest = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (!_itemScrollController.isAttached) return;
        await _scrollToLatestExact(animated: false);
        if (!mounted) return;
        if (_atLatest == false) setState(() => _atLatest = true);
      });
    }

    // ✅ if positions are empty, we can't reliably decide latest visibility
    // so keep the last known _atLatest (do NOT flip it here)
    final bool newAtLatest = positions.isEmpty ? _atLatest : _isLatestVisibleFromPositions();

    if (newAtLatest != _atLatest) {
      setState(() => _atLatest = newAtLatest);
    }

    // ✅ if newest visible, clear badge (respect grace window)
    if (newAtLatest && _showNewIndicator) {
      final shownAt = _newBadgeShownAt;
      final tooSoon = shownAt != null && DateTime.now().difference(shownAt) < _newBadgeMinVisible;

      if (!tooSoon) {
        setState(() {
          _showNewIndicator = false;
          _newCount = 0;
          _newBadgeShownAt = null;
        });
      }
    }

    // ================= load-more pagination =================

    if (widget.isBlocked) return;
    if (_isLoadingMore || !_hasMore) return;

    // ✅ if positions empty, can't detect bottom-near threshold
    if (positions.isEmpty) return;

    int maxVisibleIndex = -1;
    for (final p in positions) {
      if (p.index > maxVisibleIndex) maxVisibleIndex = p.index;
    }

    final docs = _lastBuiltDocs;
    if (docs.isEmpty) return;

    if (maxVisibleIndex >= docs.length - 6) {
      unawaited(_loadMoreOlder());
    }
  }

  // ================= PAGINATION =================

  Future<void> _loadMoreOlder() async {
    if (_isLoadingMore || !_hasMore) return;
    if (widget.isBlocked) return;

    if (mounted) setState(() => _isLoadingMore = true);
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
      if (!mounted || myGen != _gen) return;

      if (snap.docs.isEmpty) {
        _hasMore = false;
        return;
      }

      for (final d in snap.docs) {
        _docMap.putIfAbsent(d.id, () => d);
      }

      _oldestDoc = snap.docs.last;
      if (snap.docs.length < _pageSize) _hasMore = false;

      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('[ChatMessageList] _loadMoreOlder error: $e\n$st');
    } finally {
      if (!mounted || myGen != _gen) return;
      setState(() => _isLoadingMore = false);
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

        // ✅ use the correct "visible" logic for indicator decisions
        final bool latestVisibleNow = _hasPositions ? _atLatest : false;

        final anchor = latestVisibleNow ? null : _captureAnchorIfNeeded();

        if (snap.docs.isEmpty) {
          setState(() {
            _docMap.clear();
            _pendingLocalRemovals.clear();
            _oldestDoc = null;
            _hasMore = false;
            _isLoadingMore = false;

            _showNewIndicator = false;
            _newCount = 0;
            _latestMessageId = null;
          });
          return;
        }

        bool changedSomething = false;
        for (final change in snap.docChanges) {
          final doc = change.doc;

          if (_pendingLocalRemovals.contains(doc.id) && change.type != DocumentChangeType.removed) {
            continue;
          }

          if (change.type == DocumentChangeType.removed) {
            _pendingLocalRemovals.remove(doc.id);
            if (_docMap.remove(doc.id) != null) changedSomething = true;
            continue;
          }

          final prev = _docMap[doc.id];
          _docMap[doc.id] = doc;
          if (prev == null || prev.data() != doc.data()) {
            changedSomething = true;
          }
        }

        if (!changedSomething) {
          _restoreAnchorNextFrame(anchor);
          return;
        }

        final visibleDocsNow = _computeVisibleDocs();
        final newest = visibleDocsNow.isNotEmpty ? visibleDocsNow.first : null;

        // ✅ always track the real newest id
        _latestMessageId = newest?.id;

        // detect NEW message from changes list (added) where sender != me
        bool addedFromOther = false;
        for (final c in snap.docChanges) {
          if (c.type == DocumentChangeType.added) {
            final data = c.doc.data() ?? const <String, dynamic>{};
            final senderId = data['senderId'] as String?;
            if (senderId != null && senderId != widget.currentUserId) {
              addedFromOther = true;
              break;
            }
          }
        }

        if (latestVisibleNow) {
          final shownAt = _newBadgeShownAt;
          final tooSoon = shownAt != null &&
              DateTime.now().difference(shownAt) < _newBadgeMinVisible;

          if ((_showNewIndicator || _newCount != 0) && !tooSoon) {
            setState(() {
              _showNewIndicator = false;
              _newCount = 0;
              _newBadgeShownAt = null;
            });
          } else {
            if (tooSoon && _showNewIndicator) {
            }
            setState(() {});
          }

          if (_hasPositions) {
            _scheduleAutoScrollToLatest();
          }
          return;
        }

        // not at latest => show indicator only if new came from other
        setState(() {
          if (addedFromOther) {
            _showNewIndicator = true;
            _newCount = (_newCount + 1).clamp(1, 9999);
            _newBadgeShownAt = DateTime.now(); // ✅
          } else {
          }
        });

        _restoreAnchorNextFrame(anchor);
      },
      onError: (e, st) {
        debugPrint('[ChatMessageList] live listener error: $e\n$st');
      },
    );
  }

  // ================= ✅ EXACT SCROLL TO NEWEST =================

  Future<void> _scrollToLatestExact({required bool animated}) async {
    if (!mounted) return;
    if (!_itemScrollController.isAttached) return;

    final latestId = _latestMessageId;
    final docs = _lastBuiltDocs;

    int targetIndex = 0;
    if (latestId != null) {
      final idx = _indexOfMessageId(docs, latestId);
      if (idx >= 0) targetIndex = idx;
    }

    try {
      _itemScrollController.jumpTo(index: targetIndex, alignment: 0.0);
    } catch (_) {}

    if (!animated) return;

    try {
      await _itemScrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        alignment: 0.0,
      );
    } catch (_) {}
  }

  // Public helper
  Future<void> scrollToLatest({bool animated = true}) async {
    await _scrollToLatestExact(animated: animated);
  }

  void _onTapNewIndicator() async {
    if (!mounted) return;
    setState(() {
      _showNewIndicator = false;
      _newCount = 0;
    });

    await _scrollToLatestExact(animated: false);
  }

  // ================= JUMP TO MESSAGE (reply preview) =================

  Future<void> _flash(String messageId) async {
    if (!mounted) return;
    setState(() => _flashMessageId = messageId);

    await Future<void>.delayed(const Duration(milliseconds: 650));
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

  Future<DocumentSnapshot<Map<String, dynamic>>?> _fetchMessageDoc(String messageId) async {
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
        final docs = _lastBuiltDocs;
        final idx = _indexOfMessageId(docs, id);
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
        MwFeedback.show(
          context,
          message: l10n.originalMessageNotFound ?? 'Original message not found',
          type: MwFeedbackType.info,
        );
        return;
      }

      final targetTs = _effectiveTs(target);

      const int maxLoads = 10;
      for (int i = 0; i < maxLoads; i++) {
        if (!mounted || myGen != _gen) return;

        final docs = _lastBuiltDocs;
        final idxNow = _indexOfMessageId(docs, id);
        if (idxNow >= 0) {
          await _jumpToIndex(idxNow);
          await _flash(id);
          return;
        }

        if (!_hasMore) break;

        final oldest = _oldestDoc;
        final oldestTs = oldest == null ? null : _effectiveTs(oldest);

        final stillNewerThanTarget = oldestTs == null ? true : oldestTs.compareTo(targetTs) > 0;

        await _loadMoreOlder();
        if (!mounted || myGen != _gen) return;

        if (!stillNewerThanTarget) break;
      }

      final docs2 = _lastBuiltDocs;
      final finalIdx = _indexOfMessageId(docs2, id);
      if (finalIdx >= 0) {
        await _jumpToIndex(finalIdx);
        await _flash(id);
        return;
      }

      final l10n = AppLocalizations.of(context)!;
      MwFeedback.show(
        context,
        message: l10n.originalMessageNotFound ?? 'Original message not found',
        type: MwFeedbackType.info,
      );
    } finally {
      _jumping = false;
    }
  }

  // ================= UI =================

  Widget _buildOverlayMessage(String text) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: kTextPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      shadows: const [
        Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 4),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        try {
          MwReactionOverlay.hide();
        } catch (_) {}
        widget.onMessageTap?.call();
      },
      child: ListView(
        reverse: true,
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + widget.bottomInset),
        children: [
          const SizedBox(height: 80),
          Center(child: Text(text, textAlign: TextAlign.center, style: style)),
        ],
      ),
    );
  }

  Widget _buildNewIndicator(AppLocalizations l10n, double extraBottom) {
    final label = (l10n.newLabel ?? 'New').trim().isEmpty ? 'New' : l10n.newLabel!;
    final text = _newCount > 1 ? '$label ($_newCount)' : label;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          right: 14,
          bottom: 14 + extraBottom,
        ),
        child: Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _onTapNewIndicator,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: kPrimaryGold.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_downward_rounded, size: 18, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.isBlocked) {
      final msg = l10n.userBlockedInfo.toString().trim().isEmpty
          ? 'You can’t view messages in this chat.'
          : l10n.userBlockedInfo;
      return _buildOverlayMessage(msg);
    }

    final safeBottom = MediaQuery.of(context).padding.bottom;
    const composerFallback = 74.0;
    final bottomReserve = math.max(widget.bottomInset, composerFallback);
    final extraBottom = bottomReserve + safeBottom + 8;

    final visibleDocs = _computeVisibleDocs();
    _lastBuiltDocs = visibleDocs;

    _latestMessageId = visibleDocs.isNotEmpty ? visibleDocs.first.id : null;

    final listPadding = EdgeInsets.fromLTRB(12, 12, 12, 12 + extraBottom);
    final bool selectionMode = _isSelectionMode();

    Widget body;

    if (visibleDocs.isEmpty) {
      body = ListView(
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
                  Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 4),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      final bool showLoadingItem = _isLoadingMore;
      final maxWidth = MediaQuery.of(context).size.width * 0.72;
      final int itemCount = visibleDocs.length + (showLoadingItem ? 1 : 0);

      body = ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _positionsListener,
        reverse: true,
        padding: listPadding,
        physics: const AlwaysScrollableScrollPhysics(),
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

          final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? const <String>[];

          final att = ChatAttachmentUtils.normalizeAttachment(data);
          final displayText = ChatAttachmentUtils.displayTextForMessage(data['text'], att);

          final replyTo = (data['replyTo'] is Map)
              ? (data['replyTo'] as Map).cast<String, dynamic>()
              : null;

          final reactions = (data['reactions'] is Map)
              ? (data['reactions'] as Map).cast<String, dynamic>()
              : null;

          final bool flash = _flashMessageId == doc.id;
          final bool isSelected = _isSelected(doc.id);

          void handleTap() {
            try {
              MwReactionOverlay.hide();
            } catch (_) {}

            final onTapWithDoc = widget.onMessageTapWithDoc;
            if (onTapWithDoc != null) {
              onTapWithDoc(doc, isMe);
              return;
            }

            if (selectionMode) {
              widget.onMessageLongPress?.call(doc, isMe);
              return;
            }

            widget.onMessageTap?.call();
          }

          final bubble = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
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
                onReactionCommitted: () {
                  try {
                    MwReactionOverlay.hide();
                  } catch (_) {}
                  widget.onMessageTap?.call();
                },
                isSelected: isSelected,
                onBubbleLongPress: () => widget.onMessageLongPress?.call(doc, isMe),
                onBubbleTap: handleTap,
                disableSwipeReply: selectionMode,
                onSwipeReply: (widget.onReply == null)
                    ? null
                    : () {
                  final fallbackType = (att.type ?? 'text').toString().trim();
                  final reply = MwReplyTo.fromMessageDoc(
                    doc: doc,
                    fallbackType: fallbackType,
                  );

                  // 1) set reply in ChatScreen
                  widget.onReply!(reply);

                  // 2) IMPORTANT: jump to latest so composer/reply bar is visible at bottom
                  _requestJumpToLatestForReply();
                },
                onReactionTapAsync: widget.onReactionTapAsync == null
                    ? null
                    : (emoji) => widget.onReactionTapAsync!(doc.id, emoji),
                onReplyPreviewTap: (targetId) => _jumpToMessage(targetId),
              ),
            ),
          );

          return RepaintBoundary(
            key: ValueKey(doc.id),
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: bubble,
            ),
          );
        },
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        try {
          MwReactionOverlay.hide();
        } catch (_) {}
        widget.onMessageTap?.call();
      },
      child: Stack(
        children: [
          Positioned.fill(child: body),

          // ✅ Show "New" only when newest is NOT visible
          if (_showNewIndicator && !_atLatest) _buildNewIndicator(l10n, extraBottom),
        ],
      ),
    );
  }
}

class _ScrollAnchor {
  final String messageId;
  final double alignment;
  const _ScrollAnchor({required this.messageId, required this.alignment});
}
