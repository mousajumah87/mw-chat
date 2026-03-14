import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart' as app;
import 'call_screen.dart';

class MwCallPushUi {
  static final FlutterLocalNotificationsPlugin _ln =
  FlutterLocalNotificationsPlugin();

  // Keep aligned with main.dart / server payloads.
  static const String _callChannelId = 'mw_calls_v2';
  static const String _callChannelName = 'MW Calls';

  static bool _inited = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // Prevent double navigation races (FCM + CallKit, or multiple events).
  static String? _openingCallId;

  static void setHandlingCallKitAnswer(bool v) =>
      app.setHandlingCallKitAnswer(v);

  static Future<void> ensureInit() async {
    if (_inited) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _ln.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (resp) {
        final payload = (resp.payload ?? '').trim();
        if (payload.isNotEmpty) {
          handleCallPushOnOpen({
            'callId': payload,
            'type': 'call',
          });
        }
      },
    );

    if (_isAndroid) {
      const channel = AndroidNotificationChannel(
        _callChannelId,
        _callChannelName,
        description: 'Incoming calls',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('mw_ring'),
        enableVibration: true,
      );

      await _ln
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await _ln
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    if (_isIOS) {
      await _ln
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    await _ln
        .resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    _inited = true;
  }

  static Future<void> showIncomingCallNotificationFromBg(
      Map<String, dynamic> data,
      ) async {
    await ensureInit();

    final callId = (data['callId'] ?? '').toString().trim();
    if (callId.isEmpty) return;

    if (_isAndroid) {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannelId,
          _callChannelName,
          channelDescription: 'Incoming calls',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ticker: 'MW',
          icon: '@mipmap/ic_launcher',
          playSound: true,
          sound: RawResourceAndroidNotificationSound('mw_ring'),
          enableVibration: true,
        ),
      );

      await _ln.show(
        callId.hashCode,
        'MW',
        '',
        details,
        payload: callId,
      );
      return;
    }

    if (_isIOS) {
      await _ln.show(
        callId.hashCode,
        'MW',
        '',
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'mw_ring.caf',
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'mw_ring.caf',
          ),
        ),
        payload: callId,
      );
    }
  }

  static void handleCallPushInForeground(Map<String, dynamic> data) {
    _openCallUiIfPossible(data);
  }

  static void handleCallPushOnOpen(Map<String, dynamic> data) {
    _openCallUiIfPossible(data);
  }

  static void _openCallUiIfPossible(Map<String, dynamic> data) {
    // IncomingCallListener is responsible for observing Firestore and
    // presenting the call UI based on call state changes.
    final _ = app.rootNavigatorKey.currentState;
  }

  static Future<void> handleCallKitAnswer(String callId) async {
    if (callId.isEmpty) return;

    if (_openingCallId == callId) return;
    _openingCallId = callId;

    try {
      final nav = app.rootNavigatorKey.currentState;
      if (nav == null) return;

      final me = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (me.isEmpty) return;

      final snap =
      await FirebaseFirestore.instance.collection('calls').doc(callId).get();
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString().trim();
      if (status != 'ringing' && status != 'accepted') {
        setHandlingCallKitAnswer(false);
        return;
      }

      final callerId = (data['callerId'] ?? '').toString().trim();
      final calleeId = (data['calleeId'] ?? '').toString().trim();
      final roomId = (data['roomId'] ?? '').toString().trim();
      final type = ((data['type'] ?? '').toString().trim().isEmpty)
          ? 'audio'
          : (data['type'] ?? '').toString().trim();

      if (roomId.isEmpty || callerId.isEmpty || calleeId.isEmpty) {
        setHandlingCallKitAnswer(false);
        return;
      }

      try {
        await FirebaseFirestore.instance.collection('calls').doc(callId).set(
          {
            'status': 'accepted',
            'acceptedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}

      await nav.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/call_screen'),
          builder: (_) => CallScreen.incoming(
            roomId: roomId,
            callerId: callerId,
            calleeId: calleeId,
            callId: callId,
            video: type == 'video',
          ),
        ),
      );
    } finally {
      setHandlingCallKitAnswer(false);
      _openingCallId = null;
    }
  }

  static Future<void> handleCallKitEnd(String callId) async {
    if (callId.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('calls').doc(callId).set(
        {
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}