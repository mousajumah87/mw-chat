import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class PresenceService with WidgetsBindingObserver {
  PresenceService._internal();
  static final PresenceService instance = PresenceService._internal();

  static const String _profileVisEveryone = 'everyone';
  static const String _friendReqEveryone = 'everyone';

  StreamSubscription<User?>? _authSub;
  User? _currentUser;

  bool _initialized = false;
  bool _disposed = false;

  Timer? _heartbeat;
  static const Duration _heartbeatEvery = Duration(seconds: 60);

  Timer? _inactiveDebounce;
  static const Duration _inactiveDebounceDelay = Duration(milliseconds: 800);

  Future<void> _writeChain = Future<void>.value();

  bool _lastKnownOnline = false;

  void _log(String msg) {
    debugPrint('[PresenceService] $msg');
  }

  void init() {
    if (_initialized) {
      _log('init skipped: already initialized');
      return;
    }

    _initialized = true;
    _disposed = false;

    WidgetsBinding.instance.addObserver(this);
    _log('init start');

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      _currentUser = user;
      _log('authStateChanges user=${user?.uid}');

      _inactiveDebounce?.cancel();
      _inactiveDebounce = null;

      if (_disposed) return;

      if (user != null) {
        await _ensureUserPrivacyDefaults(user.uid);
        await _markOnlineInternal();
        _startHeartbeat();
      } else {
        _stopHeartbeat();
        _lastKnownOnline = false;
      }
    });
  }

  Future<void> _ensureUserPrivacyDefaults(String uid) async {
    if (_disposed) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? <String, dynamic>{};

      final patch = <String, dynamic>{};

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
    } catch (e, st) {
      _log('ensureUserPrivacyDefaults failed: $e\n$st');
    }
  }

  void _enqueueWrite(Future<void> Function() task) {
    _writeChain = _writeChain.then((_) async {
      if (_disposed) return;
      await task();
    }).catchError((e, st) {
      _log('write failed: $e\n$st');
    });
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) {
      _enqueueWrite(() async {
        final user = _currentUser ?? FirebaseAuth.instance.currentUser;
        if (_disposed || user == null) return;
        if (!_lastKnownOnline) return;

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'isOnline': true,
            'online': true,
            'lastActive': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
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

  Future<void> _setOnlinePresence() async {
    final user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (_disposed || user == null) return;

    if (_lastKnownOnline) {
      // still refresh timestamps if needed, but avoid duplicate state churn
      _enqueueWrite(() async {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'isOnline': true,
            'online': true,
            'lastActive': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      await _writeChain;
      return;
    }

    _lastKnownOnline = true;

    _enqueueWrite(() async {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'isOnline': true,
          'online': true,
          'lastActive': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    await _writeChain;
  }

  Future<void> _setOfflinePresence() async {
    final user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (_disposed || user == null) return;

    if (!_lastKnownOnline) return;
    _lastKnownOnline = false;

    _enqueueWrite(() async {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'isOnline': false,
          'online': false,
          'lastSeen': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    await _writeChain;
  }

  Future<void> _markOnlineInternal() async {
    final user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (_disposed || user == null) return;

    await _setOnlinePresence();
  }

  Future<void> markOnline() async {
    if (_disposed) return;

    _inactiveDebounce?.cancel();
    _inactiveDebounce = null;

    await _markOnlineInternal();
    _startHeartbeat();
  }

  Future<void> markOffline() async {
    if (_disposed) return;

    _inactiveDebounce?.cancel();
    _inactiveDebounce = null;

    _stopHeartbeat();
    await _setOfflinePresence();
  }

  void _scheduleInactiveFallback() {
    _inactiveDebounce?.cancel();
    _inactiveDebounce = Timer(_inactiveDebounceDelay, () {
      unawaited(markOffline());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    _log('lifecycle=$state');

    switch (state) {
      case AppLifecycleState.resumed:
        _inactiveDebounce?.cancel();
        _inactiveDebounce = null;
        unawaited(markOnline());
        break;

      case AppLifecycleState.inactive:
      // transient on iOS during app switch / overlays / lock transition
        _scheduleInactiveFallback();
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
      // mobile-safe: write offline immediately before app is suspended
        unawaited(markOffline());
        break;
    }
  }

  Future<void> disposeService() async {
    if (_disposed) return;

    _inactiveDebounce?.cancel();
    _inactiveDebounce = null;
    _stopHeartbeat();

    try {
      await _setOfflinePresence();
    } catch (e, st) {
      _log('dispose offline write failed: $e\n$st');
    }

    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);

    await _authSub?.cancel();
    _authSub = null;
    _currentUser = null;
  }
}
