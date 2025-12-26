// lib/widgets/ui/mw_avatar.dart

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// MW Avatar (single pattern everywhere):
/// - Network profile photo if allowed + available
/// - Fallback to local asset (bear/smurf)
/// - Fallback to icon if asset missing
/// - Optional gold ring, online glow + dot, Hero animation
/// - Optional cache control via URL cache-busting and custom headers
///
/// ✅ FIXES:
/// 1) Avoid re-downloading Firebase Storage bytes on every parent rebuild:
///    - MwAvatar is now Stateful
///    - Future is memoized and only changes when URL changes
///    - small in-memory LRU cache for Firebase bytes
/// 2) Avoid accidental infinite reload:
///    - MwAvatarCachePolicy.refresh MUST use a stable cacheBustKey (otherwise it changes every build)
class MwAvatar extends StatefulWidget {
  const MwAvatar({
    super.key,
    required this.avatarType,
    this.profileUrl,
    this.hideRealAvatar = false,
    this.radius = 18,
    this.backgroundColor,

    // Ring + Online UX
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

    // Hero animation
    this.heroTag,

    // Cache control
    this.cachePolicy = MwAvatarCachePolicy.normal,
    this.cacheBustKey,
    this.networkHeaders,
  });

  /// 'bear' or 'smurf'
  final String avatarType;

  /// User real profile image URL (Firebase Storage / https)
  final String? profileUrl;

  /// If true, never show profileUrl even if exists
  final bool hideRealAvatar;

  final double radius;
  final Color? backgroundColor;

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
  /// If non-null, wraps avatar in Hero(tag: heroTag)
  final Object? heroTag;

  // ===== Cache control =====
  /// Normal = default Flutter caching (by URL)
  /// refresh = adds a cache-busting query param (safe everywhere)
  /// noCache = attempts to reduce caching using headers (best-effort; web may ignore)
  final MwAvatarCachePolicy cachePolicy;

  /// Optional key appended to URL when cachePolicy == refresh
  /// IMPORTANT: must be stable (e.g., profileUpdatedAt) or it will refresh every rebuild.
  final String? cacheBustKey;

  /// Optional headers for Image.network (best-effort; some platforms may ignore)
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
  static const String _smurfAsset = 'assets/images/smurf.png';

  // Default MW gold (no dependency on app_theme.dart)
  static const Color _defaultGold = Color(0xFFD6B25E);

  // Small in-memory LRU cache for Firebase bytes to avoid re-fetching
  // across list rebuilds / scrolls.
  static final _firebaseBytesCache = _LruBytesCache(maxEntries: 120);

  Future<Uint8List?>? _firebaseBytesFuture;
  String? _firebaseUrlKey;

  // We also memoize the resolved network URL to avoid rebuilding it every build.
  String? _resolvedNetworkUrlKey;
  String? _resolvedNetworkUrl;

  @override
  void initState() {
    super.initState();
    _prepareMemoizedResources();
  }

