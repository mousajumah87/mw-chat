// lib/widgets/ui/mw_auth_image.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

class MwAuthImage extends StatefulWidget {
  const MwAuthImage({
    super.key,
    required this.pathOrUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.maxBytes = 2 * 1024 * 1024, // 2MB
  });

  /// Can be:
  /// - a gs:// url
  /// - a Firebase Storage path like "profile_pics/abc123"
  /// - (optionally) an https downloadUrl (we’ll try to derive a ref)
  final String pathOrUrl;

  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  final Widget? placeholder;
  final Widget? errorWidget;

  final int maxBytes;

  @override
  State<MwAuthImage> createState() => _MwAuthImageState();
}

class _MwAuthImageState extends State<MwAuthImage> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant MwAuthImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pathOrUrl != widget.pathOrUrl) {
      _future = _load();
    }
  }

  Reference? _refFromInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // gs://bucket/path
    if (trimmed.startsWith('gs://')) {
      return FirebaseStorage.instance.refFromURL(trimmed);
    }

    // direct https download URL: try refFromURL (works if it’s a Firebase Storage URL)
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      try {
        return FirebaseStorage.instance.refFromURL(trimmed);
      } catch (_) {
        return null;
      }
    }

    // otherwise treat as storage path: "profile_pics/abc"
    return FirebaseStorage.instance.ref(trimmed);
  }

  Future<Uint8List?> _load() async {
    final ref = _refFromInput(widget.pathOrUrl);
    if (ref == null) return null;

    try {
      final data = await ref.getData(widget.maxBytes);
      return data;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.placeholder ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Colors.white10,
        );

    final errorWidget = widget.errorWidget ?? placeholder;

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return errorWidget;

        final img = Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
        );

        if (widget.borderRadius != null) {
          return ClipRRect(borderRadius: widget.borderRadius!, child: img);
        }
        return img;
      },
    );
  }
}
