import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  final String text;
  final String timeLabel;
  final bool isMe;
  final bool isSeen;
  final String? fileUrl;
  final String? fileName;
  final String? fileType;
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

  bool get hasAttachment => fileUrl?.isNotEmpty == true;
  bool get isImage => (fileType ?? '').toLowerCase() == 'image';

  static const _bubbleRadius = 16.0;
  static const _myBubbleColor = Color(0xFF2563EB); // MW Blue
  static const _theirBubbleColor = Color(0xFF1E1E1E); // Dark Gray

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.white;
    final timeColor = isMe
        ? Colors.white70.withOpacity(0.8)
        : Colors.white.withOpacity(0.65);
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    return RepaintBoundary(
      child: AnimatedSlide(
        offset: const Offset(0, 0.05),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeIn,
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: BoxConstraints(maxWidth: maxWidth),
              decoration: BoxDecoration(
                color: isMe ? _myBubbleColor : _theirBubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(_bubbleRadius),
                  topRight: const Radius.circular(_bubbleRadius),
                  bottomLeft:
                  Radius.circular(isMe ? _bubbleRadius : _bubbleRadius / 3),
                  bottomRight:
                  Radius.circular(isMe ? _bubbleRadius / 3 : _bubbleRadius),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2.5,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // === Attachment (Lightweight & Cached) ===
                  if (hasAttachment && isImage)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          fileUrl!,
                          fit: BoxFit.cover,
                          width: 200,
                          height: 200,
                          filterQuality: FilterQuality.low,
                          cacheWidth: 400, // mobile-optimized
                          cacheHeight: 400,
                          loadingBuilder: (context, child, event) {
                            if (event == null) return child;
                            return const SizedBox(
                              width: 200,
                              height: 200,
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.3,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => const SizedBox(
                            width: 200,
                            height: 200,
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // === Message Text ===
                  if (text.isNotEmpty)
                    Text(
                      text,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        height: 1.35,
                      ),
                      softWrap: true,
                    ),

                  // === Timestamp & Seen marker ===
                  if (showTimestamp)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeLabel,
                            style: TextStyle(
                              color: timeColor,
                              fontSize: 10,
                              height: 1.2,
                            ),
                          ),
                          if (isMe)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                isSeen ? Icons.done_all : Icons.done,
                                size: 12,
                                color: isSeen
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
          ),
        ),
      ),
    );
  }
}
