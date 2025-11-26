// lib/utils/presence_service.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Central place to track if the current user is online / offline.
///
/// It listens to auth changes + app lifecycle and updates
/// users/<uid> with:
///   isOnline: bool
///   lastSeen: Timestamp (last activity – updated on every change)
class PresenceService with WidgetsBindingObserver {
  PresenceService._internal();
  static final PresenceService instance = PresenceService._internal();

  StreamSubscription<User?>? _authSub;
  User? _currentUser;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    _authSub = FirebaseAuth.instance.authStateChanges().listen(
          (user) async {
        _currentUser = user;
        if (user != null) {
          // Logged in → mark online.
          await _setPresence(isOnline: true);
        } else {
          // Logged out → mark offline for the last known user (best-effort).
          await _setPresence(isOnline: false);
        }
      },
    );
  }

  Future<void> _setPresence({
    required bool isOnline,
  }) async {
    final user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final update = <String, dynamic>{
      'isOnline': isOnline,
      // Treat lastSeen as "last activity" (online or offline)
      'lastSeen': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      update,
      SetOptions(merge: true),
    );
  }

  Future<void> markOnline() => _setPresence(isOnline: true);

  Future<void> markOffline() => _setPresence(isOnline: false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Web/mobile: treat background as offline; foreground as online.
    switch (state) {
      case AppLifecycleState.resumed:
        markOnline();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        markOffline();
        break;
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await markOffline();
    await _authSub?.cancel();
  }
}
