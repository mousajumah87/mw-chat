// lib/widgets/ui/mw_avatar.dart

import 'dart:collection';
import 'dart:math' as math;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

/// MW Avatar (single pattern everywhere):
/// - Network profile photo if allowed + available
/// - Fallback to initials when provided
/// - Fallback to local asset (bear/girl)
/// - Fallback to icon if asset missing
/// - Optional gold ring, story ring/glow, online glow + dot, Hero animation
/// - Optional cache control via URL cache-busting and custom headers
///
/// ✅ BEST PRACTICE (iOS/Android/Web):
/// - If profileUrl is already a direct media URL (contains `alt=media`), display it directly.
/// - Only call Firebase Storage getDownloadURL() when input is a storage path, gs://
///   or a Firebase URL that is NOT already a direct media URL.
class MwAvatar extends StatefulWidget {
  const MwAvatar({
    super.key,
    required this.avatarType,
    this.profileUrl,
    this.hideRealAvatar = false,
    this.radius = 18,
    this.backgroundColor,

    /// Optional initials fallback, like "MA" or "YD".
    /// Used when network image is unavailable or hidden.
    this.initials,

    // ===== Story UX =====
    this.hasStory = false,
    this.isOwnStory = false,
    this.storySeen = false,
    this.showStoryGlow = true,
    this.storyGlowColor,
    this.storyGlowBlur = 12,
    this.storyGlowSpread = 1.0,

    /// v2 polish:
    this.showStoryRing = true,
    this.useGradientStoryRing = true,
    this.dimSeenStoryRing = true,
    this.showStoryInnerStroke = true,
    this.storyRingWidth,
    this.storyGradientColors,

    // ===== Ring + Online UX =====
    this.showRing = false,
    this.ringColor,
    this.ringWidth = 2.0,
    this.isOnline = false,
    this.showOnlineGlow = true,
    this.onlineGlowColor,
    this.onlineGlowBlur = 10,
    this.showOnlineDot = true,
    this.onlineDotColor,
    this.offlineDotColor,
    this.dotSize = 11,
    this.dotBorderWidth = 2,

    // ===== Hero =====
    this.heroTag,

    // ===== Cache control =====
    this.cachePolicy = MwAvatarCachePolicy.normal,
    this.cacheBustKey,
    this.networkHeaders,
  });

  /// Accepts:
  /// - "bear"
  /// - "girl" (preferred)
  /// - legacy: "smurf" (kept only for backwards compatibility)
  final String avatarType;

  /// Real profile photo reference (supports):
  /// - direct download url (alt=media&token=...)
  /// - gs:// bucket ref
  /// - Firebase REST url (may or may not include alt=media)
  /// - storage path like: profile_pics/<uid>.jpg
  final String? profileUrl;

  /// If true, never show profileUrl even if exists
  final bool hideRealAvatar;

  final double radius;
  final Color? backgroundColor;

  /// Optional initials fallback when real avatar is not available.
  final String? initials;

  // ===== Story UX =====

  /// Whether this avatar represents a user/story with an active story.
  final bool hasStory;

  /// Stronger highlight for "Your Story".
  final bool isOwnStory;

  /// Seen story styling can be dimmed.
  final bool storySeen;

  /// Enables soft outer glow for story state.
  final bool showStoryGlow;

  /// Optional story glow color override.
  final Color? storyGlowColor;

  /// Blur radius for story glow.
  final double storyGlowBlur;

  /// Spread for story glow.
  final double storyGlowSpread;

  /// Whether to draw a dedicated story ring.
  final bool showStoryRing;

  /// Enables warm gold gradient ring for active story state.
  final bool useGradientStoryRing;

  /// Dims seen stories for a cleaner, calmer look.
  final bool dimSeenStoryRing;

  /// Adds a subtle inner white stroke between ring and avatar content.
  final bool showStoryInnerStroke;

  /// Optional story ring width override.
  final double? storyRingWidth;

  /// Optional gradient colors override for story ring.
  final List<Color>? storyGradientColors;

  // ===== Ring + online glow + dot =====
  final bool showRing;
  final Color? ringColor;
  final double ringWidth;

  /// Online state for dot/glow (does NOT affect which avatar is shown)
  final bool isOnline;

  final bool showOnlineGlow;
  final Color? onlineGlowColor;
  final double onlineGlowBlur;

  final bool showOnlineDot;
  final Color? onlineDotColor;
  final Color? offlineDotColor;
  final double dotSize;
  final double dotBorderWidth;

  // ===== Hero =====
  final Object? heroTag;

  // ===== Cache control =====
  final MwAvatarCachePolicy cachePolicy;
  final String? cacheBustKey;
  final Map<String, String>? networkHeaders;

