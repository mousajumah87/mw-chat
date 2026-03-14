// lib/screens/chat/chat_app_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../utils/presence_helper.dart';
import '../profile/profile_screen.dart';
import '../home/user_profile_screen.dart';
import '../../l10n/app_localizations.dart';

// ✅ Reuse shared dialogs/helpers (no duplication)
import '../../widgets/safety/report_user_dialog.dart';
import '../../widgets/ui/mw_feedback.dart';

// ✅ Shared avatar widget
import '../../widgets/ui/mw_avatar.dart';

// ✅ Friendship helpers/status constants
import 'chat_friendship_service.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String currentUserId;
  final String? otherUserId;
  final VoidCallback onLogout;
  final VoidCallback? onClearChat;

  // ✅ WhatsApp-like selection mode (for message actions in header)
  final bool selectionMode;
  final int selectedCount;
  final VoidCallback? onClearSelection; // exit selection mode
  final VoidCallback? onCopySelected; // copy selected message text(s)
  final VoidCallback? onDeleteSelected; // delete selected message(s)
  final VoidCallback? onReportSelected; // report selected message (usually 1)

  // ✅ Calls (owned by ChatScreen)
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;

  const ChatAppBar({
    super.key,
    required this.title,
    required this.currentUserId,
    required this.otherUserId,
    required this.onLogout,
    this.onClearChat,
    this.selectionMode = false,
    this.selectedCount = 0,
    this.onClearSelection,
    this.onCopySelected,
    this.onDeleteSelected,
    this.onReportSelected,
    this.onAudioCall,
    this.onVideoCall,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  // -------- constants / schema helpers --------
  static const int _onlineTtlSeconds = 300;

  // Presence privacy values
  static const String _presenceEveryone = 'everyone';
  static const String _presenceFriends = 'friends';
  static const String _presenceNobody = 'nobody';


  // Profile visibility values
  static const String _profileEveryone = 'everyone';
  static const String _profileFriends = 'friends';
  static const String _profileNobody = 'nobody';

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  List<String> _asStringList(dynamic raw) {
    final list = (raw as List?) ?? const [];
    return list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
  }

  // ✅ Privacy-safe display name (matches your mw_friends_tab approach)
  String _displayNameFromData(AppLocalizations l10n, Map<String, dynamic> data) {
    String clean(String? v) => (v ?? '').trim();

    final first = clean(data['firstName'] as String?);
    final last = clean(data['lastName'] as String?);

    if (first.isNotEmpty && last.isNotEmpty) return '$first $last';
    if (first.isNotEmpty) return first;
    if (last.isNotEmpty) return last;

    final displayName = clean(data['displayName'] as String?);
    if (displayName.isNotEmpty) return displayName;

    final fullName = clean(data['fullName'] as String?);
    if (fullName.isNotEmpty) return fullName;

    final username = clean(data['username'] as String?);
    if (username.isNotEmpty) return username;

    return title.trim().isNotEmpty ? title.trim() : l10n.unknownUser;
  }

  // ✅ IMPORTANT: avoid any old “smurf” naming (IP risk). Use neutral "girl".
  String _avatarFromGender(dynamic rawGender) {
    final g = _norm(rawGender?.toString());
    if (g == 'female' || g == 'f' || g == 'woman' || g == 'girl') return 'girl';
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
    if (a.isNotEmpty) {
      if (a == 'smurf') return 'girl';
      return a;
    }
    return _avatarFromGender(gender);
  }

  String? _normalizeFriendStatus(dynamic raw) {
    final v = (raw ?? '').toString().trim().toLowerCase();
    if (v.isEmpty) return null;

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

  bool _isOnlineForDisplay({
    required bool canSeePresence,
    required bool rawIsOnline,
    required Timestamp? lastActive,
  }) {
    return MwPresenceHelper.isOnlineForDisplay(
      canSeePresence: canSeePresence,
      rawIsOnline: rawIsOnline,
      lastActive: lastActive,
      ttlSeconds: _onlineTtlSeconds,
    );
  }



  String _readPresenceVisibility(Map<String, dynamic> otherData) {
    // Legacy boolean wins: if user disabled online status → nobody
    final dynamic legacy = otherData['showOnlineStatus'];
    if (legacy is bool && legacy == false) return _presenceNobody;

    final raw = (otherData['presenceVisibility'] as String?)?.trim().toLowerCase();

    if (raw == _presenceNobody) return _presenceNobody;
    if (raw == _presenceEveryone) return _presenceEveryone;
    if (raw == _presenceFriends) return _presenceFriends;

    // default
    return _presenceFriends;
  }


  String _readProfileVisibility(Map<String, dynamic> otherData) {
    final raw = (otherData['profileVisibility'] as String?)?.trim().toLowerCase();
    if (raw == _profileNobody) return _profileNobody;
    if (raw == _profileFriends) return _profileFriends;
    if (raw == _profileEveryone) return _profileEveryone;
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

    if (presenceVisibility == _presenceEveryone) return true;

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

    return ChatFriendshipService.isFriends(friendStatus);
  }

  Future<void> _toastInfo(BuildContext context, String message) async {
    if (!context.mounted) return;
    await MwFeedback.show(
      context,
      message: message,
      type: MwFeedbackType.info,
    );
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
    final effectiveAvatarType = _resolveAvatarType(
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

  Widget _buildSelectionTitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = selectedCount < 0 ? 0 : selectedCount;

    final text = (count == 1)
        ? (l10n?.selectedOne ?? '1 selected')
        : '${count} selected';

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    );
  }

  // --- lightweight helpers to reduce rebuild churn inside nested builders ---
  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> _friendDocStream({
    required String me,
    required String other,
  }) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('friends')
          .doc(other)
          .snapshots();

  Map<String, dynamic> _safeMap(DocumentSnapshot<Map<String, dynamic>>? snap) => snap?.data() ?? const {};

  Widget _buildTitle(BuildContext context) {
    if (selectionMode) return _buildSelectionTitle(context);

    final l10n = AppLocalizations.of(context)!;
    final otherId = otherUserId;

    if (otherId == null || otherId.trim().isEmpty) {
      return Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream(otherId),
      builder: (context, otherSnap) {
        final otherData = _safeMap(otherSnap.data);

        if (otherData.isEmpty) {
          return Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userDocStream(currentUserId),
          builder: (context, mySnap) {
            final myData = _safeMap(mySnap.data);

            final myBlockedList = _asStringList(myData['blockedUserIds']);
            final isBlockedByMe = myBlockedList.contains(otherId);

            final theirBlockedList = _asStringList(otherData['blockedUserIds']);
            final hasBlockedMe = theirBlockedList.contains(currentUserId);

            final isBlockedRelationship = isBlockedByMe || hasBlockedMe;

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _friendDocStream(me: currentUserId, other: otherId),
              builder: (context, friendSnap) {
                final friendStatusRaw = friendSnap.data?.data()?['status'];
                final friendStatus = _normalizeFriendStatus(friendStatusRaw);

                final bool isActive = otherData['isActive'] != false;

                final presenceVisibility = _readPresenceVisibility(otherData);
                final canSeePresence = _canSeePresence(
                  isActive: isActive,
                  isBlockedRelationship: isBlockedRelationship,
                  presenceVisibility: presenceVisibility,
                  friendStatus: friendStatus,
                );

                final bool rawIsOnline = MwPresenceHelper.readRawOnline(
                  otherData,
                  isActive: isActive,
                );

                // ✅ Online TTL must use only lastActive.
                // Keep null-safe behavior inside _isOnlineForDisplay for rollout compatibility.
                final Timestamp? lastActive =
                otherData['lastActive'] is Timestamp ? otherData['lastActive'] as Timestamp : null;

                // ✅ lastSeen is the offline timestamp shown to the user.
                final Timestamp? lastSeen =
                otherData['lastSeen'] is Timestamp ? otherData['lastSeen'] as Timestamp : null;

                final bool effectiveOnline = _isOnlineForDisplay(
                  canSeePresence: canSeePresence,
                  rawIsOnline: rawIsOnline,
                  lastActive: lastActive,
                );


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

                final String displayName = _displayNameFromData(l10n, otherData);

                final profileUrl = otherData['profileUrl'] as String?;
                final avatarType = otherData['avatarType'] as String?;
                final gender = otherData['gender'];

                final hideRealAvatar = hasBlockedMe || !canViewProfile;

                final showDot = canSeePresence && isActive && !isBlockedRelationship;
                final dotColor = effectiveOnline ? Colors.greenAccent : Colors.grey;

                Future<void> openProfile() async {
                  if (!canViewProfile) {
                    await _toastInfo(context, l10n.profilePrivate ?? 'This profile is private.');
                    return;
                  }
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => UserProfileScreen(userId: otherId)),
                  );
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: canViewProfile ? () => openProfile() : null,
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
                          if (showDot)
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
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
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

  // ----------------------------
  // Menu actions (unchanged)
  // ----------------------------
  Future<void> _confirmToggleBlockUser(
      BuildContext context, {
        required bool isCurrentlyBlocked,
      }) async {
    final otherId = otherUserId;
    if (otherId == null) return;

    final l10n = AppLocalizations.of(context)!;

    final dialogTitle = isCurrentlyBlocked ? l10n.unblockUserTitle : l10n.blockUserTitle;
    final description = isCurrentlyBlocked ? l10n.unblockUserDescription : l10n.blockUserDescription;
    final confirmLabel = isCurrentlyBlocked ? l10n.unblockUserConfirm : l10n.blockUserTitle;

    final shouldProceed =
        (await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogTitle),
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
        )) ??
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
              ? FieldValue.arrayRemove([otherId])
              : FieldValue.arrayUnion([otherId]),
        },
        SetOptions(merge: true),
      );

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await MwFeedback.success(context, message: isCurrentlyBlocked ? l10n.userUnblocked : l10n.userBlocked);
    } catch (_) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await _toastError(context, l10n.generalErrorMessage);
    }
  }

  Future<void> _confirmRemoveFriend(BuildContext context) async {
    final otherId = otherUserId;
    if (otherId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    final shouldProceed =
        (await showDialog<bool>(
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
        )) ??
            false;

    if (!shouldProceed) return;

    final batch = FirebaseFirestore.instance.batch();

    final myRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('friends').doc(otherId);
    final theirRef = FirebaseFirestore.instance.collection('users').doc(otherId).collection('friends').doc(user.uid);

    batch.delete(myRef);
    batch.delete(theirRef);

    try {
      await batch.commit();
      await MwFeedback.success(context, message: l10n.friendRemoved);
    } catch (_) {
      await _toastError(context, l10n.generalErrorMessage);
    }
  }

  Future<void> _confirmCancelFriendRequest(BuildContext context) async {
    final otherId = otherUserId;
    if (otherId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    final shouldProceed =
        (await showDialog<bool>(
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
                child: Text(l10n.cancelFriendRequestConfirm, style: const TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        )) ??
            false;

    if (!shouldProceed) return;

    final batch = FirebaseFirestore.instance.batch();

    final myRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('friends').doc(otherId);
    final theirRef = FirebaseFirestore.instance.collection('users').doc(otherId).collection('friends').doc(user.uid);

    batch.delete(myRef);
    batch.delete(theirRef);

    try {
      await batch.commit();
      await MwFeedback.success(context, message: l10n.friendRequestCancelled);
    } catch (_) {
      await _toastError(context, l10n.generalErrorMessage);
    }
  }

  Future<void> _openMenu(BuildContext context) async {
    final parentContext = context;
    final l10n = AppLocalizations.of(parentContext)!;
    final hasOther = otherUserId != null && otherUserId!.trim().isNotEmpty;
    final otherId = otherUserId;

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
                    child: Text(label, style: TextStyle(color: effectiveColor, fontWeight: FontWeight.w700)),
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
                    stream: _userDocStream(currentUserId),
                    builder: (sheetBuildContext, mySnap) {
                      final myData = _safeMap(mySnap.data);
                      final blockedList = _asStringList(myData['blockedUserIds']);
                      final isBlocked = hasOther && otherId != null && blockedList.contains(otherId);

                      final blockLabel = isBlocked ? l10n.unblockUserTitle : l10n.blockUserTitle;

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: (hasOther && otherId != null)
                            ? _friendDocStream(me: currentUserId, other: otherId)
                            : Stream<DocumentSnapshot<Map<String, dynamic>>>.empty(),
                        builder: (sheetBuildContext2, friendSnap) {
                          final friendData = friendSnap.data?.data();
                          final friendStatus = _normalizeFriendStatus(friendData?['status']);
                          final isFriendAccepted = ChatFriendshipService.isFriends(friendStatus);
                          final isOutgoingRequested = ChatFriendshipService.isRequested(friendStatus);

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
                                      fontWeight: FontWeight.w900,
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

                              if (hasOther && otherId != null)
                                buildItem(
                                  icon: Icons.info_outline_rounded,
                                  label: l10n.viewFriendProfile,
                                  onTap: () => closeThen(() {
                                    Navigator.of(parentContext).push(
                                      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: otherId)),
                                    );
                                  }),
                                ),
                              if (hasOther) const SizedBox(height: 10),

                              if (hasOther && otherId != null)
                                buildItem(
                                  icon: Icons.flag_outlined,
                                  label: l10n.reportUserTitle,
                                  color: Colors.redAccent,
                                  onTap: () => closeThen(() {
                                    ReportUserDialog.open(parentContext, reportedUserId: otherId);
                                  }),
                                ),
                              if (hasOther) const SizedBox(height: 10),

                              if (hasOther && otherId != null)
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

  // ✅ Reuse your call logs tooltips if they exist (so you don’t add new keys)
  String _voiceCallTooltip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n?.callLogs_tooltip_voiceCall ?? 'Voice call';
  }

  String _videoCallTooltip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n?.callLogs_tooltip_videoCall ?? 'Video call';
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    Widget compactIconButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      final enabled = onPressed != null;
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: enabled ? Colors.white70 : Colors.white24),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        visualDensity: VisualDensity.compact,
      );
    }

    // ✅ Calls should NEVER show during selection mode (matches WhatsApp)
    final hasOther = (otherUserId ?? '').trim().isNotEmpty;
    final canShowCallButtons = !selectionMode && hasOther;

    Future<void> safeCall(VoidCallback cb) async {
      // small UX polish: consistent haptic + safe error toast
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
      try {
        cb();
      } catch (e) {
        final l10n = AppLocalizations.of(context);
        await _toastError(context, l10n?.generalErrorMessage ?? 'Something went wrong');
      }
    }

    final actions = <Widget>[];

    if (selectionMode) {
      final l10n = AppLocalizations.of(context);

      if (onCopySelected != null) {
        actions.add(
          compactIconButton(
            tooltip: l10n?.copy ?? 'Copy',
            icon: Icons.copy_rounded,
            onPressed: (selectedCount > 0) ? onCopySelected : null,
          ),
        );
      }

      if (onDeleteSelected != null) {
        actions.add(
          compactIconButton(
            tooltip: l10n?.delete ?? 'Delete',
            icon: Icons.delete_outline_rounded,
            onPressed: (selectedCount > 0) ? onDeleteSelected : null,
          ),
        );
      }

      if (onReportSelected != null) {
        final enabled = selectedCount == 1;
        actions.add(
          compactIconButton(
            tooltip: l10n?.report ?? 'Report',
            icon: Icons.flag_outlined,
            onPressed: enabled ? onReportSelected : null,
          ),
        );
      }

      actions.add(const SizedBox(width: 8));
    } else {
      if (canShowCallButtons) {
        // ✅ Voice
        actions.add(
          compactIconButton(
            tooltip: _voiceCallTooltip(context),
            icon: Icons.call_rounded,
            onPressed: (onAudioCall != null) ? () => safeCall(onAudioCall!) : null,
          ),
        );

        // ✅ Video
        actions.add(
          compactIconButton(
            tooltip: _videoCallTooltip(context),
            icon: Icons.videocam_rounded,
            onPressed: (onVideoCall != null) ? () => safeCall(onVideoCall!) : null,
          ),
        );

        actions.add(const SizedBox(width: 6));
      }
    }

    final sideWidth = canPop ? 88.0 : 48.0;
    final l10n = AppLocalizations.of(context);

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
                  tooltip: selectionMode
                      ? (l10n?.cancel ?? 'Cancel')
                      : MaterialLocalizations.of(context).backButtonTooltip,
                  icon: selectionMode ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded,
                  onPressed: () {
                    if (selectionMode) {
                      onClearSelection?.call();
                      return;
                    }
                    Navigator.of(context).maybePop();
                  },
                )
              else if (selectionMode)
                compactIconButton(
                  tooltip: l10n?.cancel ?? 'Cancel',
                  icon: Icons.close_rounded,
                  onPressed: onClearSelection,
                ),

              if (!selectionMode)
                compactIconButton(
                  tooltip: _menuTooltip(context),
                  icon: Icons.menu_rounded,
                  onPressed: () => _openMenu(context),
                ),
            ],
          ),
        ),
        actions: actions,
      ),
    );
  }
}
