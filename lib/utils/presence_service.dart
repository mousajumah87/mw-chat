// lib/utils/presence_service.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PresenceService with WidgetsBindingObserver {
  PresenceService._internal();
  static final PresenceService instance = PresenceService._internal();

  // Firestore string values (keep stable)
  static const String _profileVisEveryone = 'everyone';
  static const String _friendReqEveryone = 'everyone';

  StreamSubscription<User?>? _authSub;
  User? _currentUser;

  bool _initialized = false;
  bool _disposed = false;

  Timer? _heartbeat;
  static const Duration _heartbeatEvery = Duration(seconds: 60);

  // Prevent overlapping writes
  Future<void> _writeChain = Future<void>.value();

  void init() {
    if (_initialized) return;
    _initialized = true;
    _disposed = false;

    WidgetsBinding.instance.addObserver(this);

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      _currentUser = user;

      if (user != null) {
        // Ensure privacy defaults exist (only set missing fields).
        await _ensureUserPrivacyDefaults(user.uid);

        // Bring user online (respects showOnlineStatus).
        await _markOnlineInternal();
        _startHeartbeat();
      } else {
        _stopHeartbeat();
        await _setPresence(isOnline: false);
      }
    });
  }

  /// Ensures new privacy fields exist without overwriting user choices.
  Future<void> _ensureUserPrivacyDefaults(String uid) async {
    if (_disposed) return;

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? <String, dynamic>{};

      final Map<String, dynamic> patch = {};

      // Only set defaults if missing (do NOT overwrite).
      if (!data.containsKey('showOnlineStatus')) {
        patch['showOnlineStatus'] = true;
      }
      if (!data.containsKey('profileVisibility')) {
        patch['profileVisibility'] = _profileVisEveryone;
      }
      if (!data.containsKey('friendRequests')) {
        patch['friendRequests'] = _friendReqEveryone;
      }

      if (patch.isEmpty) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        patch,
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best-effort only. Presence should still work if this fails.
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) {
      // Fire-and-forget heartbeat update (serialized via _enqueueWrite)
      _enqueueWrite(() async {
        final user = _currentUser ?? FirebaseAuth.instance.currentUser;
        if (_disposed || user == null) return;

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'lastSeen': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// Serializes Firestore writes to avoid overlaps from lifecycle + timers.
  void _enqueueWrite(Future<void> Function() task) {
    _writeChain = _writeChain.then((_) async {
      if (_disposed) return;
      await task();
    }).catchError((_) {
      // swallow to keep chain alive
    });
  }

  /// Reads showOnlineStatus and decides whether we are allowed to show online.
  Future<bool> _canShowOnline(String uid) async {
    if (_disposed) return false;

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      return (data['showOnlineStatus'] as bool?) ?? true;
    } catch (_) {
      // Default to true if read fails.
      return true;
    }
  }

  Future<void> _setPresence({required bool isOnline}) async {
    final user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (_disposed || user == null) return;

    _enqueueWrite(() async {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'isOnline': isOnline,
          'lastSeen': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    // ensure chain completes when awaited by callers
    await _writeChain;
  }

  Future<void> _markOnlineInternal() async {
    final user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (_disposed || user == null) return;

    // Respect privacy: if user disabled online status, keep isOnline = false.
    final allowed = await _canShowOnline(user.uid);
    await _setPresence(isOnline: allowed ? true : false);
  }

  Future<void> markOnline() async {
    if (_disposed) return;
    await _markOnlineInternal();
    _startHeartbeat();
  }

  Future<void> markOffline() async {
    if (_disposed) return;
    _stopHeartbeat();
    await _setPresence(isOnline: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    switch (state) {
      case AppLifecycleState.resumed:
      // When resuming, reflect privacy setting again.
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
    if (_disposed) return;
    _disposed = true;

    WidgetsBinding.instance.removeObserver(this);
    _stopHeartbeat();

    // Best-effort offline update (don't throw)
    try {
      await _setPresence(isOnline: false);
    } catch (_) {}

    await _authSub?.cancel();
    _authSub = null;
    _currentUser = null;
  }
}
