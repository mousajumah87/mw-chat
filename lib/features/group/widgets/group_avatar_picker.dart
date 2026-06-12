import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class GroupAvatarPicker extends StatelessWidget {
  const GroupAvatarPicker({
    super.key,
    this.imageFile,
    this.imageBytes,
    this.imageUrl,
    required this.onTap,
    this.radius = 42,
  });

  final File? imageFile;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    ImageProvider? provider;

    if (imageBytes != null) {
      provider = MemoryImage(imageBytes!);
    } else if (imageFile != null) {
      provider = FileImage(imageFile!);
    } else if ((imageUrl ?? '').trim().isNotEmpty) {
      provider = NetworkImage(imageUrl!.trim());
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius + 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundImage: provider,
            child: provider == null
                ? const Icon(Icons.camera_alt_rounded, size: 28)
                : null,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: radius * 0.7,
              height: radius * 0.7,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.edit_rounded,
                size: radius * 0.32,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}