import 'package:flutter/material.dart';

/// MW Avatar (single pattern everywhere):
/// - Network profile photo if allowed + available
/// - Fallback to local asset (bear/smurf)
/// - Fallback to icon if asset missing
/// - Optional gold ring, online glow + dot, Hero animation
/// - Optional cache control via URL cache-busting and custom headers
class MwAvatar extends StatelessWidget {
  const MwAvatar({
    super.key,
    required this.avatarType,
    this.profileUrl,
    this.hideRealAvatar = false,
    this.radius = 18,
    this.backgroundColor,

    // ✅ Ring + Online UX
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

    // ✅ Hero animation
    this.heroTag,

    // ✅ Cache control
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
  /// If null, DateTime.now().millisecondsSinceEpoch is used.
  final String? cacheBustKey;

  /// Optional headers for Image.network (best-effort; some platforms may ignore)
  final Map<String, String>? networkHeaders;

  static const String _bearAsset = 'assets/images/bear.png';
  static const String _smurfAsset = 'assets/images/smurf.png';

  // Default MW gold (no dependency on app_theme.dart)
  static const Color _defaultGold = Color(0xFFD6B25E);

  String get _assetPath {
    final t = avatarType.toLowerCase().trim();
    return t == 'smurf' ? _smurfAsset : _bearAsset;
  }

  bool get _isSmurf => avatarType.toLowerCase().trim() == 'smurf';

  String? get _effectiveUrl {
    if (hideRealAvatar) return null;
    final url = profileUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  String _applyCachePolicyToUrl(String url) {
    final policy = cachePolicy;

    if (policy == MwAvatarCachePolicy.normal) return url;

    // Best cross-platform cache control: URL cache busting.
    if (policy == MwAvatarCachePolicy.refresh) {
      final key = (cacheBustKey?.trim().isNotEmpty == true)
          ? cacheBustKey!.trim()
          : DateTime.now().millisecondsSinceEpoch.toString();

      // Append ?v= or &v=
      final sep = url.contains('?') ? '&' : '?';
      return '$url${sep}v=$key';
    }

    // noCache: try headers; still return original URL.
    // (Web may ignore cache headers; this is best-effort.)
    return url;
  }

  Map<String, String>? _headersForPolicy() {
    if (cachePolicy != MwAvatarCachePolicy.noCache) return networkHeaders;
    final merged = <String, String>{};
    if (networkHeaders != null) merged.addAll(networkHeaders!);

    // Best-effort. Some platforms / CDNs may ignore.
    merged.putIfAbsent('Cache-Control', () => 'no-cache, no-store, must-revalidate');
    merged.putIfAbsent('Pragma', () => 'no-cache');
    merged.putIfAbsent('Expires', () => '0');
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Colors.white10;
    final size = radius * 2;

    // --- Fallback icon (ultra-safe) ---
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
          size: radius,
          color: Colors.white70,
        ),
      );
    }

    // --- Asset avatar ---
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

    // --- Network avatar (with loading + error fallback) ---
    Widget buildNetworkAvatar(String url) {
      final resolvedUrl = _applyCachePolicyToUrl(url);
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
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Stack(
                fit: StackFit.expand,
                children: [
                  buildAssetAvatar(),
                  Center(
                    child: SizedBox(
                      width: radius * 0.9,
                      height: radius * 0.9,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              );
            },
            errorBuilder: (_, __, ___) => buildAssetAvatar(),
          ),
        ),
      );
    }

    // --- Core avatar content ---
    final url = _effectiveUrl;
    final innerAvatar = (url != null) ? buildNetworkAvatar(url) : buildAssetAvatar();

    // --- Ring / glow wrapper ---
    final resolvedRingColor = ringColor ?? _defaultGold;
    final resolvedGlowColor = onlineGlowColor ?? Colors.greenAccent.withOpacity(0.55);

    final bool shouldGlow = isOnline && showOnlineGlow;
    final bool shouldRing = showRing;

    Widget avatarWithDecor = Container(
      width: shouldRing ? (size + ringWidth * 2) : size,
      height: shouldRing ? (size + ringWidth * 2) : size,
      padding: shouldRing ? EdgeInsets.all(ringWidth) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: shouldRing ? resolvedRingColor.withOpacity(0.22) : Colors.transparent,
        shape: BoxShape.circle,
        border: shouldRing ? Border.all(color: resolvedRingColor, width: ringWidth) : null,
        boxShadow: shouldGlow
            ? [
          BoxShadow(
            color: resolvedGlowColor,
            blurRadius: onlineGlowBlur,
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

    // --- Online dot ---
    if (showOnlineDot) {
      final dotColor = isOnline
          ? (onlineDotColor ?? Colors.greenAccent)
          : (offlineDotColor ?? Colors.grey);

      // Position dot relative to outer size
      final outerSize = shouldRing ? (size + ringWidth * 2) : size;

      avatarWithDecor = Stack(
        clipBehavior: Clip.none,
        children: [
          avatarWithDecor,
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black,
                  width: dotBorderWidth,
                ),
              ),
            ),
          ),
        ],
      );

      // Ensure Stack doesn't shrink weirdly in tight rows
      avatarWithDecor = SizedBox(
        width: outerSize,
        height: outerSize,
        child: avatarWithDecor,
      );
    }

    // --- Hero wrapper ---
    if (heroTag != null) {
      avatarWithDecor = Hero(
        tag: heroTag!,
        flightShuttleBuilder: (flightContext, animation, flightDirection, fromContext, toContext) {
          // Smooth scale during hero flight
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

enum MwAvatarCachePolicy {
  /// Default Flutter cache behavior (cache by URL)
  normal,

  /// Forces refresh by appending a cache-busting query param (?v=...)
  /// safest cross-platform cache control
  refresh,

  /// Best-effort "no-cache" via request headers (may be ignored on web/CDNs)
  noCache,
}
