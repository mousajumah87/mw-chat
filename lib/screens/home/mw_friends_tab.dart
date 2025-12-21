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

// ✅ NEW: separate page for incoming requests
import 'mw_friend_requests_screen.dart';

/// ✅ New: determines which list to show
enum MwFriendsTabMode {
  friendsOnly, // show accepted + requested (incoming moved to a separate page)
  mwUsersOnly, // show MW users excluding friends + excluding pending/incoming
}

class MwFriendsTab extends StatefulWidget {
  final User currentUser;
  final MwFriendsTabMode mode;

  // NEW: callback for switching HomeScreen tab
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

  final Map<String, String?> _photoUrlCache = {}; // uid -> url or null
  final Set<String> _photoDenied = {}; // uid -> permission denied

  // ----------------------------
  // Friend requests seen tracking
  // ----------------------------
  static const String _fieldFriendRequestsLastSeenAt =
      'friendRequestsLastSeenAt';
  Timestamp? _friendRequestsLastSeenAt;

  // Track updatedAt per friend doc (for unseen request badge)
  final Map<String, Timestamp?> _friendUpdatedAt = {};

  /// friendUid -> status (canonical: accepted/requested/incoming)
  Map<String, String> _friendStatuses = {};
  bool _friendsLoaded = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatStreamSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _friendsSub;

  // Pagination ONLY for mwUsersOnly
  static const int _pageSize = 40;
  int _currentLimit = _pageSize;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final ScrollController _scrollController = ScrollController();
  Timer? _loadMoreDebounce;

  final Set<String> _resettingRooms = <String>{};

  // ✅ Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  bool get _isFriendsOnly => widget.mode == MwFriendsTabMode.friendsOnly;
  bool get _isMwUsersOnly => widget.mode == MwFriendsTabMode.mwUsersOnly;

  // Presence privacy values
  static const String _presenceFriends = 'friends';
  static const String _presenceNobody = 'nobody';

  // Profile & Add friend privacy values
  static const String _privacyEveryone = 'everyone';
  static const String _privacyFriends = 'friends';
  static const String _privacyNobody = 'nobody';

  // New field names
  static const String _fieldProfileVisibility = 'profileVisibility';
  static const String _fieldAddFriendVisibility = 'addFriendVisibility';

  // Legacy field names (your screenshot shows friendRequests)
  static const String _legacyFriendRequestsField = 'friendRequests';
  static const String _legacyShowOnlineStatusField = 'showOnlineStatus';

  /// Cache addFriendVisibility so we don't re-read the same doc repeatedly.
  final Map<String, String> _addFriendVisibilityCache = {};

  // ----------------------------
  // Private photo prefetch throttle
  // ----------------------------
  final Set<String> _photoPrefetchQueue = <String>{};
  bool _photoPrefetchRunning = false;

  // Animations can be expensive on web (especially with glass/blur backgrounds).
  Duration get _tileAnim =>
      kIsWeb ? Duration.zero : const Duration(milliseconds: 200);
  Duration get _trailingAnim =>
      kIsWeb ? Duration.zero : const Duration(milliseconds: 250);

  // ----------------------------
  // ✅ FIX: Keep Online/Offline sections accurate (rebucket on changes)
  // ----------------------------
  // We cache presence/activity for friends and whenever a friend switches
  // online/offline (or active/inactive), we trigger a debounced rebuild
  // so the friend moves to the correct section.
  final Map<String, bool> _friendOnlineDisplayCache = {}; // uid -> online (visible)
  final Map<String, bool> _friendActiveCache = {}; // uid -> isActive

  Timer? _friendsRebucketDebounce;

