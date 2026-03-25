import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/story_audience_user.dart';

class StoryAudienceService {
  const StoryAudienceService();

  Stream<List<StoryAudienceUser>> customAudienceFriendsStream({
    required String? currentUid,
  }) {
    final uid = currentUid?.trim() ?? '';

    if (uid.isEmpty) {
      debugPrint('StoryAudienceService: currentUid is empty');
      return Stream<List<StoryAudienceUser>>.value(const <StoryAudienceUser>[]);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .asyncMap((friendsSnap) async {
      debugPrint(
        'StoryAudienceService: friends docs fetched = ${friendsSnap.docs.length} for uid=$uid',
      );

      if (friendsSnap.docs.isEmpty) {
        return <StoryAudienceUser>[];
      }

      final friendIds = <String>[];
      final friendMetaById = <String, Map<String, dynamic>>{};
      final seen = <String>{};

      for (final doc in friendsSnap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().trim().toLowerCase();

        final isAccepted = status.isEmpty ||
            status == 'accepted' ||
            status == 'active' ||
            status == 'friends';

        if (!isAccepted) continue;

        final friendId = _resolveFriendId(doc.id, data);
        if (friendId.isEmpty || friendId == uid || seen.contains(friendId)) {
          continue;
        }

        seen.add(friendId);
        friendIds.add(friendId);
        friendMetaById[friendId] = data;
      }

      debugPrint(
        'StoryAudienceService: resolved friendIds count = ${friendIds.length}',
      );

      if (friendIds.isEmpty) {
        return <StoryAudienceUser>[];
      }

      final users = <StoryAudienceUser>[];

      await Future.wait(
        friendIds.map((friendId) async {
          final friendMeta =
              friendMetaById[friendId] ?? const <String, dynamic>{};

          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(friendId)
                .get();

            final userData = userDoc.data();

            final audienceUser = _buildAudienceUser(
              friendId: friendId,
              userData: userData,
              friendMeta: friendMeta,
            );

            if (audienceUser != null) {
              users.add(audienceUser);
              return;
            }

            debugPrint(
              'StoryAudienceService: unable to build audience user for friendId=$friendId',
            );
          } catch (e, st) {
            debugPrint(
              'StoryAudienceService: failed to fetch/build user for $friendId error=$e',
            );
            debugPrint('$st');

            final fallbackUser = _buildAudienceUser(
              friendId: friendId,
              userData: null,
              friendMeta: friendMeta,
            );

            if (fallbackUser != null) {
              users.add(fallbackUser);
            }
          }
        }),
      );

      final result = _dedupeAudienceUsers(users, currentUid: uid);

      debugPrint(
        'StoryAudienceService: final audience users count = ${result.length}',
      );

      return result;
    }).handleError((error, stackTrace) {
      debugPrint('StoryAudienceService error: $error');
      debugPrint('$stackTrace');
      return <StoryAudienceUser>[];
    });
  }

  List<StoryAudienceUser> dedupeAudienceUsers(
      List<StoryAudienceUser> users, {
        String? currentUid,
      }) {
    return _dedupeAudienceUsers(users, currentUid: currentUid);
  }

  String _resolveFriendId(String docId, Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data['friendId'],
      data['friendUid'],
      data['uid'],
      data['userId'],
      data['user_id'],
      data['targetUid'],
      data['targetUserId'],
      data['otherUserId'],
      data['otherUid'],
      data['memberId'],
      data['contactUid'],
      docId,
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    return '';
  }

