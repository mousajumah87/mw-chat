import 'package:cloud_firestore/cloud_firestore.dart';

class StoryAudienceUser {
  final String id;
  final String firstName;
  final String lastName;
  final String displayName;
  final String username;
  final String? photoUrl;
  final bool isActive;
  final bool isFavorite;
  final DateTime? lastInteractionAt;

  const StoryAudienceUser({
    required this.id,
    this.firstName = '',
    this.lastName = '',
    this.displayName = '',
    this.username = '',
    this.photoUrl,
    this.isActive = true,
    this.isFavorite = false,
    this.lastInteractionAt,
  });

  String get fullName {
    return '${firstName.trim()} ${lastName.trim()}'.trim();
  }

  String get displayLabel {
    if (fullName.isNotEmpty) return fullName;
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (username.trim().isNotEmpty) return username.trim();
    return 'Unknown user';
  }

  String get subtitleLabel {
    final cleanUsername = username.trim();
    final cleanDisplayName = displayName.trim();
    final label = displayLabel.trim();

    if (cleanUsername.isNotEmpty && cleanUsername != label) {
      return '@$cleanUsername';
    }
    if (cleanDisplayName.isNotEmpty && cleanDisplayName != label) {
      return cleanDisplayName;
    }
    return '';
  }

  StoryAudienceUser copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? displayName,
    String? username,
    String? photoUrl,
    bool? isActive,
    bool? isFavorite,
    DateTime? lastInteractionAt,
    bool clearLastInteractionAt = false,
  }) {
    return StoryAudienceUser(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      isActive: isActive ?? this.isActive,
      isFavorite: isFavorite ?? this.isFavorite,
      lastInteractionAt: clearLastInteractionAt
          ? null
          : (lastInteractionAt ?? this.lastInteractionAt),
    );
  }

  factory StoryAudienceUser.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc, {
        Map<String, dynamic>? friendMeta,
      }) {
    final data = doc.data() ?? const <String, dynamic>{};
    final meta = friendMeta ?? const <String, dynamic>{};

    String readString(
        Map<String, dynamic> primary,
        List<String> keys, {
          Map<String, dynamic>? secondary,
        }) {
      for (final key in keys) {
        final value = primary[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      if (secondary != null) {
        for (final key in keys) {
          final value = secondary[key];
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }

      return '';
    }

    bool readBool(
        Map<String, dynamic> primary,
        List<String> keys, {
          Map<String, dynamic>? secondary,
          bool fallback = false,
        }) {
      bool? parse(dynamic value) {
        if (value is bool) return value;
        if (value is num) return value != 0;
        if (value is String) {
          final normalized = value.trim().toLowerCase();
          if (normalized == 'true' ||
              normalized == 'yes' ||
              normalized == '1') {
            return true;
          }
          if (normalized == 'false' ||
              normalized == 'no' ||
              normalized == '0') {
            return false;
          }
        }
        return null;
      }

      for (final key in keys) {
        final parsed = parse(primary[key]);
        if (parsed != null) return parsed;
      }

      if (secondary != null) {
        for (final key in keys) {
          final parsed = parse(secondary[key]);
          if (parsed != null) return parsed;
        }
      }

      return fallback;
    }

    DateTime? readDate(
        Map<String, dynamic> primary,
        List<String> keys, {
          Map<String, dynamic>? secondary,
        }) {
      DateTime? parse(dynamic value) {
        if (value is Timestamp) return value.toDate();
        if (value is DateTime) return value;

        if (value is num) {
          final raw = value.toInt();
          if (raw <= 0) return null;
          if (raw > 1000000000000) {
            return DateTime.fromMillisecondsSinceEpoch(raw);
          }
          return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
        }

        if (value is String && value.trim().isNotEmpty) {
          final trimmed = value.trim();

          final numeric = num.tryParse(trimmed);
          if (numeric != null) {
            final raw = numeric.toInt();
            if (raw > 1000000000000) {
              return DateTime.fromMillisecondsSinceEpoch(raw);
            }
            if (raw > 0) {
              return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
            }
          }

          return DateTime.tryParse(trimmed);
        }

        return null;
      }

      for (final key in keys) {
        final parsed = parse(primary[key]);
        if (parsed != null) return parsed;
      }

      if (secondary != null) {
        for (final key in keys) {
          final parsed = parse(secondary[key]);
          if (parsed != null) return parsed;
        }
      }

      return null;
    }

    final firstName = readString(
      data,
      const [
        'firstName',
        'firstname',
        'givenName',
        'given_name',
        'first_name',
      ],
      secondary: meta,
    );

    final lastName = readString(
      data,
      const [
        'lastName',
        'lastname',
        'familyName',
        'family_name',
        'last_name',
        'surname',
      ],
      secondary: meta,
    );

    final explicitId = readString(
      data,
      const ['uid', 'id'],
      secondary: meta,
    );

    return StoryAudienceUser(
      id: explicitId.isNotEmpty ? explicitId : doc.id,
      firstName: firstName,
      lastName: lastName,
      displayName: readString(
        data,
        const [
          'displayName',
          'name',
          'fullName',
          'full_name',
        ],
        secondary: meta,
      ),
      username: readString(
        data,
        const [
          'username',
          'userName',
          'handle',
        ],
        secondary: meta,
      ),
      photoUrl: (() {
        final value = readString(
          data,
          const [
            'photoUrl',
            'photoURL',
            'profileUrl',
            'avatarUrl',
            'avatarURL',
            'avatar',
            'avatarPath',
            'avatar_path',
            'imageUrl',
            'imageURL',
            'image',
            'imagePath',
            'image_path',
            'profileImageUrl',
            'profileImageURL',
            'profileImage',
            'profile_image',
            'profilePic',
            'profilePicture',
            'profile_picture',
            'photo',
            'photoPath',
            'photo_path',
          ],
          secondary: meta,
        );
        return value.isEmpty ? null : value;
      })(),
      isActive: readBool(
        data,
        const ['isActive', 'active'],
        secondary: meta,
        fallback: true,
      ),
      isFavorite: readBool(
        meta,
        const ['isFavorite', 'favorite', 'pinned', 'starred'],
        secondary: data,
        fallback: false,
      ),
      lastInteractionAt: readDate(
        meta,
        const [
          'lastInteractionAt',
          'lastMessageAt',
          'updatedAt',
          'recentAt',
          'lastSeenAt',
        ],
        secondary: data,
      ) ??
          readDate(
            data,
            const [
              'lastSeenAt',
              'updatedAt',
              'createdAt',
            ],
          ),
    );
  }
}