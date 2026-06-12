import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/create_group_controller.dart';
import '../widgets/group_avatar_picker.dart';
import 'group_chat_screen.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({
    super.key,
    required this.controller,
  });

  final CreateGroupController controller;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  late final TextEditingController _nameController;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.controller.groupName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickGroupImage() async {
    FocusScope.of(context).unfocus();

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1400,
      );

      if (picked == null) return;

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        widget.controller.setPickedImage(
          bytes: bytes,
          fileName: picked.name,
        );
      } else {
        widget.controller.setPickedImage(
          file: File(picked.path),
          fileName: picked.name,
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick group image: $e')),
      );
    }
  }

  Future<void> _createGroup() async {
    FocusScope.of(context).unfocus();

    try {
      final roomId = await widget.controller.createGroup();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(roomId: roomId),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create group: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Group Details'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: GroupAvatarPicker(
                  imageFile: widget.controller.pickedImage,
                  imageBytes: widget.controller.pickedImageBytes,
                  onTap: _pickGroupImage,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: widget.controller.isCreating ? null : _pickGroupImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    widget.controller.pickedImage != null ||
                        widget.controller.pickedImageBytes != null
                        ? 'Change group photo'
                        : 'Add group photo',
                  ),
                ),
              ),
              if (widget.controller.pickedImageFileName?.trim().isNotEmpty == true)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.controller.pickedImageFileName!,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                onChanged: widget.controller.setGroupName,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  hintText: 'Enter group name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Members (${widget.controller.selectedUsers.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ...widget.controller.selectedUsers.map(
                    (user) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundImage: (user.photoUrl ?? '').trim().isNotEmpty
                        ? NetworkImage(user.photoUrl!.trim())
                        : null,
                    child: (user.photoUrl ?? '').trim().isEmpty
                        ? Text(user.initials)
                        : null,
                  ),
                  title: Text(user.displayName),
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: widget.controller.canCreateGroup &&
                      !widget.controller.isCreating
                      ? _createGroup
                      : null,
                  child: widget.controller.isCreating
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Create Group'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}