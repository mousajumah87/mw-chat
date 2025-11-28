import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_language_button.dart';
import '../../utils/presence_service.dart';
import '../about/about_screen.dart';
import 'mw_friends_tab.dart';
import 'invite_friends_tab.dart';
import '../../../l10n/app_localizations.dart';

class UserListScreen extends StatelessWidget {
  const UserListScreen({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    await PresenceService.instance.markOffline();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background stays behind
          const MwBackground(child: SizedBox.shrink()),

          // Foreground scaffold
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight + 10),
              child: ClipRRect(
                borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: AppBar(
                    elevation: 0,
                    centerTitle: true,
                    backgroundColor: Colors.black.withOpacity(0.6),
                    title: Text(
                      'MW Chat',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    actions: [
                      const MwLanguageButton(),
                      IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: l10n.about,
                        onPressed: () {
                          Navigator.of(context).push(PageRouteBuilder(
                            pageBuilder: (_, __, ___) => const AboutScreen(),
                            transitionsBuilder: (_, anim, __, child) =>
                                FadeTransition(opacity: anim, child: child),
                          ));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: l10n.logout,
                        onPressed: () => _handleLogout(context),
                      ),
                    ],
                    bottom: TabBar(
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0057FF), Color(0xFFFFB300)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.white70,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      tabs: [
                        Tab(
                          icon:
                          const Icon(Icons.people_alt_outlined, size: 20),
                          text: l10n.usersTitle,
                        ),
                        Tab(
                          icon: const Icon(Icons.person_add_alt_1_outlined,
                              size: 20),
                          text: l10n.inviteFriendsTitle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            body: const SafeArea(
              child: TabBarView(
                physics: BouncingScrollPhysics(),
                children: [
                  _FriendsTabWrapper(),
                  InviteFriendsTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A lightweight wrapper that only rebuilds the friends tab if needed.
class _FriendsTabWrapper extends StatelessWidget {
  const _FriendsTabWrapper();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return MwFriendsTab(currentUser: user);
  }
}
