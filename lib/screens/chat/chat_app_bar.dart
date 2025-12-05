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
    final String effectiveAvatarType =
    hideRealAvatar ? 'bear' : (avatarType ?? 'bear');

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

    // First listen to the *other* user's document
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUserId)
          .snapshots(),
      builder: (context, snapshot) {
        final otherData = snapshot.data?.data();
        if (otherData == null) {
          return Text(
            title,
            style: const TextStyle(color: Colors.white),
          );
        }

        // Then also listen to *my* user document so we know if I blocked them
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .snapshots(),
          builder: (context, mySnap) {
            final myData = mySnap.data?.data() ?? {};

            final myBlockedListDynamic =
                (myData['blockedUserIds'] as List<dynamic>?) ?? const [];
            final myBlockedList =
            myBlockedListDynamic.map((e) => e.toString()).toList();
            final bool isBlockedByMe = myBlockedList.contains(otherUserId);

            final theirBlockedListDynamic =
            otherData['blockedUserIds'] as List<dynamic>?;
            final bool hasBlockedMe = theirBlockedListDynamic
                ?.whereType<String>()
                .contains(currentUserId) ??
                false;

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

            // If there is a block relationship, never show as online
            final effectiveOnline = isBlockedRelationship
                ? false
                : _isOnlineWithTtl(
              rawIsOnline: rawIsOnline,
              lastSeen: lastSeen,
            );

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

            // Use Flexible around the text part to avoid horizontal overflow
            return InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: otherUserId!),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Stack(
                    children: [
                      _buildOtherAvatar(
                        profileUrl: profileUrl,
                        avatarType: avatarType,
                        // If they blocked me, hide their real avatar
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

  Widget _buildMyAvatarAction(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final profileUrl = data?['profileUrl'] as String?;
        final avatarType = data?['avatarType'] as String?;

        Widget avatar;
        if (profileUrl != null && profileUrl.isNotEmpty) {
          avatar = CircleAvatar(
            radius: 14,
            backgroundImage: NetworkImage(profileUrl),
          );
        } else {
          final emoji = avatarType == 'smurf' ? '🧜‍♀️' : '🐻';
          avatar = CircleAvatar(
            radius: 14,
            backgroundColor: Colors.white10,
            child: Text(
              emoji,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: avatar,
          ),
        );
      },
    );
  }

  /// Dialog to report the *user* (not a specific message)
  ///
  /// Requires a category (dropdown) and treats the free-text details
  /// as optional. "Save" is disabled until a category is selected.
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
                        .map(
                          (r) => DropdownMenuItem<String>(
                        value: r,
                        child: Text(r),
                      ),
                    )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedCategory = val;
                      });
                    },
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
                    if (user != null && selectedCategory != null) {
                      final details = reasonController.text.trim();
                      try {
                        await FirebaseFirestore.instance
                            .collection('userReports')
                            .add({
                          'reporterId': user.uid,
                          'reportedUserId': otherUserId,
                          'reasonCategory': selectedCategory,
                          'reasonDetails':
                          details.isEmpty ? null : details,
                          'createdAt': FieldValue.serverTimestamp(),
                          'status': 'open',
                        });
                      } catch (e, st) {
                        debugPrint(
                            '[ChatAppBar] _showReportDialog error: $e\n$st');
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
                          : Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.4),
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

  /// Confirm + persist a block / unblock operation.
  /// This only updates `blockedUserIds` on the current user; `ChatScreen`
  /// listens to that doc and updates its own `_isBlocked` state.
  Future<void> _confirmToggleBlockUser(
      BuildContext context, {
        required bool isCurrentlyBlocked,
      }) async {
    if (otherUserId == null) return;

    final l10n = AppLocalizations.of(context)!;

    final title =
    isCurrentlyBlocked ? l10n.unblockUserTitle : l10n.blockUserTitle;
    final description = isCurrentlyBlocked
        ? l10n.unblockUserDescription
        : l10n.blockUserDescription;
    final confirmLabel =
    isCurrentlyBlocked ? l10n.unblockUserConfirm : l10n.blockUserTitle;

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
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
        );
      },
    ) ??
        false;

    if (!shouldProceed) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(
        {
          'blockedUserIds': isCurrentlyBlocked
              ? FieldValue.arrayRemove([otherUserId])
              : FieldValue.arrayUnion([otherUserId]),
        },
        SetOptions(merge: true),
      );

      if (context.mounted) {
        final snackText =
        isCurrentlyBlocked ? l10n.userUnblocked : l10n.userBlocked;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(snackText)),
        );
      }
    } catch (e, st) {
      debugPrint('[ChatAppBar] _confirmToggleBlockUser error: $e\n$st');
    }
  }

  /// Confirm + remove friend relationship (both sides).
  Future<void> _confirmRemoveFriend(BuildContext context) async {
    if (otherUserId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
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
        );
      },
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
    } catch (e, st) {
      debugPrint('[ChatAppBar] _confirmRemoveFriend error: $e\n$st');
    }
  }

  /// Confirm + cancel an outgoing friend request (both sides).
  Future<void> _confirmCancelFriendRequest(BuildContext context) async {
    if (otherUserId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
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
        );
      },
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
    } catch (e, st) {
      debugPrint('[ChatAppBar] _confirmCancelFriendRequest error: $e\n$st');
    }
  }

  /// Builds the 3-dot menu with:
  /// - “Report user”
  /// - “Block / Unblock user”
  /// - “Remove friend” (when status == "accepted")
  /// - “Cancel friend request” (when status == "requested" from me)
  Widget _buildOverflowMenu(BuildContext context, AppLocalizations l10n) {
    if (otherUserId == null) return const SizedBox.shrink();

    // Listen to *my* user doc to know if I already blocked this user.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final blockedListDynamic =
            (data['blockedUserIds'] as List<dynamic>?) ?? const [];
        final blockedList =
        blockedListDynamic.map((e) => e.toString()).toList();
        final isBlocked = blockedList.contains(otherUserId);

        final blockLabel =
        isBlocked ? l10n.unblockUserTitle : l10n.blockUserTitle;

        // Also listen to the friend document so we can show "Remove friend"
        // or "Cancel friend request" depending on status.
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .collection('friends')
              .doc(otherUserId)
              .snapshots(),
          builder: (context, friendSnap) {
            final friendData = friendSnap.data?.data();
            final friendStatus = friendData?['status'] as String?;
            final bool isFriendAccepted = friendStatus == 'accepted';
            final bool isOutgoingRequested = friendStatus == 'requested';

            final items = <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'report',
                child: Text(l10n.reportUserTitle),
              ),
              PopupMenuItem(
                value: 'blockToggle',
                child: Text(blockLabel),
              ),
              if (isFriendAccepted)
                PopupMenuItem(
                  value: 'unfriend',
                  child: Text(l10n.removeFriendTitle),
                ),
              if (!isFriendAccepted && isOutgoingRequested)
                PopupMenuItem(
                  value: 'cancelRequest',
                  child: Text(l10n.cancelFriendRequestTitle),
                ),
            ];

            return PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              onSelected: (value) {
                if (value == 'report') {
                  _showReportDialog(context);
                } else if (value == 'blockToggle') {
                  _confirmToggleBlockUser(
                    context,
                    isCurrentlyBlocked: isBlocked,
                  );
                } else if (value == 'unfriend') {
                  _confirmRemoveFriend(context);
                } else if (value == 'cancelRequest') {
                  _confirmCancelFriendRequest(context);
                }
              },
              itemBuilder: (context) => items,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
        titleSpacing: 8,
        title: _buildTitle(context),
        centerTitle: false,
        actions: [
          if (onClearChat != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              tooltip: l10n.deleteChatTitle,
              onPressed: onClearChat,
            ),

          // Report / Block–Unblock / Remove friend / Cancel request
          _buildOverflowMenu(context, l10n),

          _buildMyAvatarAction(context),

          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            tooltip: l10n.logoutTooltip,
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
