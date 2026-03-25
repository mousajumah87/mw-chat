// lib/features/stories/widgets/story_create_button.dart
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../screens/create_story_screen.dart';

class StoryCreateButton extends StatelessWidget {
  const StoryCreateButton({
    super.key,
    this.label,
    this.imageUrl,
    this.onCreated,
    this.size = 64,
    this.onTapOverride,
    this.showPlus = true,
    this.onPlusTap,
  });

  final String? label;
  final String? imageUrl;
  final Future<void> Function()? onCreated;
  final double size;
  final VoidCallback? onTapOverride;
  final bool showPlus;
  final VoidCallback? onPlusTap;

  Future<void> _openCreateStory(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CreateStoryScreen(),
      ),
    );

    if (created == true && onCreated != null) {
      await onCreated!();
    }
  }

  void _handleMainTap(BuildContext context) {
    if (onTapOverride != null) {
      onTapOverride!();
      return;
    }
    _openCreateStory(context);
  }

  void _handlePlusTap(BuildContext context) {
    if (onPlusTap != null) {
      onPlusTap!();
      return;
    }
    _openCreateStory(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final avatarSize = size;
    final plusSize = size * 0.32;
    final resolvedLabel =
    (label != null && label!.trim().isNotEmpty) ? label!.trim() : l10n.storyYourStory;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: SizedBox(
        width: avatarSize + 28,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        splashColor: Colors.white.withValues(alpha: 0.08),
                        highlightColor: Colors.white.withValues(alpha: 0.04),
                        onTap: () => _handleMainTap(context),
                        child: Container(
                          padding: const EdgeInsets.all(2.8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                kPrimaryGold.withValues(alpha: 0.98),
                                kGoldDeep.withValues(alpha: 0.96),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: kGoldDeep.withValues(alpha: 0.22),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kBgColor,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: CircleAvatar(
                              backgroundColor: kSurfaceAltColor,
                              backgroundImage:
                              (imageUrl != null && imageUrl!.trim().isNotEmpty)
                                  ? NetworkImage(imageUrl!.trim())
                                  : null,
                              child: (imageUrl == null || imageUrl!.trim().isEmpty)
                                  ? const Icon(
                                Icons.person_rounded,
                                size: 28,
                                color: Colors.white70,
                              )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showPlus)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          splashColor: Colors.white.withValues(alpha: 0.08),
                          highlightColor: Colors.white.withValues(alpha: 0.04),
                          onTap: () => _handlePlusTap(context),
                          child: Container(
                            width: plusSize,
                            height: plusSize,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  kPrimaryGold,
                                  kGoldDeep,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: kBgColor,
                                width: 2.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: kGoldDeep.withValues(alpha: 0.32),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 17,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              resolvedLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.18,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              l10n.storiesRowAddStory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: kPrimaryGold,
                fontWeight: FontWeight.w800,
                height: 1.12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}