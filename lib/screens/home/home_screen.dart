import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calls/outgoing_call_screen.dart';
import '../../features/group/controllers/create_group_controller.dart';
import '../../features/group/screens/select_group_members_screen.dart';
import '../../features/group/services/group_chat_service.dart';
import '../../features/group/widgets/my_groups_section.dart';
import '../../features/stories/widgets/stories_row.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/app_info.dart';
import '../../widgets/ui/mw_app_header.dart';
import '../../widgets/ui/mw_background.dart';
import '../chat/chat_screen.dart';
import '../legal/terms_of_use_screen.dart';
import 'call_logs_screen.dart';
import 'mw_friends_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _HomeTab {
  chats,
  people,
  stories,
  groups,
  calls,
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _websiteUrl = AppInfo.websiteUrl;

  static const String _kTermsAcceptedAt = 'termsAcceptedAt';
  static const String _kTermsAcceptedAtLegacy = 'terms_accepted_at';
  static const String _kHasAcceptedTermsLegacy = 'hasAcceptedTerms';

  bool _termsCheckedOnce = false;
  bool _termsFlowInProgress = false;

  _HomeTab _selectedTab = _HomeTab.chats;

  void _logTerms(String msg) {
    if (kDebugMode) debugPrint('[TermsGate] $msg');
  }

  TextDirection _screenDirection(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('ar') ? TextDirection.rtl : TextDirection.ltr;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_termsCheckedOnce) return;
      _termsCheckedOnce = true;
      await _ensureUserAcceptedTerms();
    });
  }

  // ---------------------------------------------------------------------------
  // Launch helpers
  // ---------------------------------------------------------------------------

  Future<bool> _launchExternalUri(
      Uri uri, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
    try {
      final ok = await launchUrl(uri, mode: mode);
      if (!ok && kDebugMode) {
        debugPrint('Could not launch: $uri');
      }
      return ok;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Launch failed for $uri: $e');
      }
      return false;
    }
  }

  Future<void> _openMwWebsite() async {
    final uri = Uri.tryParse(_websiteUrl);
    if (uri == null) return;
    await _launchExternalUri(uri);
  }

  String _sanitizePhoneNumber(String value) {
    final trimmed = value.trim();
    return trimmed.replaceAll(RegExp(r'[^\d+]'), '');
  }

  Future<void> _openPhoneNumber(String phone) async {
    final cleaned = _sanitizePhoneNumber(phone);
    if (cleaned.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: cleaned);
    final ok = await _launchExternalUri(uri);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone app')),
      );
    }
  }

  Future<void> _openSms(String phone, {String? body}) async {
    final cleaned = _sanitizePhoneNumber(phone);
    if (cleaned.isEmpty) return;

    final uri = Uri(
      scheme: 'sms',
      path: cleaned,
      queryParameters: body == null || body.trim().isEmpty
          ? null
          : <String, String>{'body': body},
    );

    final ok = await _launchExternalUri(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open SMS app')),
      );
    }
  }

  Future<void> _openEmailAddress(
      String email, {
        String? subject,
        String? body,
      }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;

    final uri = Uri(
      scheme: 'mailto',
      path: trimmed,
      queryParameters: <String, String>{
        if (subject != null && subject.trim().isNotEmpty) 'subject': subject,
        if (body != null && body.trim().isNotEmpty) 'body': body,
      },
    );

    final ok = await _launchExternalUri(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Terms gate helpers
  // ---------------------------------------------------------------------------

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
        'firestoreHost=${fs.settings.host} sslEnabled=${fs.settings.sslEnabled}',
      );

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

        _logTerms(
          'VERIFY accepted=$ok ($_kTermsAcceptedAt=${vData[_kTermsAcceptedAt]})',
        );
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

  // ---------------------------------------------------------------------------
  // Chat / call unread counters
  // ---------------------------------------------------------------------------

  Stream<int> _unreadChatCountStream(String uid) {
    final rooms = FirebaseFirestore.instance
        .collection('chatRooms')
        .where('memberIds', arrayContains: uid);

    return rooms.snapshots(includeMetadataChanges: false).map((snapshot) {
      var total = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final unreadCounts = data['unreadCounts'];
        if (unreadCounts is Map<String, dynamic>) {
          final value = unreadCounts[uid];
          if (value is int) {
            total += value;
            continue;
          }
          if (value is num) {
            total += value.toInt();
            continue;
          }
        }

        final directValue = data['unread_$uid'];
        if (directValue is int) {
          total += directValue;
          continue;
        }
        if (directValue is num) {
          total += directValue.toInt();
        }
      }

      return total;
    }).distinct();
  }

  Stream<int> _unreadGroupChatCountStream(String uid) {
    final rooms = FirebaseFirestore.instance
        .collection('groupChats')
        .where('memberIds', arrayContains: uid);

    return rooms.snapshots(includeMetadataChanges: false).map((snapshot) {
      var total = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final unreadCounts = data['unreadCounts'];
        if (unreadCounts is Map<String, dynamic>) {
          final value = unreadCounts[uid];
          if (value is int) {
            total += value;
            continue;
          }
          if (value is num) {
            total += value.toInt();
            continue;
          }
        }

        final fallback = data['unread_$uid'];
        if (fallback is int) {
          total += fallback;
          continue;
        }
        if (fallback is num) {
          total += fallback.toInt();
        }
      }

      return total;
    }).distinct();
  }

  Stream<int> _unseenStoriesCountStream(String uid) {
    final now = Timestamp.now();

    return FirebaseFirestore.instance
        .collection('stories')
        .where('expiresAt', isGreaterThan: now)
        .snapshots(includeMetadataChanges: false)
        .map((snapshot) {
      var count = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ownerId = data['ownerId']?.toString();

        if (ownerId == null || ownerId == uid) {
          continue;
        }

        final viewerIdsDynamic = data['viewerIds'];
        final viewerIds = viewerIdsDynamic is List
            ? viewerIdsDynamic.map((e) => e.toString()).toSet()
            : <String>{};

        if (!viewerIds.contains(uid)) {
          count++;
        }
      }

      return count;
    }).distinct();
  }

  Stream<int> _peopleBadgeCountStream(String uid) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final friendsRef = userRef.collection('friends');

    return userRef.snapshots(includeMetadataChanges: false).asyncMap((userSnap) async {
      final userData = userSnap.data() ?? const <String, dynamic>{};
      final lastSeen = userData['friendRequestsLastSeenAt'];

      final friendsSnap = await friendsRef.snapshots().first;
      var count = 0;

      for (final doc in friendsSnap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString();

        if (status != 'incoming') continue;

        if (lastSeen is Timestamp) {
          final updatedAt = data['updatedAt'];
          if (updatedAt is Timestamp) {
            if (updatedAt.compareTo(lastSeen) > 0) {
              count++;
            }
          } else {
            count++;
          }
        } else {
          count++;
        }
      }

      return count;
    }).distinct();
  }

  Stream<int> _unreadMissedCountStream(String uid) {
    final callLogs =
    FirebaseFirestore.instance.collection('users').doc(uid).collection(
      'call_logs',
    );

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

        final calleeId = d['calleeId']?.toString();
        return calleeId != null && calleeId == uid;
      }

      bool isMissed(Map<String, dynamic> d) {
        final result = (d['result'] ?? d['status'] ?? d['callResult'])
            ?.toString()
            .toLowerCase();

        if (result == 'missed') return true;
        if (result == 'no_answer' || result == 'noanswer') return true;
        if (result == 'timeout' || result == 'unanswered') return true;

        final endedReason = d['endedReason']?.toString().toLowerCase();
        if (endedReason == 'missed' || endedReason == 'no_answer') return true;

        return false;
      }

      for (final doc in s.docs) {
        final d = doc.data();
        final isRead = d['isRead'] == true;
        if (!isRead && isIncoming(d) && isMissed(d)) {
          unread++;
        }
      }

      return unread;
    }).distinct();
  }

  Future<void> _debugInsertCallLog(String uid) async {
    if (!kDebugMode) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('call_logs')
        .doc();

    await ref.set({
      'callId': ref.id,
      'roomId': 'DEBUG_ROOM_ID',
      'direction': 'incoming',
      'result': 'missed',
      'type': 'audio',
      'callerId': 'DEBUG_CALLER_ID',
      'calleeId': uid,
      'peerId': 'DEBUG_CALLER_ID',
      'peerName': 'Debug Caller',
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

  // ---------------------------------------------------------------------------
  // Chat / call actions
  // ---------------------------------------------------------------------------

  Future<void> _openChatFromLogs({
    required String peerId,
    required String displayName,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final other = peerId.trim();
    if (other.isEmpty || other == me.uid) return;

    final ids = [me.uid, other]..sort();
    final roomId = '${ids[0]}_${ids[1]}';

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          roomId: roomId,
          title: displayName.trim().isEmpty
              ? AppLocalizations.of(context)!.home_default_chat_title
              : displayName.trim(),
        ),
      ),
    );
  }

  Future<void> _startCallFromLogs({
    required String peerId,
    required bool video,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.callLogs_notSignedIn),
        ),
      );
      return;
    }

    final target = peerId.trim();
    if (target.isEmpty || target == me.uid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.home_invalid_peer),
        ),
      );
      return;
    }

    final pcConfig = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

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

  Future<String?> _currentUserProfileUrl() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      final data = snap.data() ?? const <String, dynamic>{};
      final url = (data['profileUrl'] ?? '').toString().trim();
      return url.isEmpty ? null : url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshAfterStoryCreated() async {
    if (!mounted) return;
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Groups / nav helpers
  // ---------------------------------------------------------------------------

  void _openCreateGroupFlow() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final controller = CreateGroupController(
      groupChatService: GroupChatService(),
      currentUserId: currentUser.uid,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectGroupMembersScreen(controller: controller),
      ),
    );
  }

  Future<void> _onBottomNavTap(_HomeTab tab) async {
    if (_selectedTab == tab) return;

    setState(() => _selectedTab = tab);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final uid = currentUser.uid;

    try {
      if (tab == _HomeTab.people) {
        await _markFriendRequestsSeen(uid);
      }

      if (tab == _HomeTab.calls) {
        await _markAllVisibleMissedCallsRead(uid);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Bottom nav side effect failed for $tab: $e');
      }
    }
  }

  String _titleForSelectedTab(AppLocalizations l10n) {
    switch (_selectedTab) {
      case _HomeTab.chats:
        return l10n.home_tab_chats;
      case _HomeTab.people:
        return l10n.home_tab_people;
      case _HomeTab.stories:
        return l10n.home_tab_stories;
      case _HomeTab.groups:
        return l10n.home_tab_groups;
      case _HomeTab.calls:
        return l10n.home_tab_calls;
    }
  }

  BoxDecoration _contentCardDecoration() {
    return BoxDecoration(
      color: kSurfaceAltColor.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: kBorderColor.withValues(alpha: 0.70),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.55),
          blurRadius: 30,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: kGoldDeep.withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: kPrimaryGold.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: kPrimaryGold,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kOffWhite,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Flexible(child: trailing),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

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
    final textDirection = _screenDirection(context);

    return Directionality(
      textDirection: textDirection,
      child: Scaffold(
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
                        title: _titleForSelectedTab(l10n),
                        showTabs: false,
                        tabBar: null,
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedTab.index,
                        children: [
                          _buildChatsPage(currentUser, isWide),
                          _buildPeoplePage(currentUser, isWide),
                          _buildStoriesPage(isWide),
                          _buildGroupsPage(isWide),
                          _buildCallsPage(currentUser.uid, isWide),
                        ],
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
        bottomNavigationBar: _buildBottomNav(l10n),
      ),
    );
  }

  Widget _buildChatsPage(User currentUser, bool isWide) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isWide ? 16 : 12,
        vertical: 4,
      ),
      decoration: _contentCardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: MwFriendsTab(
          currentUser: currentUser,
          mode: MwFriendsTabMode.friendsOnly,
          // onTapPhone: _openPhoneNumber,
          // onTapEmail: _openEmailAddress,
          // onTapSms: _openSms,
        ),
      ),
    );
  }

  Widget _buildPeoplePage(User currentUser, bool isWide) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isWide ? 16 : 12,
        vertical: 4,
      ),
      decoration: _contentCardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: MwFriendsTab(
          currentUser: currentUser,
          mode: MwFriendsTabMode.mwUsersOnly,
          onSwitchToFriendsTab: () {
            if (!mounted) return;
            setState(() => _selectedTab = _HomeTab.chats);
          },
        ),
      ),
    );
  }

  Widget _buildStoriesPage(bool isWide) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 12),
      child: FutureBuilder<String?>(
        future: _currentUserProfileUrl(),
        builder: (context, snap) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: kSurfaceAltColor.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: kBorderColor.withValues(alpha: 0.38),
              ),
            ),
            child: StoriesRow(
              currentUserImageUrl: snap.data,
              onStoryCreated: _refreshAfterStoryCreated,
            ),
          );
        },
      ),
    );
  }

  Widget _buildGroupsPage(bool isWide) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 12),
      child: Column(
        children: [
          _buildSectionHeader(
            icon: Icons.groups_rounded,
            title: l10n.home_tab_groups,
            subtitle: l10n.home_groups_subtitle,
            trailing: FilledButton.icon(
              onPressed: _openCreateGroupFlow,
              icon: const Icon(Icons.group_add_rounded, size: 18),
              label: Text(
                l10n.home_groups_new,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kSurfaceAltColor.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: kBorderColor.withValues(alpha: 0.38),
                ),
              ),
              child: MyGroupsSectionWrapper(
                onCreateGroup: _openCreateGroupFlow,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallsPage(String uid, bool isWide) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 12),
      child: Column(
        children: [
          _buildSectionHeader(
            icon: Icons.call_rounded,
            title: l10n.home_tab_calls,
            subtitle: l10n.home_calls_subtitle,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: kSurfaceAltColor.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: kBorderColor.withValues(alpha: 0.38),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: CallLogsScreen(
                  onStartCall: _startCallFromLogs,
                  onOpenChat: ({
                    required String peerId,
                    required String displayName,
                  }) {
                    _openChatFromLogs(
                      peerId: peerId,
                      displayName: displayName,
                    );
                  },
                  enableVideoButton: false,
                ),
              ),
            ),
          ),
        ],
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
      color: kTextSecondary.withValues(alpha: 0.85),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    final versionStyle = textStyle?.copyWith(
      color: kTextSecondary.withValues(alpha: 0.55),
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
          // Text(l10n.appBrandingBeta, style: textStyle),
          // Text(AppInfo.version, style: versionStyle),
          // InkWell(
          //   onTap: _openMwWebsite,
          //   borderRadius: BorderRadius.circular(16),
          //   child: Padding(
          //     padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          //     child: Text(
          //       'mwchats.com',
          //       style: textStyle?.copyWith(
          //         decoration: TextDecoration.underline,
          //         fontWeight: FontWeight.w800,
          //         color: kPrimaryGold.withValues(alpha: 0.90),
          //       ),
          //     ),
          //   ),
          // ),
          //if (false) Text('', style: versionStyle),
        ],
      ),
    );
  }

  Widget _buildBottomNav(AppLocalizations l10n) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return _buildBottomNavShell(
        l10n: l10n,
        chatsBadge: 0,
        peopleBadge: 0,
        storiesBadge: 0,
        groupsBadge: 0,
        callsBadge: 0,
      );
    }

    final uid = currentUser.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final friendsRef = userRef.collection('friends');

    return StreamBuilder<int>(
      stream: _unreadChatCountStream(uid),
      builder: (context, directSnap) {
        return StreamBuilder<int>(
          stream: _unreadGroupChatCountStream(uid),
          builder: (context, groupSnap) {
            return StreamBuilder<int>(
              stream: _unseenStoriesCountStream(uid),
              builder: (context, storiesSnap) {
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userRef.snapshots(includeMetadataChanges: false),
                  builder: (context, userSnap) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: friendsRef.snapshots(includeMetadataChanges: false),
                      builder: (context, friendsSnap) {
                        return StreamBuilder<int>(
                          stream: _unreadMissedCountStream(uid),
                          builder: (context, callsSnap) {
                            final directUnread = directSnap.data ?? 0;
                            final groupUnread = groupSnap.data ?? 0;
                            final storiesUnread = storiesSnap.data ?? 0;
                            final callsUnread = callsSnap.data ?? 0;

                            final userData =
                                userSnap.data?.data() ?? const <String, dynamic>{};
                            final lastSeen = userData['friendRequestsLastSeenAt'];

                            var peopleUnread = 0;
                            final friendDocs = friendsSnap.data?.docs ?? const [];

                            for (final doc in friendDocs) {
                              final data = doc.data();
                              final status = (data['status'] ?? '').toString();
                              if (status != 'incoming') continue;

                              if (lastSeen is Timestamp) {
                                final updatedAt = data['updatedAt'];
                                if (updatedAt is Timestamp) {
                                  if (updatedAt.compareTo(lastSeen) > 0) {
                                    peopleUnread++;
                                  }
                                } else {
                                  peopleUnread++;
                                }
                              } else {
                                peopleUnread++;
                              }
                            }

                            return _buildBottomNavShell(
                              l10n: l10n,
                              chatsBadge: directUnread + groupUnread,
                              peopleBadge: peopleUnread,
                              storiesBadge: storiesUnread,
                              groupsBadge: groupUnread,
                              callsBadge: callsUnread,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBottomNavShell({
    required AppLocalizations l10n,
    required int chatsBadge,
    required int peopleBadge,
    required int storiesBadge,
    required int groupsBadge,
    required int callsBadge,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _navItem(
              tab: _HomeTab.chats,
              icon: Icons.chat_bubble_rounded,
              label: l10n.home_tab_chats,
              badgeCount: chatsBadge,
            ),
            _navItem(
              tab: _HomeTab.people,
              icon: Icons.public_rounded,
              label: l10n.home_tab_people,
              badgeCount: peopleBadge,
            ),
            _navItem(
              tab: _HomeTab.stories,
              icon: Icons.auto_stories_rounded,
              label: l10n.home_tab_stories,
              badgeCount: storiesBadge,
            ),
            _navItem(
              tab: _HomeTab.groups,
              icon: Icons.groups_rounded,
              label: l10n.home_tab_groups,
              badgeCount: groupsBadge,
            ),
            _navItem(
              tab: _HomeTab.calls,
              icon: Icons.call_rounded,
              label: l10n.home_tab_calls,
              badgeCount: callsBadge,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markDirectRoomAsRead(String roomId, String uid) async {
    await FirebaseFirestore.instance.collection('chatRooms').doc(roomId).set({
      'unreadCounts': {uid: 0},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _markGroupRoomAsRead(String roomId, String uid) async {
    await FirebaseFirestore.instance.collection('groupChats').doc(roomId).set({
      'unreadCounts': {uid: 0},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markStoryViewed(String storyId, String uid) async {
    final ref = FirebaseFirestore.instance.collection('stories').doc(storyId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? const <String, dynamic>{};

      final viewerIdsDynamic = data['viewerIds'];
      final viewerIds = viewerIdsDynamic is List
          ? viewerIdsDynamic.map((e) => e.toString()).toSet()
          : <String>{};

      if (viewerIds.contains(uid)) {
        return;
      }

      final currentViewerCount = data['viewerCount'];
      final nextCount = currentViewerCount is num ? currentViewerCount.toInt() + 1 : 1;

      tx.set(
        ref,
        {
          'viewerIds': FieldValue.arrayUnion([uid]),
          'viewerCount': nextCount,
          'viewerTimestamps': {
            uid: FieldValue.serverTimestamp(),
          },
          'viewedAt': {
            uid: FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _markAllVisibleMissedCallsRead(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('call_logs')
        .where('isRead', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    bool isIncoming(Map<String, dynamic> d) {
      final dir = (d['direction'] ?? d['dir'] ?? d['callDirection'])
          ?.toString()
          .toLowerCase();

      if (dir == 'incoming' || dir == 'in') return true;

      final calleeId = d['calleeId']?.toString();
      return calleeId != null && calleeId == uid;
    }

    bool isMissed(Map<String, dynamic> d) {
      final result = (d['result'] ?? d['status'] ?? d['callResult'])
          ?.toString()
          .toLowerCase();

      if (result == 'missed') return true;
      if (result == 'no_answer' || result == 'noanswer') return true;
      if (result == 'timeout' || result == 'unanswered') return true;

      final endedReason = d['endedReason']?.toString().toLowerCase();
      return endedReason == 'missed' || endedReason == 'no_answer';
    }

    for (final doc in snap.docs) {
      final data = doc.data();
      if (!isIncoming(data) || !isMissed(data)) {
        continue;
      }

      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<void> _markFriendRequestsSeen(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'friendRequestsLastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Widget _navItem({
    required _HomeTab tab,
    required IconData icon,
    required String label,
    int badgeCount = 0,
  }) {
    final selected = _selectedTab == tab;
    final showBadge = badgeCount > 0;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onBottomNavTap(tab),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            decoration: BoxDecoration(
              color: selected
                  ? kPrimaryGold.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: selected ? kPrimaryGold : Colors.white70,
                    ),
                    if (showBadge)
                      PositionedDirectional(
                        top: -7,
                        end: -10,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.black,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: selected ? 11 : 10,
                      fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? kPrimaryGold : Colors.white70,
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

class MyGroupsSectionWrapper extends StatelessWidget {
  final VoidCallback onCreateGroup;

  const MyGroupsSectionWrapper({
    super.key,
    required this.onCreateGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 72),
            child: MyGroupsSection(),
          ),
        ),
        PositionedDirectional(
          end: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'groups_fab',
            backgroundColor: kPrimaryGold,
            foregroundColor: Colors.black,
            onPressed: onCreateGroup,
            child: const Icon(Icons.group_add_rounded),
          ),
        ),
      ],
    );
  }
}