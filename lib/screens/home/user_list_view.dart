// lib/screens/home/user_list_view.dart
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

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 2,
      child: Stack(
        children: [
          const MwBackground(child: SizedBox.expand()),

          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: Colors.black.withOpacity(0.75),
              centerTitle: true,
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
                  tooltip: 'About',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () async {
                    await PresenceService.instance.markOffline();
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    }
                  },
                ),
              ],
              bottom: TabBar(
                indicator: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  gradient: LinearGradient(
                    colors: [Color(0xFF0057FF), Color(0xFFFFB300)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: [
                  Tab(icon: const Icon(Icons.people_alt_outlined), text: l10n.usersTitle),
                  Tab(icon: const Icon(Icons.person_add_alt_1_outlined), text: l10n.inviteFriendsTitle),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                MwFriendsTab(currentUser: currentUser),
                const InviteFriendsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
