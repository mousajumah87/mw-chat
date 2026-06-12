import 'package:flutter/material.dart';

import '../controllers/create_group_controller.dart';

class SelectedMemberChip extends StatelessWidget {
  const SelectedMemberChip({
    super.key,
    required this.user,
    required this.onRemove,
  });

  final GroupSelectableUser user;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Chip(
        avatar: CircleAvatar(
          child: Text(
            user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
          ),
        ),
        label: Text(user.displayName),
        onDeleted: onRemove,
      ),
    );
  }
}