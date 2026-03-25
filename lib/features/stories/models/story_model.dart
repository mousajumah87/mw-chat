// lib/features/stories/models/story_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum StoryVisibility {
  public,
  friends,
  custom;

  String get value {
    switch (this) {
      case StoryVisibility.public:
        return 'public';
      case StoryVisibility.friends:
        return 'friends';
      case StoryVisibility.custom:
        return 'custom';
    }
  }

  static StoryVisibility fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'friends':
        return StoryVisibility.friends;
      case 'custom':
        return StoryVisibility.custom;
      case 'public':
      default:
        return StoryVisibility.public;
    }
  }
}

enum StoryMediaType {
  image,
  video,
  text;

  String get value {
    switch (this) {
      case StoryMediaType.image:
        return 'image';
      case StoryMediaType.video:
        return 'video';
      case StoryMediaType.text:
        return 'text';
    }
  }

  static StoryMediaType fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'video':
        return StoryMediaType.video;
      case 'text':
        return StoryMediaType.text;
      case 'image':
      default:
        return StoryMediaType.image;
    }
  }
}

class StoryModel {
  const StoryModel({
    required this.id,
    required this.ownerId,
    required this.mediaUrl,
    required this.mediaType,
    required this.text,
    required this.visibility,
    required this.allowedViewerIds,
    required this.viewerIds,
    required this.viewerCount,
    required this.backgroundColor,
    required this.textColor,
    required this.linkUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String id;
  final String ownerId;
  final String? mediaUrl;
  final StoryMediaType mediaType;
  final String? text;
  final StoryVisibility visibility;
  final List<String> allowedViewerIds;
  final List<String> viewerIds;
  final int viewerCount;
  final String? backgroundColor;
  final String? textColor;
  final String? linkUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  bool get isImage => mediaType == StoryMediaType.image;
  bool get isVideo => mediaType == StoryMediaType.video;
  bool get isText => mediaType == StoryMediaType.text;

  bool seenBy(String uid) => viewerIds.contains(uid);

  StoryModel copyWith({
    String? id,
    String? ownerId,
    Object? mediaUrl = _noChange,
    StoryMediaType? mediaType,
    Object? text = _noChange,
    StoryVisibility? visibility,
    List<String>? allowedViewerIds,
    List<String>? viewerIds,
    int? viewerCount,
    Object? backgroundColor = _noChange,
    Object? textColor = _noChange,
    Object? linkUrl = _noChange,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
  }) {
    return StoryModel(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      mediaUrl: identical(mediaUrl, _noChange) ? this.mediaUrl : mediaUrl as String?,
      mediaType: mediaType ?? this.mediaType,
      text: identical(text, _noChange) ? this.text : text as String?,
      visibility: visibility ?? this.visibility,
      allowedViewerIds: allowedViewerIds ?? this.allowedViewerIds,
      viewerIds: viewerIds ?? this.viewerIds,
      viewerCount: viewerCount ?? this.viewerCount,
      backgroundColor: identical(backgroundColor, _noChange)
          ? this.backgroundColor
          : backgroundColor as String?,
      textColor:
      identical(textColor, _noChange) ? this.textColor : textColor as String?,
      linkUrl: identical(linkUrl, _noChange) ? this.linkUrl : linkUrl as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType.value,
      'text': text,
      'visibility': visibility.value,
      'allowedViewerIds': allowedViewerIds,
      'viewerIds': viewerIds,
      'viewerCount': viewerCount,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'linkUrl': linkUrl,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    };
  }

  factory StoryModel.fromMap(
      Map<String, dynamic> map, {
        required String id,
      }) {
    final allowedViewerIds = _readStringList(map['allowedViewerIds']);
    final viewerIds = _readStringList(map['viewerIds']);
    final rawViewerCount = _readInt(map['viewerCount']);
    final normalizedViewerCount =
    rawViewerCount > viewerIds.length ? rawViewerCount : viewerIds.length;

    return StoryModel(
      id: id,
      ownerId: (map['ownerId'] ?? '').toString().trim(),
      mediaUrl: _readNullableString(map['mediaUrl']),
      mediaType: StoryMediaType.fromString(map['mediaType']?.toString()),
      text: _readNullableString(map['text']),
      visibility: StoryVisibility.fromString(map['visibility']?.toString()),
      allowedViewerIds: allowedViewerIds,
      viewerIds: viewerIds,
      viewerCount: normalizedViewerCount,
      backgroundColor: _readNullableString(map['backgroundColor']),
      textColor: _readNullableString(map['textColor']),
      linkUrl: _readNullableString(map['linkUrl']),
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
      expiresAt: _readDateTime(map['expiresAt']),
    );
  }

  factory StoryModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return StoryModel.fromMap(data, id: doc.id);
  }

  static DateTime? _readDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static int _readInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  static String? _readNullableString(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const <String>[];

    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  static DateTime defaultExpiresAt({
    Duration lifetime = const Duration(hours: 24),
  }) {
    return DateTime.now().add(lifetime);
  }

  static const Object _noChange = Object();
}