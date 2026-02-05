import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../theme/app_theme.dart';
import '../../utils/chat_attachment_utils.dart';
import '../../utils/io/file_image_provider.dart';

// ✅ Web-safe: conditional import for io File
import '../../utils/io/io_file_stub.dart'
if (dart.library.io) '../../utils/io/io_file.dart';

// ✅ Web thumbnail + preview helpers
import '../../utils/web/web_video_thumbnail_stub.dart'
if (dart.library.html) '../../utils/web/web_video_thumbnail.dart';

import '../../utils/web/web_video_preview_stub.dart'
if (dart.library.html) '../../utils/web/web_video_preview.dart';

class PendingAttachment {
  final PlatformFile file;
  final String type; // 'image' | 'video' | 'audio' | 'file'

  const PendingAttachment({required this.file, required this.type});

  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';
  bool get isAudio => type == 'audio';
  bool get isFile => type == 'file';
}

typedef PreviewSendFn = Future<void> Function(
    List<PendingAttachment> items,
    String caption,
    );

class ChatMediaPreviewSheet extends StatefulWidget {
  final List<PendingAttachment> initialItems;
  final PreviewSendFn onSend;

  const ChatMediaPreviewSheet({
    super.key,
    required this.initialItems,
    required this.onSend,
  });

  static Future<void> open(
      BuildContext context, {
        required List<PendingAttachment> items,
        required PreviewSendFn onSend,
      }) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatMediaPreviewSheet(initialItems: items, onSend: onSend),
    );
  }

  @override
  State<ChatMediaPreviewSheet> createState() => _ChatMediaPreviewSheetState();
}

