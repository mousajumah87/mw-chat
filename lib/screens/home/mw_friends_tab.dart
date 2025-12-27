// lib/screens/home/mw_friends_tab.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_utils.dart';
import '../../widgets/ui/mw_avatar.dart';
import '../../widgets/ui/mw_search_field.dart';
import '../chat/chat_screen.dart';
import '../chat/chat_friendship_service.dart';
import 'mw_friend_requests_screen.dart';

enum MwFriendsTabMode {
  friendsOnly,
  mwUsersOnly,
}

class MwFriendsTab extends StatefulWidget {
  final User currentUser;
  final MwFriendsTabMode mode;
  final VoidCallback? onSwitchToFriendsTab;

  const MwFriendsTab({
    super.key,
    required this.currentUser,
    required this.mode,
    this.onSwitchToFriendsTab,
  });

  @override
  State<MwFriendsTab> createState() => _MwFriendsTabState();
}

class _MwFriendsTabState extends State<MwFriendsTab>
    with AutomaticKeepAliveClientMixin {
  late final String _currentUid;

  Map<String, int> _unreadCache = {};
  Set<String> _blockedUserIds = {};

  final Map<String, String?> _photoUrlCache = {};
  final Set<String> _photoDenied = {};

  static const String _fieldFriendRequestsLastSeenAt = 'friendRequestsLastSeenAt';
  Timestamp? _friendRequestsLastSeenAt;

  final Map<String, Timestamp?> _friendUpdatedAt = {};

  Map<String, String> _friendStatuses = {};
  bool _friendsLoaded = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatStreamSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _friendsSub;

  // ✅ NEW: background subscriptions for each related user doc (fixes “online only after scroll”)
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _friendUserDocSubs =
  <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
  final Map<String, Map<String, dynamic>> _friendUserDataCache = <String, Map<String, dynamic>>{};
  final Set<String> _missingUserIds = <String>{};

  // ✅ MW USERS tab: cursor pagination (FAST)
  static const int _pageSize = 40;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _mwUserDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _mwUsersCursor;
  bool _mwUsersLoading = false;
  bool _mwUsersHasMore = true;
  bool _mwUsersBootstrapped = false;

  final ScrollController _scrollController = ScrollController();
  Timer? _loadMoreDebounce;

  final Set<String> _resettingRooms = <String>{};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  bool get _isFriendsOnly => widget.mode == MwFriendsTabMode.friendsOnly;
  bool get _isMwUsersOnly => widget.mode == MwFriendsTabMode.mwUsersOnly;

  static const String _presenceFriends = 'friends';
  static const String _presenceNobody = 'nobody';

  static const String _privacyEveryone = 'everyone';
  static const String _privacyFriends = 'friends';
  static const String _privacyNobody = 'nobody';

  static const String _fieldProfileVisibility = 'profileVisibility';
  static const String _fieldAddFriendVisibility = 'addFriendVisibility';

  static const String _legacyFriendRequestsField = 'friendRequests';
  static const String _legacyShowOnlineStatusField = 'showOnlineStatus';

  final Map<String, String> _addFriendVisibilityCache = {};

  final Set<String> _photoPrefetchQueue = <String>{};
  bool _photoPrefetchRunning = false;

  Duration get _tileAnim => kIsWeb ? Duration.zero : const Duration(milliseconds: 180);
  Duration get _trailingAnim => kIsWeb ? Duration.zero : const Duration(milliseconds: 220);

  // ============================================================
  // ✅ ZERO-MOVEMENT FRIENDS LIST (NO FLASH / NO JUMP)
  // ============================================================

  // Real-time presence caches (updated by user doc streams)
  final Map<String, bool> _friendOnlineDisplayCache = {};
  final Map<String, bool> _friendActiveCache = {};

  // Stable buckets/order used by UI (only updated on "safe moments")
  final Map<String, bool> _stableOnlineBucket = {}; // uid -> true if currently in Online section
  List<String> _stableFriendsOrder = const []; // stable order used for friend section sorting

  // Friends-only scroll controller (separate from MW users list)
  final ScrollController _friendsScrollController = ScrollController();
  bool _friendsIsScrolling = false;
  Timer? _friendsScrollIdleTimer;

  // Pending updates while user is interacting
  bool _pendingFriendsRebucket = false;
  bool _pendingFriendsResort = false;
  Timer? _friendsApplyDebounce;

  // Optional periodic "safe" refresh (prevents stale buckets forever)
  Timer? _friendsPeriodicTimer;

  void _onFriendsScroll() {
    if (!_isFriendsOnly) return;
    if (!_friendsScrollController.hasClients) return;

    _friendsIsScrolling = true;
    _friendsScrollIdleTimer?.cancel();
    _friendsScrollIdleTimer = Timer(const Duration(milliseconds: 900), () {
      _friendsIsScrolling = false;
      _applyPendingFriendsMovesIfSafe();
    });
  }

  void _scheduleApplyPendingFriendsMoves() {
    if (!_isFriendsOnly) return;

    _friendsApplyDebounce?.cancel();
    _friendsApplyDebounce = Timer(const Duration(milliseconds: 650), () {
      _applyPendingFriendsMovesIfSafe();
    });
  }

  void _applyPendingFriendsMovesIfSafe() {
    if (!mounted) return;
    if (!_isFriendsOnly) return;
    if (!_friendsLoaded) return;

    if (_friendsIsScrolling) return; // zero movement while scrolling

    bool changed = false;

    // 1) Rebucket (online/offline)
    if (_pendingFriendsRebucket) {
      _pendingFriendsRebucket = false;

      for (final uid in _friendStatuses.keys) {
        final status = _friendStatuses[uid];
        if (!ChatFriendshipService.isFriends(status)) continue;

        final bool nowOnline =
        _missingUserIds.contains(uid) ? false : (_friendOnlineDisplayCache[uid] ?? false);

        final prev = _stableOnlineBucket[uid];
        if (prev == null || prev != nowOnline) {
          _stableOnlineBucket[uid] = nowOnline;
          changed = true;
        }
      }
    }

    // 2) Resort
    if (_pendingFriendsResort) {
      _pendingFriendsResort = false;

      final friendIds = <String>[];
      _friendStatuses.forEach((uid, status) {
        if (uid == _currentUid) return;
        if (ChatFriendshipService.isFriends(status)) friendIds.add(uid);
      });

      friendIds.sort(_compareFriendIdsForFriendsSection);

      if (!_listEquals(friendIds, _stableFriendsOrder)) {
        _stableFriendsOrder = List<String>.unmodifiable(friendIds);
        changed = true;
      }
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _markFriendsNeedRebucket() {
    if (!_isFriendsOnly) return;
    _pendingFriendsRebucket = true;
    _scheduleApplyPendingFriendsMoves();
  }

  void _markFriendsNeedResort() {
    if (!_isFriendsOnly) return;
    _pendingFriendsResort = true;
    _scheduleApplyPendingFriendsMoves();
  }

  void _initializeStableBucketsAndOrderIfNeeded() {
    if (!_isFriendsOnly) return;
    if (!_friendsLoaded) return;

    if (_stableFriendsOrder.isEmpty) {
      final friendIds = <String>[];
      _friendStatuses.forEach((uid, status) {
        if (uid == _currentUid) return;
        if (ChatFriendshipService.isFriends(status)) friendIds.add(uid);
      });
      friendIds.sort(_compareFriendIdsForFriendsSection);
      _stableFriendsOrder = List<String>.unmodifiable(friendIds);
    }

    for (final uid in _stableFriendsOrder) {
      _stableOnlineBucket.putIfAbsent(
        uid,
            () => _missingUserIds.contains(uid) ? false : (_friendOnlineDisplayCache[uid] ?? false),
      );
    }
  }

  void _setFriendPresenceCaches({
    required String uid,
    required bool isActive,
    required bool isOnlineForDisplay,
  }) {
    final prevOnline = _friendOnlineDisplayCache[uid];
    final prevActive = _friendActiveCache[uid];

    _friendOnlineDisplayCache[uid] = isOnlineForDisplay;
    _friendActiveCache[uid] = isActive;

    final changed = (prevOnline != isOnlineForDisplay) || (prevActive != isActive);
    if (changed) {
      _markFriendsNeedRebucket();
      _markFriendsNeedResort();
    }
  }

  int _compareFriendIdsForFriendsSection(String a, String b) {
    // 0) Missing always last
    final bool aMissing = _missingUserIds.contains(a);
    final bool bMissing = _missingUserIds.contains(b);
    if (aMissing != bMissing) return aMissing ? 1 : -1;

    // 1) Unread first
    final int unreadA = _unreadCache[buildRoomId(_currentUid, a)] ?? 0;
    final int unreadB = _unreadCache[buildRoomId(_currentUid, b)] ?? 0;
    final bool aHasUnread = unreadA > 0;
    final bool bHasUnread = unreadB > 0;
    if (aHasUnread != bHasUnread) return aHasUnread ? -1 : 1;
    if (unreadA != unreadB) return unreadB.compareTo(unreadA);

    // 2) Active next
    final bool aActive = _friendActiveCache[a] ?? true;
    final bool bActive = _friendActiveCache[b] ?? true;
    if (aActive != bActive) return aActive ? -1 : 1;

    // 3) Online next
    final bool aOnline = _friendOnlineDisplayCache[a] ?? false;
    final bool bOnline = _friendOnlineDisplayCache[b] ?? false;
    if (aOnline != bOnline) return aOnline ? -1 : 1;

    // 4) fallback
    return a.compareTo(b);
  }

  @override
  void initState() {
    super.initState();
    _currentUid = widget.currentUser.uid;

    _listenUnreadCounts();
    _listenBlockedUsers();
    _listenFriends();

    _scrollController.addListener(_onScroll);
    _friendsScrollController.addListener(_onFriendsScroll);

    _friendsPeriodicTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      if (!_isFriendsOnly) return;
      if (!_friendsLoaded) return;
      if (_friendsIsScrolling) return;
      _applyPendingFriendsMovesIfSafe();
    });

    if (_isMwUsersOnly) {
      unawaited(_bootstrapMwUsers());
    }
  }

  void _onScroll() {
    if (!_isMwUsersOnly) return;
    if (!_mwUsersHasMore || _mwUsersLoading) return;
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    if (pos.pixels >= (pos.maxScrollExtent - 260)) {
      _requestLoadMore();
    }
  }

  void _requestLoadMore() {
    if (_mwUsersLoading || !_mwUsersHasMore) return;
    if (_loadMoreDebounce?.isActive ?? false) return;

    _loadMoreDebounce = Timer(const Duration(milliseconds: 220), () async {
      if (!mounted) return;
      await _fetchMoreMwUsers();
    });
  }

  Future<void> _bootstrapMwUsers() async {
    if (_mwUsersBootstrapped) return;
    _mwUsersBootstrapped = true;
    await _fetchMoreMwUsers(reset: true);
  }

  Future<void> _fetchMoreMwUsers({bool reset = false}) async {
    if (_mwUsersLoading) return;
    if (!mounted) return;

    setState(() => _mwUsersLoading = true);

    try {
      Query<Map<String, dynamic>> q =
      FirebaseFirestore.instance.collection('users').orderBy(FieldPath.documentId);

      if (!reset && _mwUsersCursor != null) {
        q = q.startAfterDocument(_mwUsersCursor!);
      }

      q = q.limit(_pageSize);

      final snap = await q.get();
      final docs = snap.docs;

      if (!mounted) return;

      setState(() {
        if (reset) {
          _mwUserDocs.clear();
          _mwUsersCursor = null;
          _mwUsersHasMore = true;
        }

        if (docs.isNotEmpty) {
          _mwUsersCursor = docs.last;
        }

        for (final d in docs) {
          if (d.id == _currentUid) continue;
          _mwUserDocs.add(d);
        }

        _mwUsersHasMore = docs.length >= _pageSize;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _mwUsersHasMore = false);
    } finally {
      if (!mounted) return;
      setState(() => _mwUsersLoading = false);
    }
  }

  void _listenUnreadCounts() {
    _chatStreamSub?.cancel();

    _chatStreamSub = FirebaseFirestore.instance
        .collection('privateChats')
        .where('participants', arrayContains: _currentUid)
        .snapshots()
        .listen((snapshot) {
      final newCache = <String, int>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final unreadMap =
            (data['unreadCounts'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

        final dynamic raw = unreadMap[_currentUid];
        final int myUnread = (raw is num) ? raw.toInt() : 0;
        newCache[doc.id] = myUnread;
      }

      if (!mounted) return;
      if (_mapsEqual(newCache, _unreadCache)) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _unreadCache = newCache);
        _markFriendsNeedResort();
      });
    });
  }

  void _listenBlockedUsers() {
    _userDocSub?.cancel();

    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUid)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;

      final list = data['blockedUserIds'] as List<dynamic>?;
      final newSet = list == null ? <String>{} : list.whereType<String>().toSet();

      final ts = data[_fieldFriendRequestsLastSeenAt];
      final Timestamp? seen = ts is Timestamp ? ts : null;

      final bool blockedChanged = !setEquals(newSet, _blockedUserIds);
      final bool seenChanged =
      (_friendRequestsLastSeenAt?.millisecondsSinceEpoch != seen?.millisecondsSinceEpoch);

      if (!blockedChanged && !seenChanged) return;
      if (!mounted) return;

      setState(() {
        _blockedUserIds = newSet;
        _friendRequestsLastSeenAt = seen;
      });

      // privacy + blocked affects presence visibility -> rebucket/resort
      _markFriendsNeedRebucket();
      _markFriendsNeedResort();
    });
  }

  void _listenFriends() {
    _friendsSub?.cancel();

    _friendsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .snapshots()
        .listen((snapshot) {
      final statusMap = <String, String>{};
      final updatedAtMap = <String, Timestamp?>{};

      for (final doc in snapshot.docs) {
        if (doc.id == _currentUid) continue;

        final data = doc.data();
        final rawStatus = data['status'] as String?;
        final normalized = ChatFriendshipService.normalizeStatus(rawStatus);
        if (normalized == null || normalized.isEmpty) continue;

        final updatedAt = data['updatedAt'];
        updatedAtMap[doc.id] = (updatedAt is Timestamp) ? updatedAt : null;

        statusMap[doc.id] =
        (normalized == ChatFriendshipService.statusRequestReceivedAlias)
            ? ChatFriendshipService.statusIncoming
            : normalized;
      }

      if (!mounted) return;

      setState(() {
        _friendStatuses = statusMap;

        _friendUpdatedAt
          ..clear()
          ..addAll(updatedAtMap);

        _friendsLoaded = true;

        // cleanup old caches
        _friendOnlineDisplayCache.removeWhere((uid, _) => !statusMap.containsKey(uid));
        _friendActiveCache.removeWhere((uid, _) => !statusMap.containsKey(uid));
        _friendUserDataCache.removeWhere((uid, _) => !statusMap.containsKey(uid));

        _stableOnlineBucket.removeWhere((uid, _) => !statusMap.containsKey(uid));
        _stableFriendsOrder =
            _stableFriendsOrder.where((uid) => statusMap.containsKey(uid)).toList(growable: false);

        _missingUserIds.removeWhere((uid) => !statusMap.containsKey(uid));
      });

      // ✅ CRITICAL FIX: ensure we listen to ALL related users immediately (not only on scroll)
      _syncFriendUserDocSubscriptions(statusMap.keys.toSet());

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _initializeStableBucketsAndOrderIfNeeded();
        _markFriendsNeedRebucket();
        _markFriendsNeedResort();
      });
    });
  }

  void _syncFriendUserDocSubscriptions(Set<String> targetIds) {
    // Exclude self
    targetIds.remove(_currentUid);

    // Cancel subscriptions not needed anymore
    final existing = _friendUserDocSubs.keys.toList();
    for (final uid in existing) {
      if (!targetIds.contains(uid)) {
        _friendUserDocSubs[uid]?.cancel();
        _friendUserDocSubs.remove(uid);
      }
    }

    // Add subscriptions for new ids
    for (final uid in targetIds) {
      if (_friendUserDocSubs.containsKey(uid)) continue;

      final sub = FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((snap) {
        if (!mounted) return;

        final friendStatus = _friendStatuses[uid];
        final data = snap.data();

        // missing/deleted
        if (data == null) {
          final wasMissing = _missingUserIds.contains(uid);
          _missingUserIds.add(uid);
          _friendUserDataCache.remove(uid);

          if (!wasMissing) {
            _markFriendsNeedRebucket();
            _markFriendsNeedResort();
          }
          return;
        }

        // became available again
        final wasMissing = _missingUserIds.remove(uid);
        _friendUserDataCache[uid] = data;

        // Presence computation WITHOUT waiting for tile build:
        final bool isActive = _isActiveUser(data);
        final bool isBlockedRelationship = _isRelationshipBlocked(data, uid);

        final presenceVisibility = _readPresenceVisibility(data);
        final canSeePresence = _canSeePresence(
          presenceVisibility: presenceVisibility,
          friendStatus: friendStatus,
          isBlockedRelationship: isBlockedRelationship,
          isActive: isActive,
        );

        final bool rawIsOnline = isActive && data['isOnline'] == true;
        final bool isOnlineForDisplay = canSeePresence ? rawIsOnline : false;

        _setFriendPresenceCaches(
          uid: uid,
          isActive: isActive,
          isOnlineForDisplay: isOnlineForDisplay,
        );

        if (wasMissing) {
          _markFriendsNeedRebucket();
          _markFriendsNeedResort();
        }
      });

      _friendUserDocSubs[uid] = sub;
    }
  }

  bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _chatStreamSub?.cancel();
    _userDocSub?.cancel();
    _friendsSub?.cancel();

    for (final sub in _friendUserDocSubs.values) {
      sub.cancel();
    }
    _friendUserDocSubs.clear();

    _loadMoreDebounce?.cancel();
    _friendsScrollIdleTimer?.cancel();
    _friendsApplyDebounce?.cancel();
    _friendsPeriodicTimer?.cancel();

    _scrollController.dispose();
    _friendsScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ----------------------------
  // Search helpers
  // ----------------------------
  String _normalizeQ(String s) => s.trim().toLowerCase();

  /// ✅ Display name builder:
  /// Uses firstName + lastName first, then displayName/fullName/username,
  /// never uses email, and always returns a safe fallback.
  String _displayNameFromData(AppLocalizations l10n, Map<String, dynamic> data, String userId) {
    String clean(String? v) => (v ?? '').trim();

    final first = clean(data['firstName'] as String?);
    final last = clean(data['lastName'] as String?);

    if (first.isNotEmpty && last.isNotEmpty) return '$first $last';
    if (first.isNotEmpty) return first;
    if (last.isNotEmpty) return last;

    final displayName = clean(data['displayName'] as String?);
    if (displayName.isNotEmpty) return displayName;

    final fullName = clean(data['fullName'] as String?);
    if (fullName.isNotEmpty) return fullName;

    final username = clean(data['username'] as String?);
    if (username.isNotEmpty) return username;

    // last resort: anonymous label (do not show uid in production)
    return l10n.unknownUser;
  }

  bool _matchesSearch(Map<String, dynamic> data, String userId) {
    final q = _normalizeQ(_searchQuery);
    if (q.isEmpty) return true;

    // ✅ Email removed from search for privacy
    final String displayName = (data['displayName'] as String?) ?? '';
    final String username = (data['username'] as String?) ?? '';
    final String fullName = (data['fullName'] as String?) ?? '';
    final String firstName = (data['firstName'] as String?) ?? '';
    final String lastName = (data['lastName'] as String?) ?? '';

    final haystack = <String>[
      userId,
      displayName,
      username,
      fullName,
      firstName,
      lastName,
    ].map(_normalizeQ).join(' ');

    return haystack.contains(q);
  }

  Widget _buildSearchBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hint = _isFriendsOnly ? l10n.searchFriendsHint : l10n.searchPeopleHint;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: MwSearchField(
        controller: _searchController,
        hintText: hint,
        onChanged: (v) {
          if (!mounted) return;
          setState(() => _searchQuery = v);
        },
        onClear: () {
          if (!mounted) return;
          setState(() => _searchQuery = '');
        },
      ),
    );
  }

  // ----------------------------
  // Privacy helpers
  // ----------------------------
  String _normalizePrivacy(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return _privacyEveryone;
    if (v == _privacyFriends) return _privacyFriends;
    if (v == _privacyNobody) return _privacyNobody;
    return _privacyEveryone;
  }

  Future<String> _fetchAddFriendVisibility(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? const <String, dynamic>{};

      final rawNew = (data[_fieldAddFriendVisibility] as String?)?.trim();
      final rawLegacy = (data[_legacyFriendRequestsField] as String?)?.trim();
      final chosen = (rawNew != null && rawNew.isNotEmpty) ? rawNew : rawLegacy;

      return _normalizePrivacy(chosen);
    } catch (_) {
      return _privacyEveryone;
    }
  }

  bool _canRequestFriendByRule({
    required String targetAddFriendVisibility,
    required String? currentStatusWithTarget,
  }) {
    if (targetAddFriendVisibility == _privacyEveryone) return true;
    if (targetAddFriendVisibility == _privacyNobody) return false;
    return ChatFriendshipService.isFriends(currentStatusWithTarget);
  }

  // ----------------------------
  // Block / Unblock
  // ----------------------------
  Future<void> _unblockUser(String uid) async {
    if (uid.isEmpty) return;
    if (!_blockedUserIds.contains(uid)) return;

    final l10n = AppLocalizations.of(context)!;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        title: Text(
          l10n.unblockUserTitle ?? 'Unblock user?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.unblockUserDescription ?? 'They will be able to interact with you again.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.unblockUserConfirm ?? 'Unblock',
              style: const TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(_currentUid).set(
        {'blockedUserIds': FieldValue.arrayRemove([uid])},
        SetOptions(merge: true),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileBlockSnackbarError ?? 'Failed to unblock user.')),
      );
    }
  }

  // ----------------------------
  // Friend actions
  // ----------------------------
  Future<void> _sendFriendRequest(String friendUid) async {
    final l10n = AppLocalizations.of(context)!;
    if (friendUid.isEmpty || friendUid == _currentUid) return;

    final existingStatus = _friendStatuses[friendUid];
    if (ChatFriendshipService.isFriends(existingStatus) ||
        ChatFriendshipService.isRequested(existingStatus) ||
        ChatFriendshipService.isIncoming(existingStatus)) {
      return;
    }

    final targetVisibility =
        _addFriendVisibilityCache[friendUid] ?? await _fetchAddFriendVisibility(friendUid);

    final canRequest = _canRequestFriendByRule(
      targetAddFriendVisibility: targetVisibility,
      currentStatusWithTarget: existingStatus,
    );

    if (!canRequest) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestSendFailed)),
      );
      return;
    }

    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .doc(friendUid);

    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(friendUid)
        .collection('friends')
        .doc(_currentUid);

    final now = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch();

    batch.set(
      myRef,
      {
        'status': ChatFriendshipService.statusRequested,
        'createdAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    batch.set(
      theirRef,
      {
        'status': ChatFriendshipService.statusIncoming,
        'createdAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    try {
      await batch.commit();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestSent)),
      );
    } on FirebaseException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestSendFailed)),
      );
    }
  }

  Future<void> _acceptFriend(String friendUid) async {
    final l10n = AppLocalizations.of(context)!;
    if (friendUid.isEmpty || friendUid == _currentUid) return;

    final status = _friendStatuses[friendUid];
    if (!ChatFriendshipService.isIncoming(status)) return;

    final batch = FirebaseFirestore.instance.batch();

    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .doc(friendUid);

    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(friendUid)
        .collection('friends')
        .doc(_currentUid);

    final now = FieldValue.serverTimestamp();
    final payload = {
      'status': ChatFriendshipService.statusAccepted,
      'updatedAt': now,
    };

    batch.set(myRef, payload, SetOptions(merge: true));
    batch.set(theirRef, payload, SetOptions(merge: true));

    try {
      await batch.commit();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestAccepted)),
      );

      widget.onSwitchToFriendsTab?.call();
    } on FirebaseException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestSendFailed)),
      );
    }
  }

  Future<void> _declineFriend(String friendUid) async {
    final l10n = AppLocalizations.of(context)!;
    if (friendUid.isEmpty || friendUid == _currentUid) return;

    final batch = FirebaseFirestore.instance.batch();
    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .doc(friendUid);
    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(friendUid)
        .collection('friends')
        .doc(_currentUid);

    batch.delete(myRef);
    batch.delete(theirRef);

    try {
      await batch.commit();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestDeclined)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestDeclined)),
      );
    }
  }

  void _queuePrivatePhotoPrefetch(String uid) {
    if (uid.isEmpty) return;
    if (_photoUrlCache.containsKey(uid) || _photoDenied.contains(uid)) return;
    if (_photoPrefetchQueue.contains(uid)) return;

    _photoPrefetchQueue.add(uid);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainPhotoPrefetchQueue();
    });
  }

  Future<void> _drainPhotoPrefetchQueue() async {
    if (_photoPrefetchRunning) return;
    _photoPrefetchRunning = true;

    final int maxConcurrent = kIsWeb ? 1 : 3;

    try {
      while (mounted && _photoPrefetchQueue.isNotEmpty) {
        final batch = _photoPrefetchQueue.take(maxConcurrent).toList();
        for (final uid in batch) {
          _photoPrefetchQueue.remove(uid);
        }

        await Future.wait(batch.map(_prefetchPrivateProfilePhoto));
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } finally {
      _photoPrefetchRunning = false;
    }
  }

  // ----------------------------
  // ✅ UNKNOWN / DELETED USER TILE
  // ----------------------------
  Widget _buildMissingUserTile(
      BuildContext context, {
        required String uid,
        required String? friendStatus,
      }) {
    final l10n = AppLocalizations.of(context)!;

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty && !uid.toLowerCase().contains(q)) {
      return const SizedBox.shrink();
    }

    final isRequested = ChatFriendshipService.isRequested(friendStatus);
    final isIncoming = ChatFriendshipService.isIncoming(friendStatus);
    final isFriends = ChatFriendshipService.isFriends(friendStatus);
    final canRemove = isRequested || isIncoming || isFriends;

    final showUid = kDebugMode;
    final titleText = (l10n.deletedAccount ?? l10n.unknownUser);
    final subtitleText = (l10n.accountUnavailableSubtitle ?? 'This account is no longer available.');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: Colors.white.withOpacity(0.08),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white24),
      ),
      child: ListTile(
        leading: MwAvatar(
          radius: 26,
          avatarType: 'bear',
          profileUrl: null,
          hideRealAvatar: true,
          showRing: true,
          ringColor: kGoldDeep.withOpacity(0.70),
          ringWidth: 2.0,
          isOnline: false,
          showOnlineDot: false,
          showOnlineGlow: false,
          backgroundColor: kSurfaceAltColor.withOpacity(0.85),
        ),
        title: Text(
          titleText,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          showUid ? uid : subtitleText,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRequested)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  l10n.friendRequestedChip,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (canRemove) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: (l10n.remove ?? l10n.friendDeclineTooltip),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                onPressed: () => _declineFriend(uid),
              ),
            ],
            if (!canRemove) const Icon(Icons.help_outline_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Future<void> _prefetchPrivateProfilePhoto(String uid) async {
    if (uid.isEmpty) return;
    if (_photoUrlCache.containsKey(uid) || _photoDenied.contains(uid)) return;

    try {
      final snap = await FirebaseFirestore.instance.doc('users/$uid/private/profile').get();
      final data = snap.data();
      final url = (data?['profileUrl'] as String?)?.trim();
      if (!mounted) return;

      final String? normalized = (url != null && url.isNotEmpty) ? url : null;
      if (_photoUrlCache[uid] == normalized) return;

      setState(() => _photoUrlCache[uid] = normalized);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        if (!mounted) return;
        if (_photoDenied.contains(uid) && _photoUrlCache[uid] == null) return;

        setState(() {
          _photoDenied.add(uid);
          _photoUrlCache[uid] = null;
        });
      }
    } catch (_) {}
  }

  // ----------------------------
  // Presence privacy
  // ----------------------------
  String _readPresenceVisibility(Map<String, dynamic> data) {
    final dynamic rawShow = data[_legacyShowOnlineStatusField];
    if (rawShow is bool && rawShow == false) return _presenceNobody;

    final raw = (data['presenceVisibility'] as String?)?.trim().toLowerCase();
    if (raw == _presenceNobody) return _presenceNobody;

    return _presenceFriends;
  }

  bool _canSeePresence({
    required String presenceVisibility,
    required String? friendStatus,
    required bool isBlockedRelationship,
    required bool isActive,
  }) {
    if (!isActive) return false;
    if (isBlockedRelationship) return false;
    if (presenceVisibility == _presenceNobody) return false;
    return ChatFriendshipService.isFriends(friendStatus);
  }

  // ----------------------------
  // Profile + Add friend privacy
  // ----------------------------
  String _readPrivacyValue(Map<String, dynamic> data, String field) {
    final String? rawNew = data[field] as String?;
    String? rawLegacy;
    if (field == _fieldAddFriendVisibility) {
      rawLegacy = data[_legacyFriendRequestsField] as String?;
    }
    final chosen = (rawNew != null && rawNew.trim().isNotEmpty) ? rawNew : rawLegacy;
    return _normalizePrivacy(chosen);
  }

  bool _canViewProfile({
    required String profileVisibility,
    required String? friendStatus,
    required bool isBlockedRelationship,
    required bool isActive,
  }) {
    if (!isActive) return false;
    if (isBlockedRelationship) return false;
    if (profileVisibility == _privacyNobody) return false;
    if (profileVisibility == _privacyEveryone) return true;
    return ChatFriendshipService.isFriends(friendStatus);
  }

  bool _canSendFriendRequestUI({
    required String addFriendVisibility,
    required String? friendStatus,
    required bool isBlockedRelationship,
    required bool isActive,
  }) {
    if (!isActive) return false;
    if (isBlockedRelationship) return false;

    if (ChatFriendshipService.isFriends(friendStatus) ||
        ChatFriendshipService.isRequested(friendStatus) ||
        ChatFriendshipService.isIncoming(friendStatus)) {
      return false;
    }

    return _canRequestFriendByRule(
      targetAddFriendVisibility: addFriendVisibility,
      currentStatusWithTarget: friendStatus,
    );
  }

  String _buildSubtitle(
      BuildContext context, {
        required bool isActive,
        required bool canSeePresence,
        required bool isOnline,
        required Timestamp? lastSeen,
      }) {
    final l10n = AppLocalizations.of(context)!;

    if (!isActive) return l10n.notActivated;
    if (!canSeePresence) return l10n.offline;
    if (isOnline) return l10n.online;

    if (lastSeen != null) {
      final diff = DateTime.now().difference(lastSeen.toDate());
      if (diff.inMinutes < 1) return l10n.lastSeenJustNow;
      if (diff.inMinutes < 60) return l10n.lastSeenMinutes(diff.inMinutes);
      if (diff.inHours < 24) return l10n.lastSeenHours(diff.inHours);
      return l10n.lastSeenDays(diff.inDays);
    }

    return l10n.offline;
  }

  Widget _buildAvatar({
    required String? profileUrl,
    required String? avatarType,
    required bool isOnline,
    required bool hideRealAvatar,
  }) {
    final String? effectiveProfileUrl = hideRealAvatar ? null : profileUrl;
    final String effectiveAvatarType = hideRealAvatar ? 'bear' : (avatarType ?? 'bear');
    final ring = isOnline ? kAccentColor.withOpacity(0.85) : kGoldDeep.withOpacity(0.70);

    return MwAvatar(
      radius: 26,
      avatarType: effectiveAvatarType,
      profileUrl: effectiveProfileUrl,
      hideRealAvatar: hideRealAvatar,
      showRing: true,
      ringColor: ring,
      ringWidth: 2.0,
      isOnline: isOnline,
      showOnlineDot: true,
      showOnlineGlow: isOnline,
      onlineGlowColor: kAccentColor.withOpacity(0.55),
      onlineDotColor: kAccentColor,
      offlineDotColor: Colors.white24,
      backgroundColor: kSurfaceAltColor.withOpacity(0.85),
    );
  }

  Future<void> _resetUnreadIfNeeded(String roomId, int unreadCount) async {
    if (unreadCount <= 0) return;
    if (_resettingRooms.contains(roomId)) return;
    _resettingRooms.add(roomId);

    try {
      await FirebaseFirestore.instance.collection('privateChats').doc(roomId).set(
        {
          'unreadCounts': {_currentUid: 0},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // ignore
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _resettingRooms.remove(roomId);
    }
  }

  bool _isBlockedByMe(String userId) => _blockedUserIds.contains(userId);

  bool _hasBlockedMe(Map<String, dynamic> data, String userId) {
    final List<dynamic>? theirBlocked = data['blockedUserIds'] as List<dynamic>?;
    return theirBlocked?.whereType<String>().contains(_currentUid) ?? false;
  }

  bool _isRelationshipBlocked(Map<String, dynamic> data, String userId) {
    return _isBlockedByMe(userId) || _hasBlockedMe(data, userId);
  }

  bool _isActiveUser(Map<String, dynamic> data) => data['isActive'] != false;

  bool _shouldHideFromMwUsersTab(String? status) {
    if (status == null) return false;
    return ChatFriendshipService.isFriends(status) ||
        ChatFriendshipService.isIncoming(status) ||
        ChatFriendshipService.isRequested(status);
  }

  Widget _buildUserTile(
      BuildContext context,
      Map<String, dynamic> data,
      String userId, {
        required String? friendStatus,
        bool hideIncomingActions = false,
      }) {
    final l10n = AppLocalizations.of(context)!;

    // ✅ Email removed from UI completely
    final String displayName = _displayNameFromData(l10n, data, userId);

    final legacyPublicUrl = (data['profileUrl'] as String?)?.trim();
    final privateUrl = _photoUrlCache[userId]?.trim();

    final String? profileUrl = (legacyPublicUrl != null && legacyPublicUrl.isNotEmpty)
        ? legacyPublicUrl
        : (privateUrl != null && privateUrl.isNotEmpty ? privateUrl : null);

    final avatarType = data['avatarType'] as String?;
    final bool isActive = _isActiveUser(data);

    final bool blockedByMe = _isBlockedByMe(userId);
    final bool blockedMe = _hasBlockedMe(data, userId);
    final bool isBlockedRelationship = blockedByMe || blockedMe;

    final profileVisibility = _readPrivacyValue(data, _fieldProfileVisibility);
    final addFriendVisibility = _readPrivacyValue(data, _fieldAddFriendVisibility);

    if (_addFriendVisibilityCache[userId] != addFriendVisibility) {
      _addFriendVisibilityCache[userId] = addFriendVisibility;
    }

    final bool canViewProfile = _canViewProfile(
      profileVisibility: profileVisibility,
      friendStatus: friendStatus,
      isBlockedRelationship: isBlockedRelationship,
      isActive: isActive,
    );

    final bool canSendRequest = _canSendFriendRequestUI(
      addFriendVisibility: addFriendVisibility,
      friendStatus: friendStatus,
      isBlockedRelationship: isBlockedRelationship,
      isActive: isActive,
    );

    final bool hasRelationship = ChatFriendshipService.isFriends(friendStatus) ||
        ChatFriendshipService.isRequested(friendStatus) ||
        ChatFriendshipService.isIncoming(friendStatus);

    final bool canOpenChat =
        isActive && !isBlockedRelationship && (hasRelationship || profileVisibility == _privacyEveryone);

    final presenceVisibility = _readPresenceVisibility(data);
    final canSeePresence = _canSeePresence(
      presenceVisibility: presenceVisibility,
      friendStatus: friendStatus,
      isBlockedRelationship: isBlockedRelationship,
      isActive: isActive,
    );

    final bool rawIsOnline = isActive && data['isOnline'] == true;
    final bool isOnlineForDisplay = canSeePresence ? rawIsOnline : false;

    final Timestamp? lastSeen =
    (canSeePresence && data['lastSeen'] is Timestamp) ? (data['lastSeen'] as Timestamp) : null;

    final subtitleText = blockedMe
        ? (l10n.blockedByUserBanner ?? 'This user has blocked you.')
        : (blockedByMe
        ? (l10n.userBlocked ?? 'You blocked this user.')
        : _buildSubtitle(
      context,
      isActive: isActive,
      canSeePresence: canSeePresence,
      isOnline: isOnlineForDisplay,
      lastSeen: lastSeen,
    ));

    final subtitleColor = !isActive
        ? Colors.grey
        : (blockedMe || blockedByMe)
        ? Colors.redAccent.withOpacity(0.85)
        : (isOnlineForDisplay ? Colors.greenAccent : Colors.white70);

    final roomId = buildRoomId(_currentUid, userId);
    final unreadCount = _unreadCache[roomId] ?? 0;
    final bool hasUnread = !isBlockedRelationship && unreadCount > 0;

    // ✅ Prevent double tap / double push
    final bool isBusy = _resettingRooms.contains(roomId);

    Future<void> openChat() async {
      if (!mounted) return;

      // ✅ close keyboard (search, etc.)
      FocusManager.instance.primaryFocus?.unfocus();

      try {
        if (!kIsWeb && (await Vibration.hasVibrator() ?? false)) {
          Vibration.vibrate(duration: 40);
        }
      } catch (_) {}

      if (!isBlockedRelationship) {
        await _resetUnreadIfNeeded(roomId, unreadCount);
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(roomId: roomId, title: displayName),
        ),
      );
    }

    Widget buildTrailing() {
      if (blockedByMe) {
        return TextButton.icon(
          onPressed: () => _unblockUser(userId),
          icon: const Icon(Icons.lock_open_rounded, color: Colors.greenAccent),
          label: Text(
            l10n.unblockUserTitle ?? 'Unblock',
            style: const TextStyle(color: Colors.greenAccent),
          ),
        );
      }

      if (blockedMe) {
        return const Icon(Icons.block, color: Colors.redAccent);
      }

      if (ChatFriendshipService.isIncoming(friendStatus)) {
        if (hideIncomingActions) {
          return const Icon(Icons.chevron_right, color: Colors.white38);
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.friendAcceptTooltip,
              icon: Icon(Icons.check_circle, color: kPrimaryGold.withOpacity(0.95)),
              onPressed: isActive ? () => _acceptFriend(userId) : null,
            ),
            IconButton(
              tooltip: l10n.friendDeclineTooltip,
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
              onPressed: isActive ? () => _declineFriend(userId) : null,
            ),
          ],
        );
      }

      if (ChatFriendshipService.isRequested(friendStatus)) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            l10n.friendRequestedChip,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }

      if (friendStatus == null) {
        if (canSendRequest) {
          return IconButton(
            tooltip: l10n.addFriendTooltip,
            icon: Icon(
              Icons.person_add_alt_1,
              color: isActive ? Colors.white70 : Colors.white24,
            ),
            onPressed: isActive ? () => _sendFriendRequest(userId) : null,
          );
        }
        return const Icon(Icons.lock_outline, color: Colors.white38);
      }

      if (hasUnread) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            unreadCount > 99 ? '99+' : '$unreadCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }

      return const Icon(Icons.chevron_right, color: Colors.white38);
    }

    final trailingKey = ValueKey<String>(
      'trail:$userId'
          ':${friendStatus ?? "none"}'
          ':u${hasUnread ? unreadCount : 0}'
          ':bm${blockedByMe ? 1 : 0}'
          ':bt${blockedMe ? 1 : 0}'
          ':a${isActive ? 1 : 0}',
    );

    return AnimatedOpacity(
      duration: _tileAnim,
      opacity: isActive ? (isBlockedRelationship ? 0.75 : 1.0) : 0.5,
      child: AbsorbPointer(
        absorbing: isBusy, // ✅ blocks double taps while we reset unread
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          color: Colors.white.withOpacity(0.08),
          elevation: hasUnread ? 5 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: hasUnread ? Colors.white.withOpacity(0.40) : Colors.white24,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: canOpenChat ? openChat : null,
            child: ListTile(
              enabled: canOpenChat,
              leading: _buildAvatar(
                profileUrl: profileUrl,
                avatarType: avatarType,
                isOnline: isOnlineForDisplay,
                hideRealAvatar: false,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!canViewProfile && !ChatFriendshipService.isFriends(friendStatus))
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 8),
                      child: Icon(
                        Icons.visibility_off,
                        size: 16,
                        color: Colors.white38,
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                subtitleText,
                style: TextStyle(color: subtitleColor, fontSize: 12),
              ),
              trailing: AnimatedSwitcher(
                duration: _trailingAnim,
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: KeyedSubtree(
                  key: trailingKey,
                  child: buildTrailing(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  // ----------------------------
  // FRIENDS ONLY UI
  // ----------------------------
  int _computeUnseenRequestsCount(List<String> incomingIds) {
    int unseen = 0;
    for (final uid in incomingIds) {
      final ts = _friendUpdatedAt[uid];
      if (_friendRequestsLastSeenAt == null) {
        unseen++;
      } else if (ts != null && ts.compareTo(_friendRequestsLastSeenAt!) > 0) {
        unseen++;
      }
    }
    return unseen;
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              letterSpacing: 0.2,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _userTileFast(String uid) {
    // ✅ Uses cached user data populated by background subscriptions.
    final friendStatus = _friendStatuses[uid];
    final data = _friendUserDataCache[uid];

    if (data == null) {
      // missing/deleted (or still loading)
      if (_missingUserIds.contains(uid)) {
        return _buildMissingUserTile(context, uid: uid, friendStatus: friendStatus);
      }
      // still loading: lightweight placeholder (keeps UI fast)
      return const SizedBox(height: 0);
    }

    if (!_matchesSearch(data, uid)) return const SizedBox.shrink();

    final publicUrl = (data['profileUrl'] as String?)?.trim();
    if ((publicUrl == null || publicUrl.isEmpty) && !_photoDenied.contains(uid)) {
      _queuePrivatePhotoPrefetch(uid);
    }

    return _buildUserTile(context, data, uid, friendStatus: friendStatus);
  }

  Widget _buildFriendsOnlyTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (!_friendsLoaded) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    _initializeStableBucketsAndOrderIfNeeded();

    final requestedIds = <String>[];
    final incomingIds = <String>[];

    _friendStatuses.forEach((uid, status) {
      if (uid == _currentUid) return;

      if (ChatFriendshipService.isRequested(status)) {
        requestedIds.add(uid);
      } else if (ChatFriendshipService.isIncoming(status)) {
        incomingIds.add(uid);
      }
    });

    int sortMissingLast(String a, String b) {
      final am = _missingUserIds.contains(a);
      final bm = _missingUserIds.contains(b);
      if (am != bm) return am ? 1 : -1;
      return a.compareTo(b);
    }

    requestedIds.sort(sortMissingLast);
    incomingIds.sort(sortMissingLast);

    final friendIds = List<String>.from(_stableFriendsOrder);

    final onlineFriendIds = <String>[];
    final offlineFriendIds = <String>[];

    for (final id in friendIds) {
      final bool stableOnline = _stableOnlineBucket[id] ?? false;
      if (stableOnline) {
        onlineFriendIds.add(id);
      } else {
        offlineFriendIds.add(id);
      }
    }

    final unseenRequests = _computeUnseenRequestsCount(incomingIds);

    final hasAnyRelationships =
        friendIds.isNotEmpty || requestedIds.isNotEmpty || incomingIds.isNotEmpty;

    if (!hasAnyRelationships) {
      return Column(
        children: [
          _buildSearchBar(context),
          Expanded(
            child: Center(
              child: Text(
                l10n.noOtherUsers,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      );
    }

    final rows = <_FriendsRow>[];
    rows.add(const _FriendsRow.search());

    if (incomingIds.isNotEmpty) {
      rows.add(_FriendsRow.requestsBanner(
        unseenCount: unseenRequests,
        incomingCount: incomingIds.length,
      ));
    }

    if (friendIds.isNotEmpty) {
      rows.add(_FriendsRow.header(
        titleText: l10n.friendSectionYourFriends,
        count: friendIds.length,
      ));

      if (onlineFriendIds.isNotEmpty) {
        rows.add(_FriendsRow.subHeader(
          titleText: l10n.online,
          count: onlineFriendIds.length,
        ));
        for (final id in onlineFriendIds) {
          rows.add(_FriendsRow.user(uid: id));
        }
      }

      if (offlineFriendIds.isNotEmpty) {
        rows.add(_FriendsRow.subHeader(
          titleText: l10n.offline,
          count: offlineFriendIds.length,
        ));
        for (final id in offlineFriendIds) {
          rows.add(_FriendsRow.user(uid: id));
        }
      }
    }

    if (requestedIds.isNotEmpty) {
      rows.add(_FriendsRow.header(
        titleText: l10n.friendRequestedChip,
        count: requestedIds.length,
      ));
      for (final id in requestedIds) {
        rows.add(_FriendsRow.user(uid: id));
      }
    }

    return ListView.builder(
      controller: _friendsScrollController,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];

        switch (row.kind) {
          case _FriendsRowKind.search:
            return _buildSearchBar(context);

          case _FriendsRowKind.requestsBanner:
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  // ✅ close keyboard / search focus first
                  FocusManager.instance.primaryFocus?.unfocus();

                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => MwFriendRequestsScreen(
                        currentUserId: _currentUid,
                        friendStatuses: _friendStatuses,
                        buildUserTile: _buildUserTile,
                        acceptFriend: _acceptFriend,
                        declineFriend: _declineFriend,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active, color: kPrimaryGold.withOpacity(0.95)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.friendRequestsSubtitle(row.unseenCount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (row.unseenCount > 0)
                        Container(
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            row.unseenCount > 99 ? '99+' : '${row.unseenCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      const Icon(Icons.chevron_right, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            );

          case _FriendsRowKind.header:
            return KeyedSubtree(
              key: ValueKey('hdr:${row.titleText}:${row.count}'),
              child: _sectionHeader(row.titleText ?? '', row.count),
            );

          case _FriendsRowKind.subHeader:
            return KeyedSubtree(
              key: ValueKey('sub:${row.titleText}:${row.count}'),
              child: _subSectionHeader(row.titleText ?? '', row.count),
            );

          case _FriendsRowKind.user:
            return KeyedSubtree(
              key: ValueKey('u:${row.uid}'),
              child: _userTileFast(row.uid!),
            );
        }
      },
    );
  }

  // ----------------------------
  // MW USERS ONLY UI (FAST PAGED LIST)
  // ----------------------------
  Widget _buildMwUsersOnlyTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (!_mwUsersBootstrapped) {
      unawaited(_bootstrapMwUsers());
    }

    final filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in _mwUserDocs) {
      final status = _friendStatuses[d.id];
      if (_shouldHideFromMwUsersTab(status)) continue;
      filtered.add(d);
    }

    final searched = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in filtered) {
      final data = d.data();
      if (_matchesSearch(data, d.id)) searched.add(d);
    }

    if (searched.isEmpty && !_mwUsersLoading) {
      return Column(
        children: [
          _buildSearchBar(context),
          Expanded(
            child: Center(
              child: Text(
                _searchQuery.trim().isNotEmpty ? l10n.noSearchResults : l10n.noOtherUsers,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      );
    }

    final rows = <_MwUsersRow>[];
    rows.add(const _MwUsersRow.search());

    for (final doc in searched) {
      rows.add(_MwUsersRow.user(doc: doc));
    }

    if (_mwUsersHasMore || _mwUsersLoading) {
      rows.add(const _MwUsersRow.loadMore());
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];

        switch (row.kind) {
          case _MwUsersRowKind.search:
            return _buildSearchBar(context);

          case _MwUsersRowKind.user:
            final doc = row.doc!;
            final data = doc.data();
            final status = _friendStatuses[doc.id];

            final publicUrl = (data['profileUrl'] as String?)?.trim();
            if ((publicUrl == null || publicUrl.isEmpty) && !_photoDenied.contains(doc.id)) {
              _queuePrivatePhotoPrefetch(doc.id);
            }

            return _buildUserTile(
              context,
              data,
              doc.id,
              friendStatus: status,
            );

          case _MwUsersRowKind.loadMore:
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              child: Center(
                child: SizedBox(
                  width: 240,
                  child: OutlinedButton(
                    onPressed: _mwUsersLoading ? null : _requestLoadMore,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: _mwUsersLoading
                        ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(l10n.loading),
                      ],
                    )
                        : Text(_mwUsersHasMore ? l10n.loadMore : (l10n.noSearchResults ?? 'No more users')),
                  ),
                ),
              ),
            );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              physics: const BouncingScrollPhysics(),
            ),
            child: _isFriendsOnly ? _buildFriendsOnlyTab(context) : _buildMwUsersOnlyTab(context),
          ),
        ),
      ),
    );
  }
}

enum _FriendsRowKind { search, requestsBanner, header, subHeader, user }

class _FriendsRow {
  final _FriendsRowKind kind;

  final int count;
  final int unseenCount;
  final String? uid;
  final String? titleText;

  const _FriendsRow._(
      this.kind, {
        this.count = 0,
        this.unseenCount = 0,
        this.uid,
        this.titleText,
      });

  const _FriendsRow.search() : this._(_FriendsRowKind.search);

  const _FriendsRow.requestsBanner({
    required int unseenCount,
    required int incomingCount,
  }) : this._(
    _FriendsRowKind.requestsBanner,
    unseenCount: unseenCount,
    count: incomingCount,
  );

  const _FriendsRow.header({
    required String titleText,
    required int count,
  }) : this._(
    _FriendsRowKind.header,
    titleText: titleText,
    count: count,
  );

  const _FriendsRow.subHeader({
    required String titleText,
    required int count,
  }) : this._(
    _FriendsRowKind.subHeader,
    titleText: titleText,
    count: count,
  );

  const _FriendsRow.user({required String uid}) : this._(_FriendsRowKind.user, uid: uid);
}

enum _MwUsersRowKind { search, user, loadMore }

class _MwUsersRow {
  final _MwUsersRowKind kind;
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;

  const _MwUsersRow._(this.kind, {this.doc});

  const _MwUsersRow.search() : this._(_MwUsersRowKind.search);

  const _MwUsersRow.user({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) : this._(_MwUsersRowKind.user, doc: doc);

  const _MwUsersRow.loadMore() : this._(_MwUsersRowKind.loadMore);
}
