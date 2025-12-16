import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

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

  bool _audioReady = false;
  bool _audioError = false;

  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  String? _preparedUrl;

  // ===== VIDEO =====
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoInitError = false;

  static const double _mediaSize = 220; // image & video

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

  // ========= STYLE HELPERS =========

  Color _tint(Color base, Color tint, double amount) {
    return Color.lerp(base, tint, amount.clamp(0.0, 1.0)) ?? base;
  }

  /// ✅ Dark glass bubbles:
  /// - "Me": dark glass with a *very subtle* gold tint
  /// - "Other": dark glass only
  Color get _bubbleColor {
    final base = kSurfaceAltColor; // dark
    if (!widget.isMe) {
      return base.withOpacity(0.62);
    }
    final tinted = _tint(base, kGoldDeep, 0.10); // tiny warm tint
    return tinted.withOpacity(0.70); // more transparent than before
  }

  /// ✅ Text colors now always readable on dark glass
  Color get _onBubblePrimary => kTextPrimary;
  Color get _onBubbleSecondary => kTextSecondary.withOpacity(0.90);

  /// ✅ Border becomes subtle (no heavy gold frame)
  Border? get _bubbleBorder {
    final c = widget.isMe
        ? kGoldDeep.withOpacity(0.18)
        : kBorderColor.withOpacity(0.45);
    return Border.all(color: c, width: 1);
  }

  // ---------------- VIDEO ----------------

  void _initVideoIfNeeded() {
    if (!isVideo || widget.fileUrl == null || widget.fileUrl!.isEmpty) return;

    _videoInitialized = false;
    _videoInitError = false;

    _disposeVideo();

    final uri = Uri.tryParse(widget.fileUrl!);
    if (uri == null) {
      _videoInitError = true;
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
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
      if (playing != _isPlaying) setState(() => _isPlaying = playing);
    });

    _posSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (!mounted) return;
      if ((pos - _audioPosition).inMilliseconds.abs() < 120) return;

      final d = _audioDuration;
      if (d != Duration.zero && pos > d) pos = d;
      setState(() => _audioPosition = pos);
    });

    _durSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (!mounted) return;
      if (dur != _audioDuration) setState(() => _audioDuration = dur);
    });

    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _audioPosition =
        _audioDuration == Duration.zero ? Duration.zero : _audioDuration;
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

  Future<bool> _ensureAudioSourceReady() async {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return false;

    if (_audioReady && !_audioError && _preparedUrl == url) return true;

    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setSourceUrl(url).timeout(const Duration(seconds: 6));

      _preparedUrl = url;
      _audioReady = true;
      _audioError = false;

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

      final d = _audioDuration;
      final atEnd =
          d != Duration.zero && _audioPosition >= d - const Duration(milliseconds: 400);

      if (atEnd) {
        await _audioPlayer.seek(Duration.zero);
        if (mounted) setState(() => _audioPosition = Duration.zero);
      }

      try {
        await _audioPlayer.resume().timeout(const Duration(seconds: 5));
      } catch (_) {
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

  Future<void> _jumpAudio(int seconds) async {
    final next = _audioPosition + Duration(seconds: seconds);
    await _seekAudio(next);
  }

  // ===== FILE OPEN =====
  Future<void> _openFile() async {
    final url = widget.fileUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;

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
                  backgroundColor: kSurfaceAltColor.withOpacity(0.65),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: kTextPrimary),
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
              return SizedBox(
                width: _mediaSize,
                height: _mediaSize,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => SizedBox(
              width: _mediaSize,
              height: _mediaSize,
              child: Center(
                child: Icon(Icons.broken_image, color: kTextSecondary.withOpacity(0.8)),
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
      return SizedBox(
        width: _mediaSize,
        height: _mediaSize,
        child: Center(
          child: Icon(Icons.broken_image, color: kTextSecondary.withOpacity(0.8)),
        ),
      );
    }

    if (!_videoInitialized || c == null || !c.value.isInitialized) {
      return SizedBox(
        width: _mediaSize,
        height: _mediaSize,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
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
          CircleAvatar(
            backgroundColor: Colors.black.withOpacity(0.55),
            child: const Icon(Icons.play_arrow, color: kTextPrimary),
          ),
        ],
      ),
    );
  }

  // ================= WHATSAPP-STYLE AUDIO BUBBLE + WAVEFORM =================

  List<double> _waveformHeights(String seed, int count) {
    final int hash = seed.codeUnits.fold<int>(0, (p, c) => (p * 31 + c) & 0x7fffffff);
    final rnd = math.Random(hash);
    final List<double> bars = List<double>.generate(count, (_) {
      final v = 0.25 + rnd.nextDouble() * 0.75;
      return v;
    });

    for (int i = 1; i < bars.length - 1; i++) {
      bars[i] = (bars[i - 1] + bars[i] + bars[i + 1]) / 3.0;
    }
    return bars;
  }

  Widget _buildAudioBubble() {
    final l10n = AppLocalizations.of(context)!;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final duration = _audioDuration;
    final position = _clampToDuration(_audioPosition, duration);

    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds.clamp(0, totalMs == 0 ? 0 : totalMs);

    final progress = (totalMs == 0) ? 0.0 : (posMs / totalMs).clamp(0.0, 1.0);

    final seed = widget.fileUrl ?? '${widget.timeLabel}_${widget.isMe}';
    final bars = _waveformHeights(seed, 42);

    Future<void> seekByRatio(double ratio) async {
      if (totalMs == 0) return;
      final r = ratio.clamp(0.0, 1.0);
      final ms = (r * totalMs).round();
      await _seekAudio(Duration(milliseconds: ms));
    }

    Widget waveform = LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (d) async {
            final w = constraints.maxWidth;
            if (w <= 0) return;
            final dx = d.localPosition.dx.clamp(0.0, w);
            final ratio = isRtl ? (1.0 - dx / w) : (dx / w);
            await seekByRatio(ratio);
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, 28),
            painter: _WaveformPainter(
              bars: bars,
              progress: progress,
              isMe: widget.isMe,
              isRtl: isRtl,
            ),
          ),
        );
      },
    );

    final backBtn = IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: _isAudioLoading ? null : () => _jumpAudio(-10),
      icon: Icon(Icons.replay_10, color: kTextPrimary.withOpacity(0.92)),
      tooltip: 'Back 10s',
    );

    final fwdBtn = IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: _isAudioLoading ? null : () => _jumpAudio(10),
      icon: Icon(Icons.forward_10, color: kTextPrimary.withOpacity(0.92)),
      tooltip: 'Forward 10s',
    );

    final playBtn = InkWell(
      onTap: _isAudioLoading ? null : _toggleAudio,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: kSurfaceAltColor.withOpacity(0.55),
          shape: BoxShape.circle,
          border: Border.all(color: kBorderColor.withOpacity(0.50)),
        ),
        child: Center(
          child: _isAudioLoading
              ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          )
              : Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            color: kTextPrimary,
            size: 26,
          ),
        ),
      ),
    );

    final leftTime = Text(
      _formatTime(position),
      style: TextStyle(color: kTextSecondary.withOpacity(0.9), fontSize: 11),
    );

    final rightTime = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          duration == Duration.zero ? '--:--' : _formatTime(duration),
          style: TextStyle(color: kTextSecondary.withOpacity(0.9), fontSize: 11),
        ),
        if (_audioError) ...[
          const SizedBox(width: 6),
          const Icon(Icons.error_outline, size: 14, color: kErrorColor),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // ✅ slightly darker + more transparent
        color: kSurfaceAltColor.withOpacity(0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor.withOpacity(0.45)),
      ),
      child: Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            playBtn,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.voiceMessageLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(height: 28, child: waveform),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      leftTime,
                      const Spacer(),
                      rightTime,
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                backBtn,
                fwdBtn,
              ],
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
          color: kSurfaceAltColor.withOpacity(0.50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorderColor.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, color: kTextSecondary.withOpacity(0.9)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.fileName ?? l10n.genericFileLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kTextPrimary),
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
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _initVideoIfNeeded();
    _initAudioStreams();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool urlChanged = oldWidget.fileUrl != widget.fileUrl;
    final bool typeChanged =
        (oldWidget.fileType ?? '').toLowerCase() != (widget.fileType ?? '').toLowerCase();

    if (urlChanged || typeChanged) {
      _disposeVideo();
      _initVideoIfNeeded();
    }

    if (urlChanged && isAudio) {
      _audioPlayer.stop().catchError((_) {});
      if (mounted) setState(_resetAudioUi);
    }

    if (typeChanged && !isAudio) {
      _audioPlayer.stop().catchError((_) {});
      _resetAudioUi();
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
          color: _bubbleColor,
          borderRadius: BorderRadius.circular(_bubbleRadius),
          border: _bubbleBorder,
          // ✅ remove heavy glow; keep super subtle depth
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
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
                  style: TextStyle(color: _onBubblePrimary),
                ),
              ),
            if (widget.showTimestamp)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.timeLabel,
                      style: TextStyle(color: _onBubbleSecondary, fontSize: 10),
                    ),
                    if (widget.isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          widget.isSeen ? Icons.done_all : Icons.done,
                          size: 12,
                          // ✅ gold accent on dark bubble (not black)
                          color: widget.isSeen
                              ? kPrimaryGold.withOpacity(0.92)
                              : kPrimaryGold.withOpacity(0.55),
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

class _WaveformPainter extends CustomPainter {
  final List<double> bars; // 0..1
  final double progress; // 0..1
  final bool isMe;
  final bool isRtl;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.isMe,
    required this.isRtl,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintBase = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    final paintPlayed = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    paintPlayed.color = (isMe ? kPrimaryGold : kOffWhite).withOpacity(0.92);
    paintBase.color = kTextSecondary.withOpacity(isMe ? 0.36 : 0.26);

    final w = size.width;
    final h = size.height;
    final mid = h / 2;

    final count = bars.length;
    if (count == 0 || w <= 0) return;

    final playedCount = (progress * count).clamp(0.0, count.toDouble());

    for (int i = 0; i < count; i++) {
      final idx = isRtl ? (count - 1 - i) : i;

      final x = (i + 0.5) * (w / count);
      final amp = (bars[idx]).clamp(0.15, 1.0);
      final barH = (amp * (h * 0.85)).clamp(6.0, h);

      final y1 = mid - barH / 2;
      final y2 = mid + barH / 2;

      final isPlayed = isRtl ? (i >= (count - playedCount)) : (i < playedCount);
      final p = isPlayed ? paintPlayed : paintBase;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), p);
    }

    final headX = isRtl ? (w * (1.0 - progress)) : (w * progress);
    final headPaint = Paint()
      ..color = (isMe ? kPrimaryGold : kOffWhite).withOpacity(0.85)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(headX, mid - 12), Offset(headX, mid + 12), headPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isMe != isMe ||
        oldDelegate.isRtl != isRtl ||
        oldDelegate.bars != bars;
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

    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) {
      _error = true;
      return;
    }

    _controller = VideoPlayerController.networkUrl(uri)
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
    if (!_error) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: const BackButton(color: kTextPrimary),
      ),
      body: Center(
        child: _error
            ? Icon(Icons.broken_image, color: kTextSecondary.withOpacity(0.8))
            : !_initialized
            ? CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        )
            : AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
