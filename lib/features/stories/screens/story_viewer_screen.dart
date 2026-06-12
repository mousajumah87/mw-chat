import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/mw_avatar.dart';
import '../models/story_model.dart';
import '../models/story_repository.dart';
import '../widgets/stories_row.dart';

class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.group,
    this.ownerDisplayName,
    this.ownerImageUrl,
  });

  final StoryGroup group;
  final String? ownerDisplayName;
  final String? ownerImageUrl;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  final StoryRepository _repo = StoryRepository();

  late final AnimationController _progressController;
  late final AnimationController _hintController;

  List<StoryModel> _stories = <StoryModel>[];

  VideoPlayerController? _videoController;
  StreamSubscription<List<StoryModel>>? _storiesSub;

  final Map<String, _ViewerMeta> _viewerMetaCache = <String, _ViewerMeta>{};
  final Set<String> _loadingViewerIds = <String>{};

  int _currentIndex = 0;
  bool _deleting = false;
  bool _holding = false;
  bool _videoReady = false;
  bool _isNavigating = false;
  bool _loadingViewerSheet = false;
  bool _isClosing = false;
  bool _isDisposed = false;

  static const Duration _imageDuration = Duration(seconds: 5);
  static const Duration _textDuration = Duration(seconds: 6);
  static const Duration _videoFallbackDuration = Duration(seconds: 8);

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  bool get _canUseState => mounted && !_isDisposed;
  bool get _hasStories => _stories.isNotEmpty;

  Color _mwGlass([double alpha = 0.72]) =>
      Color.lerp(kSurfaceColor, Colors.black, 0.18)!.withValues(alpha: alpha);

  Color _mwGlassStrong([double alpha = 0.86]) =>
      Color.lerp(kSurfaceAltColor, Colors.black, 0.10)!.withValues(alpha: alpha);

  Color get _mwBorder => Colors.white.withValues(alpha: 0.08);

  double _storyMediaInset(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;
    final height = size.height;

    if (height < 700 || shortest < 360) return 6;
    if (height < 820 || shortest < 390) return 8;
    return 10;
  }

  double _storyMediaRadius(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;
    final height = size.height;

    if (height < 700 || shortest < 360) return 18;
    if (height < 820 || shortest < 390) return 22;
    return 26;
  }

  double _storyMediaHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1400) return 28;
    if (width >= 1000) return 22;
    if (width >= 700) return 16;
    return 10;
  }

  Size _storyMediaMaxSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    final double maxWidth = isLandscape
        ? math.min(size.width * 0.76, 980)
        : math.min(size.width - (_storyMediaHorizontalPadding(context) * 2), 560);

    final double maxHeight = isLandscape
        ? math.min(size.height * 0.74, 720)
        : math.min(size.height * 0.70, 780);

    return Size(maxWidth, maxHeight);
  }

  Widget _buildMediaStage({
    required Widget child,
    EdgeInsetsGeometry? margin,
  }) {
    final radius = _storyMediaRadius(context);
    final maxSize = _storyMediaMaxSize(context);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: margin ??
              EdgeInsets.symmetric(
                horizontal: _storyMediaHorizontalPadding(context),
                vertical: 8,
              ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxSize.width,
              maxHeight: maxSize.height,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: kGoldDeep.withValues(alpha: 0.025),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _mwPanelDecoration({
    double radius = 24,
    double alpha = 0.72,
    bool warm = false,
    List<BoxShadow>? boxShadow,
  }) {
    final base = warm
        ? Color.lerp(kSurfaceAltColor, kGoldDeep, 0.10)!
        : Color.lerp(kSurfaceColor, Colors.black, 0.18)!;

    return BoxDecoration(
      color: base.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _mwBorder),
      boxShadow: boxShadow ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
    );
  }

  LinearGradient get _mwScreenOverlay => LinearGradient(
    colors: [
      Colors.black.withValues(alpha: 0.28),
      Colors.transparent,
      Colors.black.withValues(alpha: 0.22),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  LinearGradient get _mwTopFade => LinearGradient(
    colors: [
      Colors.black.withValues(alpha: 0.28),
      Colors.transparent,
      Colors.black.withValues(alpha: 0.22),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  @override
  void initState() {
    super.initState();

    _stories = [...widget.group.stories]..sort(_sortStoriesByCreatedAt);
    _currentIndex = _clampIndex(_currentIndex, _stories.length);

    _progressController = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (!_canUseState) return;
        if (status == AnimationStatus.completed) {
          unawaited(_goNext());
        }
      });

    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      reverseDuration: const Duration(milliseconds: 1400),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canUseState) return;

      _dismissKeyboard();

      if (_stories.isEmpty) return;
      unawaited(_prepareCurrentStory());
      unawaited(_markCurrentSeen());
      unawaited(_primeViewerMetaForCurrentStory());
      _syncHintAnimation();
    });

    _listenToStoryUpdates();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _storiesSub?.cancel();
    _progressController.dispose();
    _hintController.dispose();
    unawaited(_disposeVideoController());
    super.dispose();
  }

  int _clampIndex(int index, int length) {
    if (length <= 0) return 0;
    if (index < 0) return 0;
    if (index >= length) return length - 1;
    return index;
  }

  int _sortStoriesByCreatedAt(StoryModel a, StoryModel b) {
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aTime.compareTo(bTime);
  }

  StoryModel? get _currentStoryOrNull {
    if (!_hasStories) return null;
    final safeIndex = _clampIndex(_currentIndex, _stories.length);
    if (safeIndex != _currentIndex) {
      _currentIndex = safeIndex;
    }
    return _stories[safeIndex];
  }

  StoryModel get _currentStory =>
      _stories[_clampIndex(_currentIndex, _stories.length)];

  bool get _isMine {
    final story = _currentStoryOrNull;
    if (story == null) return false;
    return story.ownerId == _repo.currentUserId;
  }

  int get _totalGroupViews {
    int total = 0;
    for (final story in _stories) {
      total += story.viewerCount;
    }
    return total;
  }

  int get _uniqueGroupViewerCount {
    final ids = <String>{};
    for (final story in _stories) {
      ids.addAll(
        story.viewerIds.map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    }
    return ids.length;
  }

  Future<void> _closeViewer([bool? result]) async {
    if (!_canUseState || _isClosing) return;
    _isClosing = true;

    final navigator = Navigator.of(context); // capture BEFORE await

    await _disposeVideoController();

    if (mounted && !_isDisposed) {
      navigator.maybePop(result);
    }
  }

  void _listenToStoryUpdates() {
    final ownerId = widget.group.ownerId;

    _storiesSub = _repo.watchActiveStories().listen((allStories) async {
      final updatedStories = allStories
          .where((s) => s.ownerId == ownerId && !s.isExpired)
          .toList()
        ..sort(_sortStoriesByCreatedAt);

      if (!_canUseState) return;

      if (updatedStories.isEmpty) {
        await _closeViewer(true);
        return;
      }

      final previousStoryId = _hasStories
          ? _stories[_clampIndex(_currentIndex, _stories.length)].id
          : null;

      int nextIndex = 0;
      if (previousStoryId != null) {
        final foundIndex =
        updatedStories.indexWhere((story) => story.id == previousStoryId);
        if (foundIndex >= 0) {
          nextIndex = foundIndex;
        } else {
          nextIndex = _clampIndex(_currentIndex, updatedStories.length);
        }
      }

      final currentBefore = _currentStoryOrNull;
      final currentAfter =
      updatedStories[_clampIndex(nextIndex, updatedStories.length)];

      final switchedStory = currentBefore?.id != currentAfter.id;
      final videoUrlChanged = currentBefore?.mediaUrl != currentAfter.mediaUrl ||
          currentBefore?.mediaType != currentAfter.mediaType;

      setState(() {
        _stories = updatedStories;
        _currentIndex = _clampIndex(nextIndex, _stories.length);
      });

      _syncHintAnimation();
      unawaited(_primeViewerMetaForCurrentStory());

      if (switchedStory || videoUrlChanged) {
        await _prepareCurrentStory();
      }
    });
  }

  void _syncHintAnimation() {
    if (!_hasStories || !_isMine) {
      if (_hintController.isAnimating) {
        _hintController.stop();
      }
      _hintController.value = 0;
      return;
    }

    final current = _currentStoryOrNull;
    if (current == null) {
      if (_hintController.isAnimating) {
        _hintController.stop();
      }
      _hintController.value = 0;
      return;
    }

    final canOpen = current.viewerIds.isNotEmpty;
    if (!canOpen) {
      if (_hintController.isAnimating) {
        _hintController.stop();
      }
      _hintController.value = 0;
      return;
    }

    if (!_hintController.isAnimating) {
      _hintController.repeat(reverse: true);
    }
  }

  Future<void> _primeViewerMetaForCurrentStory() async {
    if (!_hasStories || !_isMine) return;
    final story = _currentStoryOrNull;
    if (story == null) return;
    await _primeViewerMeta(story.viewerIds);
  }

  Future<void> _primeViewerMeta(List<String> viewerIds) async {
    final ids = viewerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !_viewerMetaCache.containsKey(e))
        .where((e) => !_loadingViewerIds.contains(e))
        .toList();

    if (ids.isEmpty) return;

    _loadingViewerIds.addAll(ids);

    bool updated = false;

    for (final userId in ids) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();

        final data = snap.data() ?? const <String, dynamic>{};

        final firstName = (data['firstName'] ?? '').toString().trim();
        final lastName = (data['lastName'] ?? '').toString().trim();
        final fullName =
        [firstName, lastName].where((e) => e.isNotEmpty).join(' ').trim();

        final username = (data['username'] ?? '').toString().trim();
        final imageUrl = (data['profileUrl'] ?? '').toString().trim();

        final displayName = fullName.isNotEmpty
            ? fullName
            : (username.isNotEmpty ? username : l10n.storyViewerUserFallback);

        _viewerMetaCache[userId] = _ViewerMeta(
          userId: userId,
          displayName: displayName,
          username: username.isEmpty ? null : username,
          imageUrl: imageUrl.isEmpty ? null : imageUrl,
        );

        updated = true;
      } catch (_) {
        _viewerMetaCache[userId] = _ViewerMeta(
          userId: userId,
          displayName: l10n.storyViewerUserFallback,
          username: null,
          imageUrl: null,
        );

        updated = true;
      } finally {
        _loadingViewerIds.remove(userId);
      }
    }

    if (updated && _canUseState) {
      setState(() {});
    }
  }

  Duration _durationForStory(StoryModel story) {
    if (story.isText) return _textDuration;
    if (story.isImage) return _imageDuration;
    return _videoFallbackDuration;
  }

  Future<void> _markCurrentSeen() async {
    if (!_hasStories) return;
    if (_currentIndex < 0 || _currentIndex >= _stories.length) return;

    final story = _stories[_currentIndex];
    final viewerId = _repo.currentUserId;

    if (story.ownerId == viewerId) return;
    if (story.viewerIds.contains(viewerId)) return;

    try {
      await _repo.markStorySeen(story);

      if (!_canUseState) return;
      if (_currentIndex < 0 || _currentIndex >= _stories.length) return;

      final current = _stories[_currentIndex];
      if (current.id != story.id) return;
      if (current.viewerIds.contains(viewerId)) return;

      setState(() {
        _stories[_currentIndex] = current.copyWith(
          viewerIds: [...current.viewerIds, viewerId],
          viewerCount: current.viewerCount + 1,
        );
      });

      _syncHintAnimation();
    } catch (e) {
      debugPrint('Story viewer error: $e');
    }
  }

  Future<void> _prepareCurrentStory() async {
    if (!_hasStories) return;

    _videoReady = false;
    _progressController.stop();
    _progressController.reset();

    await _disposeVideoController();

    final story = _currentStoryOrNull;
    if (story == null) return;

    if (story.isVideo) {
      await _prepareVideoStory(story);
      return;
    }

    _startStaticStoryProgress(_durationForStory(story));

    if (_canUseState) {
      setState(() {});
    }
  }

  void _startStaticStoryProgress(Duration duration) {
    if (!_canUseState) return;
    _progressController
      ..duration = duration
      ..value = 0
      ..forward();
  }

  Future<void> _prepareVideoStory(StoryModel story) async {
    final url = (story.mediaUrl ?? '').trim();
    if (url.isEmpty) {
      _startStaticStoryProgress(_videoFallbackDuration);
      if (_canUseState) setState(() {});
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _startStaticStoryProgress(_videoFallbackDuration);
      if (_canUseState) setState(() {});
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _videoController = controller;

    try {
      await controller.initialize();

      if (!_canUseState || _videoController != controller) {
        await controller.dispose();
        return;
      }

      final actualDuration = controller.value.duration;
      final duration =
      actualDuration > Duration.zero ? actualDuration : _videoFallbackDuration;

      await controller.setLooping(false);
      controller.addListener(_videoListener);
      await controller.play();

      _videoReady = true;

      _progressController
        ..duration = duration
        ..value = 0
        ..forward();

      if (_canUseState) {
        setState(() {});
      }
    } catch (_) {
      if (_videoController == controller) {
        _videoController = null;
      }
      try {
        controller.removeListener(_videoListener);
      } catch (e) {
        debugPrint('Story viewer error: $e');
      }
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('Story viewer error: $e');
      }

      _videoReady = false;
      _startStaticStoryProgress(_videoFallbackDuration);
      if (_canUseState) {
        setState(() {});
      }
    }
  }

  void _videoListener() {
    final controller = _videoController;
    if (controller == null || !_canUseState) return;

    final value = controller.value;
    if (!value.isInitialized) return;

    final duration = value.duration;
    final position = value.position;

    if (duration > Duration.zero && duration.inMilliseconds > 0) {
      final fraction =
      (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
      if ((_progressController.value - fraction).abs() > 0.01) {
        _progressController.value = fraction;
      }
    }

    final reachedEnd = duration > Duration.zero &&
        position >= duration &&
        value.isInitialized &&
        !value.isPlaying;

    if (reachedEnd && !_isNavigating) {
      unawaited(_goNext());
    }
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    _videoController = null;

    if (controller == null) return;

    try {
      controller.removeListener(_videoListener);
    } catch (e) {
      debugPrint('Story viewer error: $e');
    }

    try {
      await controller.pause();
    } catch (e) {
      debugPrint('Story viewer error: $e');
    }

    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('Story viewer error: $e');
    }
  }

  void _pauseStory() {
    if (_holding || !_hasStories) return;

    _holding = true;
    _progressController.stop();

    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      controller.pause();
    }

    if (_canUseState) setState(() {});
  }

  void _resumeStory() {
    if (!_holding || !_hasStories) return;

    _holding = false;

    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      controller.play();
    }

    if (_progressController.duration != null) {
      _progressController.forward();
    }

    if (_canUseState) setState(() {});
  }

  Future<void> _jumpToStory(int index) async {
    if (!_hasStories || _isNavigating) return;
    if (index < 0 || index >= _stories.length) return;
    if (index == _currentIndex) return;

    _isNavigating = true;
    try {
      if (!_canUseState) return;

      setState(() {
        _currentIndex = index;
      });

      await _prepareCurrentStory();
      _syncHintAnimation();
      unawaited(_markCurrentSeen());
      unawaited(_primeViewerMetaForCurrentStory());
    } finally {
      _isNavigating = false;
    }
  }

  Future<void> _goPrevious() async {
    if (!_hasStories || _isNavigating) return;
    _isNavigating = true;

    try {
      if (_currentIndex <= 0) {
        await _closeViewer();
        return;
      }

      if (!_canUseState) return;

      setState(() {
        _currentIndex--;
      });

      await _prepareCurrentStory();
      _syncHintAnimation();
      unawaited(_markCurrentSeen());
      unawaited(_primeViewerMetaForCurrentStory());
    } finally {
      _isNavigating = false;
    }
  }

  Future<void> _goNext() async {
    if (!_hasStories || _isNavigating) return;
    _isNavigating = true;

    try {
      if (_currentIndex >= _stories.length - 1) {
        await _closeViewer();
        return;
      }

      if (!_canUseState) return;

      setState(() {
        _currentIndex++;
      });

      await _prepareCurrentStory();
      _syncHintAnimation();
      unawaited(_markCurrentSeen());
      unawaited(_primeViewerMetaForCurrentStory());
    } finally {
      _isNavigating = false;
    }
  }

  Future<void> _deleteCurrentStory() async {
    if (_deleting || !_isMine || !_hasStories) return;

    _dismissKeyboard();
    _pauseStory();

    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);

        return AlertDialog(
          backgroundColor: kSurfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          title: Text(
            l10n.storyViewerDeleteTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            l10n.storyViewerDeleteMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.55,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.storyViewerCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kErrorColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.storyViewerDeleteAction),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      _resumeStory();
      return;
    }

    if (!_canUseState) return;
    setState(() => _deleting = true);

    try {
      final story = _currentStory;
      await _repo.deleteStory(story);

      if (!_canUseState) return;

      _stories.removeAt(_clampIndex(_currentIndex, _stories.length));

      if (_stories.isEmpty) {
        await _closeViewer(true);
        return;
      }

      _currentIndex = _clampIndex(_currentIndex, _stories.length);

      setState(() {});
      _syncHintAnimation();
      await _prepareCurrentStory();

      if (!_canUseState) return;
      messenger.showSnackBar(
        _buildSnackBar(l10n.storyViewerDeleted),
      );
    } catch (_) {
      if (!_canUseState) return;
      messenger.showSnackBar(
        _buildSnackBar(l10n.storyViewerDeleteFailed),
      );
      if (_canUseState) {
        _resumeStory();
      }
    } finally {
      if (_canUseState) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _showViewersSheet() async {
    if (!_isMine || !_hasStories) return;

    _dismissKeyboard();

    final story = _currentStory;
    final viewerIds = story.viewerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // capture before async gaps
    final sheetContext = context;
    final theme = Theme.of(sheetContext);
    final mediaQuery = MediaQuery.of(sheetContext);
    final navigator = Navigator.of(sheetContext);

    if (_canUseState) {
      setState(() => _loadingViewerSheet = true);
    }

    await _primeViewerMeta(viewerIds);
    if (!_canUseState) return;

    final viewedAtByUser = viewerIds.isEmpty
        ? const <String, DateTime>{}
        : await _loadViewerTimesForStory(story.id);

    if (!_canUseState) return;
    setState(() => _loadingViewerSheet = false);

    final sortedViewerIds = [...viewerIds];
    sortedViewerIds.sort((a, b) {
      final bTime = viewedAtByUser[b];
      final aTime = viewedAtByUser[a];
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    _pauseStory();
    await showModalBottomSheet<void>(
      context: sheetContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.96, end: 1.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, (1 - value) * 40),
              child: Opacity(
                opacity: ((value - 0.96) / 0.04).clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: SafeArea(
            top: false,
            child: FractionallySizedBox(
              heightFactor: 0.76,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _mwGlassStrong(0.94),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                      border: Border.all(color: _mwBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 28,
                          offset: const Offset(0, -8),
                        ),
                        BoxShadow(
                          color: kGoldDeep.withValues(alpha: 0.04),
                          blurRadius: 22,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _mwGlass(0.86),
                                  border: Border.all(
                                    color: kPrimaryGold.withValues(alpha: 0.26),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kGoldDeep.withValues(alpha: 0.10),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.remove_red_eye_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compact = constraints.maxWidth < 220;

                                    return MediaQuery(
                                      data: mediaQuery.copyWith(
                                        textScaler: mediaQuery.textScaler.clamp(
                                          minScaleFactor: 0.9,
                                          maxScaleFactor: 1.0,
                                        ),
                                      ),
                                      child: sortedViewerIds.isEmpty
                                          ? Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            l10n.storyViewerNoViewsYet,
                                            maxLines: 1,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style: theme
                                                .textTheme.titleLarge
                                                ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: compact ? 20 : null,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            l10n.storyViewerStoryCounter(
                                              _currentIndex + 1,
                                              _stories.length,
                                            ),
                                            maxLines: 1,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.white60,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            l10n.storyViewerPeopleAppearHere,
                                            maxLines: 1,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.white38,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      )
                                          : Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            l10n.storyViewerViewsCount(
                                              story.viewerCount,
                                            ),
                                            maxLines: 1,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style: theme
                                                .textTheme.titleLarge
                                                ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: compact ? 20 : null,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            l10n.storyViewerStoryCounter(
                                              _currentIndex + 1,
                                              _stories.length,
                                            ),
                                            maxLines: 1,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.white60,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            l10n.storyViewerTotals(
                                              _totalGroupViews,
                                              _uniqueGroupViewerCount,
                                            ),
                                            maxLines: 1,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.white38,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              IconButton(
                                onPressed: () => navigator.pop(),
                                icon: const Icon(Icons.close_rounded),
                                color: Colors.white70,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0x1FFFFFFF)),
                        Expanded(
                          child: sortedViewerIds.isEmpty
                              ? _buildEmptyViewersState()
                              : ListView.separated(
                            padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: sortedViewerIds.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final userId = sortedViewerIds[index];
                              final meta = _viewerMetaCache[userId];
                              final viewedAt = viewedAtByUser[userId];

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    navigator.pop();
                                  },
                                  borderRadius:
                                  BorderRadius.circular(18),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.045,
                                      ),
                                      borderRadius:
                                      BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.06,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding:
                                          const EdgeInsets.all(1.5),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: [
                                                kPrimaryGold.withValues(
                                                  alpha: 0.95,
                                                ),
                                                Colors.white.withValues(
                                                  alpha: 0.28,
                                                ),
                                              ],
                                              begin: Alignment.topLeft,
                                              end:
                                              Alignment.bottomRight,
                                            ),
                                          ),
                                          child: MwAvatar(
                                            avatarType: 'bear',
                                            profileUrl: meta?.imageUrl,
                                            radius: 22,
                                            backgroundColor: kSurfaceAltColor,

                                            initials: meta?.displayName.isNotEmpty == true
                                                ? meta!.displayName.substring(0, 1).toUpperCase()
                                                : null,

                                            hasStory: false,
                                            showStoryGlow: false,

                                            showRing: false,
                                            showOnlineDot: false,
                                            showOnlineGlow: false,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder:
                                                (context, constraints) {
                                              final compact =
                                                  constraints.maxWidth <
                                                      220;

                                              return meta == null
                                                  ? Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                                mainAxisSize:
                                                MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: compact
                                                        ? 90
                                                        : 120,
                                                    height: 14,
                                                    decoration:
                                                    BoxDecoration(
                                                      color: Colors
                                                          .white
                                                          .withValues(
                                                        alpha: 0.08,
                                                      ),
                                                      borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                        999,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    height: 8,
                                                  ),
                                                  Container(
                                                    width: compact
                                                        ? 72
                                                        : 92,
                                                    height: 11,
                                                    decoration:
                                                    BoxDecoration(
                                                      color: Colors
                                                          .white
                                                          .withValues(
                                                        alpha: 0.05,
                                                      ),
                                                      borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                        999,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                                  : Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                                mainAxisSize:
                                                MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    meta.displayName,
                                                    maxLines: 1,
                                                    overflow:
                                                    TextOverflow
                                                        .ellipsis,
                                                    softWrap: false,
                                                    style: theme
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                      color: Colors
                                                          .white,
                                                      fontWeight:
                                                      FontWeight
                                                          .w800,
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    height: 3,
                                                  ),
                                                  Text(
                                                    meta
                                                        .subtitleWithViewedAt(
                                                      viewedAt,
                                                      formatter:
                                                      _timeAgoFromNow,
                                                      viewedYourStoryLabel:
                                                      l10n.storyViewerViewedYourStory,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                    TextOverflow
                                                        .ellipsis,
                                                    softWrap: false,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                      color: Colors
                                                          .white60,
                                                      fontWeight:
                                                      FontWeight
                                                          .w500,
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                              horizontal: 10,
                                              vertical: 7,
                                            ),
                                            decoration: BoxDecoration(
                                              color: kPrimaryGold
                                                  .withValues(
                                                alpha: 0.08,
                                              ),
                                              borderRadius:
                                              BorderRadius.circular(
                                                999,
                                              ),
                                              border: Border.all(
                                                color: kPrimaryGold
                                                    .withValues(
                                                  alpha: 0.25,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              viewedAt != null
                                                  ? _timeAgoFromNow(
                                                  viewedAt)
                                                  : l10n.storyViewerViewed,
                                              maxLines: 1,
                                              overflow:
                                              TextOverflow.ellipsis,
                                              softWrap: false,
                                              style: theme
                                                  .textTheme.labelMedium
                                                  ?.copyWith(
                                                color: kPrimaryGold,
                                                fontWeight:
                                                FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (_canUseState) {
      _resumeStory();
    }
  }

  Widget _buildEmptyViewersState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.of(context).textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Icon(
                  Icons.visibility_off_outlined,
                  color: Colors.white38,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.storyViewerNoViewsYet,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.storyViewerNameWillAppearHere,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white54,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, DateTime>> _loadViewerTimesForStory(String storyId) async {
    try {
      final snap =
      await FirebaseFirestore.instance.collection('stories').doc(storyId).get();

      final data = snap.data() ?? const <String, dynamic>{};

      final raw = data['viewerTimestamps'] ?? data['viewedAt'];
      if (raw is! Map) return const <String, DateTime>{};

      final result = <String, DateTime>{};

      raw.forEach((key, value) {
        final userId = key.toString().trim();
        if (userId.isEmpty) return;

        DateTime? dt;
        if (value is Timestamp) {
          dt = value.toDate();
        } else if (value is DateTime) {
          dt = value;
        }

        if (dt != null) {
          result[userId] = dt;
        }
      });

      return result;
    } catch (_) {
      return const <String, DateTime>{};
    }
  }

  String _timeAgoFromNow(DateTime? value) {
    if (value == null) return l10n.storyViewerViewed;

    final now = DateTime.now();
    final diff = now.difference(value);

    if (diff.inSeconds < 30) return l10n.storyViewerTimeNow;
    if (diff.inMinutes < 60) return l10n.storyViewerMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.storyViewerHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.storyViewerDaysAgo(diff.inDays);
    return '${value.month}/${value.day}/${value.year}';
  }

  SnackBar _buildSnackBar(String text) {
    return SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSurfaceAltColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Future<void> _openLink(String? raw) async {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return;

    final parsed = Uri.tryParse(value);
    final normalized = (parsed != null && parsed.hasScheme)
        ? value
        : 'https://$value';

    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    if (!(uri.scheme == 'https' || uri.scheme == 'http')) return;

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (e) {
      debugPrint('Story viewer error: $e');
    }
  }

  Color _hexToColor(String? hex, {Color fallback = Colors.white}) {
    final value = (hex ?? '').trim();
    if (value.isEmpty) return fallback;

    var raw = value.replaceFirst('#', '');
    if (raw.length == 6) raw = 'FF$raw';

    try {
      return Color(int.parse(raw, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  String? _firstUrlFromText(String? text) {
    final value = (text ?? '').trim();
    if (value.isEmpty) return null;

    final match = RegExp(
      r'((https?:\/\/)?([a-zA-Z0-9\-]+\.)+[a-zA-Z]{2,}([\/\w\-.?=&%#]*)?)',
    ).firstMatch(value);

    return match?.group(0);
  }

  String? _storyLink(StoryModel story) {
    final direct = (story.linkUrl ?? '').trim();
    if (direct.isNotEmpty) return direct;
    return _firstUrlFromText(story.text);
  }

  String _timeAgo(DateTime? value) {
    if (value == null) return '';

    final now = DateTime.now();
    final diff = now.difference(value);

    if (diff.inSeconds < 60) return l10n.storyViewerJustNow;
    if (diff.inMinutes < 60) return l10n.storyViewerMinutesShort(diff.inMinutes);
    if (diff.inHours < 24) return l10n.storyViewerHoursShort(diff.inHours);
    if (diff.inDays < 7) return l10n.storyViewerDaysShort(diff.inDays);
    return '${value.month}/${value.day}/${value.year}';
  }

  double _textFontSize(String text, double width) {
    final trimmed = text.trim();
    final length = trimmed.length;
    final lineCount = '\n'.allMatches(trimmed).length + 1;

    double size;

    if (width >= 1100) {
      if (length <= 18) {
        size = 52;
      } else if (length <= 45) {
        size = 42;
      } else if (length <= 100) {
        size = 34;
      } else {
        size = 28;
      }
    } else if (width >= 700) {
      if (length <= 18) {
        size = 44;
      } else if (length <= 45) {
        size = 36;
      } else if (length <= 100) {
        size = 29;
      } else {
        size = 24;
      }
    } else {
      if (length <= 18) {
        size = 30;
      } else if (length <= 45) {
        size = 25;
      } else if (length <= 100) {
        size = 21;
      } else {
        size = 18;
      }
    }

    if (lineCount >= 3) size -= 1.5;
    if (lineCount >= 5) size -= 1.5;

    return size.clamp(18.0, 52.0);
  }

  Widget _buildProgressBars() {
    return Row(
      children: List.generate(_stories.length, (index) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: index == _stories.length - 1 ? 0 : 5,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                if (index == _currentIndex) {
                  unawaited(_goNext());
                  return;
                }
                unawaited(_jumpToStory(index));
              },
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                clipBehavior: Clip.antiAlias,
                child: AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, _) {
                    double value;
                    if (index < _currentIndex) {
                      value = 1;
                    } else if (index > _currentIndex) {
                      value = 0;
                    } else {
                      value = _progressController.value.clamp(0.0, 1.0);
                    }

                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: value,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                kPrimaryGold,
                                kGoldDeep.withValues(alpha: 0.95),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: kGoldDeep.withValues(alpha: 0.20),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildViewsChip(StoryModel story, ThemeData theme) {
    final isEmpty = story.viewerIds.isEmpty;
    final text = l10n.storyViewerViewsCount(story.viewerCount);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (_loadingViewerSheet || isEmpty) ? null : _showViewersSheet,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadingViewerSheet)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  Icons.remove_red_eye_outlined,
                  size: 16,
                  color: isEmpty ? Colors.white54 : Colors.white,
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isEmpty ? Colors.white60 : Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerSwipeUpHint() {
    if (!_isMine || !_hasStories) return const SizedBox.shrink();

    final story = _currentStoryOrNull;
    if (story == null) return const SizedBox.shrink();

    final canOpen = story.viewerIds.isNotEmpty;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 14,
      child: SafeArea(
        top: false,
        child: IgnorePointer(
          ignoring: !canOpen,
          child: Center(
            child: GestureDetector(
              onVerticalDragEnd: canOpen
                  ? (details) {
                if ((details.primaryVelocity ?? 0) < -120) {
                  unawaited(_showViewersSheet());
                }
              }
                  : null,
              onTap: canOpen ? _showViewersSheet : null,
              child: AnimatedBuilder(
                animation: _hintController,
                builder: (context, child) {
                  final t = Curves.easeInOut.transform(_hintController.value);
                  final offset = lerpDouble(0, -6, t) ?? 0;
                  final opacity = canOpen ? (0.85 + (t * 0.15)) : 0.72;

                  return Transform.translate(
                    offset: Offset(0, offset),
                    child: Opacity(
                      opacity: opacity,
                      child: child,
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _mwGlassStrong(0.82),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _mwBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: kGoldDeep.withValues(alpha: 0.05),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: canOpen ? kPrimaryGold : Colors.white54,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              canOpen
                                  ? l10n.storyViewerSwipeUpToSeeViewers
                                  : l10n.storyViewerNoViewsYet,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final story = _currentStory;
    final title = (widget.ownerDisplayName ?? '').trim().isEmpty
        ? l10n.storyViewerFallbackTitle
        : widget.ownerDisplayName!.trim();

    final headerInitials = title.isNotEmpty
        ? title
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .take(2)
        .map((e) => e.characters.first.toUpperCase())
        .join()
        : null;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgressBars(),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: _mwPanelDecoration(
                    radius: 26,
                    alpha: 0.78,
                    warm: true,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: kGoldDeep.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(1.6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              kPrimaryGold.withValues(alpha: 0.95),
                              Colors.white.withValues(alpha: 0.28),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: MwAvatar(
                          avatarType: 'bear',
                          profileUrl: widget.ownerImageUrl,
                          radius: 18,
                          backgroundColor: kSurfaceAltColor,
                          initials: headerInitials,

                          // ✅ clean mode for viewer header
                          hasStory: false,
                          showStoryGlow: false,
                          showStoryRing: false,

                          showRing: false,
                          showOnlineDot: false,
                          showOnlineGlow: false,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 250;

                            return MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                textScaler: MediaQuery.of(context)
                                    .textScaler
                                    .clamp(
                                  minScaleFactor: 0.9,
                                  maxScaleFactor: 1.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: compact ? 18 : 22,
                                      height: 1.05,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_timeAgo(story.createdAt)} • ${_currentIndex + 1}/${_stories.length}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white.withValues(alpha: 0.78),
                                      fontWeight: FontWeight.w500,
                                      fontSize: compact ? 12 : 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (_isMine) ...[
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 118),
                          child: _buildViewsChip(story, theme),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_isMine)
                        _TopIconButton(
                          tooltip: l10n.storyViewerDeleteTooltip,
                          onTap: _deleting ? null : _deleteCurrentStory,
                          child: _deleting
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.1,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      const SizedBox(width: 6),
                      _TopIconButton(
                        tooltip: l10n.storyViewerCloseTooltip,
                        onTap: () => _closeViewer(),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkButton(
      StoryModel story, {
        Color? foregroundColor,
        bool compact = false,
      }) {
    final link = _storyLink(story);
    if ((link ?? '').trim().isEmpty) return const SizedBox.shrink();

    final fg = foregroundColor ?? Colors.white;

    return Padding(
      padding: EdgeInsets.only(top: compact ? 12 : 18),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openLink(link),
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 18,
                vertical: compact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: _mwGlassStrong(compact ? 0.72 : 0.78),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: fg.withValues(alpha: 0.18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: kGoldDeep.withValues(alpha: compact ? 0.03 : 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new_rounded, color: fg, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.storyViewerOpenLink,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextStory(StoryModel story) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final bg = _hexToColor(
      story.backgroundColor,
      fallback: const Color(0xFF151A2B),
    );
    final fg = _hexToColor(story.textColor, fallback: Colors.white);
    final text = (story.text ?? '').trim();
    final fontSize = _textFontSize(text, width);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.18),
          radius: 1.18,
          colors: [
            Color.lerp(bg, Colors.white, 0.08) ?? bg,
            bg,
            Color.lerp(bg, Colors.black, 0.30) ?? bg,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _mwTopFade,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 126, 22, 92),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: MediaQuery.of(context).textScaler.clamp(
                        minScaleFactor: 0.9,
                        maxScaleFactor: 1.15,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: width >= 700 ? 34 : 22,
                            vertical: width >= 700 ? 34 : 24,
                          ),
                          decoration: BoxDecoration(
                            color: _mwGlassStrong(0.58),
                            borderRadius: BorderRadius.circular(36),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.07),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: kGoldDeep.withValues(alpha: 0.035),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                text.isEmpty ? l10n.storyViewerFallbackTitle : text,
                                textAlign: TextAlign.center,
                                maxLines: 9,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w700,
                                  fontSize: fontSize,
                                  height: 1.24,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.22),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              _buildLinkButton(
                                story,
                                foregroundColor: fg,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCaption(StoryModel story) {
    final theme = Theme.of(context);
    final caption = (story.text ?? '').trim();

    if (caption.isEmpty && (_storyLink(story) ?? '').trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 54, 16, 26),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.82),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: MediaQuery.of(context).textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (caption.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Text(
                            caption,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 15.5,
                              height: 1.52,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  _buildLinkButton(story, compact: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageStory(StoryModel story) {
    final url = (story.mediaUrl ?? '').trim();

    if (url.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 56),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMediaStage(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 56,
                    ),
                  );
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: kPrimaryGold),
                  );
                },
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: _mwScreenOverlay,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildBottomCaption(story),
      ],
    );
  }

  Widget _buildVideoStory(StoryModel story) {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildMediaStage(
            child: const Center(
              child: CircularProgressIndicator(color: kPrimaryGold),
            ),
          ),
          _buildBottomCaption(story),
        ],
      );
    }

    final videoSize = controller.value.size;
    final safeWidth = videoSize.width <= 0 ? 1.0 : videoSize.width;
    final safeHeight = videoSize.height <= 0 ? 1.0 : videoSize.height;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMediaStage(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: safeWidth,
                    height: safeHeight,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: _mwScreenOverlay,
                    ),
                  ),
                ),
              ),
              if (!_videoReady)
                const Center(
                  child: CircularProgressIndicator(color: kPrimaryGold),
                ),
              if (_holding)
                Center(
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.54),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: const Icon(
                      Icons.pause_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _buildBottomCaption(story),
      ],
    );
  }

  Widget _buildStoryBody() {
    final story = _currentStory;

    if (story.isText) return _buildTextStory(story);
    if (story.isImage) return _buildImageStory(story);
    if (story.isVideo) return _buildVideoStory(story);

    return const Center(
      child: Icon(Icons.error_outline, color: Colors.white, size: 56),
    );
  }

  Widget _buildTapZones() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        onHorizontalDragStart: (_) => _dismissKeyboard(),
        onVerticalDragStart: (_) => _dismissKeyboard(),
        onHorizontalDragEnd: (details) {
          _dismissKeyboard();

          final velocity = details.primaryVelocity ?? 0;

          if (velocity < -200) {
            HapticFeedback.lightImpact();
            unawaited(_goNext());
          } else if (velocity > 200) {
            HapticFeedback.lightImpact();
            unawaited(_goPrevious());
          }
        },
        onLongPressStart: (_) {
          _dismissKeyboard();
          _pauseStory();
        },
        onLongPressEnd: (_) => _resumeStory(),
        onVerticalDragEnd: (details) {
          _dismissKeyboard();

          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 260) {
            unawaited(_closeViewer());
            return;
          }
          if (_isMine && velocity < -260) {
            unawaited(_showViewersSheet());
          }
        },
        child: Column(
          children: [
            const SizedBox(height: 112),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 110),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _dismissKeyboard();
                          HapticFeedback.lightImpact();
                          unawaited(_goPrevious());
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _dismissKeyboard,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _dismissKeyboard();
                          HapticFeedback.lightImpact();
                          unawaited(_goNext());
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stories.isEmpty) {
      return const Scaffold(
        backgroundColor: kBgColor,
        resizeToAvoidBottomInset: false,
        body: Center(
          child: CircularProgressIndicator(color: kPrimaryGold),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kBgColor,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissKeyboard,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1.0).animate(animation),
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_currentStory.id),
                child: _buildStoryBody(),
              ),
            ),
            _buildTapZones(),
            _buildHeader(),
            _buildOwnerSwipeUpHint(),
          ],
        ),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.child,
    this.onTap,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.white.withValues(alpha: 0.10),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

    if ((tooltip ?? '').isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ViewerMeta {
  const _ViewerMeta({
    required this.userId,
    required this.displayName,
    this.username,
    this.imageUrl,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? imageUrl;

  String subtitleWithViewedAt(
      DateTime? viewedAt, {
        required String Function(DateTime?) formatter,
        required String viewedYourStoryLabel,
      }) {
    final base = (username != null && username!.trim().isNotEmpty)
        ? '@${username!.trim()}'
        : viewedYourStoryLabel;

    if (viewedAt == null) return base;
    return '$base • ${formatter(viewedAt)}';
  }
}