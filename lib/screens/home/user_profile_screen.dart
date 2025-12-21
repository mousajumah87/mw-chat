// lib/screens/home/user_profile_screen.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_avatar.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_feedback.dart';
import '../../widgets/safety/report_user_dialog.dart';

// ✅ friendship normalization / helpers (accepted/requested/incoming)
import '../chat/chat_friendship_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  static const int _onlineTtlSeconds = 300;
  static const String _appVersion = 'v1.0';
  static const String _websiteUrl = 'https://www.mwchats.com';

  bool _isBlocking = false;
  late final AnimationController _glowController;

  // ✅ NEW: cache the latest good snapshots to avoid "flashing" on reconnects
  Map<String, dynamic>? _cachedMyData;
  Map<String, dynamic>? _cachedUserData; // target profile
  Map<String, dynamic>? _cachedFriendData;

  // Presence privacy values
  static const String _presenceFriends = 'friends';
  static const String _presenceNobody = 'nobody';

  // Profile privacy values
  static const String _privacyEveryone = 'everyone';
  static const String _privacyFriends = 'friends';
  static const String _privacyNobody = 'nobody';

  // New field names (aligned with your Friends tab + rules)
  static const String _fieldProfileVisibility = 'profileVisibility';
  static const String _fieldAddFriendVisibility = 'addFriendVisibility';

  // Legacy field names
  static const String _legacyFriendRequestsField = 'friendRequests';
  static const String _legacyShowOnlineStatusField = 'showOnlineStatus';

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _openMwWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok) debugPrint('Could not launch $_websiteUrl');
  }

  bool _isOnlineWithTtl({
    required bool rawIsOnline,
    required Timestamp? lastSeen,
  }) {
    if (!rawIsOnline || lastSeen == null) return false;
    final diffSeconds = DateTime.now().difference(lastSeen.toDate()).inSeconds;
    return diffSeconds <= _onlineTtlSeconds;
  }

  (String label, Color color) _buildPresenceStatus(
      AppLocalizations l10n, {
        required bool isActive,
        required bool effectiveOnline,
      }) {
    if (!isActive) return (l10n.accountNotActive, Colors.orangeAccent);
    if (effectiveOnline) return (l10n.online, kAccentColor);
    return (l10n.offline, Colors.grey);
  }

  String _ageLabel(DateTime? dob, AppLocalizations l10n) {
    if (dob == null) return l10n.unknown;
    int years = DateTime.now().year - dob.year;
    final now = DateTime.now();
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years.toString();
  }

  // ✅ Open profile image in full screen (Instagram-like)
  void _openProfilePhotoFullScreen({
    required String imageUrl,
    required String heroTag,
  }) {
    if (imageUrl.trim().isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => _FullScreenImageViewer(
          imageUrl: imageUrl,
          heroTag: heroTag,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  // ----------------------------
  // Privacy helpers (same logic as Friends tab)
  // ----------------------------

  String _normalizePrivacy(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return _privacyEveryone; // backward compatible
    if (v == _privacyFriends) return _privacyFriends;
    if (v == _privacyNobody) return _privacyNobody;
    return _privacyEveryone;
  }

  String _readPrivacyValue(Map<String, dynamic> data, String field) {
    final String? rawNew = data[field] as String?;

    String? rawLegacy;
    if (field == _fieldAddFriendVisibility) {
      rawLegacy = data[_legacyFriendRequestsField] as String?;
    } else if (field == _fieldProfileVisibility) {
      rawLegacy = null;
    }

    final chosen = (rawNew != null && rawNew.trim().isNotEmpty) ? rawNew : rawLegacy;
    return _normalizePrivacy(chosen);
  }

  String _readPresenceVisibility(Map<String, dynamic> data) {
    final dynamic rawShow = data[_legacyShowOnlineStatusField];
    if (rawShow is bool && rawShow == false) return _presenceNobody;

    final raw = (data['presenceVisibility'] as String?)?.trim().toLowerCase();
    if (raw == _presenceNobody) return _presenceNobody;

    return _presenceFriends; // privacy-first default
  }

  bool _canViewProfile({
    required String profileVisibility,
    required String? friendStatus,
    required bool isBlockedRelationship,
    required bool isActive,
  }) {
    if (!isActive) return false;
    if (isBlockedRelationship) return false;

    if (profileVisibility == _privacyNobody) return false;
    if (profileVisibility == _privacyEveryone) return true;

    return ChatFriendshipService.isFriends(friendStatus);
  }

  bool _canSeePresence({
    required String presenceVisibility,
    required String? friendStatus,
    required bool isBlockedRelationship,
    required bool isActive,
  }) {
    if (!isActive) return false;
    if (isBlockedRelationship) return false;
    if (presenceVisibility == _presenceNobody) return false;

    return ChatFriendshipService.isFriends(friendStatus);
  }

  String? _normalizeFriendStatusFromDoc(Map<String, dynamic>? data) {
    if (data == null) return null;
    final rawStatus = data['status'] as String?;
    final normalized = ChatFriendshipService.normalizeStatus(rawStatus);
    if (normalized == null || normalized.isEmpty) return null;

    // keep parity with Friends tab mapping
    if (normalized == ChatFriendshipService.statusRequestReceivedAlias) {
      return ChatFriendshipService.statusIncoming;
    }
    return normalized;
  }

  // ----------------------------
  // Block / Report actions
  // ----------------------------

  Future<void> _toggleBlockUser(
      BuildContext context, {
        required String currentUid,
        required bool currentlyBlocked,
      }) async {
    final l10n = AppLocalizations.of(context)!;

    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceAltColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kBorderColor.withOpacity(0.55)),
        ),
        title: Text(
          currentlyBlocked
              ? l10n.profileBlockDialogTitleUnblock
              : l10n.profileBlockDialogTitleBlock,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          currentlyBlocked
              ? l10n.profileBlockDialogBodyUnblock
              : l10n.profileBlockDialogBodyBlock,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: kTextSecondary.withOpacity(0.95)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              currentlyBlocked
                  ? l10n.profileBlockDialogConfirmUnblock
                  : l10n.profileBlockDialogConfirmBlock,
              style: TextStyle(
                color: currentlyBlocked ? kPrimaryGold : Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ) ??
        false;

    if (!confirm) return;

    if (!mounted) return;
    setState(() => _isBlocking = true);

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(currentUid);

      await ref.set(
        {
          'blockedUserIds': currentlyBlocked
              ? FieldValue.arrayRemove([widget.userId])
              : FieldValue.arrayUnion([widget.userId]),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      await MwFeedback.success(
        context,
        message: currentlyBlocked
            ? l10n.profileBlockSnackbarUnblocked
            : l10n.profileBlockSnackbarBlocked,
      );
    } catch (e, st) {
      debugPrint('[UserProfile] block/unblock error: $e\n$st');
      if (!mounted) return;
      await MwFeedback.error(context, message: l10n.generalErrorMessage);
    } finally {
      if (mounted) setState(() => _isBlocking = false);
    }
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
    final versionStyle = textStyle?.copyWith(color: Colors.white38);

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
          Text(l10n.appBrandingBeta, style: textStyle, textAlign: TextAlign.center),
          Text(_appVersion, style: versionStyle, textAlign: TextAlign.center),
          InkWell(
            onTap: _openMwWebsite,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                l10n.websiteDomain,
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

  // ✅ Helper: extract user snapshot data, but keep cache if stream is reconnecting
  Map<String, dynamic>? _safeDataFromSnapshot(
      AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
      Map<String, dynamic>? cache,
      ) {
    if (snap.hasData && snap.data != null && snap.data!.exists) {
      final d = snap.data!.data();
      if (d != null) return d;
    }
    // If reconnecting (waiting), return cache to prevent flashing
    return cache;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid;
    final isSelf = currentUid == widget.userId;

    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    // If user not signed in, still allow viewing with limited features.
    final myDocStream = (currentUid == null)
        ? null
        : FirebaseFirestore.instance.collection('users').doc(currentUid).snapshots();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.userProfileTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        )
            : null,
      ),
      body: MwBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
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
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: myDocStream,
                        builder: (context, mySnap) {
                          // ✅ cache my user doc to avoid flashing
                          final myDataCandidate = _safeDataFromSnapshot(mySnap, _cachedMyData);
                          if (myDataCandidate != null) _cachedMyData = myDataCandidate;
                          final myData = myDataCandidate ?? const <String, dynamic>{};

                          final myBlockedDynamic =
                              (myData['blockedUserIds'] as List<dynamic>?) ?? const [];
                          final myBlocked = myBlockedDynamic.map((e) => e.toString()).toList();
                          final isBlockedByMe =
                              currentUid != null && myBlocked.contains(widget.userId);

                          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(widget.userId)
                                .snapshots(),
                            builder: (context, snapshot) {
                              // ✅ cache target profile doc to avoid shimmer on return
                              final userDataCandidate =
                              _safeDataFromSnapshot(snapshot, _cachedUserData);

                              if (userDataCandidate != null) _cachedUserData = userDataCandidate;

                              // Show shimmer ONLY if we have nothing cached yet (true first load)
                              final hasAnyProfileData = userDataCandidate != null;
                              if (!hasAnyProfileData) {
                                // If stream is still connecting and we have no cache, show loader
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const _ShimmerLoader();
                                }
                                // If not found
                                return Center(
                                  child: Text(
                                    l10n.userNotFound,
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                );
                              }

                              final data = userDataCandidate!;

                              final firstName = (data['firstName'] ?? '').toString();
                              final lastName = (data['lastName'] ?? '').toString();
                              final fullName = '$firstName $lastName'.trim();

                              final avatarType = (data['avatarType'] ?? 'bear').toString();
                              final profileUrl = (data['profileUrl'] ?? '').toString();
                              final gender = (data['gender'] ?? '').toString();
                              final isActive = data['isActive'] != false;

                              // Who they block (includes: if they blocked me)
                              final theirBlockedDynamic =
                                  (data['blockedUserIds'] as List<dynamic>?) ?? const [];
                              final theirBlocked =
                              theirBlockedDynamic.map((e) => e.toString()).toList();
                              final hasBlockedMe =
                                  currentUid != null && theirBlocked.contains(currentUid);

                              final isBlockedRelationship = isBlockedByMe || hasBlockedMe;

                              // Relationship doc stream: /users/{me}/friends/{them}
                              final friendDocStream = (currentUid == null || isSelf)
                                  ? null
                                  : FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(currentUid)
                                  .collection('friends')
                                  .doc(widget.userId)
                                  .snapshots();

                              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                stream: friendDocStream,
                                builder: (context, relSnap) {
                                  // ✅ cache relationship doc too (prevents banner/buttons flicker)
                                  Map<String, dynamic>? relCandidate;
                                  if (relSnap.hasData && relSnap.data != null && relSnap.data!.exists) {
                                    relCandidate = relSnap.data!.data();
                                  } else {
                                    relCandidate = _cachedFriendData;
                                  }
                                  if (relCandidate != null) _cachedFriendData = relCandidate;

                                  final friendStatus =
                                  _normalizeFriendStatusFromDoc(relCandidate);

                                  // Privacy decisions
                                  final profileVisibility =
                                  _readPrivacyValue(data, _fieldProfileVisibility);
                                  final canViewProfile = _canViewProfile(
                                    profileVisibility: profileVisibility,
                                    friendStatus: friendStatus,
                                    isBlockedRelationship: isBlockedRelationship,
                                    isActive: isActive,
                                  );

                                  final presenceVisibility = _readPresenceVisibility(data);
                                  final canSeePresence = _canSeePresence(
                                    presenceVisibility: presenceVisibility,
                                    friendStatus: friendStatus,
                                    isBlockedRelationship: isBlockedRelationship,
                                    isActive: isActive,
                                  );

                                  // Presence fields
                                  final rawIsOnline = isActive && data['isOnline'] == true;
                                  final lastSeen = data['lastSeen'] is Timestamp
                                      ? data['lastSeen'] as Timestamp
                                      : null;

                                  final effectiveOnline = canSeePresence &&
                                      _isOnlineWithTtl(
                                        rawIsOnline: rawIsOnline,
                                        lastSeen: lastSeen,
                                      );

                                  final (presenceLabel, presenceColor) =
                                  _buildPresenceStatus(
                                    l10n,
                                    isActive: isActive,
                                    effectiveOnline: effectiveOnline,
                                  );

                                  DateTime? dob;
                                  final rawBirthday = data['birthday'];
                                  if (rawBirthday is Timestamp) {
                                    dob = rawBirthday.toDate();
                                  }

                                  // If profile is private, don’t show personal fields.
                                  final ageLabel =
                                  canViewProfile ? _ageLabel(dob, l10n) : l10n.unknown;
                                  final birthdayLabel = (canViewProfile && dob != null)
                                      ? DateFormat.yMMMd(l10n.localeName).format(dob)
                                      : l10n.unknown;
                                  String _localizedGender(
                                      AppLocalizations l10n,
                                      String gender,
                                      bool canViewProfile,
                                      ) {
                                    if (!canViewProfile || gender.isEmpty) {
                                      return l10n.notSpecified;
                                    }

                                    switch (gender.toLowerCase()) {
                                      case 'male':
                                        return l10n.male;
                                      case 'female':
                                        return l10n.female;
                                      default:
                                        return l10n.notSpecified;
                                    }
                                  }
                                  final genderLabel = _localizedGender(
                                    l10n,
                                    gender,
                                    canViewProfile,
                                  );
                                  // Show avatar image only if viewer can view profile & not blocked
                                  final bool canShowProfilePhoto =
                                      canViewProfile && !isBlockedRelationship;

                                  final heroTag = 'profile_photo_${widget.userId}';

                                  final avatar = GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: (!canShowProfilePhoto || profileUrl.isEmpty)
                                        ? null
                                        : () => _openProfilePhotoFullScreen(
                                      imageUrl: profileUrl,
                                      heroTag: heroTag,
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        AnimatedBuilder(
                                          animation: _glowController,
                                          builder: (_, __) {
                                            final glow = _glowController.value;
                                            return Container(
                                              width: 130,
                                              height: 130,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: RadialGradient(
                                                  colors: [
                                                    kPrimaryGold.withOpacity(0.3 + glow * 0.2),
                                                    kGoldDeep.withOpacity(0.2 + glow * 0.2),
                                                    Colors.transparent,
                                                  ],
                                                  stops: const [0.4, 0.8, 1],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        MwAvatar(
                                          heroTag: heroTag,
                                          radius: 58,
                                          avatarType: avatarType,
                                          profileUrl: canShowProfilePhoto ? profileUrl : '',
                                          hideRealAvatar: !canShowProfilePhoto,
                                          showRing: true,
                                          showOnlineDot: false,
                                          showOnlineGlow: false,
                                          cachePolicy: MwAvatarCachePolicy.normal,
                                        ),
                                        if (canShowProfilePhoto && profileUrl.isNotEmpty)
                                          Positioned(
                                            bottom: 2,
                                            right: 2,
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.60),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white.withOpacity(0.12),
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.zoom_in_rounded,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );

                                  // ✅ Safety tools ONLY for friends (accepted)
                                  final bool canShowSafetyTools = !isSelf &&
                                      currentUid != null &&
                                      ChatFriendshipService.isFriends(friendStatus);

                                  return SingleChildScrollView(
                                    key: PageStorageKey<String>('user_profile_${widget.userId}'),
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.all(24),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 540),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            avatar,
                                            const SizedBox(height: 16),
                                            Text(
                                              fullName.isNotEmpty ? fullName : l10n.unknown,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 12),

                                            // Presence chip (respects privacy)
                                            AnimatedContainer(
                                              duration: const Duration(milliseconds: 400),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: presenceColor.withOpacity(0.20),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: presenceColor.withOpacity(0.8),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: presenceColor.withOpacity(0.35),
                                                    blurRadius: 10,
                                                    spreadRadius: 1,
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.circle, size: 10, color: presenceColor),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    presenceLabel,
                                                    style: TextStyle(
                                                      color: presenceColor,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            if (isBlockedRelationship) ...[
                                              const SizedBox(height: 10),
                                              Text(
                                                l10n.profileBlockedUserHintLimitedVisibility,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.white60,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ] else if (!canViewProfile) ...[
                                              const SizedBox(height: 10),
                                              Text(
                                                l10n.privacySectionTitle,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.white60,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],

                                            const SizedBox(height: 24),
                                            const Divider(color: Colors.white24),
                                            const SizedBox(height: 16),

                                            _InfoRow(
                                              icon: Icons.cake_outlined,
                                              label: l10n.ageLabel,
                                              value: ageLabel,
                                            ),
                                            const SizedBox(height: 10),
                                            _InfoRow(
                                              icon: Icons.calendar_today_outlined,
                                              label: l10n.birthdayLabel,
                                              value: birthdayLabel,
                                            ),
                                            const SizedBox(height: 10),
                                            _InfoRow(
                                              icon: Icons.person_outline,
                                              label: l10n.genderLabel,
                                              value: genderLabel,
                                            ),

                                            // ✅ Safety Tools (friends only)
                                            if (canShowSafetyTools) ...[
                                              const SizedBox(height: 28),
                                              const Divider(color: Colors.white24),
                                              const SizedBox(height: 12),
                                              Align(
                                                alignment: AlignmentDirectional.centerStart,
                                                child: Text(
                                                  l10n.profileSafetyToolsSectionTitle,
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                    color: Colors.white70,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Column(
                                                children: [
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: ElevatedButton.icon(
                                                      onPressed: (_isBlocking || currentUid == null)
                                                          ? null
                                                          : () => _toggleBlockUser(
                                                        context,
                                                        currentUid: currentUid,
                                                        currentlyBlocked: isBlockedByMe,
                                                      ),
                                                      icon: Icon(
                                                        isBlockedByMe
                                                            ? Icons.person_remove
                                                            : Icons.block,
                                                        size: 18,
                                                      ),
                                                      label: Text(
                                                        isBlockedByMe
                                                            ? l10n.profileBlockButtonUnblock
                                                            : l10n.profileBlockButtonBlock,
                                                      ),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: isBlockedByMe
                                                            ? Colors.red.withOpacity(0.45)
                                                            : Colors.redAccent,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(24),
                                                        ),
                                                        elevation: 6,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: OutlinedButton.icon(
                                                      onPressed: () => ReportUserDialog.open(
                                                        context,
                                                        reportedUserId: widget.userId,
                                                        reporterUserIdOverride: currentUid,
                                                      ),
                                                      icon: const Icon(Icons.flag_outlined, size: 18),
                                                      label: Text(l10n.profileReportButtonLabel),
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: kGoldDeep,
                                                        side: const BorderSide(
                                                          color: kGoldDeep,
                                                          width: 1.4,
                                                        ),
                                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(24),
                                                        ),
                                                        backgroundColor: Colors.black.withOpacity(0.35),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
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
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white70),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ShimmerLoader extends StatelessWidget {
  const _ShimmerLoader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: const BoxDecoration(
          color: kSurfaceAltColor,
          shape: BoxShape.circle,
        ),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

// ✅ Full-screen image viewer (Instagram-like) WITH CACHED NETWORK IMAGE
class _FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String heroTag;

  const _FullScreenImageViewer({
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  double _dragDy = 0.0;
  bool _isDraggingDown = false;

  static const double _dismissThreshold = 140.0;
  static const double _maxBgFadeDistance = 420.0;

  double get _currentScale => _transform.value.storage[0];
  bool get _isZoomed => _currentScale > 1.01;

  void _resetZoom() {
    _transform.value = Matrix4.identity();
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      setState(_resetZoom);
      return;
    }

    final d = _doubleTapDetails;
    if (d == null) return;

    const double scale = 2.6;
    final tap = d.localPosition;

    final zoomed = Matrix4.identity()
      ..translate(-tap.dx * (scale - 1), -tap.dy * (scale - 1))
      ..scale(scale);

    setState(() {
      _transform.value = zoomed;
    });
  }

  void _onVerticalDragStart(DragStartDetails d) {
    if (_isZoomed) return;
    _isDraggingDown = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (!_isDraggingDown || _isZoomed) return;
    setState(() {
      _dragDy += d.delta.dy;
      if (_dragDy < 0) _dragDy = 0;
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (!_isDraggingDown || _isZoomed) return;

    final velocity = d.primaryVelocity ?? 0.0;
    final shouldDismiss = _dragDy > _dismissThreshold || velocity > 1200;

    if (shouldDismiss) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _dragDy = 0.0;
        _isDraggingDown = false;
      });
    }
  }

  double _backgroundOpacity() {
    final t = (_dragDy / _maxBgFadeDistance).clamp(0.0, 1.0);
    return (1.0 - (t * 0.75)).clamp(0.25, 1.0);
  }

  double _contentScaleDuringDrag() {
    final t = (_dragDy / _maxBgFadeDistance).clamp(0.0, 1.0);
    return (1.0 - (t * 0.10)).clamp(0.90, 1.0);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgOpacity = _backgroundOpacity();
    final dragScale = _contentScaleDuringDrag();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 90),
                opacity: bgOpacity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(color: Colors.black),
                ),
              ),
            ),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTapDown: (d) => _doubleTapDetails = d,
                onDoubleTap: _handleDoubleTap,
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOut,
                  transform: Matrix4.identity()
                    ..translate(0.0, _dragDy)
                    ..scale(dragScale),
                  child: Hero(
                    tag: widget.heroTag,
                    child: Material(
                      color: Colors.transparent,
                      child: InteractiveViewer(
                        transformationController: _transform,
                        panEnabled: true,
                        minScale: 1.0,
                        maxScale: 5.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            placeholder: (context, url) => const SizedBox(
                              width: 56,
                              height: 56,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            ),
                            errorWidget: (context, url, error) => const Padding(
                              padding: EdgeInsets.all(18),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white70,
                                size: 42,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
