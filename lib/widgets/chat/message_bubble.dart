// lib/widgets/chat/message_bubble.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
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

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  bool _isPlaying = false;
  bool _isAudioLoading = false;

  bool _audioReady = false; // source prepared at least once
  bool _audioError = false;

  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  String? _preparedUrl; // track current prepared url

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

  // ---------------- VIDEO ----------------

  void _initVideoIfNeeded() {
    if (!isVideo || widget.fileUrl == null || widget.fileUrl!.isEmpty) return;

    _videoInitialized = false;
    _videoInitError = false;

    _disposeVideo();

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.fileUrl!));
    _videoController = controller;

    controller.initialize().then((_) {
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

  // ---------------- AUDIO ----------------

  void _initAudioStreams() {
    _playerStateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;

      final playing = state == PlayerState.playing;
      if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
    });

    _posSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (!mounted) return;

      // Avoid rebuild storms
      if ((pos - _audioPosition).inMilliseconds.abs() < 120) return;

      final d = _audioDuration;
      if (d != Duration.zero && pos > d) {
        pos = d;
      }
      setState(() => _audioPosition = pos);
    });

    _durSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (!mounted) return;
      if (dur != _audioDuration) {
        setState(() => _audioDuration = dur);
      }
    });

    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        // Keep at end visually; replay must reset/seek(0)
        _audioPosition = _audioDuration == Duration.zero ? Duration.zero : _audioDuration;
      });
    });
  }

  void _resetAudioUi() {
    _isAudioLoading = false;
    _isPlaying = false;
    _audioReady = false;
    _audioError = false;
    _audioDuration = Duration.zero;
    _audioPosition = Duration.zero;
    _preparedUrl = null;
  }

  Duration _clampToDuration(Duration value, Duration max) {
    if (max == Duration.zero) {
      return value < Duration.zero ? Duration.zero : value;
    }
    if (value < Duration.zero) return Duration.zero;
    if (value > max) return max;
    return value;
  }

  String _formatTime(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(1, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// ✅ Prepare source reliably (iOS/Web safer).
  /// Also re-prepares if URL changed.
  Future<bool> _ensureAudioSourceReady() async {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return false;

    // If already prepared for this URL and no error → ok
    if (_audioReady && !_audioError && _preparedUrl == url) return true;

    try {
      // release mode STOP makes replay more deterministic across platforms
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);

      // Prepare source (timeout prevents "loading forever")
      await _audioPlayer
          .setSourceUrl(url)
          .timeout(const Duration(seconds: 6));

      _preparedUrl = url;
      _audioReady = true;
      _audioError = false;

      // Try to fetch duration (may be null on web until playback starts; that's ok)
      final d = await _audioPlayer.getDuration();
      if (d != null && d != Duration.zero && mounted) {
        setState(() => _audioDuration = d);
      }

      return true;
    } catch (_) {
      _audioReady = false;
      _audioError = true;
      return false;
    }
  }

  Future<void> _toggleAudio() async {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;

    if (_isAudioLoading) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        return;
      }

      setState(() {
        _isAudioLoading = true;
        _audioError = false;
      });

      final ok = await _ensureAudioSourceReady();
      if (!ok) {
        if (mounted) {
          setState(() {
            _isAudioLoading = false;
            _audioError = true;
          });
        }
        return;
      }

      // ✅ Replay fix:
      // If at/near end OR player was completed, force seek(0) before starting again.
      final d = _audioDuration;
      final atEnd = d != Duration.zero &&
          _audioPosition >= d - const Duration(milliseconds: 400);

      if (atEnd) {
        await _audioPlayer.seek(Duration.zero);
        if (mounted) setState(() => _audioPosition = Duration.zero);
      }

      // Web sometimes needs "play" instead of "resume" after completion.
      // We try resume first; if it stalls, fall back to play(UrlSource).
      try {
        await _audioPlayer.resume().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Fallback path (very important for Chrome replay reliability)
        await _audioPlayer.stop().catchError((_) {});
        await _audioPlayer.play(UrlSource(url)).timeout(const Duration(seconds: 6));
      }
    } catch (_) {
      // swallow
    } finally {
      if (mounted) setState(() => _isAudioLoading = false);
    }
  }

  Future<void> _seekAudio(Duration target) async {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;

    final t = _clampToDuration(target, _audioDuration);

    try {
      final ok = await _ensureAudioSourceReady();
      if (!ok) {
        if (mounted) setState(() => _audioError = true);
        return;
      }

      await _audioPlayer.seek(t);
      if (mounted) setState(() => _audioPosition = t);
    } catch (_) {}
  }

  /// ✅ Perfect back/forward behavior (paused OR playing)
  Future<void> _jumpAudio(int seconds) async {
    final next = _audioPosition + Duration(seconds: seconds);
    await _seekAudio(next);
  }

  // ===== FILE OPEN =====
  Future<void> _openFile() async {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ===== FULLSCREEN IMAGE =====
  void _openImageFullScreen() {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;

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
    if (url == null || url.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenVideoPage(videoUrl: url),
      ),
    );
  }

  // IMAGE BUBBLE
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

  // VIDEO BUBBLE
  Widget _buildVideoBubble() {
    final c = _videoController;

    if (_videoInitError) {
      return const SizedBox(
        width: _mediaSize,
        height: _mediaSize,
        child: Center(child: Icon(Icons.broken_image, color: Colors.white54)),
      );
    }

    if (!_videoInitialized || c == null || !c.value.isInitialized) {
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
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
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

  // AUDIO BUBBLE (seek + progress + back/forward)
  Widget _buildAudioBubble() {
    final l10n = AppLocalizations.of(context)!;

    final duration = _audioDuration;
    final position = _clampToDuration(_audioPosition, duration);

    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds.clamp(0, totalMs == 0 ? 0 : totalMs);

    final sliderMax = totalMs == 0 ? 1.0 : totalMs.toDouble();
    final sliderValue = totalMs == 0 ? 0.0 : posMs.toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play/Pause
              InkWell(
                onTap: _isAudioLoading ? null : _toggleAudio,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: _isAudioLoading
                      ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Title + times
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.voiceMessageLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _formatTime(position),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          duration == Duration.zero ? '--:--' : _formatTime(duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        if (_audioError) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.error_outline,
                              size: 14, color: Colors.redAccent),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Back/Forward 10
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _isAudioLoading ? null : () => _jumpAudio(-10),
                icon: const Icon(Icons.replay_10, color: Colors.white),
                tooltip: 'Back 10s',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _isAudioLoading ? null : () => _jumpAudio(10),
                icon: const Icon(Icons.forward_10, color: Colors.white),
                tooltip: 'Forward 10s',
              ),
            ],
          ),

          // Slider seek
          Slider(
            value: sliderValue,
            min: 0.0,
            max: sliderMax,
            onChanged: (v) {
              if (!mounted) return;
              setState(() {
                _audioPosition = Duration(milliseconds: v.round());
              });
            },
            onChangeEnd: (v) async {
              await _seekAudio(Duration(milliseconds: v.round()));
            },
          ),
        ],
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
            Flexible(
              child: Text(
                widget.fileName ?? l10n.genericFileLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // helps some platform edge cases (web replay)
    _audioPlayer.setReleaseMode(ReleaseMode.stop);

    _initVideoIfNeeded();
    _initAudioStreams();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool urlChanged = oldWidget.fileUrl != widget.fileUrl;
    final bool typeChanged = (oldWidget.fileType ?? '').toLowerCase() !=
        (widget.fileType ?? '').toLowerCase();

    // Video: recreate controller on url/type changes
    if (urlChanged || typeChanged) {
      _disposeVideo();
      _initVideoIfNeeded();
    }

    // Audio: if URL changed, stop and reset UI
    if (urlChanged && isAudio) {
      _audioPlayer.stop().catchError((_) {});
      if (mounted) setState(_resetAudioUi);
    }
  }

  @override
  void dispose() {
    _audioPlayer.stop().catchError((_) {});
    _playerStateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer.dispose();

    _disposeVideo();
    super.dispose();
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
            if (widget.showTimestamp)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.timeLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    if (widget.isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          widget.isSeen ? Icons.done_all : Icons.done,
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
      appBar: AppBar(
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
