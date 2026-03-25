// lib/features/stories/widgets/stories_row.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/mw_avatar.dart';
import '../models/story_model.dart';
import '../models/story_repository.dart';
import '../screens/create_story_screen.dart';
import '../screens/story_viewer_screen.dart';

class StoriesRow extends StatefulWidget {
  const StoriesRow({
    super.key,
    this.currentUserImageUrl,
    this.onStoryCreated,
    this.onOpenStoryGroup,
    this.height = 138,
    this.showIfEmpty = true,
  });

  final String? currentUserImageUrl;
  final Future<void> Function()? onStoryCreated;
  final void Function(StoryGroup group)? onOpenStoryGroup;
  final double height;
  final bool showIfEmpty;

  @override
  State<StoriesRow> createState() => _StoriesRowState();
}

class _StoriesRowState extends State<StoriesRow> {
  final StoryRepository _repo = StoryRepository();

  final Map<String, String?> _nameCache = <String, String?>{};
  final Map<String, String?> _imageCache = <String, String?>{};
  final Set<String> _loadingOwnerIds = <String>{};

  bool _isOpeningStory = false;
  bool _isOpeningCreateStory = false;
  bool _ownerPrimeScheduled = false;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String? _userDisplayNameCache(String userId) => _nameCache[userId];
  String? _userImageCache(String userId) => _imageCache[userId];