class _ChatMediaPreviewSheetState extends State<ChatMediaPreviewSheet> {
  late List<PendingAttachment> _items;
  final _captionCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initialItems);
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  void _removeAt(int i) {
    if (!mounted) return;
    setState(() => _items.removeAt(i));
    if (_items.isEmpty && mounted) Navigator.of(context).pop();
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_items.isEmpty) return;

    setState(() => _sending = true);
    try {
      await widget.onSend(_items, _captionCtrl.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send. Please try again.')),
      );
    }
  }

  Future<void> _openVideoPreview(PendingAttachment it) async {
    if (!mounted) return;

    final pf = it.file;

    // ✅ WEB: preview from bytes
    if (kIsWeb) {
      final bytes = pf.bytes;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Web preview needs bytes (withData: true).')),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => WebVideoPreviewDialog(bytes: bytes),
      );
      return;
    }

    // ✅ iOS/Android/Desktop: Prefer real path if usable
    final normalizedPath = _normalizeVideoPath(pf.path);
    if (_isUsableVideoPath(normalizedPath)) {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => _VideoPreviewDialog(path: normalizedPath!),
      );
      return;
    }

    // ✅ Fallback: if we have bytes, write temp video and preview it
    final bytes = pf.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      final tempPath = await _writeTempVideoFromBytes(
        bytes: bytes,
        originalName: pf.name,
      );
      if (!mounted) return;
      if (tempPath == null) return;

      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => _VideoPreviewDialog(path: tempPath),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Missing local video data for preview.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final height = mq.size.height * 0.82;

    return SafeArea(
      top: false,
      child: Container(
        height: height,
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: kSurfaceAltColor.withOpacity(0.97),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.20),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text(
                    'Preview (${_items.length}/${ChatAttachmentUtils.defaultMaxSelection})',
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: kTextPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.builder(
                  itemCount: _items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    final key = ValueKey<String>(
                      '${it.type}:${it.file.path ?? ''}:${it.file.name}:${it.file.size}',
                    );
                    return _PreviewTile(
                      key: key,
                      item: it,
                      onRemove: () => _removeAt(i),
                      onOpen: it.isVideo ? () => _openVideoPreview(it) : null,
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: mq.viewInsets.bottom + 12,
                top: 6,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionCtrl,
                      maxLines: 2,
                      minLines: 1,
                      enabled: !_sending,
                      style: const TextStyle(color: kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Add a caption…',
                        hintStyle: TextStyle(color: kTextSecondary.withOpacity(0.8)),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: kBorderColor.withOpacity(0.35)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: kBorderColor.withOpacity(0.35)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: kPrimaryGold.withOpacity(0.55)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 46,
                    width: 46,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: kPrimaryGold.withOpacity(0.95),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _sending
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.send, color: Colors.black),
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

class _PreviewTile extends StatelessWidget {
  final PendingAttachment item;
  final VoidCallback onRemove;
  final VoidCallback? onOpen;

  const _PreviewTile({
    super.key,
    required this.item,
    required this.onRemove,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final pf = item.file;

    Widget body;

    if (item.isImage) {
      final Uint8List? bytes = pf.bytes;
      final String? path = pf.path;

      if (bytes != null && bytes.isNotEmpty) {
        body = Image.memory(bytes, fit: BoxFit.cover);
      } else if (!kIsWeb && path != null && path.trim().isNotEmpty) {
        final prov = fileImageProvider(path);
        body = (prov != null)
            ? Image(image: prov, fit: BoxFit.cover)
            : _cleanPlaceholder(icon: Icons.image);
      } else {
        body = _cleanPlaceholder(icon: Icons.image);
      }
    } else if (item.isVideo) {
      body = _VideoThumb(platformFile: pf);
    } else if (item.isAudio) {
      body = _cleanPlaceholder(icon: Icons.audiotrack);
    } else {
      body = _cleanPlaceholder(icon: Icons.insert_drive_file);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              body,
              if (item.isVideo)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'VIDEO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _cleanPlaceholder({required IconData icon}) {
    return Container(
      color: Colors.black.withOpacity(0.10),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white.withOpacity(0.65)),
    );
  }
}

String? _normalizeVideoPath(String? raw) {
  final pth = (raw ?? '').trim();
  if (pth.isEmpty) return null;
  if (pth.startsWith('file://')) return pth.replaceFirst('file://', '');
  return pth;
}

bool _isUsableVideoPath(String? path) {
  if (path == null) return false;
  final t = path.trim();
  if (t.isEmpty) return false;
  if (t.startsWith('ph://')) return false;
  return true;
}

Future<String?> _writeTempVideoFromBytes({
  required Uint8List bytes,
  required String originalName,
}) async {
  if (kIsWeb) return null;
  if (bytes.isEmpty) return null;

  try {
    final dir = await getTemporaryDirectory();

    final ext = p.extension(originalName).toLowerCase();
    final safeExt = (ext.isNotEmpty) ? ext : '.mp4';

    final fileName = 'mw_vid_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    final full = p.join(dir.path, fileName);

    final f = ioFile(full);
    await f.writeAsBytes(bytes, flush: true);
    return full;
  } catch (_) {
    return null;
  }
}

class _VideoThumb extends StatefulWidget {
  final PlatformFile platformFile;
  const _VideoThumb({required this.platformFile});

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  static final Map<String, Uint8List> _thumbCache = <String, Uint8List>{};
  static final Map<String, String> _tempVideoPathCache = <String, String>{};

  Uint8List? _thumb;
  bool _loading = false;

  String get _cacheKey {
    final pf = widget.platformFile;
    final path = _normalizeVideoPath(pf.path);
    if (_isUsableVideoPath(path)) return 'path:$path';
    return 'bytes:${pf.name}|${pf.size}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _VideoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.platformFile.path ?? '') != (widget.platformFile.path ?? '') ||
        oldWidget.platformFile.name != widget.platformFile.name ||
        oldWidget.platformFile.size != widget.platformFile.size) {
      _thumb = null;
      _loading = false;
      _load();
    }
  }

  Future<String?> _resolveVideoPathForThumb() async {
    final pf = widget.platformFile;

    final normalized = _normalizeVideoPath(pf.path);
    if (_isUsableVideoPath(normalized)) return normalized;

    final key = _cacheKey;
    final cachedTemp = _tempVideoPathCache[key];
    if (cachedTemp != null && cachedTemp.trim().isNotEmpty) {
      return cachedTemp;
    }

    final bytes = pf.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      final tempPath = await _writeTempVideoFromBytes(
        bytes: bytes,
        originalName: pf.name,
      );
      if (tempPath != null) _tempVideoPathCache[key] = tempPath;
      return tempPath;
    }

    return null;
  }

  Future<Uint8List?> _makeThumbBytes(String videoPath, {required int timeMs}) async {
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 360,
        quality: 75,
        timeMs: timeMs,
      );
      if (data == null || data.isEmpty) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final key = _cacheKey;

    final cached = _thumbCache[key];
    if (cached != null) {
      if (mounted) setState(() => _thumb = cached);
      return;
    }

    if (_loading) return;
    _loading = true;

    try {
      final pf = widget.platformFile;

      // ✅ WEB: thumbnail from bytes
      if (kIsWeb) {
        final bytes = pf.bytes;
        if (bytes == null || bytes.isEmpty) return;

        Uint8List? thumb = await webVideoThumbnailFromBytes(bytes, timeMs: 500);
        thumb ??= await webVideoThumbnailFromBytes(bytes, timeMs: 0);

        if (!mounted) return;
        if (thumb == null || thumb.isEmpty) return;

        _thumbCache[key] = thumb;
        setState(() => _thumb = thumb);
        return;
      }

      // ✅ iOS/Android/Desktop: use video_thumbnail on file path
      final videoPath = await _resolveVideoPathForThumb();
      if (!mounted) return;
      if (videoPath == null || videoPath.trim().isEmpty) return;

      Uint8List? bytes = await _makeThumbBytes(videoPath, timeMs: 1000);
      bytes ??= await _makeThumbBytes(videoPath, timeMs: 0);

      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) return;

      _thumbCache[key] = bytes;
      setState(() => _thumb = bytes);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _thumb;

    // ✅ show on ALL platforms (including web)
    if (b != null && b.isNotEmpty) {
      return Image.memory(b, fit: BoxFit.cover);
    }
    return _PreviewTile._cleanPlaceholder(icon: Icons.videocam);
  }
}

class _VideoPreviewDialog extends StatefulWidget {
  final String path;
  const _VideoPreviewDialog({required this.path});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();

    final normalized = widget.path.startsWith('file://')
        ? widget.path.replaceFirst('file://', '')
        : widget.path;

    final file = ioFile(normalized);

    final c = VideoPlayerController.file(file);
    _controller = c;

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
      _controller?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

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
            if (_ready && c != null && c.value.isInitialized)
              Positioned(
                left: 10,
                bottom: 10,
                child: IconButton(
                  onPressed: () {
                    if (!mounted) return;
                    if (c.value.isPlaying) {
                      c.pause();
                    } else {
                      c.play();
                    }
                    setState(() {});
                  },
                  icon: Icon(
                    c.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
