// lib/widgets/chat_app_bar.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../profile/profile_screen.dart';
import '../home/user_profile_screen.dart';
import '../../l10n/app_localizations.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String currentUserId;
  final String? otherUserId;
  final VoidCallback onLogout;
  final VoidCallback? onClearChat;

  const ChatAppBar({
    super.key,
    required this.title,
    required this.currentUserId,
    required this.otherUserId,
    required this.onLogout,
    this.onClearChat,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 10);

  static const int _onlineTtlSeconds = 300;

  bool _isOnlineWithTtl({required bool rawIsOnline, required Timestamp? lastSeen}) {
    if (!rawIsOnline || lastSeen == null) return false;
    final diffSeconds = DateTime.now().difference(lastSeen.toDate()).inSeconds;
    return diffSeconds <= _onlineTtlSeconds;
  }

  Widget _buildOtherAvatar(String? profileUrl, String? avatarType) {
    if (profileUrl != null && profileUrl.isNotEmpty) {
      return CircleAvatar(radius: 18, backgroundImage: NetworkImage(profileUrl));
    }
    final emoji = avatarType == 'smurf' ? '🧜‍♀️️' : '🐻';
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.white.withOpacity(0.1),
      child: Text(emoji, style: const TextStyle(fontSize: 18, color: Colors.white)),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (otherUserId == null) {
      return Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(otherUserId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null) {
          return Text(title, style: const TextStyle(color: Colors.white));
        }

        final email = data['email'] as String? ?? title;
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        final displayName = (firstName.isNotEmpty ? '$firstName $lastName' : email).trim();

        final isActive = (data['isActive'] != false);
        final rawIsOnline = (data['isOnline'] == true) && isActive;

        Timestamp? lastSeen;
        final rawTs = data['lastSeen'];
        if (rawTs is Timestamp) lastSeen = rawTs;

        final effectiveOnline = _isOnlineWithTtl(rawIsOnline: rawIsOnline, lastSeen: lastSeen);

        String subtitle;
        if (!isActive) {
          subtitle = l10n.notActivated;
        } else if (effectiveOnline) {
          subtitle = l10n.online;
        } else if (lastSeen != null) {
          final now = DateTime.now();
          final last = lastSeen.toDate();
          final diff = now.difference(last);
          if (diff.inMinutes < 1) {
            subtitle = l10n.lastSeenJustNow;
          } else if (diff.inMinutes < 60) {
            subtitle = l10n.lastSeenMinutes(diff.inMinutes);
          } else if (diff.inHours < 24) {
            subtitle = l10n.lastSeenHours(diff.inHours);
          } else {
            subtitle = l10n.lastSeenDays(diff.inDays);
          }
        } else {
          subtitle = l10n.offline;
        }

        final profileUrl = data['profileUrl'] as String?;
        final avatarType = data['avatarType'] as String?;
        final dotColor = !isActive ? Colors.grey : (effectiveOnline ? Colors.greenAccent : Colors.grey);

        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserProfileScreen(userId: otherUserId!)),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  _buildOtherAvatar(profileUrl, avatarType),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyAvatarAction(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final profileUrl = data?['profileUrl'] as String?;
        final avatarType = data?['avatarType'] as String?;

        Widget avatar;
        if (profileUrl != null && profileUrl.isNotEmpty) {
          avatar = CircleAvatar(radius: 14, backgroundImage: NetworkImage(profileUrl));
        } else {
          final emoji = avatarType == 'smurf' ? '🧜‍♀️' : '🐻';
          avatar = CircleAvatar(
            radius: 14,
            backgroundColor: Colors.white.withOpacity(0.1),
            child: Text(emoji, style: const TextStyle(color: Colors.white, fontSize: 14)),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(right: 6.0),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: avatar,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withOpacity(0.85),
            Colors.black.withOpacity(0.65),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _buildTitle(context),
        centerTitle: false,
        actions: [
          if (onClearChat != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              onPressed: onClearChat,
            ),
          _buildMyAvatarAction(context),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
