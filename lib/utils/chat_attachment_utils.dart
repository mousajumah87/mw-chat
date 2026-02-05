// lib/utils/chat_attachment_utils.dart
//
// Shared attachment normalization + UI helpers for chat.
// Keeps MessageBubble + message list consistent across iOS/Android/Web.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';

@immutable
class NormalizedAttachment {
  final String? url;
  final String? name;

  /// Canonical type used by UI widgets:
  /// - "image" / "video" / "audio" / "file"
  /// - or mime-like "image/*", "video/*", "audio/*"
  final String? type;

  const NormalizedAttachment({
    required this.url,
    required this.name,
    required this.type,
  });

  bool get hasUrl => (url ?? '').trim().isNotEmpty;

  String get typeLower => (type ?? '').trim().toLowerCase();
}

/// Represents a media item selected by the user *before sending*.
/// Works on:
/// - Mobile/desktop: uses [path]
/// - Web: uses [bytes]
@immutable
class PendingMediaItem {
  final String id;
  final String type; // "image" | "video"
  final PlatformFile file;

  const PendingMediaItem({
    required this.id,
    required this.type,
    required this.file,
  });

  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';

  String get name => file.name;
  Uint8List? get bytes => file.bytes;
  String? get path => file.path;

  String get ext => ChatAttachmentUtils.extFrom(file.name);
}

class ChatAttachmentUtils {
  ChatAttachmentUtils._();

  // -------------------------
  // Normalization
  // -------------------------

  static NormalizedAttachment normalizeAttachment(Map<String, dynamic> data) {
    String? url;
    String? name;
    String? type;

    // Preferred modern fields
    url = (data['fileUrl'] as String?)?.trim();
    name = (data['fileName'] as String?)?.trim();
    type = (data['type'] as String?)?.trim();

    // Back/alt fields
    url ??= (data['voiceUrl'] as String?)?.trim();
    url ??= (data['audioUrl'] as String?)?.trim();
    url ??= (data['mediaUrl'] as String?)?.trim();
    url ??= (data['imageUrl'] as String?)?.trim();
    url ??= (data['videoUrl'] as String?)?.trim();
    url ??= (data['url'] as String?)?.trim();

    // Some senders store media map
    final media = data['media'];
    if ((url == null || url.isEmpty) && media is Map) {
      final m = media.cast<String, dynamic>();
      url = (m['url'] as String?)?.trim() ?? (m['downloadUrl'] as String?)?.trim();
      type ??= (m['type'] as String?)?.trim();
      name ??= (m['name'] as String?)?.trim();
    }

    // Normalize voice variants -> audio
    final t = (type ?? '').toLowerCase().trim();
    if (_isVoiceAlias(t)) {
      type = 'audio';
    }

    // Infer type if missing/unknown
    type = _inferTypeIfNeeded(type, name, url);

    final cleanUrl = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
    final cleanName = (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    final cleanType = (type != null && type.trim().isNotEmpty) ? type.trim() : null;

    return NormalizedAttachment(url: cleanUrl, name: cleanName, type: cleanType);
  }

  static String? _inferTypeIfNeeded(String? type, String? name, String? url) {
    final t = (type ?? '').toLowerCase().trim();
    if (t.isNotEmpty) {
      if (_isImageType(t) || _isVideoType(t) || _isAudioType(t)) return type;
      if (t == 'file') return 'file';
      if (_isVoiceAlias(t)) return 'audio';
    }

    final n = (name ?? '').toLowerCase().trim();
    final u = (url ?? '').toLowerCase().trim();

    final ext = extFrom(n).isNotEmpty ? extFrom(n) : extFrom(u);

    // audio first (webm sometimes voice)
    final looksVoice = n.contains('voice') ||
        n.contains('audio') ||
        n.contains('record') ||
        n.contains('rec') ||
        n.contains('mic');

    if (ext == 'webm' && looksVoice) return 'audio';

    // ✅ Expanded for real device camera outputs
    const imageExtsLocal = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif'};
    const videoExtsLocal = {'mp4', 'mov', 'mkv', 'avi', 'm4v', 'webm', '3gp', 'qt'};
    const audioExtsLocal = {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'webm'};

    if (imageExtsLocal.contains(ext) || u.contains('/image/') || u.contains('image/')) {
      return 'image';
    }
    if (videoExtsLocal.contains(ext) || u.contains('/video/') || u.contains('video/')) {
      return 'video';
    }
    if (audioExtsLocal.contains(ext) || u.contains('/audio/') || u.contains('audio/')) {
      return 'audio';
    }

    if (u.isNotEmpty) return 'file';
    return null;
  }

  static bool _isVoiceAlias(String t) {
    return t == 'voice' || t == 'voice_note' || t == 'voicenote' || t == 'voice-message';
  }

  // -------------------------
  // Type helpers
  // -------------------------

  static bool isImage(NormalizedAttachment att) => _isImageType(att.typeLower);
  static bool isVideo(NormalizedAttachment att) => _isVideoType(att.typeLower);
  static bool isAudio(NormalizedAttachment att) => _isAudioType(att.typeLower);
  static bool isFile(NormalizedAttachment att) {
    final t = att.typeLower;
    if (t.isEmpty) return false;
    return t == 'file' || (!_isImageType(t) && !_isVideoType(t) && !_isAudioType(t));
  }

  static bool _isImageType(String t) => t == 'image' || t.startsWith('image/');
  static bool _isVideoType(String t) => t == 'video' || t.startsWith('video/');
  static bool _isAudioType(String t) => t == 'audio' || t.startsWith('audio/') || _isVoiceAlias(t);

  static String extFrom(String s) {
    final clean = s.split('?').first.split('#').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return '';
    return clean.substring(dot + 1).toLowerCase();
  }

  static String extFromPlatformFile(PlatformFile f) {
    final e1 = (f.extension ?? '').trim().toLowerCase();
    if (e1.isNotEmpty) return e1;
    return extFrom(f.name);
  }

  // -------------------------
  // UI helpers
  // -------------------------

  /// For image/video we hide device file names in list UI.
  static String? uiFileNameForAttachment(NormalizedAttachment att) {
    if (isImage(att) || isVideo(att)) return null;
    return att.name;
  }

  /// Prevent showing "IMG_..." or "Screen Recording..." when stored as text.
  static String displayTextForMessage(dynamic rawText, NormalizedAttachment att) {
    final text = (rawText ?? '').toString().trim();
    if (text.isEmpty) return '';

    if (isImage(att) || isVideo(att)) {
      final name = (att.name ?? '').trim();
      if (name.isNotEmpty && text.toLowerCase() == name.toLowerCase()) {
        return '';
      }
      if (looksLikeAutoFileName(text)) return '';
    }

    return text;
  }

  static bool looksLikeAutoFileName(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();

    const exts = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.heic',
      '.heif',
      '.mp4',
      '.mov',
      '.webm',
      '.3gp',
      '.m4a',
      '.mp3',
      '.wav',
      '.aac',
      '.pdf',
      '.doc',
      '.docx',
    ];
    for (final e in exts) {
      if (lower.endsWith(e)) return true;
    }

    if (lower.startsWith('img_') ||
        lower.startsWith('vid_') ||
        lower.startsWith('dsc_') ||
        lower.startsWith('pxl_') ||
        lower.contains('screen recording') ||
        lower.contains('screenshot') ||
        lower.contains('screen shot')) {
      return true;
    }

    if (RegExp(r'^(img|vid|dsc|pxl)\s*\d', caseSensitive: false).hasMatch(t)) {
      return true;
    }

    return false;
  }

