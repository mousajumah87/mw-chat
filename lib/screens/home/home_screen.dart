// lib/screens/home/home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_app_header.dart';
import 'mw_friends_tab.dart';
import 'invite_friends_tab.dart';
import '../../l10n/app_localizations.dart';
import '../legal/terms_of_use_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const String _appVersion = 'v1.0';
  static const String _websiteUrl = 'https://www.mwchats.com';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureUserAcceptedTerms();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openMwWebsite() async {
    final uri = Uri.parse(_websiteUrl);

    // ✅ Better cross-platform behavior (Web/iOS/Android)
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok) {
      debugPrint('Could not launch $_websiteUrl');
    }
  }

  /// Ensure the logged-in user has accepted Terms of Use.
  /// - If `hasAcceptedTerms != true`, we show the TermsOfUseScreen.
  /// - If they dismiss without accepting, we sign them out.
  Future<void> _ensureUserAcceptedTerms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = snap.data() ?? {};
      final hasAcceptedTerms = data['hasAcceptedTerms'] == true;

      if (!hasAcceptedTerms && mounted) {
        final accepted = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => const TermsOfUseScreen(),
            fullscreenDialog: true,
          ),
        );

        // ✅ If user navigated away while Terms screen was open
        if (!mounted) return;

        if (accepted == true) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {
              'hasAcceptedTerms': true,
              'termsAcceptedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } else {
          // If the user did NOT explicitly accept, log them out
          await FirebaseAuth.instance.signOut();
        }
      }
    } catch (e, st) {
      debugPrint('[HomeScreen] _ensureUserAcceptedTerms error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isWide = width >= 900;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: MwBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  MwAppHeader(
                    title: l10n.mainTitle,
                    showTabs: true,
                    tabBar: _buildFixedTabBar(l10n, theme),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isWide ? 16 : 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: TabBarView(
                        controller: _tabController,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _KeepAlive(
                            child: MwFriendsTab(currentUser: currentUser),
                          ),
                          const _KeepAlive(child: InviteFriendsTab()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildFooter(context, l10n, isWide: isWide),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(
      BuildContext context,
      AppLocalizations l10n, {
        required bool isWide,
      }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      fontSize: 11,
    );
    final versionStyle = textStyle?.copyWith(
      color: Colors.white38,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 16 : 12,
        vertical: 8,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.appBrandingBeta,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
          Text(
            _appVersion,
            style: versionStyle,
            textAlign: TextAlign.center,
          ),
          InkWell(
            onTap: _openMwWebsite,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'mwchats.com',
                style: textStyle?.copyWith(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TabBar _buildFixedTabBar(AppLocalizations l10n, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return TabBar(
      controller: _tabController,
      isScrollable: false,
      labelColor: isDark ? Colors.black : Colors.black,
      unselectedLabelColor: Colors.white.withOpacity(0.78),
      indicator: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(999),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      tabs: [
        Tab(
          iconMargin: const EdgeInsets.only(bottom: 2),
          icon: const Icon(Icons.people_alt_outlined, size: 22),
          text: l10n.usersTitle,
        ),
        Tab(
          iconMargin: const EdgeInsets.only(bottom: 2),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 22),
          text: l10n.inviteFriendsTitle,
        ),
      ],
    );
  }
}

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