  void _scheduleFriendsRebucketRebuild() {
    if (!_isFriendsOnly) return;

    _friendsRebucketDebounce?.cancel();
    _friendsRebucketDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        // Just rebuild to re-split into Online/Offline using updated caches.
      });
    });
  }

  void _setFriendPresenceCaches({
    required String uid,
    required bool isActive,
    required bool isOnlineForDisplay,
  }) {
    final prevOnline = _friendOnlineDisplayCache[uid];
    final prevActive = _friendActiveCache[uid];

    // Update caches in-memory (NO immediate setState)
    _friendOnlineDisplayCache[uid] = isOnlineForDisplay;
    _friendActiveCache[uid] = isActive;

    final changed =
        (prevOnline != isOnlineForDisplay) || (prevActive != isActive);

    if (changed) {
      _scheduleFriendsRebucketRebuild();
    }
  }

  int _compareFriendIdsForFriendsSection(String a, String b) {
    // Active first (so deactivated friends go down)
    final bool aActive = _friendActiveCache[a] ?? true;
    final bool bActive = _friendActiveCache[b] ?? true;
    if (aActive != bActive) return aActive ? -1 : 1;

    // Online first (ONLY what you can see by privacy rules)
    final bool aOnline = _friendOnlineDisplayCache[a] ?? false;
    final bool bOnline = _friendOnlineDisplayCache[b] ?? false;
    if (aOnline != bOnline) return aOnline ? -1 : 1;

    // Stable fallback
    return a.compareTo(b);
  }

  bool _isFriendOnlineForDisplay(String uid) =>
      _friendOnlineDisplayCache[uid] ?? false;

  @override
  void initState() {
    super.initState();
    _currentUid = widget.currentUser.uid;

    _listenUnreadCounts();
    _listenBlockedUsers();
    _listenFriends();

    if (_isMwUsersOnly) {
      _scrollController.addListener(_onScrollLoadMore);
    }
  }

  void _onScrollLoadMore() {
    if (!_hasMore || _isLoadingMore) return;
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    if (pos.pixels >= (pos.maxScrollExtent - 260)) {
      _requestLoadMore();
    }
  }

  void _requestLoadMore() {
    if (_isLoadingMore || !_hasMore) return;
    if (_loadMoreDebounce?.isActive ?? false) return;

    _loadMoreDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = true;
        _currentLimit += _pageSize;
      });
    });
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
            (data['unreadCounts'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};

        final dynamic raw = unreadMap[_currentUid];
        final int myUnread = (raw is num) ? raw.toInt() : 0;

        newCache[doc.id] = myUnread;
      }

      if (!mounted) return;
      if (_mapsEqual(newCache, _unreadCache)) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _unreadCache = newCache);
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
      final newSet =
      list == null ? <String>{} : list.whereType<String>().toSet();

      final ts = data[_fieldFriendRequestsLastSeenAt];
      final Timestamp? seen = ts is Timestamp ? ts : null;

      final bool blockedChanged = !setEquals(newSet, _blockedUserIds);
      final bool seenChanged =
      (_friendRequestsLastSeenAt?.millisecondsSinceEpoch !=
          seen?.millisecondsSinceEpoch);

      if (!blockedChanged && !seenChanged) return;
      if (!mounted) return;

      setState(() {
        _blockedUserIds = newSet;
        _friendRequestsLastSeenAt = seen;
      });
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
        // ✅ FIX: ignore any accidental "self" friend document
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

        // Keep caches small
        _friendOnlineDisplayCache
            .removeWhere((uid, _) => !statusMap.containsKey(uid));
        _friendActiveCache.removeWhere((uid, _) => !statusMap.containsKey(uid));
      });

      // ✅ NEW: If list changed, rebuild once so online/offline split updates cleanly.
      _scheduleFriendsRebucketRebuild();
    });
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
    _loadMoreDebounce?.cancel();
    _friendsRebucketDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ----------------------------
  // Search helpers
  // ----------------------------

  String _normalizeQ(String s) => s.trim().toLowerCase();

  bool _matchesSearch(Map<String, dynamic> data, String userId) {
    final q = _normalizeQ(_searchQuery);
    if (q.isEmpty) return true;

    final String email = (data['email'] as String?) ?? '';
    final String displayName = (data['displayName'] as String?) ?? '';
    final String username = (data['username'] as String?) ?? '';
    final String fullName = (data['fullName'] as String?) ?? '';

    final haystack = <String>[
      userId,
      email,
      displayName,
      username,
      fullName,
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
  // Privacy helpers (aligned with rules)
  // ----------------------------

  String _normalizePrivacy(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return _privacyEveryone; // backward compatible
    if (v == _privacyFriends) return _privacyFriends;
    if (v == _privacyNobody) return _privacyNobody;
    return _privacyEveryone;
  }

  Future<String> _fetchAddFriendVisibility(String uid) async {
    try {
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? const <String, dynamic>{};

      final rawNew = (data[_fieldAddFriendVisibility] as String?)?.trim();
      final rawLegacy = (data[_legacyFriendRequestsField] as String?)?.trim();
      final chosen =
      (rawNew != null && rawNew.isNotEmpty) ? rawNew : rawLegacy;

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

    final targetVisibility = _addFriendVisibilityCache[friendUid] ??
        await _fetchAddFriendVisibility(friendUid);

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

    // Web needs extra throttling.
    final int maxConcurrent = kIsWeb ? 1 : 3;

    try {
      while (mounted && _photoPrefetchQueue.isNotEmpty) {
        final batch = _photoPrefetchQueue.take(maxConcurrent).toList();
        for (final uid in batch) {
          _photoPrefetchQueue.remove(uid);
        }

        await Future.wait(batch.map(_prefetchPrivateProfilePhoto));

        // yield between batches
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } finally {
      _photoPrefetchRunning = false;
    }
  }

  Widget _buildMissingUserTile(
      BuildContext context, {
        required String uid,
        required String? friendStatus,
      }) {
    final l10n = AppLocalizations.of(context)!;

    // respect search: if user typed something and it doesn't match uid, hide
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty && !uid.toLowerCase().contains(q)) {
      return const SizedBox.shrink();
    }

    final isRequested = ChatFriendshipService.isRequested(friendStatus);
    final isIncoming = ChatFriendshipService.isIncoming(friendStatus);

    // Only allow cancel/decline on non-accepted states
    final canRemove = isRequested || isIncoming;
    final showUid = kDebugMode;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: Colors.white.withOpacity(0.08),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white24),
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
          l10n.unknownUser,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          showUid ? uid : l10n.accountUnavailableSubtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          overflow: TextOverflow.ellipsis,
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
              const SizedBox(width: 10),
              IconButton(
                tooltip: l10n.friendDeclineTooltip,
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                onPressed: () => _declineFriend(uid),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _prefetchPrivateProfilePhoto(String uid) async {
    if (uid.isEmpty) return;
    if (_photoUrlCache.containsKey(uid) || _photoDenied.contains(uid)) return;

    try {
      final snap = await FirebaseFirestore.instance
          .doc('users/$uid/private/profile')
          .get();
      final data = snap.data();
      final url = (data?['profileUrl'] as String?)?.trim();
      if (!mounted) return;

      final String? normalized = (url != null && url.isNotEmpty) ? url : null;

      if (_photoUrlCache[uid] == normalized) return;

      setState(() {
        _photoUrlCache[uid] = normalized;
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        if (!mounted) return;

        if (_photoDenied.contains(uid) && _photoUrlCache[uid] == null) return;

        setState(() {
          _photoDenied.add(uid);
          _photoUrlCache[uid] = null;
        });
      }
    } catch (_) {
      // ignore
    }
  }

  // ----------------------------
  // Presence privacy
  // ----------------------------

  String _readPresenceVisibility(Map<String, dynamic> data) {
    final dynamic rawShow = data[_legacyShowOnlineStatusField];
    if (rawShow is bool && rawShow == false) return _presenceNobody;

    final raw = (data['presenceVisibility'] as String?)?.trim().toLowerCase();
    if (raw == _presenceNobody) return _presenceNobody;

    return _presenceFriends; // privacy-first default
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

    final chosen =
    (rawNew != null && rawNew.trim().isNotEmpty) ? rawNew : rawLegacy;
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
    final String effectiveAvatarType =
    hideRealAvatar ? 'bear' : (avatarType ?? 'bear');

    // ✅ MW-consistent ring colors
    final ring = isOnline
        ? kAccentColor.withOpacity(0.85)
        : kGoldDeep.withOpacity(0.70);

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
      await FirebaseFirestore.instance
          .collection('privateChats')
          .doc(roomId)
          .set(
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

  bool _isRelationshipBlocked(Map<String, dynamic> data, String userId) {
    final bool isBlockedByMe = _blockedUserIds.contains(userId);
    final List<dynamic>? theirBlocked = data['blockedUserIds'] as List<dynamic>?;
    final bool hasBlockedMe =
        theirBlocked?.whereType<String>().contains(_currentUid) ?? false;
    return isBlockedByMe || hasBlockedMe;
  }

  bool _isActiveUser(Map<String, dynamic> data) => data['isActive'] != false;

  /// ✅ MW USERS TAB must NOT contain:
  /// - accepted friends
  /// - incoming requests
  /// - requested (sent) requests
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

    final email = data['email'] as String? ?? l10n.unknownEmail;
    final legacyPublicUrl = (data['profileUrl'] as String?)?.trim();
    final privateUrl = _photoUrlCache[userId]?.trim();

    final String? profileUrl =
    (legacyPublicUrl != null && legacyPublicUrl.isNotEmpty)
        ? legacyPublicUrl
        : (privateUrl != null && privateUrl.isNotEmpty ? privateUrl : null);

    final avatarType = data['avatarType'] as String?;
    final bool isActive = _isActiveUser(data);

    final bool isBlockedRelationship = _isRelationshipBlocked(data, userId);

    final profileVisibility = _readPrivacyValue(data, _fieldProfileVisibility);
    final addFriendVisibility =
    _readPrivacyValue(data, _fieldAddFriendVisibility);

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

    final bool canOpenChat = isActive &&
        !isBlockedRelationship &&
        (hasRelationship || profileVisibility == _privacyEveryone);

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
    (canSeePresence && data['lastSeen'] is Timestamp)
        ? (data['lastSeen'] as Timestamp)
        : null;

    final subtitleText = _buildSubtitle(
      context,
      isActive: isActive,
      canSeePresence: canSeePresence,
      isOnline: isOnlineForDisplay,
      lastSeen: lastSeen,
    );

    final subtitleColor = !isActive
        ? Colors.grey
        : (isOnlineForDisplay ? Colors.greenAccent : Colors.white70);

    final roomId = buildRoomId(_currentUid, userId);
    final unreadCount = _unreadCache[roomId] ?? 0;
    final bool hasUnread = !isBlockedRelationship && unreadCount > 0;

    Widget buildTrailing() {
      if (_blockedUserIds.contains(userId)) {
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
              icon: Icon(Icons.check_circle,
                  color: kPrimaryGold.withOpacity(0.95)),
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

    return AnimatedOpacity(
      duration: _tileAnim,
      opacity: isActive ? (isBlockedRelationship ? 0.6 : 1.0) : 0.5,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        color: Colors.white.withOpacity(0.08),
        elevation: hasUnread ? 5 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: hasUnread ? Colors.white.withOpacity(0.4) : Colors.white24,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canOpenChat
              ? () async {
            try {
              if (!kIsWeb && (await Vibration.hasVibrator() ?? false)) {
                Vibration.vibrate(duration: 40);
              }
            } catch (_) {}

            if (!isBlockedRelationship) {
              await _resetUnreadIfNeeded(roomId, unreadCount);
            }

            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(roomId: roomId, title: email),
              ),
            );
          }
              : null,
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
                    email,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!canViewProfile &&
                    !ChatFriendshipService.isFriends(friendStatus))
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
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: buildTrailing(),
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------
  // FRIENDS ONLY UI (lazy builder)
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
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
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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

  // Smaller sub-header for Online/Offline
  Widget _subSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.80),
              fontWeight: FontWeight.w700,
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
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _userTileStream(String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        // ✅ If user doc is missing/unreadable -> show fallback tile instead of hiding
        if (!snap.hasData || snap.data?.data() == null) {
          final friendStatus = _friendStatuses[uid];
          return _buildMissingUserTile(
            context,
            uid: uid,
            friendStatus: friendStatus,
          );
        }

        final data = snap.data!.data()!;
        if (!_matchesSearch(data, uid)) return const SizedBox.shrink();

        final publicUrl = (data['profileUrl'] as String?)?.trim();
        if ((publicUrl == null || publicUrl.isEmpty) && !_photoDenied.contains(uid)) {
          _queuePrivatePhotoPrefetch(uid);
        }

        // ✅ update presence caches -> triggers debounced rebuild when status changes
        final friendStatus = _friendStatuses[uid];
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

        return _buildUserTile(
          context,
          data,
          uid,
          friendStatus: friendStatus,
        );
      },
    );
  }

  Widget _buildFriendsOnlyTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (!_friendsLoaded) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final friendIds = <String>[];
    final requestedIds = <String>[];
    final incomingIds = <String>[];

    _friendStatuses.forEach((uid, status) {
      if (uid == _currentUid) return;

      if (ChatFriendshipService.isFriends(status)) {
        friendIds.add(uid);
      } else if (ChatFriendshipService.isRequested(status)) {
        requestedIds.add(uid);
      } else if (ChatFriendshipService.isIncoming(status)) {
        incomingIds.add(uid);
      }
    });

    // ✅ stable sorting
    friendIds.sort(_compareFriendIdsForFriendsSection);
    requestedIds.sort();
    incomingIds.sort();

    // ✅ split into Online / Offline based on cache (kept accurate by debounced rebuild)
    final onlineFriendIds = <String>[];
    final offlineFriendIds = <String>[];

    for (final id in friendIds) {
      if (_isFriendOnlineForDisplay(id)) {
        onlineFriendIds.add(id);
      } else {
        offlineFriendIds.add(id);
      }
    }

    final unseenRequests = _computeUnseenRequestsCount(incomingIds);

    final hasAnyRelationships = friendIds.isNotEmpty ||
        requestedIds.isNotEmpty ||
        incomingIds.isNotEmpty;

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
                  Navigator.of(context).push(
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
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active,
                        color: kPrimaryGold.withOpacity(0.95),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.friendRequestsSubtitle(row.unseenCount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (row.unseenCount > 0)
                        Container(
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            row.unseenCount > 99
                                ? '99+'
                                : '${row.unseenCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
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
            return _sectionHeader(row.titleText ?? '', row.count);

          case _FriendsRowKind.subHeader:
            return _subSectionHeader(row.titleText ?? '', row.count);

          case _FriendsRowKind.user:
            return _userTileStream(row.uid!);
        }
      },
    );
  }

  // ----------------------------
  // MW USERS ONLY UI (builder list)
  // ----------------------------

  void _updatePaginationFlags({required bool newHasMore}) {
    if (!mounted) return;
    if (_hasMore == newHasMore && !_isLoadingMore) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _hasMore = newHasMore;
        _isLoadingMore = false;
      });
    });
  }

  Widget _buildMwUsersOnlyTab(BuildContext context) {
    final usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy(FieldPath.documentId)
        .limit(_currentLimit)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersStream,
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context)!;

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final rawDocs = snapshot.data!.docs;
        final bool newHasMore = rawDocs.length >= _currentLimit;

        final docs =
        rawDocs.where((d) => d.id != _currentUid).toList(growable: false);

        _updatePaginationFlags(newHasMore: newHasMore);

        final filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in docs) {
          final status = _friendStatuses[d.id];
          if (_shouldHideFromMwUsersTab(status)) continue;
          filtered.add(d);
        }

        final searched = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in filtered) {
          final data = d.data();
          if (_matchesSearch(data, d.id)) {
            searched.add(d);
          }
        }

        if (searched.isEmpty) {
          return Column(
            children: [
              _buildSearchBar(context),
              Expanded(
                child: Center(
                  child: Text(
                    _searchQuery.trim().isNotEmpty
                        ? l10n.noSearchResults
                        : l10n.noOtherUsers,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
          );
        }

        final activeDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final inactiveDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        for (final d in searched) {
          final data = d.data();
          if (_isActiveUser(data)) {
            activeDocs.add(d);
          } else {
            inactiveDocs.add(d);
          }
        }

        final rows = <_MwUsersRow>[];
        rows.add(const _MwUsersRow.search());

        for (final doc in activeDocs) {
          rows.add(_MwUsersRow.user(doc: doc));
        }

        if (inactiveDocs.isNotEmpty) {
          rows.add(_MwUsersRow.inactiveHeader(count: inactiveDocs.length));
          for (final doc in inactiveDocs) {
            rows.add(_MwUsersRow.user(doc: doc));
          }
        }

        if (_hasMore || _isLoadingMore) {
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

              case _MwUsersRowKind.inactiveHeader:
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Text(
                              l10n.friendSectionInactiveUsers,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${row.count}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

              case _MwUsersRowKind.user:
                final doc = row.doc!;
                final data = doc.data();
                final status = _friendStatuses[doc.id];

                final publicUrl = (data['profileUrl'] as String?)?.trim();
                if ((publicUrl == null || publicUrl.isEmpty) &&
                    !_photoDenied.contains(doc.id)) {
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
                      width: 220,
                      child: OutlinedButton(
                        onPressed: _isLoadingMore ? null : _requestLoadMore,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: _isLoadingMore
                            ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Text(l10n.loading),
                          ],
                        )
                            : Text(l10n.loadMore),
                      ),
                    ),
                  ),
                );
            }
          },
        );
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
            child: _isFriendsOnly
                ? _buildFriendsOnlyTab(context)
                : _buildMwUsersOnlyTab(context),
          ),
        ),
      ),
    );
  }
}

// ----------------------------
// Row models for lazy list building
// ----------------------------

enum _FriendsRowKind { search, requestsBanner, header, subHeader, user }

class _FriendsRow {
  final _FriendsRowKind kind;

  final int count;
  final int unseenCount;
  final String? uid;

  // ✅ flexible titles (supports Online/Offline easily)
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

  const _FriendsRow.user({required String uid})
      : this._(_FriendsRowKind.user, uid: uid);
}

enum _MwUsersRowKind { search, user, inactiveHeader, loadMore }

class _MwUsersRow {
  final _MwUsersRowKind kind;
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  final int count;

  const _MwUsersRow._(this.kind, {this.doc, this.count = 0});

  const _MwUsersRow.search() : this._(_MwUsersRowKind.search);

  const _MwUsersRow.user({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) : this._(_MwUsersRowKind.user, doc: doc);

  const _MwUsersRow.inactiveHeader({required int count})
      : this._(_MwUsersRowKind.inactiveHeader, count: count);

  const _MwUsersRow.loadMore() : this._(_MwUsersRowKind.loadMore);
}