  @override
  void didUpdateWidget(covariant MwAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If anything affecting URL/visibility changes, recompute.
    final oldEffective = _effectiveUrl(oldWidget);
    final newEffective = _effectiveUrl(widget);

    final cachePolicyChanged = oldWidget.cachePolicy != widget.cachePolicy ||
        oldWidget.cacheBustKey != widget.cacheBustKey ||
        !_mapEquals(oldWidget.networkHeaders, widget.networkHeaders);

    if (oldEffective != newEffective || cachePolicyChanged) {
      _prepareMemoizedResources();
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

  String get _assetPath {
    final t = widget.avatarType.toLowerCase().trim();
    return t == 'smurf' ? _smurfAsset : _bearAsset;
  }

  bool get _isSmurf => widget.avatarType.toLowerCase().trim() == 'smurf';

  String? _effectiveUrl(MwAvatar w) {
    if (w.hideRealAvatar) return null;
    final url = w.profileUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  bool _looksLikeFirebaseStorageUrl(String url) {
    final u = url.trim();
    if (u.startsWith('gs://')) return true;
    if (u.contains('firebasestorage.googleapis.com')) return true;
    return false;
  }

  String _applyCachePolicyToUrl(String url) {
    final policy = widget.cachePolicy;

    if (policy == MwAvatarCachePolicy.normal) return url;

    if (policy == MwAvatarCachePolicy.refresh) {
      // IMPORTANT: if cacheBustKey is null/empty, do NOT auto-generate a timestamp.
      // That would change every rebuild and force constant reload/flicker.
      final key = widget.cacheBustKey?.trim();
      if (key == null || key.isEmpty) return url;

      final sep = url.contains('?') ? '&' : '?';
      return '$url${sep}v=$key';
    }

    // noCache: try headers; still return original URL.
    return url;
  }

  Map<String, String>? _headersForPolicy() {
    if (widget.cachePolicy != MwAvatarCachePolicy.noCache) return widget.networkHeaders;
    final merged = <String, String>{};
    if (widget.networkHeaders != null) merged.addAll(widget.networkHeaders!);

    merged.putIfAbsent('Cache-Control', () => 'no-cache, no-store, must-revalidate');
    merged.putIfAbsent('Pragma', () => 'no-cache');
    merged.putIfAbsent('Expires', () => '0');
    return merged;
  }

  Future<Uint8List?> _fetchFirebaseStorageBytes(String url) async {
    // LRU cache hit
    final cached = _firebaseBytesCache.get(url);
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final ref = FirebaseStorage.instance.refFromURL(url.trim());
      // 2MB cap
      final data = await ref.getData(2 * 1024 * 1024);
      if (data != null && data.isNotEmpty) {
        _firebaseBytesCache.put(url, data);
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  void _prepareMemoizedResources() {
    final url = _effectiveUrl(widget);
    if (url == null) {
      _firebaseBytesFuture = null;
      _firebaseUrlKey = null;
      _resolvedNetworkUrlKey = null;
      _resolvedNetworkUrl = null;
      return;
    }

    final trimmed = url.trim();

    if (_looksLikeFirebaseStorageUrl(trimmed)) {
      // Only create a new future if URL actually changed.
      if (_firebaseUrlKey != trimmed) {
        _firebaseUrlKey = trimmed;
        _firebaseBytesFuture = _fetchFirebaseStorageBytes(trimmed);
      }
      _resolvedNetworkUrlKey = null;
      _resolvedNetworkUrl = null;
      return;
    }

    // Non-firebase network: memoize resolved URL
    final urlKey = '${trimmed}|${widget.cachePolicy.name}|${widget.cacheBustKey ?? ''}';
    if (_resolvedNetworkUrlKey != urlKey) {
      _resolvedNetworkUrlKey = urlKey;
      _resolvedNetworkUrl = _applyCachePolicyToUrl(trimmed);
    }

    _firebaseBytesFuture = null;
    _firebaseUrlKey = null;
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
          _isSmurf ? Icons.face_retouching_natural : Icons.pets,
          size: widget.radius,
          color: Colors.white70,
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

    Widget buildLoadingStack() {
      return Stack(
        fit: StackFit.expand,
        children: [
          buildAssetAvatar(),
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

    Widget buildFirebaseAvatar(String url) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: FutureBuilder<Uint8List?>(
            future: _firebaseBytesFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return buildLoadingStack();
              }

              final bytes = snap.data;
              if (bytes == null || bytes.isEmpty) {
                return buildAssetAvatar();
              }

              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => buildAssetAvatar(),
              );
            },
          ),
        ),
      );
    }

    Widget buildNetworkAvatar(String resolvedUrl) {
      final headers = _headersForPolicy();

      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            resolvedUrl,
            headers: headers,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            // IMPORTANT: Keep loading UI only while first loading; avoids flicker in many cases.
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return buildLoadingStack();
            },
            errorBuilder: (_, __, ___) => buildAssetAvatar(),
          ),
        ),
      );
    }

    final effective = _effectiveUrl(widget);

    final Widget innerAvatar;
    if (effective == null) {
      innerAvatar = buildAssetAvatar();
    } else if (_looksLikeFirebaseStorageUrl(effective)) {
      innerAvatar = buildFirebaseAvatar(effective);
    } else {
      innerAvatar = buildNetworkAvatar(_resolvedNetworkUrl ?? effective.trim());
    }

    final resolvedRingColor = widget.ringColor ?? _defaultGold;
    final resolvedGlowColor = widget.onlineGlowColor ?? Colors.greenAccent.withOpacity(0.55);

    final bool shouldGlow = widget.isOnline && widget.showOnlineGlow;
    final bool shouldRing = widget.showRing;

    Widget avatarWithDecor = Container(
      width: shouldRing ? (size + widget.ringWidth * 2) : size,
      height: shouldRing ? (size + widget.ringWidth * 2) : size,
      padding: shouldRing ? EdgeInsets.all(widget.ringWidth) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: shouldRing ? resolvedRingColor.withOpacity(0.22) : Colors.transparent,
        shape: BoxShape.circle,
        border: shouldRing ? Border.all(color: resolvedRingColor, width: widget.ringWidth) : null,
        boxShadow: shouldGlow
            ? [
          BoxShadow(
            color: resolvedGlowColor,
            blurRadius: widget.onlineGlowBlur,
            spreadRadius: 1.5,
          ),
        ]
            : null,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
        ),
        child: innerAvatar,
      ),
    );

    if (widget.showOnlineDot) {
      final dotColor = widget.isOnline
          ? (widget.onlineDotColor ?? Colors.greenAccent)
          : (widget.offlineDotColor ?? Colors.grey);

      final outerSize = shouldRing ? (size + widget.ringWidth * 2) : size;

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
        flightShuttleBuilder: (flightContext, animation, flightDirection, fromContext, toContext) {
          return ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            child: toContext.widget,
          );
        },
        child: avatarWithDecor,
      );
    }

    return avatarWithDecor;
  }
}

/// Tiny LRU cache for avatar bytes (Firebase Storage path).
class _LruBytesCache {
  _LruBytesCache({required this.maxEntries});

  final int maxEntries;
  final _map = LinkedHashMap<String, Uint8List>();

  Uint8List? get(String key) {
    final v = _map.remove(key);
    if (v == null) return null;
    // re-insert as most-recent
    _map[key] = v;
    return v;
  }

  void put(String key, Uint8List value) {
    _map.remove(key);
    _map[key] = value;
    // evict oldest
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }
}
