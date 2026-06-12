import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/chat_room_model.dart';
import '../screens/group_chat_screen.dart';

class MyGroupsSection extends StatelessWidget {
  const MyGroupsSection({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    final memberStream = FirebaseFirestore.instance
        .collection('groupChats')
        .where('type', isEqualTo: 'group')
        .where('memberIds', arrayContains: currentUser.uid)
        .snapshots();

    final adminStream = FirebaseFirestore.instance
        .collection('groupChats')
        .where('type', isEqualTo: 'group')
        .where('adminIds', arrayContains: currentUser.uid)
        .snapshots();

    return LayoutBuilder(
      builder: (context, constraints) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: memberStream,
          builder: (context, memberSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: adminStream,
              builder: (context, adminSnapshot) {
                final hasError =
                    memberSnapshot.hasError || adminSnapshot.hasError;

                if (hasError) {
                  final error =
                      memberSnapshot.error ?? adminSnapshot.error ?? 'Unknown error';

                  return _GroupsContainer(
                    title: 'My Groups',
                    child: _CenteredMessage(
                      child: Text(
                        'Failed to load groups: $error',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final memberWaiting =
                    memberSnapshot.connectionState == ConnectionState.waiting;
                final adminWaiting =
                    adminSnapshot.connectionState == ConnectionState.waiting;

                final memberDocs = memberSnapshot.data?.docs ?? const [];
                final adminDocs = adminSnapshot.data?.docs ?? const [];

                final hasAnyDocs = memberDocs.isNotEmpty || adminDocs.isNotEmpty;

                if ((memberWaiting || adminWaiting) && !hasAnyDocs) {
                  return const _GroupsContainer(
                    title: 'My Groups',
                    child: _CenteredMessage(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final mergedDocsById =
                <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

                for (final doc in memberDocs) {
                  mergedDocsById[doc.id] = doc;
                }
                for (final doc in adminDocs) {
                  mergedDocsById[doc.id] = doc;
                }

                final rooms = mergedDocsById.values
                    .map((doc) => ChatRoomModel.fromMap(doc.id, doc.data()))
                    .toList()
                  ..sort((a, b) {
                    final aTime =
                        a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bTime =
                        b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return bTime.compareTo(aTime);
                  });

                if (rooms.isEmpty) {
                  return const _GroupsContainer(
                    title: 'My Groups',
                    child: _CenteredMessage(
                      child: Text(
                        'No groups yet. Create your first group.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return _GroupsContainer(
                  title: 'My Groups',
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    primary: false,
                    shrinkWrap: false,
                    physics: const ClampingScrollPhysics(),
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      return _GroupTile(
                        room: room,
                        currentUserId: currentUser.uid,
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _GroupsContainer extends StatelessWidget {
  const _GroupsContainer({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),

          // Important overflow fix:
          // lets the content use the remaining height and scroll when needed.
          Expanded(
            child: child,
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.room,
    required this.currentUserId,
  });

  final ChatRoomModel room;
  final String currentUserId;

  String _title() {
    final raw = (room.name ?? '').trim();
    return raw.isEmpty ? 'Unnamed Group' : raw;
  }

  List<String> _uniqueAudienceIds() {
    final ids = <String>{
      ...room.memberIds,
      ...room.adminIds,
    };
    return ids.toList();
  }

  int _memberCount() {
    return _uniqueAudienceIds().length;
  }

  bool _isAdmin() {
    return room.adminIds.contains(currentUserId);
  }

  String _subtitle() {
    final lastMessage = (room.lastMessageText ?? '').trim();
    if (lastMessage.isNotEmpty) {
      return lastMessage;
    }

    final count = _memberCount();
    return count == 1 ? '1 member' : '$count members';
  }

  String _avatarText(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'G';
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _title();
    final subtitle = _subtitle();
    final isAdmin = _isAdmin();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupChatScreen(roomId: room.id),
            ),
          );
        },
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Text(
                  _avatarText(title),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.20),
                                ),
                              ),
                              child: Text(
                                'Admin',
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}