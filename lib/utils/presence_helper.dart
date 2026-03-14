import 'package:cloud_firestore/cloud_firestore.dart';

class MwPresenceHelper {
  static const int onlineTtlSeconds = 300;

  static Timestamp? readTimestamp(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is Timestamp ? value : null;
  }

  static bool readRawOnline(
      Map<String, dynamic> data, {
        required bool isActive,
      }) {
    if (!isActive) return false;

    // New field wins.
    if (data.containsKey('isOnline')) {
      return data['isOnline'] == true;
    }

    // Legacy fallback only if new field is missing.
    return data['online'] == true;
  }

  static bool isOnlineForDisplay({
    required bool canSeePresence,
    required bool rawIsOnline,
    required Timestamp? lastActive,
    int ttlSeconds = onlineTtlSeconds,
  }) {
    if (!canSeePresence) return false;
    if (!rawIsOnline) return false;

    // Rollout-safe fallback.
    if (lastActive == null) return true;

    final ageSeconds = DateTime.now().difference(lastActive.toDate()).inSeconds;
    return ageSeconds <= ttlSeconds;
  }
}