// lib/screens/profile/presence_privacy_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_utils.dart';
import '../../widgets/ui/mw_background.dart';

class PresencePrivacyScreen extends StatefulWidget {
  const PresencePrivacyScreen({super.key});

  @override
  State<PresencePrivacyScreen> createState() => _PresencePrivacyScreenState();
}

class _PresencePrivacyScreenState extends State<PresencePrivacyScreen>
    with AutomaticKeepAliveClientMixin {
  static const Duration _staleWindow = Duration(minutes: 3);

  // Firestore string values (keep stable for rules/backend later)
  static const String _profileVisEveryone = 'everyone';
  static const String _profileVisFriends = 'friends';
  static const String _profileVisNobody = 'nobody';

  // ✅ NEW: email visibility values (reuse same stable strings)
  static const String _emailVisEveryone = 'everyone';
  static const String _emailVisFriends = 'friends';
  static const String _emailVisNobody = 'nobody';

  static const String _friendReqEveryone = 'everyone';
  static const String _friendReqNobody = 'nobody';

  // ✅ cache last good user document to prevent “text changing” on re-enter/reconnect
  Map<String, dynamic>? _cachedUserData;

  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic> _dataOrCache(
      AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
      ) {
    if (snap.hasData && snap.data != null && snap.data!.exists) {
      final d = snap.data!.data();
      if (d != null) {
        _cachedUserData = d;
        return d;
      }
    }
    return _cachedUserData ?? <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = AppLocalizations.of(context)!;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final theme = Theme.of(context);

    String staleLabel() {
      final m = _staleWindow.inMinutes;
      return l10n.presencePrivacyStaleMinutes(m);
    }

    Future<void> setField(String key, dynamic value) async {
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          key: value,
          // keep updating lastSeen as an “activity” hint
          'lastSeen': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    Future<void> showPickerSheet({
      required String title,
      required String subtitle,
      required String currentValue,
      required List<_PickerOption> options,
      required ValueChanged<String> onSelected,
    }) async {
      final chosen = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: false,
        builder: (ctx) {
          return SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.92),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                        tooltip:
                        MaterialLocalizations.of(ctx).closeButtonTooltip,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.start,
                  ),
                  const SizedBox(height: 12),
                  ...options.map((o) {
                    final isSelected = o.value == currentValue;
                    final disabled = o.disabled;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: disabled ? null : () => Navigator.of(ctx).pop(o.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: kSurfaceAltColor.withOpacity(
                                disabled ? 0.30 : 0.55),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? kPrimaryGold.withOpacity(0.55)
                                  : Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      o.title,
                                      style:
                                      theme.textTheme.titleSmall?.copyWith(
                                        color: disabled
                                            ? Colors.white38
                                            : Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      textAlign: TextAlign.start,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      o.subtitle,
                                      style:
                                      theme.textTheme.bodySmall?.copyWith(
                                        color: disabled
                                            ? Colors.white30
                                            : Colors.white60,
                                        height: 1.25,
                                      ),
                                      textAlign: TextAlign.start,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (disabled)
                                Icon(Icons.lock_outline_rounded,
                                    color: Colors.white24, size: 18)
                              else if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: kPrimaryGold, size: 20)
                              else
                                Icon(Icons.circle_outlined,
                                    color: Colors.white24, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );

      if (chosen != null && chosen != currentValue) {
        onSelected(chosen);
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.presencePrivacyTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const BackButtonIcon(),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
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
                        horizontal: isWide ? 32 : 16,
                        vertical: 8,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 36 : 18,
                        vertical: isWide ? 26 : 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: uid == null
                          ? Center(
                        child: Text(
                          l10n.presencePrivacyNotSignedIn,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .snapshots(),
                        builder: (context, snap) {
                          final data = _dataOrCache(snap);

                          final bool hasCache = _cachedUserData != null;
                          if (!hasCache &&
                              snap.connectionState ==
                                  ConnectionState.waiting) {
                            return const Center(
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                            );
                          }

                          final showOnlineStatus =
                              (data['showOnlineStatus'] as bool?) ?? true;

                          final profileVisibility =
                              (data['profileVisibility'] as String?) ??
                                  _profileVisEveryone;

                          // ✅ NEW: Email visibility (default = friends)
                          final emailVisibility =
                              (data['emailVisibility'] as String?) ??
                                  _emailVisFriends;

                          final friendRequests =
                              (data['friendRequests'] as String?) ??
                                  _friendReqEveryone;

                          final isOnline = data['isOnline'] == true;

                          final Timestamp? lastSeenTs =
                          data['lastSeen'] is Timestamp
                              ? data['lastSeen'] as Timestamp
                              : null;

                          final DateTime? lastSeenDt = lastSeenTs?.toDate();
                          final now = DateTime.now();
                          final bool isStale = lastSeenDt == null
                              ? true
                              : now.difference(lastSeenDt) > _staleWindow;

                          final bool effectiveOnline =
                              showOnlineStatus && isOnline && !isStale;

                          String statusLine;
                          if (!showOnlineStatus) {
                            statusLine =
                                l10n.presencePrivacyStatusHiddenOffline;
                          } else if (effectiveOnline) {
                            statusLine =
                                l10n.presencePrivacyStatusVisibleOnline;
                          } else {
                            statusLine = l10n
                                .presencePrivacyStatusVisibleOfflineWhenInactive;
                          }

                          final lastSeenFull =
                          formatTimestampFull(lastSeenTs);

                          final lastSeenLine = lastSeenFull.isEmpty
                              ? l10n.presencePrivacyLastSeenUnavailable
                              : l10n.presencePrivacyLastSeenLine(
                              lastSeenFull);

                          Future<void> setShowOnline(bool v) async {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .set(
                              {
                                'showOnlineStatus': v,
                                if (!v) 'isOnline': false,
                                'lastSeen': FieldValue.serverTimestamp(),
                              },
                              SetOptions(merge: true),
                            );
                          }

                          String profileVisibilityValueLabel(String v) {
                            switch (v) {
                              case _profileVisFriends:
                                return l10n
                                    .presencePrivacyProfileVisValueFriends;
                              case _profileVisNobody:
                                return l10n
                                    .presencePrivacyProfileVisValueNobody;
                              case _profileVisEveryone:
                              default:
                                return l10n
                                    .presencePrivacyProfileVisValueEveryone;
                            }
                          }

                          // ✅ NEW: Email visibility labels (reuse existing strings, or add new l10n later)
                          String emailVisibilityValueLabel(String v) {
                            switch (v) {
                              case _emailVisEveryone:
                                return l10n
                                    .presencePrivacyProfileVisValueEveryone;
                              case _emailVisNobody:
                                return l10n
                                    .presencePrivacyProfileVisValueNobody;
                              case _emailVisFriends:
                              default:
                                return l10n
                                    .presencePrivacyProfileVisValueFriends;
                            }
                          }

                          String friendRequestsValueLabel(String v) {
                            switch (v) {
                              case _friendReqNobody:
                                return l10n
                                    .presencePrivacyFriendReqValueNobody;
                              case _friendReqEveryone:
                              default:
                                return l10n
                                    .presencePrivacyFriendReqValueEveryone;
                            }
                          }

                          Widget sectionTitle(String title, String subtitle) {
                            return Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  subtitle,
                                  style:
                                  theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white70,
                                    height: 1.35,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                              ],
                            );
                          }

                          Widget flatTile({
                            required IconData icon,
                            required String title,
                            required String subtitle,
                            Widget? trailing,
                            VoidCallback? onTap,
                          }) {
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: onTap,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kSurfaceAltColor.withOpacity(0.55),
                                    borderRadius:
                                    BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color:
                                          Colors.black.withOpacity(0.25),
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white
                                                .withOpacity(0.10),
                                          ),
                                        ),
                                        child: Icon(
                                          icon,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              title,
                                              style: theme
                                                  .textTheme.titleSmall
                                                  ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              textAlign: TextAlign.start,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              subtitle,
                                              style: theme
                                                  .textTheme.bodySmall
                                                  ?.copyWith(
                                                color: Colors.white60,
                                                height: 1.25,
                                              ),
                                              textAlign: TextAlign.start,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (trailing != null) ...[
                                        const SizedBox(width: 10),
                                        trailing,
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          Widget valueChip(String text) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.10),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    text,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      color: Colors.white.withOpacity(0.92),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ],
                              ),
                            );
                          }

                          Widget statusPill() {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.20),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: effectiveOnline
                                          ? kPrimaryGold
                                          : kTextSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      statusLine,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        color:
                                        Colors.white.withOpacity(0.92),
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                      textAlign: TextAlign.start,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          Widget autoOfflineCard() {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: kSurfaceColor.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    l10n.presencePrivacyAutoOfflineTitle,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    textAlign: TextAlign.start,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.presencePrivacyAutoOfflineBody(
                                        staleLabel()),
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                      color: Colors.white60,
                                      height: 1.35,
                                    ),
                                    textAlign: TextAlign.start,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.history_rounded,
                                        size: 18,
                                        color: Colors.white70
                                            .withOpacity(0.85),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          lastSeenLine,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: Colors.white70,
                                          ),
                                          textAlign: TextAlign.start,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }

                          return SingleChildScrollView(
                            key: const PageStorageKey<String>(
                                'presence_privacy_scroll'),
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                              children: [
                                sectionTitle(
                                  l10n.presencePrivacySectionOnlineTitle,
                                  l10n.presencePrivacySectionSubtitle,
                                ),
                                const SizedBox(height: 14),
                                flatTile(
                                  icon: Icons.shield_outlined,
                                  title: l10n
                                      .presencePrivacyShowWhenOnlineTitle,
                                  subtitle: showOnlineStatus
                                      ? l10n
                                      .presencePrivacyShowWhenOnlineSubtitleOn
                                      : l10n
                                      .presencePrivacyShowWhenOnlineSubtitleOff,
                                  trailing: Switch.adaptive(
                                    value: showOnlineStatus,
                                    activeColor: kPrimaryGold,
                                    onChanged: (v) => setShowOnline(v),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                statusPill(),
                                const SizedBox(height: 14),
                                autoOfflineCard(),
                                const SizedBox(height: 26),

                                sectionTitle(
                                  l10n.presencePrivacySectionProfileTitle,
                                  l10n
                                      .presencePrivacySectionProfileSubtitle,
                                ),
                                const SizedBox(height: 14),

                                flatTile(
                                  icon: Icons.visibility_outlined,
                                  title: l10n.presencePrivacyProfileVisTitle,
                                  subtitle:
                                  l10n.presencePrivacyProfileVisSubtitle,
                                  trailing: valueChip(
                                    profileVisibilityValueLabel(
                                        profileVisibility),
                                  ),
                                  onTap: () {
                                    showPickerSheet(
                                      title:
                                      l10n.presencePrivacyProfileVisTitle,
                                      subtitle: l10n
                                          .presencePrivacyProfileVisSheetHint,
                                      currentValue: profileVisibility,
                                      options: [
                                        _PickerOption(
                                          value: _profileVisEveryone,
                                          title: l10n
                                              .presencePrivacyProfileVisEveryoneTitle,
                                          subtitle: l10n
                                              .presencePrivacyProfileVisEveryoneSubtitle,
                                        ),
                                        _PickerOption(
                                          value: _profileVisFriends,
                                          title: l10n
                                              .presencePrivacyProfileVisFriendsTitle,
                                          subtitle: l10n
                                              .presencePrivacyProfileVisFriendsSubtitle,
                                        ),
                                        _PickerOption(
                                          value: _profileVisNobody,
                                          title: l10n
                                              .presencePrivacyProfileVisNobodyTitle,
                                          subtitle: l10n
                                              .presencePrivacyProfileVisNobodySubtitle,
                                        ),
                                      ],
                                      onSelected: (v) =>
                                          setField('profileVisibility', v),
                                    );
                                  },
                                ),

                                const SizedBox(height: 12),

                                // ✅ NEW: Email visibility
                                flatTile(
                                  icon: Icons.email_outlined,
                                  title: 'Email visibility',
                                  subtitle:
                                  'Choose who can see your email on your profile.',
                                  trailing: valueChip(
                                    emailVisibilityValueLabel(emailVisibility),
                                  ),
                                  onTap: () {
                                    showPickerSheet(
                                      title: 'Email visibility',
                                      subtitle:
                                      'This only affects what other users can see. You will always see your own email.',
                                      currentValue: emailVisibility,
                                      options: const [
                                        _PickerOption(
                                          value: _emailVisEveryone,
                                          title: 'Everyone',
                                          subtitle:
                                          'Anyone can see your email on your profile.',
                                        ),
                                        _PickerOption(
                                          value: _emailVisFriends,
                                          title: 'Friends',
                                          subtitle:
                                          'Only your friends can see your email.',
                                        ),
                                        _PickerOption(
                                          value: _emailVisNobody,
                                          title: 'Nobody',
                                          subtitle:
                                          'Hide your email from everyone.',
                                        ),
                                      ],
                                      onSelected: (v) =>
                                          setField('emailVisibility', v),
                                    );
                                  },
                                ),

                                const SizedBox(height: 12),

                                flatTile(
                                  icon: Icons.person_add_alt_1_outlined,
                                  title: l10n.presencePrivacyFriendReqTitle,
                                  subtitle:
                                  l10n.presencePrivacyFriendReqSubtitle,
                                  trailing: valueChip(
                                    friendRequestsValueLabel(friendRequests),
                                  ),
                                  onTap: () {
                                    showPickerSheet(
                                      title:
                                      l10n.presencePrivacyFriendReqTitle,
                                      subtitle: l10n
                                          .presencePrivacyFriendReqSheetHint,
                                      currentValue: friendRequests,
                                      options: [
                                        _PickerOption(
                                          value: _friendReqEveryone,
                                          title: l10n
                                              .presencePrivacyFriendReqEveryoneTitle,
                                          subtitle: l10n
                                              .presencePrivacyFriendReqEveryoneSubtitle,
                                        ),
                                        _PickerOption(
                                          value: _friendReqNobody,
                                          title: l10n
                                              .presencePrivacyFriendReqNobodyTitle,
                                          subtitle: l10n
                                              .presencePrivacyFriendReqNobodySubtitle,
                                        ),
                                      ],
                                      onSelected: (v) =>
                                          setField('friendRequests', v),
                                    );
                                  },
                                ),

                                const SizedBox(height: 18),
                                Text(
                                  l10n.presencePrivacyTip,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white54,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerOption {
  final String value;
  final String title;
  final String subtitle;
  final bool disabled;

  const _PickerOption({
    required this.value,
    required this.title,
    required this.subtitle,
    this.disabled = false,
  });
}