  static String attachmentLabel(AppLocalizations l10n, NormalizedAttachment att) {
    if (isImage(att)) return l10n.photo;
    if (isVideo(att)) return l10n.videoLabel;
    if (isAudio(att)) return l10n.voiceMessageLabel;
    return l10n.genericFileLabel;
  }

  // ---------------------------------------------------------------------------
  // Multi-pick helpers (for "preview before send" flow)
  // ---------------------------------------------------------------------------

  static const int defaultMaxSelection = 10;

  /// Keep these sets in ONE place so picker + inference + UI stay consistent.
  static const Set<String> imageExts = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
  };

  static const Set<String> videoExts = {
    'mp4',
    'mov',
    'mkv',
    'avi',
    'm4v',
    'webm',
    '3gp',
    'qt',
  };

  /// Decide "image" | "video" from PlatformFile.
  /// Returns null if not supported.
  static String? mediaTypeFromPlatformFile(PlatformFile f) {
    final e = extFromPlatformFile(f);
    if (imageExts.contains(e)) return 'image';
    if (videoExts.contains(e)) return 'video';
    return null;
  }

  /// Picks multiple images/videos (up to [maxSelection]).
  ///
  /// - Web: `withData: true` so preview + upload can use bytes.
  /// - Mobile/Desktop: `withData: false` to avoid huge memory usage; use paths.
  static Future<List<PendingMediaItem>> pickMultiMedia({
    int maxSelection = defaultMaxSelection,
  }) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb, // ✅ web needs bytes
      type: FileType.custom,
      allowedExtensions: [
        ...imageExts,
        ...videoExts,
      ].toList(),
    );

    if (res == null || res.files.isEmpty) return const [];

    final out = <PendingMediaItem>[];
    final nowBase = DateTime.now().microsecondsSinceEpoch;

    for (final f in res.files) {
      if (out.length >= maxSelection) break;

      final t = mediaTypeFromPlatformFile(f);
      if (t == null) continue;

      // ✅ Web must have bytes
      if (kIsWeb && (f.bytes == null || f.bytes!.isEmpty)) continue;

      // ✅ Mobile/Desktop should have a readable path (unless you intentionally support bytes there too)
      if (!kIsWeb && ((f.path ?? '').trim().isEmpty)) continue;

      out.add(
        PendingMediaItem(
          id: '${nowBase}_${out.length}',
          type: t,
          file: f,
        ),
      );
    }

    return out;
  }

}
