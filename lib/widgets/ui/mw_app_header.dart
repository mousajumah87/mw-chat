import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../utils/presence_service.dart';
import '../../screens/about/about_screen.dart';
import '../../screens/profile/profile_screen.dart';
import 'mw_language_button.dart';

class MwAppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showTabs;
  final TabBar? tabBar;

  const MwAppHeader({
    super.key,
    this.title = 'MW Chat',
    this.showTabs = false,
    this.tabBar,
  });

  // give enough height to prevent overflow
  @override
  Size get preferredSize => Size.fromHeight(showTabs ? 120 : 65);

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: ClipRRect(
        borderRadius:
        const BorderRadius.vertical(bottom: Radius.circular(18)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            color: Colors.black.withOpacity(0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MwLanguageButton(),
                          if (currentUser != null)
                            _UserAvatarButton(currentUser: currentUser),
                          IconButton(
                            icon: const Icon(Icons.info_outline,
                                color: Colors.white),
                            tooltip: 'About',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const AboutScreen()),
                              );
                            },
                          ),
                          IconButton(
                            icon:
                            const Icon(Icons.logout, color: Colors.white),
                            tooltip: 'Logout',
                            onPressed: () async {
                              await PresenceService.instance.markOffline();
                              await FirebaseAuth.instance.signOut();
                              if (context.mounted) {
                                Navigator.of(context)
                                    .popUntil((r) => r.isFirst);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ---- TABS ----
                if (showTabs && tabBar != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: tabBar,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserAvatarButton extends StatelessWidget {
  final User currentUser;
  const _UserAvatarButton({required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots()
          .map((snap) => snap.data()),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final profileUrl = data?['profileUrl'] as String?;
        final avatarType = data?['avatarType'] as String?;
        final isOnline = data?['isOnline'] == true;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: profileUrl != null && profileUrl.isNotEmpty
                      ? NetworkImage(profileUrl)
                      : null,
                  backgroundColor: Colors.white,
                  child: (profileUrl == null || profileUrl.isEmpty)
                      ? Text(
                    avatarType == 'smurf' ? '🧜‍♀️' : '🐻',
                    style: const TextStyle(fontSize: 14),
                  )
                      : null,
                ),
                Positioned(
                  bottom: -1,
                  right: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
