// lib/screens/home/home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_app_header.dart';
import '../legal/terms_of_use_screen.dart';
import 'invite_friends_tab.dart';
import 'mw_friends_tab.dart';

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
    final uri = Uri.tryParse(_websiteUrl);
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok) debugPrint('Could not launch $_websiteUrl');
  }

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
      backgroundColor: kBgColor,
      body: MwBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  RepaintBoundary(
                    child: MwAppHeader(
                      title: l10n.mainTitle,
                      showTabs: true,
                      tabBar: _buildFixedTabBar(l10n),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: RepaintBoundary(
                      child: Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: isWide ? 16 : 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kSurfaceAltColor.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: kBorderColor.withOpacity(0.70),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.55),
                              blurRadius: 30,
                              offset: const Offset(0, 16),
                            ),
                            BoxShadow(
                              color: kGoldDeep.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: TabBarView(
                            controller: _tabController,

                            // ✅ This feels smoother cross-platform than Bouncing.
                            // iOS still supports swipe smoothly; Android feels less "rubbery".
                            physics: const ClampingScrollPhysics(),

                            children: [
                              _KeepAlive(
                                child: MwFriendsTab(currentUser: currentUser),
                              ),
                              const _KeepAlive(child: InviteFriendsTab()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),
                  _buildFooter(context, l10n, theme, isWide: isWide),
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
      AppLocalizations l10n,
      ThemeData theme, {
        required bool isWide,
      }) {
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: kTextSecondary.withOpacity(0.85),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    final versionStyle = textStyle?.copyWith(
      color: kTextSecondary.withOpacity(0.55),
      fontWeight: FontWeight.w500,
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
          Text(l10n.appBrandingBeta, style: textStyle),
          Text(_appVersion, style: versionStyle),
          InkWell(
            onTap: _openMwWebsite,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'mwchats.com',
                style: textStyle?.copyWith(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w800,
                  color: kPrimaryGold.withOpacity(0.90),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TabBar _buildFixedTabBar(AppLocalizations l10n) {
    final radius = BorderRadius.circular(999);

    return TabBar(
      controller: _tabController,
      isScrollable: false,

      // Smooth + consistent animation
      indicatorAnimation: TabIndicatorAnimation.linear,

      // Selected / unselected colors (also affect icons automatically)
      labelColor: Colors.black,
      unselectedLabelColor: kOffWhite.withOpacity(0.82),

      // Gold pill indicator
      indicator: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kPrimaryGold.withOpacity(0.98),
            kGoldDeep.withOpacity(0.92),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: kGoldDeep.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,

      // No blue splash/overlay
      overlayColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.pressed)) {
          return kPrimaryGold.withOpacity(0.10);
        }
        if (states.contains(MaterialState.hovered)) {
          return kPrimaryGold.withOpacity(0.06);
        }
        return Colors.transparent;
      }),

      labelStyle: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13.5,
        letterSpacing: 0.15,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        letterSpacing: 0.10,
      ),

      tabs: [
        Tab(
          iconMargin: const EdgeInsets.only(bottom: 2),
          icon: const Icon(Icons.people_alt_outlined, size: 20),
          text: l10n.usersTitle,
        ),
        Tab(
          iconMargin: const EdgeInsets.only(bottom: 2),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
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
