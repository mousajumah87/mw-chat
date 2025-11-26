import 'dart:ui';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class MessageBubble extends StatelessWidget {
  final String text;
  final String timeLabel;
  final bool isMe;
  final bool isSeen;

  final String? fileUrl;
  final String? fileName;
  final String? fileType; // 'image' | 'video' | 'audio' | 'file'

  const MessageBubble({
    super.key,
    required this.text,
    required this.timeLabel,
    required this.isMe,
    required this.isSeen,
    this.fileUrl,
    this.fileName,
    this.fileType,
  });

  bool get hasAttachment => fileUrl != null && fileUrl!.isNotEmpty;
  String get _type => (fileType ?? '').toLowerCase();
  bool get isImage => _type == 'image';
  bool get isVideo => _type == 'video';
  bool get isAudio => _type == 'audio';

  void _openFullScreenImage(BuildContext context) {
    if (fileUrl == null) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  fileUrl!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachment(
      BuildContext context,
      AppLocalizations l10n,
      Color textColor,
      ) {
    if (!hasAttachment) return const SizedBox.shrink();

    // IMAGE ATTACHMENT
    if (isImage) {
      return GestureDetector(
        onTap: () => _openFullScreenImage(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
              ),
              constraints: const BoxConstraints(
                maxWidth: 260,
                maxHeight: 260,
              ),
              child: Image.network(
                fileUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    width: 200,
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    height: 120,
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.white70,
                      size: 40,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    // FILE / VIDEO / AUDIO
    IconData icon;
    if (isAudio) {
      icon = Icons.audiotrack;
    } else if (isVideo) {
      icon = Icons.videocam;
    } else {
      icon = Icons.insert_drive_file;
    }

    final label =
    fileName?.trim().isNotEmpty == true ? fileName! : l10n.attachment;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final textColor = isMe ? Colors.white : Colors.white;
    final timeColor = Colors.white70.withOpacity(isMe ? 0.7 : 0.9);

    // Bubble gradient colors (for glass style)
    final bubbleGradient = isMe
        ? const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xCC0057FF), Color(0xCCFFB300)],
    )
        : const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0x334A4A4A), Color(0x552A2A2A)],
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft:
            isMe ? const Radius.circular(18) : const Radius.circular(6),
            bottomRight:
            isMe ? const Radius.circular(6) : const Radius.circular(18),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: bubbleGradient,
                border: Border.all(
                  color: Colors.white.withOpacity(isSeen ? 0.25 : 0.12),
                  width: 0.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasAttachment) ...[
                    _buildAttachment(context, l10n, textColor),
                    const SizedBox(height: 6),
                  ],
                  if (text.isNotEmpty)
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 15,
                        color: textColor,
                        height: 1.3,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: timeColor,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isSeen ? Icons.done_all : Icons.done,
                          size: 14,
                          color: isSeen ? Colors.lightBlueAccent : timeColor,
                        ),
                      ],
                    ],
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
