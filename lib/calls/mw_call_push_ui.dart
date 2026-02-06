// lib/calls/mw_call_push_ui.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart' show rootNavigatorKey, setHandlingCallKitAnswer;
import 'call_screen.dart';

class MwCallPushUi {
  static final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();

  // ✅ Use versioned channel so sound can be changed safely
  static const String _callChannelId = 'mw_calls_v1';
  static const String _callChannelName = 'MW Calls';

  static bool _inited = false;

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String? _openingCallId;

  static void setHandlingCallKitAnswer(bool v) => setHandlingCallKitAnswer(v);

  static int _stableNotifIdFromCallId(String callId) {
    // stable + positive int
    return (callId.hashCode & 0x7fffffff);
  }

  static Future<void> ensureInit() async {
    if (_inited) return;
    _inited = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    await _ln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = (resp.payload ?? '').trim();
        if (payload.isNotEmpty) {
          handleCallPushOnOpen({'callId': payload, 'type': 'call'});
        }
      },
    );

    if (_isAndroid) {
      // ✅ Channel sound is what matters on Android 8+
      const channel = AndroidNotificationChannel(
        _callChannelId,
        _callChannelName,
        description: 'Incoming calls',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('mw_ring'), // res/raw/mw_ring.mp3
      );

      final androidPlugin =
      _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(channel);
    }
  }

  static Future<void> showIncomingCallNotificationFromBg(Map<String, dynamic> data) async {
    await ensureInit();

    final callId = (data['callId'] ?? '').toString().trim();
    if (callId.isEmpty) return;

    final callerName = (data['callerName'] ?? 'MW').toString().trim();
    final callType = (data['callType'] ?? 'audio').toString().trim().toLowerCase();

    if (_isAndroid) {
      final androidDetails = AndroidNotificationDetails(
        _callChannelId,
        _callChannelName,
        channelDescription: 'Incoming calls',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,

        // ✅ make it behave like an incoming call
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,

        icon: '@mipmap/ic_launcher',
        ticker: 'MW',
        // sound comes from the channel
      );

      final details = NotificationDetails(android: androidDetails);

      final title = callerName.isEmpty ? 'MW' : callerName;
      final body = callType == 'video' ? 'Incoming video call' : 'Incoming call';

      await _ln.show(
        _stableNotifIdFromCallId(callId),
        title,
        body,
        details,
        payload: callId,
      );
      return;
    }

    // iOS: normally VoIP->CallKit handles ringing UI.
    // Keep a light fallback notification (optional).
    if (_isIOS) {
      await _ln.show(
        _stableNotifIdFromCallId(callId),
        'MW',
        'Incoming call',
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            // If you add mw_ring.caf to iOS bundle, you can do:
            // sound: 'mw_ring.caf',
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
    // You said you intentionally rely on Firestore listener (IncomingCallListener)
    // so we keep this as no-op.
    final _ = rootNavigatorKey.currentState;
  }

  // --------------------------------------------------------------------------
  // CallKit integration (Answer / End)
  // --------------------------------------------------------------------------

  static Future<void> handleCallKitAnswer(String callId) async {
    if (callId.isEmpty) return;

    if (_openingCallId == callId) return;
    _openingCallId = callId;

    try {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;

      final me = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (me.isEmpty) return;

      final snap = await FirebaseFirestore.instance.collection('calls').doc(callId).get();
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
