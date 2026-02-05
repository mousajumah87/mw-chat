// lib/screens/home/home_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calls/call_screen.dart';
import '../../calls/call_signaling_service.dart';
import '../../calls/outgoing_call_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/app_info.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_app_header.dart';
import '../legal/terms_of_use_screen.dart';
import 'call_logs_screen.dart';
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

  // ✅ Canonical field (enforced everywhere)
  static const String _kTermsAcceptedAt = 'termsAcceptedAt';

  // ✅ Legacy variants (tolerate + migrate)
  static const String _kTermsAcceptedAtLegacy = 'terms_accepted_at';
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

    if (v1 is DateTime) return Timestamp.fromDate(v1);
    if (v2 is DateTime) return Timestamp.fromDate(v2);

    return null;
  }

  bool _isAccepted(Map<String, dynamic> data) {
    final ts = _readAcceptedTimestamp(data);
    if (ts != null) return true;

    if (data[_kHasAcceptedTermsLegacy] == true) return true;

    return false;
  }

  Future<void> _migrateAcceptanceIfNeeded(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data,
      ) async {
    final canonical = data[_kTermsAcceptedAt];
    if (canonical is Timestamp) return;

    final legacyTs = _readAcceptedTimestamp(data);
    final legacyBool = data[_kHasAcceptedTermsLegacy] == true;

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
// ----------------------------
// Call Logs: unread missed count (schema-tolerant + low-flicker)
// ----------------------------

  /// Reads last N logs and counts missed+incoming where isRead != true.
  /// Optimized to avoid UI flicker + avoid unnecessary rebuilds.
  Stream<int> _unreadMissedCountStream(String uid) {
    final callLogs = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('call_logs');

    return callLogs
        .orderBy('createdAtMs', descending: true)
        .limit(300)
        .snapshots(includeMetadataChanges: false)
        .map((s) {
      var unread = 0;

      bool isIncoming(Map<String, dynamic> d) {
        final dir = (d['direction'] ?? d['dir'] ?? d['callDirection'])
            ?.toString()
            .toLowerCase();

        if (dir == 'incoming' || dir == 'in') return true;

        // Fallback heuristic: if this user is the callee, it's incoming.
        final calleeId = d['calleeId']?.toString();
        return calleeId != null && calleeId == uid;
      }

      bool isMissed(Map<String, dynamic> d) {
        final result = (d['result'] ?? d['status'] ?? d['callResult'])
            ?.toString()
            .toLowerCase();

        // Canonical
        if (result == 'missed') return true;

        // Common alternates
        if (result == 'no_answer' || result == 'noanswer') return true;
        if (result == 'timeout' || result == 'unanswered') return true;

        // If you ever used "endedReason"
        final endedReason = d['endedReason']?.toString().toLowerCase();
        if (endedReason == 'missed' || endedReason == 'no_answer') return true;

        return false;
      }

      for (final doc in s.docs) {
        final d = doc.data();
        final isRead = d['isRead'] == true; // missing/null => unread
        if (!isRead && isIncoming(d) && isMissed(d)) {
          unread++;
        }
      }

      return unread;
    })
        .distinct();
  }

  Future<void> _debugInsertCallLog(String uid) async {
    if (!kDebugMode) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('call_logs')
        .doc();

    // ✅ Make debug doc match real schema so the UI behaves identically
    await ref.set({
      'callId': ref.id,
      'roomId': 'DEBUG_ROOM_ID',
      'direction': 'incoming',
      'result': 'missed',
      'type': 'audio',

      // ✅ ids + peer fields
      'callerId': 'DEBUG_CALLER_ID',
      'calleeId': uid,
      'peerId': 'DEBUG_CALLER_ID',
      'peerName': 'Debug Caller',

      // optional name fields
      'callerName': 'Debug Caller',
      'calleeName': 'Me',

      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,

      'isRead': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('[CallLogsChip] inserted debug call log: ${ref.id}');
  }

  bool _looksLikeIndexError(Object err) {
    final s = err.toString().toLowerCase();
    return s.contains('failed-precondition') ||
        s.contains('requires an index') ||
        s.contains('index');
  }

  bool _isPermissionDenied(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('permission-denied') ||
        s.contains('missing or insufficient permissions');
  }

  // Start-call handler used by CallLogsScreen
  Future<void> _startCallFromLogs({
    required String peerId,
    required bool video,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.callLogs_notSignedIn)),
      );
      return;
    }

    final target = peerId.trim();
    if (target.isEmpty || target == me.uid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid peer')),
      );
      return;
    }

    // ✅ IMPORTANT: define pcConfig here once (later you replace with TURN)
    final pcConfig = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    // ✅ Recommended: go through OutgoingCallScreen (it computes roomId + navigates)
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/outgoing_call'),
        builder: (_) => OutgoingCallScreen(
          peerId: target,
          video: video,
          pcConfig: pcConfig,
        ),
      ),
    );
  }

  Widget _buildCallLogsChip({required String uid}) {
    return StreamBuilder<int>(
      stream: _unreadMissedCountStream(uid),
      builder: (context, snap) {
        final l10n = AppLocalizations.of(context)!;

        // ✅ Keep last good value to reduce “0 -> real number” flicker on reconnect
        // (StreamBuilder rebuilds; we can be tolerant by showing previous data if waiting)
        final int? value = snap.hasData ? snap.data : null;

        if (snap.hasError) {
          final err = snap.error!;
          debugPrint('[CallLogsChip] stream error: $err');

          final isIndex = _looksLikeIndexError(err);
          final isPerm = _isPermissionDenied(err);

          // If App Check / rules cause permission errors, show a helpful chip but still navigable.
          final chipText = isIndex
              ? l10n.callLogs_chip_indexNeeded(l10n.callLogs_title)
              : (isPerm
              ? l10n.callLogs_chip_errorPermission(l10n.callLogs_title)
              : l10n.callLogs_chip_error(l10n.callLogs_title));

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onLongPress: () async {
                  if (!kDebugMode) return;
                  await _debugInsertCallLog(uid);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.debug_insertedCallLog)),
                  );
                },
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallLogsScreen(
                        onStartCall: _startCallFromLogs,
                        onOpenChat: ({required peerId, required displayName}) {
                          // navigate to your chat screen here
                        },
                        enableVideoButton: false,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.orangeAccent.withOpacity(0.14),
                    border: Border.all(
                      color: Colors.orangeAccent.withOpacity(0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.call_rounded,
                        size: 18,
                        color: Colors.orangeAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        chipText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.orangeAccent,
                          fontSize: 12.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.orangeAccent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // ✅ Smooth loading: if waiting and we don’t have data yet, keep neutral chip
        final missedUnread = value ?? 0;
        final hasUnreadMissed = missedUnread > 0;

        final bool showLoading =
            snap.connectionState == ConnectionState.waiting && value == null;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onLongPress: () async {
                // ✅ Debug-only: long press inserts one missed call log doc
                if (!kDebugMode) return;
                await _debugInsertCallLog(uid);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.debug_insertedCallLog)),
                );
              },
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallLogsScreen(
                      onStartCall: _startCallFromLogs,
                      onOpenChat: ({required peerId, required displayName}) {
                        // navigate to your chat screen here
                      },
                      enableVideoButton: false,
                    ),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: hasUnreadMissed
                      ? Colors.redAccent.withOpacity(0.14)
                      : Colors.white.withOpacity(0.06),
                  border: Border.all(
                    color: hasUnreadMissed
                        ? Colors.redAccent.withOpacity(0.45)
                        : Colors.white.withOpacity(0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showLoading) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ] else ...[
                      Icon(
                        Icons.call_rounded,
                        size: 18,
                        color: hasUnreadMissed ? Colors.redAccent : Colors.white70,
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      hasUnreadMissed
                          ? l10n.callLogs_chip_missedCount(
                        l10n.callLogs_title,
                        l10n.callLogs_filter_missed,
                        missedUnread,
                      )
                          : l10n.callLogs_title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: hasUnreadMissed ? Colors.redAccent : Colors.white70,
                        fontSize: 12.8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: hasUnreadMissed ? Colors.redAccent : Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ----------------------------
  // Terms gate
  // ----------------------------

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
      _logTerms(
          'firestoreHost=${fs.settings.host} sslEnabled=${fs.settings.sslEnabled}');

      // 1) CACHE
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
          unawaited(_bgVerifyServerAndMigrate(ref));
          return;
        }
      } catch (e) {
        _logTerms('CACHE read failed (ok): $e');
      }

      // 2) SERVER
      final serverSnap =
      await ref.get(const GetOptions(source: Source.server));
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

      // 3) SHOW TERMS
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const TermsOfUseScreen(),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) return;

      if (result == true) {
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
      final serverSnap =
      await ref.get(const GetOptions(source: Source.server));
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

  // ----------------------------
  // UI
  // ----------------------------

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const SizedBox.shrink();
    }

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
                  _buildCallLogsChip(uid: currentUser.uid),
                  const SizedBox(height: 10),
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
