//lib/features/group/models/chat_message_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String type; // text, system
  final String? text;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final bool deletedForEveryone;
  final String? deletedBy;
  final DateTime? deletedAt;
  final String? replyToMessageId;
  final Map<String, dynamic>? replyTo;
  final List<String> hiddenFor;
  final List<String> seenBy;

  const ChatMessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    required this.type,
    this.text,
    this.createdAt,
    this.editedAt,
    required this.deletedForEveryone,
    this.deletedBy,
    this.deletedAt,
    this.replyToMessageId,
    this.replyTo,
    this.hiddenFor = const <String>[],
    this.seenBy = const <String>[],
  });

  bool get isSystemMessage => type.trim().toLowerCase() == 'system';

  bool get hasReply =>
      replyTo != null || (replyToMessageId?.trim().isNotEmpty ?? false);

  factory ChatMessageModel.fromMap(String id, Map<String, dynamic> map) {
    final replyMap = map['replyTo'];
    final normalizedReply =
    replyMap is Map ? Map<String, dynamic>.from(replyMap) : null;

    final rawType = ((map['type'] as String?) ?? 'text').trim();

    return ChatMessageModel(
      id: id,
      senderId: (map['senderId'] as String?)?.trim() ?? '',
      senderName: (map['senderName'] as String?)?.trim() ?? '',
      senderPhotoUrl: _readNullableString(map['senderPhotoUrl']),
      type: rawType.isEmpty ? 'text' : rawType,
      text: _readNullableString(map['text']),
      createdAt:
      _readDateTime(map['createdAt']) ?? _readDateTime(map['clientCreatedAt']),
      editedAt: _readDateTime(map['editedAt']),
      deletedForEveryone: (map['deletedForEveryone'] as bool?) ?? false,
      deletedBy: _readNullableString(map['deletedBy']),
      deletedAt: _readDateTime(map['deletedAt']),
      replyToMessageId: _readNullableString(map['replyToMessageId']) ??
          _readNullableString(normalizedReply?['messageId']),
      replyTo: normalizedReply,
      hiddenFor: _readStringList(map['hiddenFor']),
      seenBy: _readStringList(map['seenBy']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'type': type,
      'text': text,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'editedAt': editedAt == null ? null : Timestamp.fromDate(editedAt!),
      'deletedForEveryone': deletedForEveryone,
      'deletedBy': deletedBy,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'replyToMessageId': replyToMessageId,
      'replyTo': replyTo,
      'hiddenFor': hiddenFor,
      'seenBy': seenBy,
    };
  }

  ChatMessageModel copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? senderPhotoUrl,
    String? type,
    String? text,
    DateTime? createdAt,
    DateTime? editedAt,
    bool? deletedForEveryone,
    String? deletedBy,
    DateTime? deletedAt,
    String? replyToMessageId,
    Map<String, dynamic>? replyTo,
    List<String>? hiddenFor,
    List<String>? seenBy,
    bool clearSenderPhotoUrl = false,
    bool clearText = false,
    bool clearDeletedBy = false,
    bool clearDeletedAt = false,
    bool clearReplyToMessageId = false,
    bool clearReplyTo = false,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderPhotoUrl:
      clearSenderPhotoUrl ? null : (senderPhotoUrl ?? this.senderPhotoUrl),
      type: type ?? this.type,
      text: clearText ? null : (text ?? this.text),
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      deletedBy: clearDeletedBy ? null : (deletedBy ?? this.deletedBy),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      replyToMessageId: clearReplyToMessageId
          ? null
          : (replyToMessageId ?? this.replyToMessageId),
      replyTo: clearReplyTo ? null : (replyTo ?? this.replyTo),
      hiddenFor: hiddenFor ?? this.hiddenFor,
      seenBy: seenBy ?? this.seenBy,
    );
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String? _readNullableString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const <String>[];

    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }
}