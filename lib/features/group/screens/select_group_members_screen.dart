import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../controllers/create_group_controller.dart';
import '../widgets/selected_member_chip.dart';
import 'group_details_screen.dart';

class SelectGroupMembersScreen extends StatefulWidget {
  const SelectGroupMembersScreen({
    super.key,
    required this.controller,
  });

  final CreateGroupController controller;

  @override
  State<SelectGroupMembersScreen> createState() =>
      _SelectGroupMembersScreenState();
}

class _SelectGroupMembersScreenState extends State<SelectGroupMembersScreen> {
  String _query = '';
  late final Future<List<GroupSelectableUser>> _friendsFuture;

  @override
  void initState() {
    super.initState();
    _friendsFuture = _loadFriends();
  }

  Future<List<GroupSelectableUser>> _loadFriends() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return <GroupSelectableUser>[];

    final friendsSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('friends')
        .where('status', isEqualTo: 'accepted')
        .get();

    final friendIds = friendsSnap.docs.map((doc) => doc.id).toList();
    if (friendIds.isEmpty) return <GroupSelectableUser>[];

    final results = <GroupSelectableUser>[];

    for (final friendId in friendIds) {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(friendId)
          .get();

      if (!userSnap.exists) continue;

      final data = userSnap.data() ?? <String, dynamic>{};

      final firstName = (data['firstName'] ?? '').toString().trim();
      final lastName = (data['lastName'] ?? '').toString().trim();
      final email = (data['email'] ?? '').toString().trim();
      final profileUrl = (data['profileUrl'] ?? '').toString().trim();

      final displayName = <String>[firstName, lastName]
          .where((e) => e.isNotEmpty)
          .join(' ')
          .trim();

      results.add(
        GroupSelectableUser(
          id: friendId,
          displayName: displayName.isNotEmpty
              ? displayName
              : (email.isNotEmpty ? email : 'Unknown User'),
          photoUrl: profileUrl.isNotEmpty ? profileUrl : null,
        ),
      );
    }

    results.sort(
          (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    return results;
  }

  void _goNext() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailsScreen(
          controller: widget.controller,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GroupSelectableUser>>(
      future: _friendsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('New Group'),
            ),
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('New Group'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load friends: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final availableFriends = snapshot.data ?? <GroupSelectableUser>[];

        final filtered = availableFriends.where((user) {
          final q = _query.trim().toLowerCase();
          if (q.isEmpty) return true;
          return user.displayName.toLowerCase().contains(q);
        }).toList();

        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('New Group'),
              ),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search friends',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _query = value;
                        });
                      },
                    ),
                  ),
                  if (widget.controller.selectedUsers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.controller.selectedUsers.map((user) {
                            return SelectedMemberChip(
                              user: user,
                              onRemove: () {
                                widget.controller.removeSelectedUser(user.id);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: availableFriends.isEmpty
                        ? const Center(
                      child: Text('No accepted friends found.'),
                    )
                        : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = filtered[index];
                        final selected =
                        widget.controller.isSelected(user.id);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: user.photoUrl != null
                                ? NetworkImage(user.photoUrl!)
                                : null,
                            child: user.photoUrl == null
                                ? Text(
                              user.displayName.isNotEmpty
                                  ? user.displayName[0]
                                  .toUpperCase()
                                  : '?',
                            )
                                : null,
                          ),
                          title: Text(user.displayName),
                          trailing: Checkbox(
                            value: selected,
                            onChanged: (_) {
                              widget.controller.toggleUser(user);
                            },
                          ),
                          onTap: () {
                            widget.controller.toggleUser(user);
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.controller.canContinueFromMembers
                              ? _goNext
                              : null,
                          child: const Text('Next'),
                        ),
                      ),
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
}