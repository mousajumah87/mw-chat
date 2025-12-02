import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_app_header.dart';
import 'mw_friends_tab.dart';
import 'invite_friends_tab.dart';
import '../../../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const String _appVersion = 'v2.0';
  static const String _websiteUrl = 'https://www.mwchats.com';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openMwWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      debugPrint('Could not launch $_websiteUrl');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final isWide = MediaQuery.of(context).size.width > 900;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: MwBackground(
        child: SafeArea(
          child: Column(
            children: [
              /// ======= HEADER + TABS =======
              MwAppHeader(
                title: 'MW Chat',
                showTabs: true,
                tabBar: _buildFixedTabBar(l10n),
              ),

              const SizedBox(height: 8),

              /// ======= BODY =======
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _KeepAlive(child: MwFriendsTab(currentUser: currentUser)),
                      const _KeepAlive(child: InviteFriendsTab()),
                    ],
                  ),
                ),
              ),

              /// ======= FOOTER =======
              if (isWide)
                Padding(
                  padding:
                  const EdgeInsets.only(bottom: 8, left: 16, top: 4),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'MW Chat • $_appVersion • ',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white38),
                        ),
                        GestureDetector(
                          onTap: _openMwWebsite,
                          child: Text(
                            'mwchats.com',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                              color: Colors.white60,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Keeps tabs alive to prevent rebuilding when switching
  TabBar _buildFixedTabBar(AppLocalizations l10n) {
    return TabBar(
      controller: _tabController,
      labelColor: Colors.black,
      unselectedLabelColor: Colors.white70,
      indicator: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      tabs: [
        Tab(
          icon: const Icon(Icons.people_alt_outlined, size: 22),
          text: l10n.usersTitle,
        ),
        Tab(
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 22),
          text: l10n.inviteFriendsTitle,
        ),
      ],
    );
  }
}

/// Keeps tabs alive to prevent rebuilding when switching
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
