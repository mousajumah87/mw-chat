// lib/widgets/chat/mw_video_message_thumb.dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Lightweight thumbnail renderer for video message bubbles.
/// Priority:
/// 1) thumbUrl (stored in Firestore) -> Image.network
/// 2) (non-web only) best-effort generate from videoUrl -> VideoThumbnail.thumbnailData
/// 3) placeholder
class MwVideoMessageThumb extends StatefulWidget {
  final String videoUrl;
  final String? thumbUrl;
  final BoxFit fit;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const MwVideoMessageThumb({
    super.key,
    required this.videoUrl,
    this.thumbUrl,
    this.fit = BoxFit.cover,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<MwVideoMessageThumb> createState() => _MwVideoMessageThumbState();
}

class _MwVideoMessageThumbState extends State<MwVideoMessageThumb> {
  static final Map<String, Uint8List> _memCache = <String, Uint8List>{};
  static const int _maxCacheItems = 120;

  Future<Uint8List?> _loadThumbBytes() async {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) return null;

    // If we already have a stored thumbUrl -> no need to generate.
    if ((widget.thumbUrl ?? '').trim().isNotEmpty) return null;

    // Web: remote video thumbnailing is usually blocked by CORS -> skip.
    if (kIsWeb) return null;

    // In-memory cache
    final cached = _memCache[url];
    if (cached != null) return cached;

    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: url, // best-effort (can fail depending on platform/network)
        imageFormat: ImageFormat.JPEG,
        maxHeight: 360,
        quality: 75,
        timeMs: 0,
      );

      if (bytes == null || bytes.isEmpty) return null;

      // Tiny cache control
      if (_memCache.length >= _maxCacheItems) {
        _memCache.remove(_memCache.keys.first);
      }
      _memCache[url] = bytes;

      return bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _placeholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.10),
        borderRadius: widget.borderRadius,
      ),
      child: Center(
        child: CircleAvatar(
          radius: 26,
          backgroundColor: Colors.black.withOpacity(0.55),
          child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = (widget.thumbUrl ?? '').trim();

    // ✅ 1) Stored thumbUrl (best path)
    if (thumbUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: Image.network(
          thumbUrl,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => _placeholder(),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              width: widget.width,
              height: widget.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: widget.borderRadius,
              ),
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        ),
      );
    }

    // ✅ 2) Fallback attempt (non-web)
    return FutureBuilder<Uint8List?>(
      future: _loadThumbBytes(),
      builder: (_, snap) {
        final b = snap.data;
        if (b == null || b.isEmpty) return _placeholder();

        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Image.memory(
            b,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        );
      },
    );
  }
}
