// lib/widgets/chat/message_bubble.dart
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';

class MessageBubble extends StatefulWidget {
  final String text;
  final String timeLabel;
  final bool isMe;
  final bool isSeen;
  final String? fileUrl;
  final String? fileName;
  final String? fileType; // "image", "video", "audio", "file"
  final bool showTimestamp;

  const MessageBubble({
    super.key,
    required this.text,
    required this.timeLabel,
    required this.isMe,
    required this.isSeen,
    this.fileUrl,
    this.fileName,
    this.fileType,
    this.showTimestamp = true,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  // ===== AUDIO =====
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  // ===== VIDEO =====
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoInitError = false;

  static const double _mediaSize = 220; // SAME SIZE for image & video

  bool get hasAttachment => widget.fileUrl?.isNotEmpty == true;

  bool get isImage {
    final type = (widget.fileType ?? '').toLowerCase();
    return type == 'image' || type.startsWith('image/');
  }

  bool get isVideo {
    final type = (widget.fileType ?? '').toLowerCase();
    return type == 'video' || type.startsWith('video/');
  }

  bool get isAudio {
    final type = (widget.fileType ?? '').toLowerCase();
    return type == 'audio' || type.startsWith('audio/');
  }

  bool get isGenericFile => hasAttachment && !isImage && !isVideo && !isAudio;

  static const double _bubbleRadius = 16.0;
  static const Color _myBubbleColor = Color(0xFF2563EB);
  static const Color _theirBubbleColor = Color(0xFF1E1E1E);

  void _initVideoIfNeeded() {
    if (!isVideo || widget.fileUrl == null || widget.fileUrl!.isEmpty) return;

    _videoInitialized = false;
    _videoInitError = false;

    // Always dispose any previous controller first
    _disposeVideo();

    final controller =
    VideoPlayerController.networkUrl(Uri.parse(widget.fileUrl!));

    _videoController = controller;

    controller.initialize().then((_) {
      // If widget disposed OR controller replaced, ignore callback
      if (!mounted || _videoController != controller) return;
      setState(() => _videoInitialized = true);
    }).catchError((_) {
      if (!mounted || _videoController != controller) return;
      setState(() => _videoInitError = true);
    });
  }


  void _disposeVideo() {
    final controller = _videoController;
    _videoController = null;
    _videoInitialized = false;
    _videoInitError = false;
    controller?.dispose();
  }

  @override
  void initState() {
    super.initState();

    // ✅ Initialize video controller only once (inside _initVideoIfNeeded)
    _initVideoIfNeeded();

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
    });
  }


  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool urlChanged = oldWidget.fileUrl != widget.fileUrl;
    final bool typeChanged = (oldWidget.fileType ?? '').toLowerCase() !=
        (widget.fileType ?? '').toLowerCase();

    // If Firestore updates the URL or type (e.g. after upload finishes),
    // recreate the video controller so the thumbnail appears immediately.
    if (urlChanged || typeChanged) {
      _disposeVideo();
      _initVideoIfNeeded();
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _disposeVideo();
    super.dispose();
  }


  // ===== AUDIO =====
  Future<void> _toggleAudio() async {
    if (widget.fileUrl == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(UrlSource(widget.fileUrl!));
      }
      if (mounted) setState(() => _isPlaying = !_isPlaying);
    } catch (_) {}
  }

  // ===== FILE OPEN =====
  Future<void> _openFile() async {
    final url = widget.fileUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ===== FULLSCREEN IMAGE =====
  void _openImageFullScreen() {
    final url = widget.fileUrl;
    if (url == null) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              Center(
                child: Hero(
                  tag: 'image_$url',
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 12,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===== FULLSCREEN VIDEO =====
  void _openVideoFullScreen() {
    final url = widget.fileUrl;
    if (url == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenVideoPage(videoUrl: url),
      ),
    );
  }

  // IMAGE BUBBLE (unchanged logic, fixed size)
  Widget _buildImageBubble() {
    final url = widget.fileUrl!;
    return GestureDetector(
      onTap: _openImageFullScreen,
      child: Hero(
        tag: 'image_$url',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            width: _mediaSize,
            height: _mediaSize,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: _mediaSize,
                height: _mediaSize,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox(
              width: _mediaSize,
              height: _mediaSize,
              child: Center(
                child: Icon(Icons.broken_image, color: Colors.white54),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // VIDEO BUBBLE — SAME SIZE, CLICKABLE, NO EXTRA PADDING
  Widget _buildVideoBubble() {
    final c = _videoController;
    if (!_videoInitialized || c == null || !c.value.isInitialized) {
      return const SizedBox(
        width: _mediaSize,
        height: _mediaSize,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_videoInitError) {
      return const SizedBox(
        width: _mediaSize,
        height: _mediaSize,
        child: Center(child: Icon(Icons.broken_image, color: Colors.white54)),
      );
    }

    if (!_videoInitialized || _videoController == null) {
      return const SizedBox(
        width: _mediaSize,
        height: _mediaSize,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return GestureDetector(
      onTap: _openVideoFullScreen,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: _mediaSize,
              height: _mediaSize,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
          ),
          const CircleAvatar(
            backgroundColor: Colors.black54,
            child: Icon(Icons.play_arrow, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioBubble() {
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: _toggleAudio,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              color: Colors.white,
              size: 26,
            ),
            const SizedBox(width: 10),
            Text(
              l10n.voiceMessageLabel,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileBubble() {
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: _openFile,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              widget.fileName ?? l10n.genericFileLabel,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: widget.isMe ? _myBubbleColor : _theirBubbleColor,
          borderRadius: BorderRadius.circular(_bubbleRadius),
        ),
        child: Column(
          crossAxisAlignment:
          widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (hasAttachment && isImage) _buildImageBubble(),
            if (hasAttachment && isVideo) _buildVideoBubble(),
            if (hasAttachment && isAudio) _buildAudioBubble(),
            if (hasAttachment && isGenericFile) _buildFileBubble(),

            if (widget.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.text,
                  style: const TextStyle(color: Colors.white),
                ),
              ),

            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.timeLabel,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 10),
                  ),
                  if (widget.isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        widget.isSeen
                            ? Icons.done_all
                            : Icons.done,
                        size: 12,
                        color: widget.isSeen
                            ? Colors.lightBlueAccent
                            : Colors.white60,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ================= FULLSCREEN VIDEO PAGE ==================

class _FullScreenVideoPage extends StatefulWidget {
  final String videoUrl;

  const _FullScreenVideoPage({required this.videoUrl});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        _controller.play();
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _error = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar( // BACK BUTTON FIX
        backgroundColor: Colors.black,
        leading: const BackButton(color: Colors.white),
      ),
      body: Center(
        child: _error
            ? const Icon(Icons.broken_image, color: Colors.white54)
            : !_initialized
            ? const CircularProgressIndicator()
            : AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
