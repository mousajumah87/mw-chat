// lib/screens/home/home_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/app_info.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_app_header.dart';
import '../legal/terms_of_use_screen.dart';
import 'mw_friends_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const String _websiteUrl = AppInfo.websiteUrl;

  // ✅ Canonical field (this is what we will enforce everywhere)
  static const String _kTermsAcceptedAt = 'termsAcceptedAt';

  // ✅ Legacy fields we may have used previously (tolerate + migrate)
  static const String _kTermsAcceptedAtLegacy = 'termsAcceptedAt'; // common older variant
  static const String _kHasAcceptedTermsLegacy = 'hasAcceptedTerms';

  bool _termsCheckedOnce = false;
  bool _termsFlowInProgress = false;

  void _logTerms(String msg) {
    if (kDebugMode) debugPrint('[TermsGate] $msg');
  }

  Timestamp? _readAcceptedTimestamp(Map<String, dynamic> data) {
    final v1 = data[_kTermsAcceptedAt];
    if (v1 is Timestamp) return v1;

    final v2 = data[_kTermsAcceptedAtLegacy];
    if (v2 is Timestamp) return v2;

    // Some people accidentally stored it as DateTime/string; tolerate but prefer Timestamp
    if (v1 is DateTime) return Timestamp.fromDate(v1);
    if (v2 is DateTime) return Timestamp.fromDate(v2);

    return null;
  }

  bool _isAccepted(Map<String, dynamic> data) {
    // ✅ Accepted if we have any timestamp (canonical or legacy)
    final ts = _readAcceptedTimestamp(data);
    if (ts != null) return true;

    // ✅ Very old boolean fallback
    if (data[_kHasAcceptedTermsLegacy] == true) return true;

    return false;
  }

  /// ✅ One-time migration:
  /// If legacy fields indicate accepted, write the canonical `termsAcceptedAt`.
  Future<void> _migrateAcceptanceIfNeeded(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data,
      ) async {
    final canonical = data[_kTermsAcceptedAt];

    // Already canonical Timestamp => nothing
    if (canonical is Timestamp) return;

    final legacyTs = _readAcceptedTimestamp(data);
    final legacyBool = data[_kHasAcceptedTermsLegacy] == true;

    // If any legacy form says accepted => write canonical
    if (legacyTs != null || legacyBool) {
      _logTerms('MIGRATE: writing $_kTermsAcceptedAt (canonical)');
      await ref.set(
        {_kTermsAcceptedAt: FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_termsCheckedOnce) return;
      _termsCheckedOnce = true;
      await _ensureUserAcceptedTerms();
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

  /// ✅ Robust Terms gate (no flicker):
  /// 1) CACHE check: if accepted => allow immediately, then verify server in background.
  /// 2) SERVER check: if accepted => allow, and migrate if needed.
  /// 3) Otherwise show Terms screen and write canonical acceptance on Agree.
  Future<void> _ensureUserAcceptedTerms() async {
    if (!mounted) return;

    if (_termsFlowInProgress) {
      _logTerms('Skipped: already running');
      return;
    }
    _termsFlowInProgress = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _logTerms('No currentUser (skip).');
        return;
      }

      final fs = FirebaseFirestore.instance;
      final ref = fs.collection('users').doc(user.uid);

      _logTerms('currentUser uid=${user.uid} email=${user.email}');
      _logTerms('projectId=${fs.app.options.projectId}');
      _logTerms('firestoreHost=${fs.settings.host} sslEnabled=${fs.settings.sslEnabled}');

      // -------------------------
      // 1) CACHE (fast path)
      // -------------------------
      try {
        final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
        final cacheData = cacheSnap.data() ?? const <String, dynamic>{};
        final cacheAccepted = _isAccepted(cacheData);

        _logTerms(
          'CACHE accepted=$cacheAccepted '
              '($_kTermsAcceptedAt=${cacheData[_kTermsAcceptedAt]} / '
              '$_kTermsAcceptedAtLegacy=${cacheData[_kTermsAcceptedAtLegacy]} / '
              '$_kHasAcceptedTermsLegacy=${cacheData[_kHasAcceptedTermsLegacy]})',
        );

        if (cacheAccepted) {
          // background verify + migrate if needed (don’t block UI)
          unawaited(_bgVerifyServerAndMigrate(ref));
          return;
        }
      } catch (e) {
        _logTerms('CACHE read failed (ok): $e');
      }

      // -------------------------
      // 2) SERVER truth
      // -------------------------
      final serverSnap = await ref.get(const GetOptions(source: Source.server));
      final serverData = serverSnap.data() ?? const <String, dynamic>{};
      final serverAccepted = _isAccepted(serverData);

      _logTerms(
        'SERVER accepted=$serverAccepted '
            '($_kTermsAcceptedAt=${serverData[_kTermsAcceptedAt]} / '
            '$_kTermsAcceptedAtLegacy=${serverData[_kTermsAcceptedAtLegacy]} / '
            '$_kHasAcceptedTermsLegacy=${serverData[_kHasAcceptedTermsLegacy]})',
      );

      if (serverAccepted) {
        await _migrateAcceptanceIfNeeded(ref, serverData);
        return;
      }

      if (!mounted) return;

      // -------------------------
      // 3) Show Terms screen
      // -------------------------
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const TermsOfUseScreen(),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) return;

      if (result == true) {
        // ✅ Always write CANONICAL field
        await ref.set(
          {_kTermsAcceptedAt: FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );

        final verify = await ref.get(const GetOptions(source: Source.server));
        final vData = verify.data() ?? const <String, dynamic>{};
        final ok = _isAccepted(vData);

        _logTerms('VERIFY accepted=$ok ($_kTermsAcceptedAt=${vData[_kTermsAcceptedAt]})');
        return;
      }

      // User did not accept
      await FirebaseAuth.instance.signOut();
    } catch (e, st) {
      debugPrint('[HomeScreen] Terms gate error: $e\n$st');
    } finally {
      _termsFlowInProgress = false;
    }
  }

  Future<void> _bgVerifyServerAndMigrate(
      DocumentReference<Map<String, dynamic>> ref,
      ) async {
    try {
      final serverSnap = await ref.get(const GetOptions(source: Source.server));
      final serverData = serverSnap.data() ?? const <String, dynamic>{};
      final serverAccepted = _isAccepted(serverData);

      _logTerms(
        'BG VERIFY SERVER accepted=$serverAccepted '
            '($_kTermsAcceptedAt=${serverData[_kTermsAcceptedAt]} / '
            '$_kTermsAcceptedAtLegacy=${serverData[_kTermsAcceptedAtLegacy]} / '
            '$_kHasAcceptedTermsLegacy=${serverData[_kHasAcceptedTermsLegacy]})',
      );

      if (serverAccepted) {
        await _migrateAcceptanceIfNeeded(ref, serverData);
      }
    } catch (e) {
      _logTerms('BG VERIFY failed (ok): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 900;

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
                          physics: const ClampingScrollPhysics(),
                          children: [
                            _KeepAlive(
                              child: MwFriendsTab(
                                currentUser: currentUser,
                                mode: MwFriendsTabMode.friendsOnly,
                              ),
                            ),
                            _KeepAlive(
                              child: _LazyTab(
                                controller: _tabController,
                                index: 1,
                                placeholder: const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(18),
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                builder: (_) => MwFriendsTab(
                                  currentUser: currentUser,
                                  mode: MwFriendsTabMode.mwUsersOnly,
                                  onSwitchToFriendsTab: () {
                                    if (!mounted) return;
                                    _tabController.animateTo(0);
                                  },
                                ),
                              ),
                            ),
                          ],
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
          Text(AppInfo.version, style: versionStyle),
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
      indicatorAnimation: TabIndicatorAnimation.linear,
      labelColor: Colors.black,
      unselectedLabelColor: kOffWhite.withOpacity(0.82),
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
          text: l10n.myFriends,
        ),
        Tab(
          iconMargin: const EdgeInsets.only(bottom: 2),
          icon: const Icon(Icons.public, size: 20),
          text: l10n.peopleOnMw,
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

class _LazyTab extends StatefulWidget {
  final TabController controller;
  final int index;
  final Widget placeholder;
  final WidgetBuilder builder;

  const _LazyTab({
    required this.controller,
    required this.index,
    required this.placeholder,
    required this.builder,
  });

  @override
  State<_LazyTab> createState() => _LazyTabState();
}

class _LazyTabState extends State<_LazyTab> {
  bool _built = false;

  @override
  void initState() {
    super.initState();
    _built = widget.controller.index == widget.index;
    widget.controller.addListener(_onTabChange);
  }

  void _onTabChange() {
    if (_built) return;
    if (widget.controller.index == widget.index) {
      setState(() => _built = true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_built) return widget.builder(context);
    return widget.placeholder;
  }
}
