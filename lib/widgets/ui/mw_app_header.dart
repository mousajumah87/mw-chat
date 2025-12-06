// lib/widgets/ui/mw_app_header.dart
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/presence_service.dart';
import '../../screens/about/about_screen.dart';
import '../../screens/profile/profile_screen.dart';
import 'mw_language_button.dart';

class MwAppHeader extends StatelessWidget implements PreferredSizeWidget {
  /// If null, we fall back to l10n.mainTitle inside build().
  final String? title;
  final bool showTabs;
  final TabBar? tabBar;

  const MwAppHeader({
    super.key,
    this.title,
    this.showTabs = false,
    this.tabBar,
  });

  @override
  Size get preferredSize => Size.fromHeight(showTabs ? 108 : 64);

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Use provided title, otherwise localized mainTitle.
    final effectiveTitle = title ?? l10n.mainTitle;

    return SafeArea(
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(18),
          ),
          border: Border.all(color: Colors.white12, width: 0.6),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(18),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ===== Header row =====
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Centered title + small logo
                      Expanded(
                        child: Center(
                          child: _TitleWithLogoRow(
                            title: effectiveTitle,
                            textStyle: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),

                      // ===== Actions (language, profile, about, logout) =====
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MwLanguageButton(),
                          if (currentUser != null)
                            Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                              child:
                              _UserAvatarButton(currentUser: currentUser),
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.info_outline,
                              color: Colors.white,
                            ),
                            tooltip: 'About',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AboutScreen(),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.logout,
                              color: Colors.white,
                            ),
                            tooltip: 'Logout',
                            onPressed: () async {
                              await PresenceService.instance.markOffline();
                              await FirebaseAuth.instance.signOut();
                              if (context.mounted) {
                                Navigator.of(context)
                                    .popUntil((route) => route.isFirst);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ===== Tabs below the header =====
                if (showTabs && tabBar != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
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

/// Compact row: glowing MW circle + title text.
class _TitleWithLogoRow extends StatelessWidget {
  final String title;
  final TextStyle? textStyle;

  const _TitleWithLogoRow({
    required this.title,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Small glowing logo
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB300).withOpacity(0.7),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              'assets/logo/mw_mark.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: textStyle,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white,
                backgroundImage: (profileUrl != null && profileUrl.isNotEmpty)
                    ? NetworkImage(profileUrl)
                    : null,
                child: (profileUrl == null || profileUrl.isEmpty)
                    ? Text(
                  avatarType == 'smurf' ? '🧜‍♀️' : '🐻',
                  style: const TextStyle(fontSize: 14),
                )
                    : null,
              ),
              Positioned(
                bottom: -1.5,
                right: -1.5,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.greenAccent : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
