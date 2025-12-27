// lib/widgets/chat/mw_reply_to.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Snapshot of a replied-to message.
/// We store a snapshot so the reply preview still works even if original is deleted.
class MwReplyTo {
  final String messageId;
  final String senderId;

  /// text|image|video|audio|file|voice (keep stable)
  final String type;

  /// short preview for UI
  final String previewText;

  final String? fileName;
  final Timestamp? createdAt;

  const MwReplyTo({
    required this.messageId,
    required this.senderId,
    required this.type,
    required this.previewText,
    this.fileName,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'senderId': senderId,
    'type': type,
    'previewText': previewText,
    if (fileName != null) 'fileName': fileName,
    if (createdAt != null) 'createdAt': createdAt,
  };

  /// More tolerant parser:
  /// - accepts Map<dynamic,dynamic>
  /// - defaults type to 'text' if missing
  /// - accepts older key variants (reply_to / reply)
  static MwReplyTo? fromMap(dynamic raw) {
    if (raw == null) return null;

    // Sometimes saved as Map<dynamic,dynamic>
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw as Map);

    final messageId = (m['messageId'] ?? '').toString().trim();
    final senderId = (m['senderId'] ?? '').toString().trim();

    // ✅ tolerate missing/empty type
    String type = (m['type'] ?? '').toString().trim();
    if (type.isEmpty) type = 'text';

    String previewText = (m['previewText'] ?? '').toString();
    previewText = previewText.trim();

    if (messageId.isEmpty || senderId.isEmpty) return null;

    final dynamic ts = m['createdAt'];
    final createdAt = ts is Timestamp ? ts : null;

    final fn = (m['fileName'] as String?)?.toString().trim();

    return MwReplyTo(
      messageId: messageId,
      senderId: senderId,
      type: type,
      previewText: previewText.isEmpty ? '…' : previewText,
      fileName: (fn == null || fn.isEmpty) ? null : fn,
      createdAt: createdAt,
    );
  }

  /// Build reply snapshot from a message document.
  static MwReplyTo fromMessageDoc({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    required String fallbackType,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};

    final senderId = (data['senderId'] ?? '').toString().trim();
    String type = (data['type'] ?? fallbackType).toString().trim();
    if (type.isEmpty) type = 'text';

    final text = (data['text'] ?? '').toString().trim();
    final fileName = (data['fileName'] ?? '').toString().trim();

    String preview = text;

    if (preview.isEmpty) {
      if (type == 'image') preview = '📷 Photo';
      else if (type == 'video') preview = '🎥 Video';
      else if (type == 'voice') preview = '🎤 Voice note';
      else if (type == 'audio') preview = '🎙️ Audio';
      else preview = fileName.isNotEmpty ? '📎 $fileName' : '📎 Attachment';
    }

    final createdAt =
    data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null;

    final safePreview = preview.length > 140 ? '${preview.substring(0, 140)}…' : preview;

    return MwReplyTo(
      messageId: doc.id,
      senderId: senderId,
      type: type,
      previewText: safePreview,
      fileName: fileName.isEmpty ? null : fileName,
      createdAt: createdAt,
    );
  }
}
