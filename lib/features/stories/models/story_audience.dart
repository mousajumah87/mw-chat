// lib/features/stories/models/story_audience.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class StoryAudience {
  const StoryAudience({
    required this.storyId,
    required this.viewerId,
    required this.seenAt,
  });

  final String storyId;
  final String viewerId;
  final DateTime? seenAt;

  Map<String, dynamic> toMap() {
    return {
      'storyId': storyId,
      'viewerId': viewerId,
      'seenAt': seenAt != null ? Timestamp.fromDate(seenAt!) : null,
    };
  }

  factory StoryAudience.fromMap(Map<String, dynamic> map) {
    return StoryAudience(
      storyId: (map['storyId'] ?? '').toString(),
      viewerId: (map['viewerId'] ?? '').toString(),
      seenAt: _readDateTime(map['seenAt']),
    );
  }

  factory StoryAudience.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return StoryAudience.fromMap(data);
  }

  StoryAudience copyWith({
    String? storyId,
    String? viewerId,
    DateTime? seenAt,
  }) {
    return StoryAudience(
      storyId: storyId ?? this.storyId,
      viewerId: viewerId ?? this.viewerId,
      seenAt: seenAt ?? this.seenAt,
    );
  }

  static DateTime? _readDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}