  Future<void> _schedulePrimeOwnerMeta(List<StoryGroup> groups) async {
    if (_ownerPrimeScheduled || groups.isEmpty) return;

    _ownerPrimeScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _ownerPrimeScheduled = false;
      if (!mounted) return;
      await _primeOwnerMeta(groups);
    });
  }

  Future<void> _primeOwnerMeta(List<StoryGroup> groups) async {
    final missingIds = groups
        .map((g) => g.ownerId)
        .where(
          (id) =>
      (!_nameCache.containsKey(id) || !_imageCache.containsKey(id)) &&
          !_loadingOwnerIds.contains(id),
    )
        .toSet()
        .toList();

    if (missingIds.isEmpty) return;

    _loadingOwnerIds.addAll(missingIds);

    bool changed = false;

    for (final userId in missingIds) {
      try {
        final snap =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();

        final data = snap.data() ?? const <String, dynamic>{};

        final firstName = (data['firstName'] ?? '').toString().trim();
        final lastName = (data['lastName'] ?? '').toString().trim();
        final displayNameRaw =
        [firstName, lastName].where((e) => e.isNotEmpty).join(' ').trim();

        final username = (data['username'] ?? '').toString().trim();
        final profileUrl = (data['profileUrl'] ?? '').toString().trim();

        final displayName = displayNameRaw.isNotEmpty
            ? displayNameRaw
            : (username.isNotEmpty ? username : null);

        _nameCache[userId] = displayName;
        _imageCache[userId] = profileUrl.isEmpty ? null : profileUrl;
        changed = true;
      } catch (_) {
        _nameCache.putIfAbsent(userId, () => null);
        _imageCache.putIfAbsent(userId, () => null);
        changed = true;
      } finally {
        _loadingOwnerIds.remove(userId);
      }
    }

    if (mounted && changed) {
      setState(() {});
    }
  }

  List<StoryGroup> _groupStories(List<StoryModel> stories) {
    final myUid = _repo.currentUserId;
    final Map<String, List<StoryModel>> grouped = <String, List<StoryModel>>{};

    for (final story in stories) {
      if (story.isExpired) continue;
      grouped.putIfAbsent(story.ownerId, () => <StoryModel>[]).add(story);
    }

    final groups = grouped.entries.map((entry) {
      final items = [...entry.value]
        ..sort((a, b) {
          final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      return StoryGroup(
        ownerId: entry.key,
        stories: items,
        isMine: entry.key == myUid,
      );
    }).toList();

    groups.sort((a, b) {
      if (a.isMine && !b.isMine) return -1;
      if (!a.isMine && b.isMine) return 1;

      final aLatest =
          a.latestStory.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bLatest =
          b.latestStory.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      return bLatest.compareTo(aLatest);
    });

    return groups;
  }

  Future<void> _openStoryGroup(
      StoryGroup group, {
        String? ownerDisplayName,
        String? ownerImageUrl,
      }) async {
    if (!mounted || _isOpeningStory) return;

    _isOpeningStory = true;

    debugPrint(
      '[StoriesRow] _openStoryGroup called -> ownerId=${group.ownerId}, ownerDisplayName=$ownerDisplayName, callbackExists=${widget.onOpenStoryGroup != null}',
    );

    try {
      widget.onOpenStoryGroup?.call(group);
    } catch (e, st) {
      debugPrint('[StoriesRow] onOpenStoryGroup callback failed: $e');
      debugPrintStack(stackTrace: st);
    }

    if (!mounted) {
      _isOpeningStory = false;
      return;
    }

    debugPrint(
      '[StoriesRow] pushing StoryViewerScreen -> ownerId=${group.ownerId}, stories=${group.stories.map((e) => e.id).toList()}',
    );

    try {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            group: group,
            ownerDisplayName: ownerDisplayName,
            ownerImageUrl: ownerImageUrl,
          ),
        ),
      );

      debugPrint(
        '[StoriesRow] returned from StoryViewerScreen -> result=$result',
      );

      if (mounted) {
        setState(() {});
      }
    } finally {
      _isOpeningStory = false;
    }
  }

  Future<void> _openCreateStory() async {
    if (!mounted || _isOpeningCreateStory) return;

    _isOpeningCreateStory = true;

    try {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const CreateStoryScreen(),
        ),
      );

      if (created == true) {
        if (widget.onStoryCreated != null) {
          await widget.onStoryCreated!();
        }
        if (mounted) {
          setState(() {});
        }
      }
    } finally {
      _isOpeningCreateStory = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: StreamBuilder<List<StoryModel>>(
        stream: _repo.watchActiveStories(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('StoriesRow stream error: ${snapshot.error}');
          }

          final stories = snapshot.data ?? const <StoryModel>[];
          final groups = _groupStories(stories);

          if (groups.isNotEmpty) {
            unawaited(_schedulePrimeOwnerMeta(groups));
          }

          if (groups.isEmpty && !widget.showIfEmpty) {
            return const SizedBox.shrink();
          }

          StoryGroup? myGroup;
          for (final group in groups) {
            if (group.isMine) {
              myGroup = group;
              break;
            }
          }

          final otherGroups = groups.where((g) => !g.isMine).toList();
          final itemCount = 1 + otherGroups.length;

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            physics: const BouncingScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                final myImage =
                    widget.currentUserImageUrl ?? _userImageCache(_repo.currentUserId);

                final mySeen = myGroup == null
                    ? false
                    : _repo.isStoryGroupFullySeen(
                  myGroup.stories,
                  _repo.currentUserId,
                );

                return MyStoryBubble(
                  label: l10n.storyYourStory,
                  imageUrl: myImage,
                  segmentCount: myGroup?.stories.length ?? 0,
                  isViewed: mySeen,
                  hasStory: myGroup != null,
                  onAvatarTap: () async {
                    debugPrint(
                      '[StoriesRow] MyStoryBubble tapped -> hasStory=${myGroup != null}, myUid=${_repo.currentUserId}',
                    );

                    if (myGroup != null) {
                      await _openStoryGroup(
                        myGroup,
                        ownerDisplayName: l10n.storyYourStory,
                        ownerImageUrl: myImage,
                      );
                    } else {
                      await _openCreateStory();
                    }
                  },
                  onPlusTap: _openCreateStory,
                );
              }

              final group = otherGroups[index - 1];
              final cachedName = _userDisplayNameCache(group.ownerId);
              final displayName = (cachedName?.trim().isNotEmpty ?? false)
                  ? cachedName!.trim()
                  : l10n.storyViewerFallbackTitle;
              final imageUrl = _userImageCache(group.ownerId);
              final isViewed =
              _repo.isStoryGroupFullySeen(group.stories, _repo.currentUserId);
              final unseenCount =
              _repo.unseenCountForGroup(group.stories, _repo.currentUserId);

              return StoryBubble(
                label: displayName,
                imageUrl: imageUrl,
                storyCount: group.stories.length,
                unseenCount: unseenCount,
                isViewed: isViewed,
                onTap: () async {
                  debugPrint(
                    '[StoriesRow] StoryBubble tapped -> ownerId=${group.ownerId}, label=$displayName, storyIds=${group.stories.map((e) => e.id).toList()}',
                  );

                  await _openStoryGroup(
                    group,
                    ownerDisplayName: displayName,
                    ownerImageUrl: imageUrl,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class StoryGroup {
  const StoryGroup({
    required this.ownerId,
    required this.stories,
    required this.isMine,
  });

  final String ownerId;
  final List<StoryModel> stories;
  final bool isMine;

  StoryModel get latestStory => stories.first;
}

class StoryBubble extends StatelessWidget {
  const StoryBubble({
    super.key,
    required this.label,
    required this.storyCount,
    required this.unseenCount,
    required this.isViewed,
    this.imageUrl,
    this.onTap,
    this.size = 72,
  });

  final String label;
  final int storyCount;
  final int unseenCount;
  final bool isViewed;
  final String? imageUrl;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final subtitle = unseenCount > 0
        ? l10n.storiesRowNewCount(unseenCount)
        : (isViewed ? l10n.storiesRowSeen : l10n.storyViewerFallbackTitle);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        splashColor: Colors.white.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.04),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size + 46,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: Color.lerp(kSurfaceColor, Colors.white, 0.02)!
                .withValues(alpha: 0.34),
            border: Border.all(
              color: isViewed
                  ? Colors.white.withValues(alpha: 0.06)
                  : kPrimaryGold.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              if (!isViewed)
                BoxShadow(
                  color: kGoldDeep.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Column(
            children: [
              _StoryAvatarCore(
                size: size,
                imageUrl: imageUrl,
                label: label,
                hasStory: true,
                isOwnStory: false,
                isViewed: isViewed,
                storyCount: storyCount,
                unseenCount: unseenCount,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _BubbleFooterText(
                  title: label,
                  subtitle: subtitle,
                  highlightSubtitle: unseenCount > 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyStoryBubble extends StatelessWidget {
  const MyStoryBubble({
    super.key,
    required this.label,
    required this.hasStory,
    required this.onAvatarTap,
    required this.onPlusTap,
    this.imageUrl,
    this.segmentCount = 0,
    this.isViewed = false,
    this.size = 72,
  });

  final String label;
  final bool hasStory;
  final VoidCallback onAvatarTap;
  final VoidCallback onPlusTap;
  final String? imageUrl;
  final int segmentCount;
  final bool isViewed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final plusSize = size * 0.34;

    return Container(
      width: size + 46,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Color.lerp(kSurfaceColor, Colors.white, 0.02)!
            .withValues(alpha: 0.38),
        border: Border.all(
          color: kPrimaryGold.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: kGoldDeep.withValues(alpha: 0.10),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onAvatarTap,
                      child: _StoryAvatarCore(
                        size: size,
                        imageUrl: imageUrl,
                        label: label,
                        hasStory: hasStory,
                        isOwnStory: true,
                        isViewed: isViewed,
                        storyCount: segmentCount,
                        unseenCount: hasStory ? 1 : 0,
                        showCountBadge: hasStory,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onPlusTap,
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
                            width: 2.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: kGoldDeep.withValues(alpha: 0.34),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _BubbleFooterText(
              title: label,
              subtitle:
              hasStory ? l10n.storiesRowTapToView : l10n.storiesRowAddStory,
              highlightSubtitle: true,
              titleFontSize: 12,
              subtitleFontSize: 10,
              titleWeight: FontWeight.w800,
              subtitleWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryAvatarCore extends StatelessWidget {
  const _StoryAvatarCore({
    required this.size,
    required this.label,
    required this.hasStory,
    required this.isOwnStory,
    required this.isViewed,
    required this.storyCount,
    required this.unseenCount,
    this.imageUrl,
    this.showCountBadge = true,
  });

  final double size;
  final String label;
  final bool hasStory;
  final bool isOwnStory;
  final bool isViewed;
  final int storyCount;
  final int unseenCount;
  final String? imageUrl;
  final bool showCountBadge;

  String _initialsFromLabel(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'MW';
    if (parts.length == 1) {
      final v = parts.first;
      return v.length >= 2 ? v.substring(0, 2).toUpperCase() : v.toUpperCase();
    }

    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bool showStoryState = hasStory;
    final int safeStoryCount = storyCount <= 0 ? 0 : storyCount;
    final int badgeCount = unseenCount > 0 ? unseenCount : safeStoryCount;

    final Color ringColor = showStoryState
        ? (isViewed && !isOwnStory
        ? Colors.white.withValues(alpha: 0.34)
        : kPrimaryGold)
        : kPrimaryGold;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  boxShadow: [
                    if (showStoryState && !isViewed)
                      BoxShadow(
                        color: kPrimaryGold.withValues(
                          alpha: isOwnStory ? 0.16 : 0.10,
                        ),
                        blurRadius: isOwnStory ? 18 : 12,
                        spreadRadius: isOwnStory ? 1.5 : 0.8,
                      ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: showStoryState && !isViewed
                        ? LinearGradient(
                      colors: [
                        kPrimaryGold,
                        kGoldDeep,
                        const Color(0xFFFFE29A).withValues(alpha: 0.92),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : null,
                    border: showStoryState && isViewed
                        ? Border.all(
                      color: ringColor,
                      width: 1.8,
                    )
                        : null,
                    color: showStoryState
                        ? null
                        : kPrimaryGold.withValues(alpha: 0.92),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2.6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kBgColor,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: MwAvatar(
                      avatarType: 'bear',
                      profileUrl: imageUrl,
                      initials: _initialsFromLabel(label),
                      radius: (size - 10.2) / 2,
                      backgroundColor: kSurfaceAltColor,
                      hasStory: showStoryState,
                      isOwnStory: isOwnStory,
                      storySeen: isViewed,
                      showStoryGlow: showStoryState && !isViewed,
                      storyGlowColor: kPrimaryGold.withValues(
                        alpha: isOwnStory ? 0.22 : 0.14,
                      ),
                      storyGlowBlur: isOwnStory ? 14 : 10,
                      storyGlowSpread: isOwnStory ? 1.0 : 0.4,
                      showRing: false,
                      showOnlineDot: false,
                      showOnlineGlow: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showCountBadge && showStoryState && badgeCount > 1)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: kSurfaceColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: kPrimaryGold.withValues(alpha: 0.40),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: kPrimaryGold,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BubbleFooterText extends StatelessWidget {
  const _BubbleFooterText({
    required this.title,
    required this.subtitle,
    this.highlightSubtitle = false,
    this.titleFontSize = 12,
    this.subtitleFontSize = 10,
    this.titleWeight = FontWeight.w700,
    this.subtitleWeight = FontWeight.w700,
  });

  final String title;
  final String subtitle;
  final bool highlightSubtitle;
  final double titleFontSize;
  final double subtitleFontSize;
  final FontWeight titleWeight;
  final FontWeight subtitleWeight;

  static const StrutStyle _tightStrut = StrutStyle(
    forceStrutHeight: true,
    height: 1.0,
    leading: 0,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight <= 30;
        final veryCompact = constraints.maxHeight <= 24;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.of(context).textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    strutStyle: _tightStrut,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: titleWeight,
                      fontSize: veryCompact ? titleFontSize - 1 : titleFontSize,
                      height: 1.0,
                    ),
                  ),
                ),
                if (!compact && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Flexible(
                    child: Text(
                      subtitle.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      strutStyle: _tightStrut,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: highlightSubtitle
                            ? kPrimaryGold
                            : Colors.white.withValues(alpha: 0.7),
                        fontWeight: subtitleWeight,
                        fontSize: veryCompact
                            ? subtitleFontSize - 1
                            : subtitleFontSize,
                        letterSpacing: 0.08,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}