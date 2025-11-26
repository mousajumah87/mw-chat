// Updated version of lib/screens/home/mw_friends_tab.dart
// Refined for consistent white tab UI and modern card style
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/chat_utils.dart';
import '../../widgets/ui/mw_side_panel.dart';
import '../chat/chat_screen.dart';

class MwFriendsTab extends StatelessWidget {
  final User currentUser;

  const MwFriendsTab({super.key, required this.currentUser});

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
      final now = DateTime.now();
      final last = lastSeen.toDate();
      final diff = now.difference(last);

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
          backgroundImage:
          (profileUrl != null && profileUrl.isNotEmpty) ? NetworkImage(profileUrl) : null,
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
      QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
      ) {
    final data = userDoc.data();
    final email = data['email'] as String? ?? 'Unknown';
    final profileUrl = data['profileUrl'] as String?;
    final avatarType = data['avatarType'] as String?;

    final isActive = (data['isActive'] != false);
    final isOnline = isActive && data['isOnline'] == true;

    final Timestamp? lastSeen = data['lastSeen'] is Timestamp ? data['lastSeen'] : null;
    final subtitleText = _buildSubtitle(context, isActive: isActive, isOnline: isOnline, lastSeen: lastSeen);

    final subtitleColor = !isActive
        ? Colors.grey
        : (isOnline ? Colors.greenAccent : Colors.white70);

    final canStartChat = isActive;
    final roomId = buildRoomId(currentUser.uid, userDoc.id);
    final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(roomId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Opacity(
        opacity: canStartChat ? 1.0 : 0.5,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: roomRef.snapshots(),
          builder: (context, roomSnap) {
            int unreadCount = 0;

            if (roomSnap.hasData && roomSnap.data!.data() != null) {
              final roomData = roomSnap.data!.data()!;
              final unreadMap = roomData['unreadCounts'] as Map<String, dynamic>?;
              if (unreadMap != null && unreadMap[currentUser.uid] != null) {
                unreadCount = (unreadMap[currentUser.uid] as num).toInt();
              }
            }

            final hasUnread = unreadCount > 0;

            return Card(
              color: Colors.white.withOpacity(0.1),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: hasUnread ? Colors.white.withOpacity(0.4) : Colors.white24,
                ),
              ),
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
                trailing: hasUnread
                    ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                )
                    : const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: canStartChat
                    ? () async {
                  await roomRef.set({'unreadCounts': {currentUser.uid: 0}}, SetOptions(merge: true));
                  // ignore: use_build_context_synchronously
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(roomId: roomId, title: email),
                    ),
                  );
                }
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUserList(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
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
      return bOnline ? 1 : -1;
    });

    return ListView.builder(
      itemCount: docs.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, i) => _buildUserTile(context, docs[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }

            final docs = snapshot.data!.docs.where((d) => d.id != currentUser.uid).toList();
            final userList = _buildUserList(context, docs);

            if (!isWide) {
              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: MwSidePanel(),
                  ),
                  Expanded(child: userList),
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 3, child: userList),
                const SizedBox(width: 16),
                const SizedBox(width: 320, child: MwSidePanel()),
              ],
            );
          },
        );
      },
    );
  }
}
