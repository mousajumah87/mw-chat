import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoomModel {
  final String id;
  final String type; // group
  final String? name;
  final String? photoUrl;

  final List<String> memberIds;
  final List<String> adminIds;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? lastMessageText;
  final String? lastMessageSenderId;
  final String? lastMessageSenderName;
  final String? lastMessageType;

  const ChatRoomModel({
    required this.id,
    required this.type,
    this.name,
    this.photoUrl,
    required this.memberIds,
    this.adminIds = const <String>[],
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.lastMessageText,
    this.lastMessageSenderId,
    this.lastMessageSenderName,
    this.lastMessageType,
  });

  bool get isGroup => type.trim().toLowerCase() == 'group';

  bool get hasPhoto => (photoUrl ?? '').trim().isNotEmpty;

  factory ChatRoomModel.fromMap(String id, Map<String, dynamic> map) {
    final type = ((map['type'] as String?) ?? 'group').trim();
    final createdBy = _readNullableString(map['createdBy']);
    final adminIds = _readStringList(map['adminIds']);

    final memberIds = _readStringList(map['memberIds']);
    final fallbackParticipants = _readStringList(map['participants']);

    final resolvedMembers = memberIds.isNotEmpty ? memberIds : fallbackParticipants;

    return ChatRoomModel(
      id: id,
      type: type.isEmpty ? 'group' : type,
      name: _readNullableString(map['name']),
      photoUrl: _readNullableString(map['photoUrl']),
      memberIds: resolvedMembers,
      adminIds: adminIds.isNotEmpty
          ? adminIds
          : (createdBy == null ? const <String>[] : <String>[createdBy]),
      createdBy: createdBy,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
      lastMessageText: _readNullableString(map['lastMessageText']),
      lastMessageSenderId: _readNullableString(map['lastMessageSenderId']),
      lastMessageSenderName: _readNullableString(map['lastMessageSenderName']),
      lastMessageType: _readNullableString(map['lastMessageType']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'name': name,
      'photoUrl': photoUrl,
      'memberIds': memberIds,
      'participants': memberIds,
      'adminIds': adminIds,
      'createdBy': createdBy,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'lastMessageText': lastMessageText,
      'lastMessageSenderId': lastMessageSenderId,
      'lastMessageSenderName': lastMessageSenderName,
      'lastMessageType': lastMessageType,
    };
  }

  ChatRoomModel copyWith({
    String? id,
    String? type,
    String? name,
    String? photoUrl,
    List<String>? memberIds,
    List<String>? adminIds,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastMessageText,
    String? lastMessageSenderId,
    String? lastMessageSenderName,
    String? lastMessageType,
    bool clearPhotoUrl = false,
    bool clearName = false,
    bool clearCreatedBy = false,
    bool clearLastMessageText = false,
    bool clearLastMessageSenderId = false,
    bool clearLastMessageSenderName = false,
    bool clearLastMessageType = false,
  }) {
    return ChatRoomModel(
      id: id ?? this.id,
      type: type ?? this.type,
      name: clearName ? null : (name ?? this.name),
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      memberIds: memberIds ?? this.memberIds,
      adminIds: adminIds ?? this.adminIds,
      createdBy: clearCreatedBy ? null : (createdBy ?? this.createdBy),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageText: clearLastMessageText
          ? null
          : (lastMessageText ?? this.lastMessageText),
      lastMessageSenderId: clearLastMessageSenderId
          ? null
          : (lastMessageSenderId ?? this.lastMessageSenderId),
      lastMessageSenderName: clearLastMessageSenderName
          ? null
          : (lastMessageSenderName ?? this.lastMessageSenderName),
      lastMessageType: clearLastMessageType
          ? null
          : (lastMessageType ?? this.lastMessageType),
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