  StoryAudienceUser? _buildAudienceUser({
    required String friendId,
    required Map<String, dynamic>? userData,
    required Map<String, dynamic>? friendMeta,
  }) {
    final data = userData ?? const <String, dynamic>{};
    final meta = friendMeta ?? const <String, dynamic>{};

    String readString(List<String> keys) {
      for (final key in keys) {
        final userValue = data[key];
        if (userValue is String && userValue.trim().isNotEmpty) {
          return userValue.trim();
        }

        final metaValue = meta[key];
        if (metaValue is String && metaValue.trim().isNotEmpty) {
          return metaValue.trim();
        }
      }
      return '';
    }

    bool readBool(
        List<String> keys, {
          bool fallback = false,
        }) {
      for (final key in keys) {
        final userValue = data[key];
        final parsedUser = _parseBool(userValue);
        if (parsedUser != null) return parsedUser;

        final metaValue = meta[key];
        final parsedMeta = _parseBool(metaValue);
        if (parsedMeta != null) return parsedMeta;
      }
      return fallback;
    }

    DateTime? readDate(List<String> keys) {
      for (final key in keys) {
        final userValue = data[key];
        final parsedUser = _parseDate(userValue);
        if (parsedUser != null) return parsedUser;

        final metaValue = meta[key];
        final parsedMeta = _parseDate(metaValue);
        if (parsedMeta != null) return parsedMeta;
      }
      return null;
    }

    final firstName = readString([
      'firstName',
      'firstname',
      'givenName',
      'given_name',
      'first_name',
    ]);

    final lastName = readString([
      'lastName',
      'lastname',
      'familyName',
      'family_name',
      'last_name',
      'surname',
    ]);

    final displayName = readString([
      'displayName',
      'name',
      'fullName',
      'full_name',
    ]);

    final username = readString([
      'username',
      'userName',
      'handle',
    ]);

    final photoUrl = readString([
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
    ]);

    final hasAnyDisplayData = firstName.isNotEmpty ||
        lastName.isNotEmpty ||
        displayName.isNotEmpty ||
        username.isNotEmpty ||
        photoUrl.isNotEmpty;

    if (!hasAnyDisplayData && data.isEmpty && meta.isEmpty) {
      return null;
    }

    return StoryAudienceUser(
      id: friendId,
      firstName: firstName,
      lastName: lastName,
      displayName: displayName,
      username: username,
      photoUrl: photoUrl.isEmpty ? null : photoUrl,
      isActive: readBool(
        ['isActive', 'active'],
        fallback: true,
      ),
      isFavorite: readBool(
        ['isFavorite', 'favorite', 'pinned', 'starred'],
        fallback: false,
      ),
      lastInteractionAt: readDate([
        'lastInteractionAt',
        'lastMessageAt',
        'updatedAt',
        'recentAt',
        'lastSeenAt',
        'createdAt',
      ]),
    );
  }

  bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == 'no' || normalized == '0') {
        return false;
      }
    }

    return null;
  }

  DateTime? _parseDate(dynamic value) {
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

      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) return parsed;
    }

    return null;
  }

  List<StoryAudienceUser> _dedupeAudienceUsers(
      List<StoryAudienceUser> users, {
        String? currentUid,
      }) {
    final map = <String, StoryAudienceUser>{};

    for (final user in users) {
      if (user.id.trim().isEmpty) continue;
      if (currentUid != null && user.id == currentUid) continue;
      if (!user.isActive) continue;

      final existing = map[user.id];
      if (existing == null) {
        map[user.id] = user;
        continue;
      }

      map[user.id] = _pickBetterUser(existing, user);
    }

    final list = map.values.toList()
      ..sort((a, b) {
        final aTime = a.lastInteractionAt;
        final bTime = b.lastInteractionAt;

        if (a.isFavorite != b.isFavorite) {
          return a.isFavorite ? -1 : 1;
        }
        if (aTime != null && bTime != null) {
          return bTime.compareTo(aTime);
        }
        if (aTime != null) return -1;
        if (bTime != null) return 1;

        return a.displayLabel.toLowerCase().compareTo(
          b.displayLabel.toLowerCase(),
        );
      });

    return list;
  }

  StoryAudienceUser _pickBetterUser(
      StoryAudienceUser a,
      StoryAudienceUser b,
      ) {
    int score(StoryAudienceUser user) {
      int value = 0;
      if (user.firstName.trim().isNotEmpty) value += 3;
      if (user.lastName.trim().isNotEmpty) value += 3;
      if (user.displayName.trim().isNotEmpty) value += 2;
      if (user.username.trim().isNotEmpty) value += 1;
      if ((user.photoUrl ?? '').trim().isNotEmpty) value += 1;
      if (user.lastInteractionAt != null) value += 1;
      if (user.isFavorite) value += 1;
      return value;
    }

    return score(b) > score(a) ? b : a;
  }
}