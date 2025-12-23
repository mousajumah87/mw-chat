//lib/screens/chat/chat_app_bar.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../profile/profile_screen.dart';
import '../home/user_profile_screen.dart';
import '../../l10n/app_localizations.dart';

// ✅ Reuse shared dialogs/helpers (no duplication)
import '../../widgets/safety/report_user_dialog.dart';
import '../../widgets/ui/mw_feedback.dart';

// ✅ NEW shared avatar widget
import '../../widgets/ui/mw_avatar.dart';

// ✅ Friendship helpers/status constants
import 'chat_friendship_service.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String currentUserId;
  final String? otherUserId;
  final VoidCallback onLogout;
  final VoidCallback? onClearChat;

  const ChatAppBar({
    super.key,
    required this.title,
    required this.currentUserId,
    required this.otherUserId,
    required this.onLogout,
    this.onClearChat,
  });

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  String _avatarFromGender(dynamic rawGender) {
    final g = _norm(rawGender?.toString());
    // accept common variants to be backward compatible
    if (g == 'female' || g == 'f' || g == 'woman' || g == 'girl') return 'smurf';
    if (g == 'male' || g == 'm' || g == 'man' || g == 'boy') return 'bear';
    return 'bear';
  }

  String _resolveAvatarType({
    required String? avatarType,
    required dynamic gender,
    required bool hideRealAvatar,
  }) {
    if (hideRealAvatar) return 'bear';

    final a = _norm(avatarType);
    if (a.isNotEmpty) return a; // "bear" or "smurf" (or future types)
    return _avatarFromGender(gender);
  }


  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  static const int _onlineTtlSeconds = 300;

  // ✅ Presence privacy values
  static const String _presenceFriends = 'friends';
  static const String _presenceNobody = 'nobody';

  // ✅ Profile visibility values (align with privacy changes)
  static const String _profileEveryone = 'everyone';
  static const String _profileFriends = 'friends';
  static const String _profileNobody = 'nobody';

  // ---- tiny helpers (safe for old users / mixed schema) ----

  List<String> _asStringList(dynamic raw) {
    final list = (raw as List?) ?? const [];
    return list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
  }

  String? _normalizeFriendStatus(dynamic raw) {
    final v = (raw ?? '').toString().trim().toLowerCase();
    if (v.isEmpty) return null;

    // legacy alias supported
    if (v == ChatFriendshipService.statusRequestReceivedAlias) {
      return ChatFriendshipService.exposeIncomingAsRequestReceived
          ? ChatFriendshipService.statusRequestReceivedAlias
          : ChatFriendshipService.statusIncoming;
    }

    if (v == ChatFriendshipService.statusRequested) return ChatFriendshipService.statusRequested;

    if (v == ChatFriendshipService.statusIncoming) {
      return ChatFriendshipService.exposeIncomingAsRequestReceived
          ? ChatFriendshipService.statusRequestReceivedAlias
          : ChatFriendshipService.statusIncoming;
    }

    if (v == ChatFriendshipService.statusAccepted) return ChatFriendshipService.statusAccepted;

    return null;
  }

  void _toastInfo(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  bool _isOnlineWithTtl({
    required bool rawIsOnline,
    required Timestamp? lastSeen,
  }) {
    if (!rawIsOnline || lastSeen == null) return false;
    final diffSeconds = DateTime.now().difference(lastSeen.toDate()).inSeconds;
    return diffSeconds <= _onlineTtlSeconds;
  }

  String _readPresenceVisibility(Map<String, dynamic> otherData) {
    final raw = (otherData['presenceVisibility'] as String?)?.trim().toLowerCase();
    if (raw == _presenceNobody) return _presenceNobody;
    // privacy-first default
    return _presenceFriends;
  }

  String _readProfileVisibility(Map<String, dynamic> otherData) {
    final raw = (otherData['profileVisibility'] as String?)?.trim().toLowerCase();
    if (raw == _profileNobody) return _profileNobody;
    if (raw == _profileFriends) return _profileFriends;
    if (raw == _profileEveryone) return _profileEveryone;

    // ✅ backward compat default: allow (do not break old users)
    return _profileEveryone;
  }

  bool _canSeePresence({
    required bool isActive,
    required bool isBlockedRelationship,
    required String presenceVisibility,
    required String? friendStatus,
  }) {
    if (!isActive) return false;
    if (isBlockedRelationship) return false;
    if (presenceVisibility == _presenceNobody) return false;
    // friends-only
    return ChatFriendshipService.isFriends(friendStatus);
  }

  bool _canViewProfile({
    required bool isActive,
    required bool isBlockedRelationship,
    required String profileVisibility,
    required String? friendStatus,
  }) {
    if (!isActive) return false;
    if (isBlockedRelationship) return false;

    if (profileVisibility == _profileNobody) return false;
    if (profileVisibility == _profileEveryone) return true;

    // friends-only
    return ChatFriendshipService.isFriends(friendStatus);
  }

  Future<void> _toastSuccess(BuildContext context, String message) async {
    if (!context.mounted) return;
    await MwFeedback.success(context, message: message);
  }

  Future<void> _toastError(BuildContext context, String message) async {
    if (!context.mounted) return;
    await MwFeedback.error(context, message: message);
  }

  Widget _buildOtherAvatar({
    required String? profileUrl,
    required String? avatarType,
    required dynamic gender,
    required bool hideRealAvatar,
  }) {
    final String effectiveAvatarType = _resolveAvatarType(
      avatarType: avatarType,
      gender: gender,
      hideRealAvatar: hideRealAvatar,
    );

    return MwAvatar(
      radius: 18,
      avatarType: effectiveAvatarType,
      profileUrl: profileUrl,
      hideRealAvatar: hideRealAvatar,
      backgroundColor: Colors.white10,
    );
  }


  Widget _buildTitle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (otherUserId == null) {
      return Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(otherUserId).snapshots(),
      builder: (context, snapshot) {
        final otherData = snapshot.data?.data();
        if (otherData == null) {
          return Text(title, style: const TextStyle(color: Colors.white));
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
          builder: (context, mySnap) {
            final myData = mySnap.data?.data() ?? {};

            final myBlockedList = _asStringList(myData['blockedUserIds']);
            final bool isBlockedByMe = myBlockedList.contains(otherUserId);

            final theirBlockedList = _asStringList(otherData['blockedUserIds']);
            final bool hasBlockedMe = theirBlockedList.contains(currentUserId);

            final bool isBlockedRelationship = isBlockedByMe || hasBlockedMe;

            // ✅ Get friendship status (my side is enough)
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUserId)
                  .collection('friends')
                  .doc(otherUserId)
                  .snapshots(),
              builder: (context, friendSnap) {
                final friendStatusRaw = friendSnap.data?.data()?['status'];
                final friendStatus = _normalizeFriendStatus(friendStatusRaw);

                final firstName = otherData['firstName'] as String? ?? '';
                final lastName = otherData['lastName'] as String? ?? '';
                final email = otherData['email'] as String? ?? title;
                final displayName = (firstName.isNotEmpty ? '$firstName $lastName' : email).trim();

                final isActive = otherData['isActive'] != false;

                // ✅ Presence privacy
                final presenceVisibility = _readPresenceVisibility(otherData);
                final canSeePresence = _canSeePresence(
                  isActive: isActive,
                  isBlockedRelationship: isBlockedRelationship,
                  presenceVisibility: presenceVisibility,
                  friendStatus: friendStatus,
                );

                final rawIsOnline = (otherData['isOnline'] == true) && isActive;
                final lastSeen =
                otherData['lastSeen'] is Timestamp ? otherData['lastSeen'] as Timestamp : null;

                final effectiveOnline = canSeePresence
                    ? _isOnlineWithTtl(rawIsOnline: rawIsOnline, lastSeen: lastSeen)
                    : false;

                // ✅ Profile privacy (controls tap + avatar hiding)
                final profileVisibility = _readProfileVisibility(otherData);
                final canViewProfile = _canViewProfile(
                  isActive: isActive,
                  isBlockedRelationship: isBlockedRelationship,
                  profileVisibility: profileVisibility,
                  friendStatus: friendStatus,
                );

                String subtitle;
                if (!isActive) {
                  subtitle = l10n.notActivated;
                } else if (!canSeePresence) {
                  subtitle = l10n.offline;
                } else if (effectiveOnline) {
                  subtitle = l10n.online;
                } else if (lastSeen != null) {
                  final diff = DateTime.now().difference(lastSeen.toDate());
                  if (diff.inMinutes < 1) {
                    subtitle = l10n.lastSeenJustNow;
                  } else if (diff.inMinutes < 60) {
                    subtitle = l10n.lastSeenMinutes(diff.inMinutes);
                  } else if (diff.inHours < 24) {
                    subtitle = l10n.lastSeenHours(diff.inHours);
                  } else {
                    subtitle = l10n.lastSeenDays(diff.inDays);
                  }
                } else {
                  subtitle = l10n.offline;
                }

                final profileUrl = otherData['profileUrl'] as String?;
                final avatarType = otherData['avatarType'] as String?;
                final gender = otherData['gender']; // could be "male"/"female" or anything


                // Hide avatar if they blocked me OR profile is not viewable
                final hideRealAvatar = hasBlockedMe || !canViewProfile;

                final dotColor =
                !isActive ? Colors.grey : (effectiveOnline ? Colors.greenAccent : Colors.grey);

                void openProfile() {
                  if (!canViewProfile) {
                    _toastInfo(
                      context,
                      l10n.profilePrivate ?? 'This profile is private.',
                    );
                    return;
                  }

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(userId: otherUserId!),
                    ),
                  );
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: canViewProfile ? openProfile : null, // ✅ not clickable when private
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          _buildOtherAvatar(
                            profileUrl: profileUrl,
                            avatarType: avatarType,
                            gender: gender,
                            hideRealAvatar: hideRealAvatar,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black, width: 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15.5,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _confirmToggleBlockUser(
      BuildContext context, {
        required bool isCurrentlyBlocked,
      }) async {
    if (otherUserId == null) return;

    final l10n = AppLocalizations.of(context)!;

    final title = isCurrentlyBlocked ? l10n.unblockUserTitle : l10n.blockUserTitle;
    final description =
    isCurrentlyBlocked ? l10n.unblockUserDescription : l10n.blockUserDescription;
    final confirmLabel = isCurrentlyBlocked ? l10n.unblockUserConfirm : l10n.blockUserTitle;

    final shouldProceed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldProceed) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _toastError(context, l10n.generalErrorMessage);
      return;
    }

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'blockedUserIds': isCurrentlyBlocked
              ? FieldValue.arrayRemove([otherUserId])
              : FieldValue.arrayUnion([otherUserId]),
        },
        SetOptions(merge: true),
      );

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await _toastSuccess(context, isCurrentlyBlocked ? l10n.userUnblocked : l10n.userBlocked);
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await _toastError(context, l10n.generalErrorMessage);
    }
  }

  Future<void> _confirmRemoveFriend(BuildContext context) async {
    if (otherUserId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    final shouldProceed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeFriendTitle),
        content: Text(l10n.removeFriendDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.removeFriendConfirm, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldProceed) return;

    final batch = FirebaseFirestore.instance.batch();

    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('friends')
        .doc(otherUserId);

    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(otherUserId!)
        .collection('friends')
        .doc(user.uid);

    batch.delete(myRef);
    batch.delete(theirRef);

    try {
      await batch.commit();
      await _toastSuccess(context, l10n.friendRemoved);
    } catch (_) {
      await _toastError(context, l10n.generalErrorMessage);
    }
  }

  Future<void> _confirmCancelFriendRequest(BuildContext context) async {
    if (otherUserId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    final shouldProceed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.cancelFriendRequestTitle),
        content: Text(l10n.cancelFriendRequestDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              l10n.cancelFriendRequestConfirm,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldProceed) return;

    final batch = FirebaseFirestore.instance.batch();

    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('friends')
        .doc(otherUserId);

    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(otherUserId!)
        .collection('friends')
        .doc(user.uid);

    batch.delete(myRef);
    batch.delete(theirRef);

    try {
      await batch.commit();
      await _toastSuccess(context, l10n.friendRequestCancelled);
    } catch (_) {
      await _toastError(context, l10n.generalErrorMessage);
    }
  }

  Future<void> _openMenu(BuildContext context) async {
    final BuildContext parentContext = context;

    final l10n = AppLocalizations.of(parentContext)!;
    final bool hasOther = otherUserId != null;

    await showModalBottomSheet<void>(
      context: parentContext,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        Widget buildItem({
          required IconData icon,
          required String label,
          Color? color,
          required VoidCallback? onTap,
        }) {
          final effectiveColor = color ?? Colors.white;
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: effectiveColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: effectiveColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
            ),
          );
        }

        final media = MediaQuery.of(sheetContext);
        final maxH = media.size.height * 0.78;

        void closeThen(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          Future.microtask(() {
            if (!parentContext.mounted) return;
            action();
          });
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF151515).withOpacity(0.96),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
                    builder: (sheetBuildContext, mySnap) {
                      final myData = mySnap.data?.data() ?? {};
                      final blockedList = _asStringList(myData['blockedUserIds']);
                      final bool isBlocked = hasOther && blockedList.contains(otherUserId);

                      final blockLabel = isBlocked ? l10n.unblockUserTitle : l10n.blockUserTitle;

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: hasOther
                            ? FirebaseFirestore.instance
                            .collection('users')
                            .doc(currentUserId)
                            .collection('friends')
                            .doc(otherUserId)
                            .snapshots()
                            : const Stream.empty(),
                        builder: (sheetBuildContext2, friendSnap) {
                          final friendData = friendSnap.data?.data();
                          final friendStatus = _normalizeFriendStatus(friendData?['status']);
                          final bool isFriendAccepted = ChatFriendshipService.isFriends(friendStatus);
                          final bool isOutgoingRequested = ChatFriendshipService.isRequested(friendStatus);

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.menu_rounded, color: Colors.white70),
                                  const SizedBox(width: 10),
                                  Text(
                                    l10n.menuTitle,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              if (onClearChat != null)
                                buildItem(
                                  icon: Icons.delete_outline,
                                  label: l10n.deleteChatTitle,
                                  color: Colors.redAccent,
                                  onTap: () => closeThen(() => onClearChat?.call()),
                                ),
                              if (onClearChat != null) const SizedBox(height: 10),

                              if (hasOther)
                                buildItem(
                                  icon: Icons.info_outline_rounded,
                                  label: l10n.viewFriendProfile,
                                  onTap: () => closeThen(() {
                                    Navigator.of(parentContext).push(
                                      MaterialPageRoute(
                                        builder: (_) => UserProfileScreen(userId: otherUserId!),
                                      ),
                                    );
                                  }),
                                ),
                              if (hasOther) const SizedBox(height: 10),

                              if (hasOther)
                                buildItem(
                                  icon: Icons.flag_outlined,
                                  label: l10n.reportUserTitle,
                                  color: Colors.redAccent,
                                  onTap: () => closeThen(() {
                                    ReportUserDialog.open(
                                      parentContext,
                                      reportedUserId: otherUserId!,
                                    );
                                  }),
                                ),
                              if (hasOther) const SizedBox(height: 10),

                              if (hasOther)
                                buildItem(
                                  icon: Icons.block,
                                  label: blockLabel,
                                  color: Colors.redAccent,
                                  onTap: () => closeThen(() {
                                    _confirmToggleBlockUser(
                                      parentContext,
                                      isCurrentlyBlocked: isBlocked,
                                    );
                                  }),
                                ),

                              if (hasOther && isFriendAccepted) ...[
                                const SizedBox(height: 10),
                                buildItem(
                                  icon: Icons.person_remove_alt_1,
                                  label: l10n.removeFriendTitle,
                                  color: Colors.redAccent,
                                  onTap: () => closeThen(() => _confirmRemoveFriend(parentContext)),
                                ),
                              ],

                              if (hasOther && !isFriendAccepted && isOutgoingRequested) ...[
                                const SizedBox(height: 10),
                                buildItem(
                                  icon: Icons.undo_rounded,
                                  label: l10n.cancelFriendRequestTitle,
                                  color: Colors.redAccent,
                                  onTap: () => closeThen(() => _confirmCancelFriendRequest(parentContext)),
                                ),
                              ],

                              const SizedBox(height: 10),

                              buildItem(
                                icon: Icons.person_outline_rounded,
                                label: l10n.viewMyProfile,
                                onTap: () => closeThen(() {
                                  Navigator.of(parentContext).push(
                                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                                  );
                                }),
                              ),

                              const SizedBox(height: 10),

                              buildItem(
                                icon: Icons.logout,
                                label: l10n.logout,
                                color: Colors.redAccent,
                                onTap: () => closeThen(onLogout),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _menuTooltip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n?.menuTitle ?? 'Menu';
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();

    Widget compactIconButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback onPressed,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white70),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        visualDensity: VisualDensity.compact,
      );
    }

    final double sideWidth = canPop ? 88 : 48;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF101010), Color(0xFF1B1B1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: true,
        title: _buildTitle(context),
        leadingWidth: sideWidth,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canPop)
                compactIconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: Icons.arrow_back_ios_new_rounded,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              compactIconButton(
                tooltip: _menuTooltip(context),
                icon: Icons.menu_rounded,
                onPressed: () => _openMenu(context),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(width: sideWidth),
        ],
      ),
    );
  }
}
