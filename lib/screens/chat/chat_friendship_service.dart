// lib/screens/chat/chat_friendship_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Friendship status values stored in Firestore under:
/// users/{me}/friends/{other} => { status: ... }
///
/// Canonical statuses in Firestore:
/// - null         => no relationship
/// - requested    => I sent request
/// - incoming     => they sent request
/// - accepted     => friends
///
/// Some UI code may use "request_received" locally (alias for incoming).
class ChatFriendshipService {
  final FirebaseFirestore _firestore;

  ChatFriendshipService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  StreamSubscription<String?>? _friendSub;

  // --- Canonical statuses ---
  static const String statusRequested = 'requested';
  static const String statusIncoming = 'incoming';
  static const String statusAccepted = 'accepted';

  // --- Local alias sometimes used in UI ---
  static const String statusRequestReceivedAlias = 'request_received';

  /// If you want the UI to use "request_received" everywhere, set to true.
  /// Otherwise keep canonical "incoming".
  static const bool exposeIncomingAsRequestReceived = false;

  /// Normalize status coming from Firestore (or legacy UI strings).
  static String? normalizeStatus(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;

    // Accept both canonical + alias safely
    if (v == statusRequestReceivedAlias) {
      return exposeIncomingAsRequestReceived
          ? statusRequestReceivedAlias
          : statusIncoming;
    }

    if (v == statusRequested) return statusRequested;

    if (v == statusIncoming) {
      return exposeIncomingAsRequestReceived
          ? statusRequestReceivedAlias
          : statusIncoming;
    }

    if (v == statusAccepted) return statusAccepted;

    return null; // unknown -> safe fallback
  }

  DocumentReference<Map<String, dynamic>> _friendDoc({
    required String me,
    required String other,
  }) {
    return _firestore.collection('users').doc(me).collection('friends').doc(other);
  }

  // ----------------------------
  // Preferred: stream style
  // ----------------------------
  Stream<String?> friendshipStatusStream({
    required String me,
    required String other,
  }) {
    if (me.isEmpty || other.isEmpty) {
      return const Stream<String?>.empty();
    }

    return _friendDoc(me: me, other: other).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data() ?? const <String, dynamic>{};
      final raw = data['status'] as String?;
      return normalizeStatus(raw);
    });
  }

  // Backward-compatible manual subscribe API
  void subscribe({
    required String me,
    required String other,
    required void Function(String? status) onUpdate,
  }) {
    if (me.isEmpty || other.isEmpty) {
      onUpdate(null);
      return;
    }

    _friendSub?.cancel();
    _friendSub = friendshipStatusStream(me: me, other: other).listen(
          (status) => onUpdate(status),
      onError: (_) => onUpdate(null),
    );
  }

  Future<String?> getStatusOnce({
    required String me,
    required String other,
  }) async {
    if (me.isEmpty || other.isEmpty) return null;

    try {
      final snap = await _friendDoc(me: me, other: other).get();
      if (!snap.exists) return null;
      final data = snap.data() ?? const <String, dynamic>{};
      return normalizeStatus(data['status'] as String?);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // Actions (UPDATED to match MwFriendsTab transaction behavior)
  // ============================================================

  /// ✅ Robust request send:
  /// - Uses a transaction (avoids batch "all-or-nothing" failures + race conditions)
  /// - Never attempts to modify target doc if it is already accepted (prevents rule denial)
  /// - Writes:
  ///   my side: requested
  ///   their side: incoming
  Future<void> sendRequest({
    required String me,
    required String other,
  }) async {
    if (me.isEmpty || other.isEmpty) return;
    if (me == other) return;

    final myDoc = _friendDoc(me: me, other: other);
    final theirDoc = _friendDoc(me: other, other: me);

    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((tx) async {
      final mySnap = await tx.get(myDoc);
      final theirSnap = await tx.get(theirDoc);

      final myData = mySnap.data();
      final theirData = theirSnap.data();

      final myStatus = normalizeStatus((myData?['status'] as String?)?.trim());
      final theirStatus = normalizeStatus((theirData?['status'] as String?)?.trim());

      // Already friends? No-op.
      if (isFriends(myStatus) || isFriends(theirStatus)) {
        // Repair my side if their side already accepted
        if (isFriends(theirStatus) && !isFriends(myStatus)) {
          tx.set(
            myDoc,
            {'status': statusAccepted, 'updatedAt': now, 'createdAt': now},
            SetOptions(merge: true),
          );
        }
        return;
      }

      // If I already have incoming, do nothing (caller should accept instead).
      if (isIncoming(myStatus)) return;

      // If I already requested, keep it idempotent.
      if (isRequested(myStatus)) return;

      // ✅ Normal request write
      tx.set(
        myDoc,
        {'status': statusRequested, 'createdAt': now, 'updatedAt': now},
        SetOptions(merge: true),
      );

      // ✅ Only write their side if it's not accepted already
      if (!isFriends(theirStatus)) {
        tx.set(
          theirDoc,
          {'status': statusIncoming, 'createdAt': now, 'updatedAt': now},
          SetOptions(merge: true),
        );
      }
    });
  }

  /// ✅ Accept request robustly with a transaction:
  /// - requires my side is incoming
  /// - sets both sides to accepted
  Future<void> acceptRequest({
    required String me,
    required String other,
  }) async {
    if (me.isEmpty || other.isEmpty) return;
    if (me == other) return;

    final myDoc = _friendDoc(me: me, other: other);
    final theirDoc = _friendDoc(me: other, other: me);
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((tx) async {
      final mySnap = await tx.get(myDoc);
      final theirSnap = await tx.get(theirDoc);

      final myStatus = normalizeStatus((mySnap.data()?['status'] as String?)?.trim());
      final theirStatus = normalizeStatus((theirSnap.data()?['status'] as String?)?.trim());

      final isIncomingMine = isIncoming(myStatus);
      if (!isIncomingMine) {
        // If already accepted, no-op.
        if (isFriends(myStatus) || isFriends(theirStatus)) return;
        return;
      }

      final payload = {'status': statusAccepted, 'updatedAt': now};

      tx.set(myDoc, payload, SetOptions(merge: true));
      tx.set(theirDoc, payload, SetOptions(merge: true));
    });
  }

  /// Decline/cancel request: deletes both docs (batch is fine here)
  Future<void> declineRequest({
    required String me,
    required String other,
  }) async {
    if (me.isEmpty || other.isEmpty) return;
    if (me == other) return;

    final batch = _firestore.batch();
    batch.delete(_friendDoc(me: me, other: other));
    batch.delete(_friendDoc(me: other, other: me));
    await batch.commit();
  }

  Future<void> removeFriend({
    required String me,
    required String other,
  }) async {
    await declineRequest(me: me, other: other);
  }

  // ----------------------------
  // ✅ Status helpers (STATIC)
  // ----------------------------
  static bool isAccepted(String? status) => normalizeStatus(status) == statusAccepted;

  static bool isIncoming(String? status) {
    final s = normalizeStatus(status);
    return s == statusIncoming || s == statusRequestReceivedAlias;
  }

  static bool isRequested(String? status) => normalizeStatus(status) == statusRequested;

  /// ✅ keep this name for existing call sites
  static bool isFriends(String? status) => isAccepted(status);

  // Optional instance wrappers (NO name collisions)
  bool isAcceptedStatus(String? status) => isAccepted(status);
  bool isIncomingStatus(String? status) => isIncoming(status);
  bool isRequestedStatus(String? status) => isRequested(status);
  bool isFriendsStatus(String? status) => isFriends(status);

  void dispose() {
    _friendSub?.cancel();
    _friendSub = null;
  }
}
