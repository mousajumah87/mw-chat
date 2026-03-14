//lib/utils/presence_service.dart

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

  Timer? _offlineDebounce;
  static const Duration _offlineDebounceDelay = Duration(seconds: 2);

  Future<void> _writeChain = Future<void>.value();

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

      _offlineDebounce?.cancel();
      _offlineDebounce = null;

      if (_disposed) return;

      if (user != null) {
        await _ensureUserPrivacyDefaults(user.uid);
        await _markOnlineInternal();
        _startHeartbeat();
      } else {
        _stopHeartbeat();
      }
    });
  }

  Future<void> _ensureUserPrivacyDefaults(String uid) async {
    if (_disposed) return;

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
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

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) {
      _enqueueWrite(() async {
        final user = _currentUser ?? FirebaseAuth.instance.currentUser;
        if (_disposed || user == null) return;

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

  void _enqueueWrite(Future<void> Function() task) {
    _writeChain = _writeChain
        .then((_) async {
      if (_disposed) return;
      await task();
    })
        .catchError((e, st) {
      _log('write failed: $e\n$st');
    });
  }

  Future<void> _setPresence({
    required bool isOnline,
    required bool updateLastSeen,
  }) async {
    final user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (_disposed || user == null) return;

    _enqueueWrite(() async {
      final payload = <String, dynamic>{
        'isOnline': isOnline,
        'online': isOnline,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      payload['lastActive'] = FieldValue.serverTimestamp();

      if (updateLastSeen) {
        payload['lastSeen'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        payload,
        SetOptions(merge: true),
      );
    });

    await _writeChain;
  }

  Future<void> _markOnlineInternal() async {
    final user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (_disposed || user == null) return;

    await _setPresence(
      isOnline: true,
      updateLastSeen: false,
    );
  }

  Future<void> markOnline() async {
    if (_disposed) return;

    _offlineDebounce?.cancel();
    _offlineDebounce = null;

    await _markOnlineInternal();
    _startHeartbeat();
  }

  Future<void> markOffline() async {
    if (_disposed) return;

    _offlineDebounce?.cancel();
    _offlineDebounce = null;

    _stopHeartbeat();
    await _setPresence(
      isOnline: false,
      updateLastSeen: true,
    );
  }

  void _scheduleOffline() {
    _offlineDebounce?.cancel();
    _offlineDebounce = Timer(_offlineDebounceDelay, () {
      unawaited(markOffline());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _offlineDebounce?.cancel();
        _offlineDebounce = null;
        unawaited(markOnline());
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _scheduleOffline();
        break;
    }
  }

  Future<void> disposeService() async {
    if (_disposed) return;

    _offlineDebounce?.cancel();
    _offlineDebounce = null;
    _stopHeartbeat();

    try {
      await _setPresence(isOnline: false, updateLastSeen: true);
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