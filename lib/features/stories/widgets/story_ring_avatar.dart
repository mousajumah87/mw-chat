// lib/features/stories/widgets/story_ring_avatar.dart
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class StoryRingAvatar extends StatelessWidget {
  const StoryRingAvatar({
    super.key,
    this.imageUrl,
    this.size = 64,
    this.ringColors,
    this.ringWidth = 2.8,
    this.padding = 3,
    this.backgroundColor,
    this.child,
    this.showRing = true,
    this.isViewed = false,
  });

  final String? imageUrl;
  final double size;
  final List<Color>? ringColors;
  final double ringWidth;
  final double padding;
  final Color? backgroundColor;
  final Widget? child;
  final bool showRing;
  final bool isViewed;

  List<Color> get _defaultActiveRing => const [
    kPrimaryGold,
    kGoldDeep,
    Color(0xFFFFE29A),
  ];

  List<Color> get _defaultViewedRing => const [
    Color(0xFF7A7A7A),
    Color(0xFF5F5F5F),
  ];

  @override
  Widget build(BuildContext context) {
    final colors =
        ringColors ?? (isViewed ? _defaultViewedRing : _defaultActiveRing);

    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    final avatar = CircleAvatar(
      backgroundColor: backgroundColor ?? kSurfaceAltColor,
      backgroundImage: hasImage ? NetworkImage(imageUrl!.trim()) : null,
      child: !hasImage
          ? (child ??
          const Icon(
            Icons.person_rounded,
            size: 28,
            color: Colors.white70,
          ))
          : null,
    );

    if (!showRing) {
      return SizedBox(
        width: size,
        height: size,
        child: avatar,
      );
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isViewed
            ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ]
            : [
          BoxShadow(
            color: kGoldDeep.withOpacity(0.24),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kBgColor,
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
          ),
        ),
        child: avatar,
      ),
    );
  }
}