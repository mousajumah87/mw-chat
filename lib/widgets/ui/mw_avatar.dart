// lib/widgets/ui/mw_avatar.dart

import 'dart:collection';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// MW Avatar (single pattern everywhere):
/// - Network profile photo if allowed + available
/// - Fallback to local asset (bear/girl)
/// - Fallback to icon if asset missing
/// - Optional gold ring, online glow + dot, Hero animation
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

  /// Cache resolved download URLs for Firebase refs/paths
  static final _downloadUrlCache = _LruStringCache(maxEntries: 250);

  Future<String?>? _resolvedUrlFuture;
  String? _resolvedKey;

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  bool _isGirlType(String? raw) {
    final t = _norm(raw);
    if (t.isEmpty) return false;
    return t == 'girl' || t == 'smurf' || t == 'female' || t == 'woman' || t == 'f';
  }

  String get _assetPath => _isGirlType(widget.avatarType) ? _girlAsset : _bearAsset;
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
    // ✅ Your DB values look exactly like this:
    // .../o/profile_pics%2F<id>?alt=media&token=...
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

    // noCache: rely on headers; keep url unchanged.
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

  Future<String?> _resolveToRenderableUrl(String raw) async {
    final trimmed = raw.trim();

    // ✅ If it's already a direct downloadable URL, DO NOT resolve.
    if (_isDirectMediaUrl(trimmed)) {
      return _applyCachePolicyToUrl(trimmed);
    }

    // Non-firebase normal web URL: show directly.
    if (_isHttpUrl(trimmed) && !trimmed.contains('firebasestorage')) {
      return _applyCachePolicyToUrl(trimmed);
    }

    // Cached result for firebase ref/path
    final cached = _downloadUrlCache.get(trimmed);
    if (cached != null && cached.isNotEmpty) {
      return _applyCachePolicyToUrl(cached);
    }

    try {
      Reference ref;

      if (_looksLikeStoragePath(trimmed)) {
        // e.g. "profile_pics/uid.jpg"
        ref = FirebaseStorage.instance.ref().child(trimmed);
      } else if (_isGsUrl(trimmed) || _isFirebaseRestUrlNeedingResolve(trimmed)) {
        // gs://... OR Firebase REST url without alt=media
        ref = FirebaseStorage.instance.refFromURL(trimmed);
      } else if (_isHttpUrl(trimmed)) {
        // Some other http(s): try showing directly as last resort.
        return _applyCachePolicyToUrl(trimmed);
      } else {
        // Unknown format
        return null;
      }

      final downloadUrl = await ref.getDownloadURL();
      if (downloadUrl.trim().isNotEmpty) {
        _downloadUrlCache.put(trimmed, downloadUrl);
        return _applyCachePolicyToUrl(downloadUrl);
      }
      return null;
    } catch (e) {
      // If file truly missing or permission denied, we fall back gracefully.
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

    final key = '${raw.trim()}|${widget.cachePolicy.name}|${widget.cacheBustKey ?? ''}';
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

    if (oldRaw != newRaw || policyChanged || oldWidget.hideRealAvatar != widget.hideRealAvatar) {
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

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? Colors.white10;
    final size = widget.radius * 2;

    Widget buildFallbackIcon() {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(
          _isGirl ? Icons.face_retouching_natural : Icons.pets,
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
            errorBuilder: (_, __, ___) => buildAssetAvatar(),
          ),
        ),
      );
    }

    final raw = _effectiveRaw(widget);

    final Widget innerAvatar;
    if (raw == null) {
      innerAvatar = buildAssetAvatar();
    } else {
      innerAvatar = FutureBuilder<String?>(
        future: _resolvedUrlFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return ClipOval(
              child: SizedBox(width: size, height: size, child: buildLoadingStack()),
            );
          }
          final resolvedUrl = (snap.data ?? '').trim();
          if (resolvedUrl.isEmpty) return buildAssetAvatar();
          return buildNetworkAvatar(resolvedUrl);
        },
      );
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
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
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
                border: Border.all(color: Colors.black, width: widget.dotBorderWidth),
              ),
            ),
          ),
        ],
      );

      avatarWithDecor = SizedBox(width: outerSize, height: outerSize, child: avatarWithDecor);
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

/// Tiny LRU cache for resolved strings (download urls).
class _LruStringCache {
  _LruStringCache({required this.maxEntries});

  final int maxEntries;
  final _map = LinkedHashMap<String, String>();

  String? get(String key) {
    final v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v; // most-recent
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
