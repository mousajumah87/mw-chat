// lib/screens/chat/chat_friendship_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Friendship status values:
/// null        => no relationship
/// requested  => I sent request
/// incoming   => they sent request
/// accepted   => friends
class ChatFriendshipService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _friendSub;

  /// 🔹 Subscribe to friendship between [me] and [other]
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
    _friendSub = _firestore
        .collection('users')
        .doc(me)
        .collection('friends')
        .doc(other)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) {
        onUpdate(null);
        return;
      }

      final data = snap.data() ?? {};
      final status = data['status'] as String?;
      onUpdate(status);
    }, onError: (_) {
      onUpdate(null);
    });
  }

  /// 🔹 Send friend request
  Future<void> sendRequest({
    required String me,
    required String other,
  }) async {
    if (me.isEmpty || other.isEmpty) return;

    final batch = _firestore.batch();

    final myDoc = _firestore
        .collection('users')
        .doc(me)
        .collection('friends')
        .doc(other);

    final theirDoc = _firestore
        .collection('users')
        .doc(other)
        .collection('friends')
        .doc(me);

    final now = FieldValue.serverTimestamp();

    batch.set(myDoc, {
      'status': 'requested',
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(theirDoc, {
      'status': 'incoming',
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// 🔹 Accept friend request
  Future<void> acceptRequest({
    required String me,
    required String other,
  }) async {
    if (me.isEmpty || other.isEmpty) return;

    final batch = _firestore.batch();

    final myDoc = _firestore
        .collection('users')
        .doc(me)
        .collection('friends')
        .doc(other);

    final theirDoc = _firestore
        .collection('users')
        .doc(other)
        .collection('friends')
        .doc(me);

    final payload = {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    batch.set(myDoc, payload, SetOptions(merge: true));
    batch.set(theirDoc, payload, SetOptions(merge: true));

    await batch.commit();
  }

  /// 🔹 Decline or cancel friend request
  Future<void> declineRequest({
    required String me,
    required String other,
  }) async {
    if (me.isEmpty || other.isEmpty) return;

    final batch = _firestore.batch();

    final myDoc = _firestore
        .collection('users')
        .doc(me)
        .collection('friends')
        .doc(other);

    final theirDoc = _firestore
        .collection('users')
        .doc(other)
        .collection('friends')
        .doc(me);

    batch.delete(myDoc);
    batch.delete(theirDoc);

    await batch.commit();
  }

  /// 🔹 Helper flags (optional use)
  static bool isAccepted(String? status) => status == 'accepted';
  static bool isIncoming(String? status) => status == 'incoming';
  static bool isRequested(String? status) => status == 'requested';

  /// 🔹 Dispose listener
  void dispose() {
    _friendSub?.cancel();
  }
}
