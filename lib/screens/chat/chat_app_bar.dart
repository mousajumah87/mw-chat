// lib/screens/chat/chat_app_bar.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../profile/profile_screen.dart';
import '../home/user_profile_screen.dart';
import '../../l10n/app_localizations.dart';

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

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  static const int _onlineTtlSeconds = 300;

  bool _isOnlineWithTtl({
    required bool rawIsOnline,
    required Timestamp? lastSeen,
  }) {
    if (!rawIsOnline || lastSeen == null) return false;
    final diffSeconds = DateTime.now().difference(lastSeen.toDate()).inSeconds;
    return diffSeconds <= _onlineTtlSeconds;
  }

  Widget _buildOtherAvatar({
    required String? profileUrl,
    required String? avatarType,
    required bool hideRealAvatar,
  }) {
    final String? effectiveProfileUrl =
    hideRealAvatar ? null : (profileUrl?.isNotEmpty == true ? profileUrl : null);
    final String effectiveAvatarType = hideRealAvatar ? 'bear' : (avatarType ?? 'bear');

    if (effectiveProfileUrl != null) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(effectiveProfileUrl),
      );
    }

    final emoji = effectiveAvatarType == 'smurf' ? '🧜‍♀️' : '🐻';
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.white10,
      child: Text(
        emoji,
        style: const TextStyle(fontSize: 18, color: Colors.white),
      ),
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

            final myBlockedListDynamic =
                (myData['blockedUserIds'] as List<dynamic>?) ?? const [];
            final myBlockedList = myBlockedListDynamic.map((e) => e.toString()).toList();
            final bool isBlockedByMe = myBlockedList.contains(otherUserId);

            final theirBlockedListDynamic = otherData['blockedUserIds'] as List<dynamic>?;
            final bool hasBlockedMe =
                theirBlockedListDynamic?.whereType<String>().contains(currentUserId) ?? false;

            final bool isBlockedRelationship = isBlockedByMe || hasBlockedMe;

            final firstName = otherData['firstName'] as String? ?? '';
            final lastName = otherData['lastName'] as String? ?? '';
            final email = otherData['email'] as String? ?? title;
            final displayName =
            (firstName.isNotEmpty ? '$firstName $lastName' : email).trim();

            final isActive = otherData['isActive'] != false;
            final rawIsOnline = (otherData['isOnline'] == true) && isActive;
            final lastSeen = otherData['lastSeen'] is Timestamp
                ? otherData['lastSeen'] as Timestamp
                : null;

            final effectiveOnline = isBlockedRelationship
                ? false
                : _isOnlineWithTtl(rawIsOnline: rawIsOnline, lastSeen: lastSeen);

            String subtitle;
            if (!isActive) {
              subtitle = l10n.notActivated;
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
            final dotColor = !isActive
                ? Colors.grey
                : (effectiveOnline ? Colors.greenAccent : Colors.grey);

            return InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: otherUserId!),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      _buildOtherAvatar(
                        profileUrl: profileUrl,
                        avatarType: avatarType,
                        hideRealAvatar: hasBlockedMe,
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

                  // ✅ Prevent iOS overflow; allows text to shrink safely.
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
  }

  Future<void> _showReportDialog(BuildContext context) async {
    if (otherUserId == null) return;

    final l10n = AppLocalizations.of(context)!;
    final reasonController = TextEditingController();

    final List<String> reasonCategories = <String>[
      l10n.reasonHarassment,
      l10n.reasonSpam,
      l10n.reasonHate,
      l10n.reasonSexual,
      l10n.reasonOther,
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? selectedCategory;

        return StatefulBuilder(
          builder: (context, setState) {
            final bool canSave = selectedCategory != null;

            return AlertDialog(
              title: Text(l10n.reportUserTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.reportUserReasonLabel,
                      border: const OutlineInputBorder(),
                    ),
                    items: reasonCategories
                        .map((r) => DropdownMenuItem<String>(
                      value: r,
                      child: Text(r),
                    ))
                        .toList(),
                    onChanged: (val) => setState(() => selectedCategory = val),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: l10n.reportUserHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: !canSave
                      ? null
                      : () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null || selectedCategory == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.generalErrorMessage)),
                        );
                      }
                    } else {
                      final details = reasonController.text.trim().isEmpty
                          ? null
                          : reasonController.text.trim();
                      try {
                        await FirebaseFirestore.instance.collection('userReports').add({
                          'reporterId': user.uid,
                          'reportedUserId': otherUserId,
                          'reasonCategory': selectedCategory,
                          'reasonDetails': details,
                          'createdAt': FieldValue.serverTimestamp(),
                          'status': 'open',
                        });
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.generalErrorMessage)),
                          );
                        }
                      }
                    }

                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.reportSubmitted)),
                      );
                    }
                  },
                  child: Text(
                    l10n.save,
                    style: TextStyle(
                      color: canSave
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.primary.withOpacity(0.4),
                    ),
                  ),
                ),
              ],
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
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final title = isCurrentlyBlocked ? l10n.unblockUserTitle : l10n.blockUserTitle;
    final description =
    isCurrentlyBlocked ? l10n.unblockUserDescription : l10n.blockUserDescription;
    final confirmLabel =
    isCurrentlyBlocked ? l10n.unblockUserConfirm : l10n.blockUserTitle;

    final shouldProceed = await showDialog<bool>(
      context: context,
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
            child: Text(
              confirmLabel,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldProceed) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(l10n.generalErrorMessage)));
      return;
    }

    showDialog(
      context: context,
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
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(isCurrentlyBlocked ? l10n.userUnblocked : l10n.userBlocked)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(l10n.generalErrorMessage)));
      }
    }
  }

  Future<void> _confirmRemoveFriend(BuildContext context) async {
    if (otherUserId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    final shouldProceed = await showDialog<bool>(
      context: context,
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
            child: Text(
              l10n.removeFriendConfirm,
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.friendRemoved)),
        );
      }
    } catch (_) {}
  }

  Future<void> _confirmCancelFriendRequest(BuildContext context) async {
    if (otherUserId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    final shouldProceed = await showDialog<bool>(
      context: context,
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.friendRequestCancelled)),
        );
      }
    } catch (_) {}
  }

  Future<void> _openMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final bool hasOther = otherUserId != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true, // ✅ allow taller + scroll (fix overflow)
      backgroundColor: Colors.transparent,
      useSafeArea: true, // ✅ iOS safe area
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
        final maxH = media.size.height * 0.78; // ✅ cap height (fix 52px overflow)

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
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUserId)
                        .snapshots(),
                    builder: (context, mySnap) {
                      final myData = mySnap.data?.data() ?? {};
                      final blockedListDynamic =
                          (myData['blockedUserIds'] as List<dynamic>?) ?? const [];
                      final blockedList = blockedListDynamic.map((e) => e.toString()).toList();
                      final bool isBlocked = hasOther && blockedList.contains(otherUserId);

                      final blockLabel =
                      isBlocked ? l10n.unblockUserTitle : l10n.blockUserTitle;

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: hasOther
                            ? FirebaseFirestore.instance
                            .collection('users')
                            .doc(currentUserId)
                            .collection('friends')
                            .doc(otherUserId)
                            .snapshots()
                            : const Stream.empty(),
                        builder: (context, friendSnap) {
                          final friendData = friendSnap.data?.data();
                          final friendStatus = friendData?['status'] as String?;
                          final bool isFriendAccepted = friendStatus == 'accepted';
                          final bool isOutgoingRequested = friendStatus == 'requested';

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
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    onClearChat?.call();
                                  },
                                ),
                              if (onClearChat != null) const SizedBox(height: 10),

                              if (hasOther)
                                buildItem(
                                  icon: Icons.info_outline_rounded,
                                  label: l10n.viewFriendProfile,
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            UserProfileScreen(userId: otherUserId!),
                                      ),
                                    );
                                  },
                                ),
                              if (hasOther) const SizedBox(height: 10),

                              if (hasOther)
                                buildItem(
                                  icon: Icons.flag_outlined,
                                  label: l10n.reportUserTitle,
                                  color: Colors.redAccent,
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    _showReportDialog(context);
                                  },
                                ),
                              if (hasOther) const SizedBox(height: 10),

                              if (hasOther)
                                buildItem(
                                  icon: Icons.block,
                                  label: blockLabel,
                                  color: Colors.redAccent,
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    _confirmToggleBlockUser(
                                      context,
                                      isCurrentlyBlocked: isBlocked,
                                    );
                                  },
                                ),

                              if (hasOther && isFriendAccepted) ...[
                                const SizedBox(height: 10),
                                buildItem(
                                  icon: Icons.person_remove_alt_1,
                                  label: l10n.removeFriendTitle,
                                  color: Colors.redAccent,
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    _confirmRemoveFriend(context);
                                  },
                                ),
                              ],

                              if (hasOther && !isFriendAccepted && isOutgoingRequested) ...[
                                const SizedBox(height: 10),
                                buildItem(
                                  icon: Icons.undo_rounded,
                                  label: l10n.cancelFriendRequestTitle,
                                  color: Colors.redAccent,
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    _confirmCancelFriendRequest(context);
                                  },
                                ),
                              ],

                              const SizedBox(height: 10),

                              buildItem(
                                icon: Icons.person_outline_rounded,
                                label: l10n.viewMyProfile,
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                                  );
                                },
                              ),

                              const SizedBox(height: 10),

                              buildItem(
                                icon: Icons.logout,
                                label: l10n.logout,
                                color: Colors.redAccent,
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  onLogout();
                                },
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

    // ✅ Compact icon buttons (fix iOS header overflow)
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

    // ✅ Keep centerTitle truly centered by balancing left and right widths
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
