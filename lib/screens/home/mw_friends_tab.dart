// lib/screens/home/mw_friends_tab.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/chat_utils.dart';
import '../chat/chat_screen.dart';

class MwFriendsTab extends StatefulWidget {
  final User currentUser;
  const MwFriendsTab({super.key, required this.currentUser});

  @override
  State<MwFriendsTab> createState() => _MwFriendsTabState();
}

class _MwFriendsTabState extends State<MwFriendsTab>
    with AutomaticKeepAliveClientMixin {
  late final String _currentUid;

  Map<String, int> _unreadCache = {};
  Set<String> _blockedUserIds = {};

  /// friendUid -> status
  ///   "accepted"         : both sides are friends
  ///   "requested"        : I sent a request to them
  ///   "request_received" : they sent a request to me (local alias for "incoming")
  Map<String, String> _friendStatuses = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatStreamSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _friendsSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentUid = widget.currentUser.uid;
    _listenUnreadCounts();
    _listenBlockedUsers();
    _listenFriends();
  }

  /// 🔹 Real-time unread count listener for all chats involving this user.
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
        final unreadMap = data['unreadCounts'] as Map<String, dynamic>? ?? {};
        final myUnread = (unreadMap[_currentUid] ?? 0) as int;
        newCache[doc.id] = myUnread;
      }

      if (mounted && !_mapsEqual(newCache, _unreadCache)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _unreadCache = newCache;
            });
          }
        });
      }
    });
  }

  /// 🔹 Listen to *current user's* blocked users list.
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

      if (!setEquals(newSet, _blockedUserIds)) {
        if (mounted) {
          setState(() {
            _blockedUserIds = newSet;
          });
        }
      }
    });
  }

  /// 🔹 Listen to current user's friends list.
  /// Path: users/{uid}/friends/{friendUid} with field "status".
  void _listenFriends() {
    _friendsSub?.cancel();

    _friendsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .snapshots()
        .listen((snapshot) {
      final map = <String, String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rawStatus = data['status'] as String?;

        // Normalise Firestore "incoming" to local "request_received"
        final status = switch (rawStatus) {
          'incoming' => 'request_received',
          null => 'accepted',
          _ => rawStatus!,
        };

        map[doc.id] = status;
      }

      if (mounted) {
        setState(() {
          _friendStatuses = map;
        });
      }
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
    super.dispose();
  }

  // === Friend request actions ===

  /// Send a new friend request:
  /// me -> friendUid: status "requested"
  /// friendUid -> me: status "incoming"
  Future<void> _sendFriendRequest(String friendUid) async {
    final l10n = AppLocalizations.of(context)!;

    if (friendUid.isEmpty || friendUid == _currentUid) return;

    // If we already have any relationship, don't spam requests.
    final existingStatus = _friendStatuses[friendUid];
    if (existingStatus == 'accepted' ||
        existingStatus == 'requested' ||
        existingStatus == 'request_received') {
      return;
    }

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

    batch.set(
      myRef,
      {
        'status': 'requested',
        'createdAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
    batch.set(
      theirRef,
      {
        'status': 'incoming', // ChatScreen expects "incoming"
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
    } catch (e, st) {
      debugPrint('[MwFriendsTab] _sendFriendRequest error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestSendFailed)),
      );
    }
  }

  Future<void> _acceptFriend(String friendUid) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestAccepted)),
      );
    } catch (e, st) {
      debugPrint('[MwFriendsTab] _acceptFriend error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestAcceptFailed)),
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
    } catch (e, st) {
      debugPrint('[MwFriendsTab] _declineFriend error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestDeclineFailed)),
      );
    }
  }

  // === Utility for subtitle text ===
  String _buildSubtitle(
      BuildContext context, {
        required bool isActive,
        required bool isOnline,
        required Timestamp? lastSeen,
      }) {
    final l10n = AppLocalizations.of(context)!;
    if (!isActive) return l10n.notActivated;
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
    // If the other user has blocked me, hide their real avatar and use a generic one.
    final String? effectiveProfileUrl = hideRealAvatar ? null : profileUrl;
    final String effectiveAvatarType =
    hideRealAvatar ? 'bear' : (avatarType ?? 'bear');

    return Stack(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Colors.white,
          backgroundImage: (effectiveProfileUrl?.isNotEmpty ?? false)
              ? NetworkImage(effectiveProfileUrl!)
              : null,
          child: (effectiveProfileUrl == null || effectiveProfileUrl.isEmpty)
              ? Text(
            effectiveAvatarType == 'smurf' ? '🧜‍♀️' : '🐻',
            style: const TextStyle(fontSize: 20),
          )
              : null,
        ),
        Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: isOnline ? Colors.greenAccent : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserTile(
      BuildContext context,
      Map<String, dynamic> data,
      String userId,
      bool isBlockedByMe,
      bool hasBlockedMe, {
        String? friendStatus,
      }) {
    final l10n = AppLocalizations.of(context)!;

    final email = data['email'] as String? ?? l10n.unknownEmail;
    final profileUrl = data['profileUrl'] as String?;
    final avatarType = data['avatarType'] as String?;

    final bool isActive = data['isActive'] != false;

    // If there is a block relationship, we never show them as online.
    final bool rawIsOnline = isActive && data['isOnline'] == true;
    final bool isBlockedRelationship = isBlockedByMe || hasBlockedMe;
    final bool isOnlineForDisplay =
    isBlockedRelationship ? false : rawIsOnline;

    final Timestamp? lastSeen =
    data['lastSeen'] is Timestamp ? data['lastSeen'] : null;

    final subtitleText = _buildSubtitle(
      context,
      isActive: isActive,
      isOnline: isOnlineForDisplay,
      lastSeen: lastSeen,
    );

    final subtitleColor = !isActive
        ? Colors.grey
        : (isOnlineForDisplay ? Colors.greenAccent : Colors.white70);

    final roomId = buildRoomId(_currentUid, userId);
    final unreadCount = _unreadCache[roomId] ?? 0;

    // If either side has blocked, we don't show unread badges.
    final bool hasUnread = !isBlockedRelationship && unreadCount > 0;

    // Decide trailing widget based on friend status + block + unread.
    Widget _buildTrailing() {
      if (isBlockedByMe) {
        return const Icon(
          Icons.block,
          key: ValueKey('blocked-icon'),
          color: Colors.redAccent,
        );
      }

      if (friendStatus == 'request_received') {
        // Incoming friend request → show Accept / Decline buttons.
        return Row(
          key: ValueKey('request-received-$roomId'),
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.friendAcceptTooltip,
              icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
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

      if (friendStatus == 'requested') {
        // Outgoing request → show a small "Requested" chip.
        return Container(
          key: ValueKey('requested-$roomId'),
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

      // No friendship yet → show an "Add friend" button (disabled for inactive).
      if (friendStatus == null) {
        return IconButton(
          key: ValueKey('add-friend-$roomId'),
          tooltip: l10n.addFriendTooltip,
          icon: Icon(
            Icons.person_add_alt_1,
            color: isActive ? Colors.white70 : Colors.white24,
          ),
          onPressed: isActive ? () => _sendFriendRequest(userId) : null,
        );
      }

      if (hasUnread) {
        return Container(
          key: ValueKey('badge-${roomId}_$unreadCount'),
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

      return const Icon(
        Icons.chevron_right,
        key: ValueKey('chevron'),
        color: Colors.white38,
      );
    }

    return RepaintBoundary(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isActive ? (isBlockedRelationship ? 0.6 : 1.0) : 0.5,
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          color: Colors.white.withOpacity(0.08),
          elevation: hasUnread ? 5 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color:
              hasUnread ? Colors.white.withOpacity(0.4) : Colors.white24,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: isActive
                ? () async {
              if (await Vibration.hasVibrator() ?? false) {
                Vibration.vibrate(duration: 40);
              }

              // NOTE: we still allow opening chat with anyone.
              // ChatScreen will handle gating send/receive based on friend status.

              // Reset unread count immediately on open.
              try {
                await FirebaseFirestore.instance
                    .collection('privateChats')
                    .doc(roomId)
                    .set(
                  {
                    'unreadCounts': {_currentUid: 0}
                  },
                  SetOptions(merge: true),
                );
              } on FirebaseException catch (e) {
                debugPrint(
                  '⚠️ Failed to reset unread count: ${e.code} ${e.message}',
                );
              }

              if (mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ChatScreen(roomId: roomId, title: email),
                  ),
                );
              }
            }
                : null,
            child: ListTile(
              leading: _buildAvatar(
                profileUrl: profileUrl,
                avatarType: avatarType,
                isOnline: isOnlineForDisplay,
                // If they blocked me, hide their real avatar.
                hideRealAvatar: hasBlockedMe,
              ),
              title: Text(
                email,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                subtitleText,
                style: TextStyle(color: subtitleColor, fontSize: 12),
              ),
              trailing: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: child,
                ),
                child: _buildTrailing(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Decide if a user should be treated as "online" for sorting purposes.
  /// If there is any block relationship, we always treat them as offline.
  bool _isOnlineForSorting(
      Map<String, dynamic> data,
      String userId,
      ) {
    final bool isActive = data['isActive'] != false;
    final bool rawOnline = isActive && data['isOnline'] == true;

    if (!rawOnline) return false;

    final bool isBlockedByMe = _blockedUserIds.contains(userId);
    final List<dynamic>? theirBlocked =
    data['blockedUserIds'] as List<dynamic>?;
    final bool hasBlockedMe =
        theirBlocked?.whereType<String>().contains(_currentUid) ?? false;

    final bool isBlockedRelationship = isBlockedByMe || hasBlockedMe;
    if (isBlockedRelationship) return false;

    return rawOnline;
  }

  /// Build a single ListView with sections:
  /// - Friend requests (incoming)
  /// - Your friends
  /// - All MW users
  /// - Inactive users
  Widget _buildSectionedUserList(
      BuildContext context,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final l10n = AppLocalizations.of(context)!;

    if (docs.isEmpty) {
      return Center(
        child: Text(
          l10n.noOtherUsers,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    final activeDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final inactiveDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final d in docs) {
      final data = d.data();
      final bool isActive = data['isActive'] != false;
      if (isActive) {
        activeDocs.add(d);
      } else {
        inactiveDocs.add(d);
      }
    }

    final friendDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final requestDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final otherDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final d in activeDocs) {
      final status = _friendStatuses[d.id];
      if (status == 'accepted') {
        friendDocs.add(d);
      } else if (status == 'request_received') {
        requestDocs.add(d);
      } else {
        otherDocs.add(d);
      }
    }

    // Sorting: online users first within each section.
    int compareOnline(
        QueryDocumentSnapshot<Map<String, dynamic>> a,
        QueryDocumentSnapshot<Map<String, dynamic>> b,
        ) {
      final aOnline = _isOnlineForSorting(a.data(), a.id);
      final bOnline = _isOnlineForSorting(b.data(), b.id);
      return (bOnline ? 1 : 0) - (aOnline ? 1 : 0);
    }

    friendDocs.sort(compareOnline);
    requestDocs.sort(compareOnline);
    otherDocs.sort(compareOnline);
    inactiveDocs.sort(compareOnline);

    final children = <Widget>[];

    Widget buildSectionHeader(String title, int count) {
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
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

    void addSection(
        String title,
        List<QueryDocumentSnapshot<Map<String, dynamic>>> list,
        ) {
      if (list.isEmpty) return;

      children.add(buildSectionHeader(title, list.length));

      for (final doc in list) {
        final data = doc.data();

        final String? status = _friendStatuses[doc.id];

        // Did *I* block this user?
        final bool isBlockedByMe = _blockedUserIds.contains(doc.id);

        // Did *they* block *me*?
        final List<dynamic>? theirBlocked =
        data['blockedUserIds'] as List<dynamic>?;
        final bool hasBlockedMe =
            theirBlocked?.whereType<String>().contains(_currentUid) ?? false;

        children.add(
          _buildUserTile(
            context,
            data,
            doc.id,
            isBlockedByMe,
            hasBlockedMe,
            friendStatus: status,
          ),
        );
      }
    }

    if (requestDocs.isNotEmpty) {
      addSection(l10n.friendSectionRequests, requestDocs);
    }

    addSection(l10n.friendSectionYourFriends, friendDocs);
    addSection(l10n.friendSectionAllUsers, otherDocs);
    addSection(l10n.friendSectionInactiveUsers, inactiveDocs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      physics: const BouncingScrollPhysics(),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final docs =
          snapshot.data!.docs.where((d) => d.id != _currentUid).toList();

          // Centered layout with max width for all platforms (mobile, tablet, web).
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  physics: const BouncingScrollPhysics(),
                ),
                child: _buildSectionedUserList(context, docs),
              ),
            ),
          );
        },
      ),
    );
  }
}
