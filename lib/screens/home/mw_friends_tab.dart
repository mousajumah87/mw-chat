// lib/screens/home/mw_friends_tab.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/chat_utils.dart';
import '../../widgets/ui/mw_side_panel.dart';
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatStreamSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentUid = widget.currentUser.uid;
    _listenUnreadCounts();
  }

  /// 🔹 Real-time unread count listener for all chats involving this user
  void _listenUnreadCounts() {
    _chatStreamSub?.cancel();

    // ✅ FIX: Listen and print after snapshot, not before
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
          if (mounted) setState(() => _unreadCache = newCache);
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
    super.dispose();
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

  Widget _buildAvatar(String? profileUrl, String? avatarType, bool isOnline) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Colors.white,
          backgroundImage: (profileUrl?.isNotEmpty ?? false)
              ? NetworkImage(profileUrl!)
              : null,
          child: (profileUrl == null || profileUrl.isEmpty)
              ? Text(
            avatarType == 'smurf' ? '🧜‍♀️' : '🐻',
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
      ) {
    final email = data['email'] as String? ?? 'Unknown';
    final profileUrl = data['profileUrl'] as String?;
    final avatarType = data['avatarType'] as String?;
    final isActive = (data['isActive'] != false);
    final isOnline = isActive && data['isOnline'] == true;
    final Timestamp? lastSeen =
    data['lastSeen'] is Timestamp ? data['lastSeen'] : null;

    final subtitleText = _buildSubtitle(
      context,
      isActive: isActive,
      isOnline: isOnline,
      lastSeen: lastSeen,
    );

    final subtitleColor = !isActive
        ? Colors.grey
        : (isOnline ? Colors.greenAccent : Colors.white70);

    final roomId = buildRoomId(_currentUid, userId);
    final unreadCount = _unreadCache[roomId] ?? 0;
    final hasUnread = unreadCount > 0;

    return RepaintBoundary(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isActive ? 1 : 0.5,
        child: Card(
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

              // Reset unread count immediately on open
              try {
                await FirebaseFirestore.instance
                    .collection('privateChats')
                    .doc(roomId)
                    .set({
                  'unreadCounts': {_currentUid: 0}
                }, SetOptions(merge: true));
              } on FirebaseException catch (e) {
                debugPrint('⚠️ Failed to reset unread count: ${e.code} ${e.message}');
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
              leading: _buildAvatar(profileUrl, avatarType, isOnline),
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
                child: hasUnread
                    ? Container(
                  key: ValueKey('badge-${roomId}_$unreadCount'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
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
                )
                    : const Icon(Icons.chevron_right, color: Colors.white38),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserList(
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

    docs.sort((a, b) {
      final aOnline = (a['isActive'] != false) && (a['isOnline'] == true);
      final bOnline = (b['isActive'] != false) && (b['isOnline'] == true);
      return (bOnline ? 1 : 0) - (aOnline ? 1 : 0);
    });

    return ListView.builder(
      itemCount: docs.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, i) =>
          _buildUserTile(context, docs[i].data(), docs[i].id),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            final docs = snapshot.data!.docs
                .where((d) => d.id != _currentUid)
                .toList();

            final userList = _buildUserList(context, docs);

            if (!isWide) {
              // MOBILE / NARROW layout
              return SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // === FRIENDS LIST ===
                            Container(
                              constraints: BoxConstraints(
                                // Ensure it never takes more than 65% of the screen height
                                maxHeight: box.maxHeight * 0.65,
                              ),
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(scrollbars: false),
                                child: ListView.builder(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: docs.length,
                                  shrinkWrap: true,
                                  itemBuilder: (context, i) => _buildUserTile(
                                    context,
                                    docs[i].data(),
                                    docs[i].id,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // === MW CHAT PANEL BELOW ===
                            const RepaintBoundary(
                              child: MwSidePanel(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }

            // DESKTOP / WIDE layout (side panel on right)
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                      physics: const BouncingScrollPhysics(),
                    ),
                    child: userList,
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  flex: 2,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12, top: 8),
                      child: RepaintBoundary(child: MwSidePanel()),
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
}