  @override
  State<MwAvatar> createState() => _MwAvatarState();
}

enum MwAvatarCachePolicy {
  normal,
  refresh,
  noCache,
}

class _MwAvatarState extends State<MwAvatar> {
  static const String _bearAsset = 'assets/images/bear.png';
  static const String _girlAsset = 'assets/images/smurf.png';

  static const Color _defaultGold = Color(0xFFD6B25E);
  static const Color _defaultGoldDeep = Color(0xFFB88A2E);
  static const Color _defaultGoldLight = Color(0xFFFFE29A);

  /// Cache resolved download URLs for Firebase refs/paths
  static final _downloadUrlCache = _LruStringCache(maxEntries: 250);

  Future<String?>? _resolvedUrlFuture;
  String? _resolvedKey;

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  bool _isGirlType(String? raw) {
    final t = _norm(raw);
    if (t.isEmpty) return false;
    return t == 'girl' ||
        t == 'smurf' ||
        t == 'female' ||
        t == 'woman' ||
        t == 'f';
  }

  String get _assetPath =>
      _isGirlType(widget.avatarType) ? _girlAsset : _bearAsset;
  bool get _isGirl => _isGirlType(widget.avatarType);

  String? _effectiveRaw(MwAvatar w) {
    if (w.hideRealAvatar) return null;
    final v = w.profileUrl?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  bool _isHttpUrl(String raw) =>
      raw.startsWith('http://') || raw.startsWith('https://');

  bool _isGsUrl(String raw) => raw.startsWith('gs://');

  /// Direct media URL => show as-is (NO resolving).
  bool _isDirectMediaUrl(String raw) {
    final u = raw.trim();
    if (!_isHttpUrl(u)) return false;
    return u.contains('alt=media');
  }

  /// Storage path (e.g., "profile_pics/uid.jpg")
  bool _looksLikeStoragePath(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return false;
    if (_isHttpUrl(u) || _isGsUrl(u)) return false;
    return u.contains('/');
  }

  /// Firebase REST URL that is not direct media (missing alt=media)
  bool _isFirebaseRestUrlNeedingResolve(String raw) {
    final u = raw.trim();
    if (!_isHttpUrl(u)) return false;
    if (!u.contains('firebasestorage')) return false;
    return !_isDirectMediaUrl(u);
  }

  String _applyCachePolicyToUrl(String url) {
    final policy = widget.cachePolicy;
    if (policy == MwAvatarCachePolicy.normal) return url;

    if (policy == MwAvatarCachePolicy.refresh) {
      final key = widget.cacheBustKey?.trim();
      if (key == null || key.isEmpty) return url;
      final sep = url.contains('?') ? '&' : '?';
      return '$url${sep}v=$key';
    }

    return url;
  }

  Map<String, String>? _headersForPolicy() {
    if (widget.cachePolicy != MwAvatarCachePolicy.noCache) {
      return widget.networkHeaders;
    }

    final merged = <String, String>{};
    if (widget.networkHeaders != null) merged.addAll(widget.networkHeaders!);

    merged.putIfAbsent(
      'Cache-Control',
          () => 'no-cache, no-store, must-revalidate',
    );
    merged.putIfAbsent('Pragma', () => 'no-cache');
    merged.putIfAbsent('Expires', () => '0');
    return merged;
  }

  Future<String?> _resolveToRenderableUrl(String raw) async {
    final trimmed = raw.trim();

    if (_isDirectMediaUrl(trimmed)) {
      return _applyCachePolicyToUrl(trimmed);
    }

    if (_isHttpUrl(trimmed) && !trimmed.contains('firebasestorage')) {
      return _applyCachePolicyToUrl(trimmed);
    }

    final cached = _downloadUrlCache.get(trimmed);
    if (cached != null && cached.isNotEmpty) {
      return _applyCachePolicyToUrl(cached);
    }

    try {
      Reference ref;

      if (_looksLikeStoragePath(trimmed)) {
        ref = FirebaseStorage.instance.ref().child(trimmed);
      } else if (_isGsUrl(trimmed) || _isFirebaseRestUrlNeedingResolve(trimmed)) {
        ref = FirebaseStorage.instance.refFromURL(trimmed);
      } else if (_isHttpUrl(trimmed)) {
        return _applyCachePolicyToUrl(trimmed);
      } else {
        return null;
      }

      final downloadUrl = await ref.getDownloadURL();
      if (downloadUrl.trim().isNotEmpty) {
        _downloadUrlCache.put(trimmed, downloadUrl);
        return _applyCachePolicyToUrl(downloadUrl);
      }
      return null;
    } catch (e) {
      debugPrint('MwAvatar resolveToDownloadUrl error: $e');
      return null;
    }
  }

  void _prepareMemoized() {
    final raw = _effectiveRaw(widget);

    if (raw == null) {
      _resolvedUrlFuture = null;
      _resolvedKey = null;
      return;
    }

    final key =
        '${raw.trim()}|${widget.cachePolicy.name}|${widget.cacheBustKey ?? ''}';
    if (_resolvedKey == key) return;

    _resolvedKey = key;
    _resolvedUrlFuture = _resolveToRenderableUrl(raw.trim());
  }

  @override
  void initState() {
    super.initState();
    _prepareMemoized();
  }

  @override
  void didUpdateWidget(covariant MwAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldRaw = _effectiveRaw(oldWidget);
    final newRaw = _effectiveRaw(widget);

    final policyChanged = oldWidget.cachePolicy != widget.cachePolicy ||
        oldWidget.cacheBustKey != widget.cacheBustKey ||
        !_mapEquals(oldWidget.networkHeaders, widget.networkHeaders);

    if (oldRaw != newRaw ||
        policyChanged ||
        oldWidget.hideRealAvatar != widget.hideRealAvatar) {
      _prepareMemoized();
    }
  }

  bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  List<Color> _resolvedStoryGradientColors(Color fallbackRingColor) {
    final custom = widget.storyGradientColors;
    if (custom != null && custom.length >= 2) {
      return custom;
    }

    if (widget.storySeen && widget.dimSeenStoryRing) {
      return <Color>[
        Colors.white.withValues(alpha: 0.24),
        Colors.white.withValues(alpha: 0.18),
        fallbackRingColor.withValues(alpha: 0.18),
      ];
    }

    return <Color>[
      _defaultGold,
      _defaultGoldDeep,
      _defaultGoldLight,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? Colors.white10;
    final size = widget.radius * 2;

    Widget buildFallbackIcon() {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isGirl ? Icons.face_retouching_natural : Icons.pets,
          size: widget.radius,
          color: Colors.white70,
        ),
      );
    }

    Widget buildInitialsAvatar() {
      final text = (widget.initials ?? '').trim();
      if (text.isEmpty) {
        return buildFallbackIcon();
      }

      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: math.max(4, widget.radius * 0.18)),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: widget.radius * 0.72,
                height: 1,
              ),
            ),
          ),
        ),
      );
    }

    Widget buildAssetAvatar() {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.asset(
            _assetPath,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => buildFallbackIcon(),
          ),
        ),
      );
    }

    Widget buildDefaultFallbackAvatar() {
      final hasInitials = (widget.initials ?? '').trim().isNotEmpty;
      return hasInitials ? buildInitialsAvatar() : buildAssetAvatar();
    }

    Widget buildLoadingStack() {
      return Stack(
        fit: StackFit.expand,
        children: [
          buildDefaultFallbackAvatar(),
          Center(
            child: SizedBox(
              width: widget.radius * 0.9,
              height: widget.radius * 0.9,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      );
    }

    Widget buildNetworkAvatar(String url) {
      final headers = _headersForPolicy();
      final resolved = _applyCachePolicyToUrl(url);

      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            resolved,
            headers: headers,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return buildLoadingStack();
            },
            errorBuilder: (_, __, ___) => buildDefaultFallbackAvatar(),
          ),
        ),
      );
    }

    final raw = _effectiveRaw(widget);

    final Widget innerAvatar;
    if (raw == null) {
      innerAvatar = buildDefaultFallbackAvatar();
    } else {
      innerAvatar = FutureBuilder<String?>(
        future: _resolvedUrlFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return ClipOval(
              child: SizedBox(
                width: size,
                height: size,
                child: buildLoadingStack(),
              ),
            );
          }

          final resolvedUrl = (snap.data ?? '').trim();
          if (resolvedUrl.isEmpty) return buildDefaultFallbackAvatar();
          return buildNetworkAvatar(resolvedUrl);
        },
      );
    }

    final resolvedRingColor = widget.ringColor ?? _defaultGold;
    final resolvedGlowColor =
        widget.onlineGlowColor ?? Colors.greenAccent.withValues(alpha: 0.55);

    final resolvedStoryGlowColor = widget.storyGlowColor ??
        (widget.storySeen
            ? resolvedRingColor.withValues(alpha: widget.dimSeenStoryRing ? 0.10 : 0.16)
            : resolvedRingColor.withValues(alpha: widget.isOwnStory ? 0.22 : 0.14));

    final bool shouldOnlineGlow = widget.isOnline && widget.showOnlineGlow;
    final bool shouldStoryGlow = widget.hasStory && widget.showStoryGlow;
    final bool shouldStoryRing = widget.hasStory && widget.showStoryRing;
    final bool shouldBaseRing = widget.showRing && !shouldStoryRing;

    final double storyRingWidth = widget.storyRingWidth ??
        (widget.isOwnStory ? math.max(2.6, widget.ringWidth) : math.max(2.2, widget.ringWidth));

    final double effectiveOuterRingWidth = shouldStoryRing
        ? storyRingWidth
        : (shouldBaseRing ? widget.ringWidth : 0);

    final double outerSize = size + (effectiveOuterRingWidth * 2);

    final double effectiveStoryGlowBlur = widget.storySeen && widget.dimSeenStoryRing
        ? math.max(0, widget.storyGlowBlur - 3)
        : (widget.isOwnStory ? widget.storyGlowBlur + 3 : widget.storyGlowBlur);

    final double effectiveStoryGlowSpread = widget.storySeen && widget.dimSeenStoryRing
        ? math.max(0, widget.storyGlowSpread - 0.5)
        : (widget.isOwnStory ? widget.storyGlowSpread + 0.6 : widget.storyGlowSpread);

    final List<Color> storyGradientColors =
    _resolvedStoryGradientColors(resolvedRingColor);

    Widget avatarWithDecor = Container(
      width: outerSize > 0 ? outerSize : size,
      height: outerSize > 0 ? outerSize : size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (shouldStoryGlow)
            BoxShadow(
              color: resolvedStoryGlowColor,
              blurRadius: effectiveStoryGlowBlur,
              spreadRadius: effectiveStoryGlowSpread,
            ),
          if (shouldOnlineGlow)
            BoxShadow(
              color: resolvedGlowColor,
              blurRadius: widget.onlineGlowBlur,
              spreadRadius: 1.4,
            ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(effectiveOuterRingWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: shouldStoryRing && widget.useGradientStoryRing
                ? LinearGradient(
              colors: storyGradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
                : null,
            color: shouldStoryRing
                ? (widget.storySeen && widget.dimSeenStoryRing
                ? Colors.white.withValues(alpha: 0.18)
                : resolvedRingColor)
                : shouldBaseRing
                ? resolvedRingColor.withValues(alpha: widget.hasStory && !widget.storySeen ? 0.26 : 0.22)
                : Colors.transparent,
            border: shouldStoryRing
                ? (!widget.useGradientStoryRing
                ? Border.all(
              color: widget.storySeen && widget.dimSeenStoryRing
                  ? Colors.white.withValues(alpha: 0.26)
                  : resolvedRingColor,
              width: storyRingWidth,
            )
                : null)
                : shouldBaseRing
                ? Border.all(
              color: resolvedRingColor,
              width: widget.ringWidth,
            )
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.showStoryInnerStroke && (shouldStoryRing || shouldBaseRing) ? 1.6 : 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: widget.showStoryInnerStroke && (shouldStoryRing || shouldBaseRing)
                    ? Border.all(
                  color: Colors.white.withValues(
                    alpha: widget.storySeen && widget.dimSeenStoryRing ? 0.08 : 0.14,
                  ),
                  width: 1.0,
                )
                    : null,
              ),
              child: ClipOval(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: innerAvatar,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.showOnlineDot) {
      final dotColor = widget.isOnline
          ? (widget.onlineDotColor ?? Colors.greenAccent)
          : (widget.offlineDotColor ?? Colors.grey);

      avatarWithDecor = Stack(
        clipBehavior: Clip.none,
        children: [
          avatarWithDecor,
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: widget.dotSize,
              height: widget.dotSize,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black,
                  width: widget.dotBorderWidth,
                ),
                boxShadow: widget.isOnline
                    ? [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.35),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ]
                    : null,
              ),
            ),
          ),
        ],
      );

      avatarWithDecor = SizedBox(
        width: outerSize,
        height: outerSize,
        child: avatarWithDecor,
      );
    }

    if (widget.heroTag != null) {
      avatarWithDecor = Hero(
        tag: widget.heroTag!,
        flightShuttleBuilder:
            (flightContext, animation, flightDirection, fromContext, toContext) {
          return ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: toContext.widget,
          );
        },
        child: avatarWithDecor,
      );
    }

    return avatarWithDecor;
  }
}

/// Tiny LRU cache for resolved strings (download urls).
class _LruStringCache {
  _LruStringCache({required this.maxEntries});

  final int maxEntries;
  final _map = LinkedHashMap<String, String>();

  String? get(String key) {
    final v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v;
    return v;
  }

  void put(String key, String value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }
}