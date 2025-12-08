// lib/widgets/chat/message_bubble.dart
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static const _bubbleRadius = 16.0;
  static const _myBubbleColor = Color(0xFF2563EB);
  static const _theirBubbleColor = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();

    // Init video controller if video message
    if (isVideo && widget.fileUrl != null) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.fileUrl!),
      )..initialize().then((_) {
        if (mounted) setState(() {});
      });
    }

    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(widget.fileUrl!));
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  Future<void> _openFile() async {
    final url = widget.fileUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.white;
    final timeColor =
    widget.isMe ? Colors.white70.withOpacity(0.8) : Colors.white.withOpacity(0.65);

    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          color: widget.isMe ? _myBubbleColor : _theirBubbleColor,
          borderRadius: BorderRadius.circular(_bubbleRadius),
        ),
        child: Column(
          crossAxisAlignment:
          widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // ===== IMAGE =====
            if (hasAttachment && isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(widget.fileUrl!, width: 220, height: 220),
              ),

            // ===== VIDEO =====
            if (hasAttachment && isVideo && _videoController != null)
              Column(
                children: [
                  AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                  IconButton(
                    icon: Icon(
                      _videoController!.value.isPlaying
                          ? Icons.pause_circle
                          : Icons.play_circle,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () {
                      setState(() {
                        _videoController!.value.isPlaying
                            ? _videoController!.pause()
                            : _videoController!.play();
                      });
                    },
                  ),
                ],
              ),

            // ===== AUDIO =====
            if (hasAttachment && isAudio)
              GestureDetector(
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
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isPlaying ? 'Playing' : 'Voice Message',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

            // ===== GENERIC FILE =====
            if (hasAttachment && isGenericFile)
              GestureDetector(
                onTap: _openFile,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      widget.fileName ?? 'File',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),

            // ===== TEXT =====
            if (widget.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.text,
                  style: TextStyle(color: textColor, fontSize: 15),
                ),
              ),

            // ===== TIME + SEEN =====
            if (widget.showTimestamp)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.timeLabel,
                      style: TextStyle(color: timeColor, fontSize: 10),
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
