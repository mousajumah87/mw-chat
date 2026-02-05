// ignore_for_file: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class WebVideoPreviewDialog extends StatefulWidget {
  final Uint8List bytes;
  const WebVideoPreviewDialog({super.key, required this.bytes});

  @override
  State<WebVideoPreviewDialog> createState() => _WebVideoPreviewDialogState();
}

class _WebVideoPreviewDialogState extends State<WebVideoPreviewDialog> {
  VideoPlayerController? _c;
  String? _url;
  bool _ready = false;

  @override
  void initState() {
    super.initState();

    final blob = html.Blob(<dynamic>[widget.bytes], 'video/mp4');
    _url = html.Url.createObjectUrlFromBlob(blob);

    final c = VideoPlayerController.networkUrl(Uri.parse(_url!));
    _c = c;

    c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      c.play();
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _ready = false);
    });
  }

  @override
  void dispose() {
    try {
      _c?.dispose();
    } catch (_) {}
    final u = _url;
    if (u != null) {
      try {
        html.Url.revokeObjectUrl(u);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: AspectRatio(
        aspectRatio: (_ready && c != null && c.value.isInitialized)
            ? c.value.aspectRatio
            : (16 / 9),
        child: Stack(
          children: [
            if (_ready && c != null && c.value.isInitialized)
              Center(child: VideoPlayer(c))
            else
              const Center(child: CircularProgressIndicator()),

            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
