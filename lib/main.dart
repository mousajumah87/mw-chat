// lib/main.dart
// MW Chat – Modern private messaging app
// Copyright © 2025 Mousa Abu Hilal.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show
    BindingBase,
    debugPrint,
    defaultTargetPlatform,
    kDebugMode,
    kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mw/screens/auth/widgets/sheets/link_email_sheet.dart';
import 'package:mw/screens/auth/widgets/sheets/link_phone_sheet.dart';
import 'package:mw/screens/chat/chat_screen.dart';
import 'package:mw/screens/home/mw_friend_requests_screen.dart';
import 'package:mw/utils/notification_badge_service.dart';
import 'package:mw/widgets/ui/mw_swipe_back.dart';
import 'package:provider/provider.dart';

import 'calls/incoming_call_listener.dart';
import 'calls/mw_call_push_ui.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/auth/widgets/complete_profile_screen.dart';
import 'screens/home/home_screen.dart';
import 'theme/app_theme.dart';
import 'utils/current_chat_tracker.dart';
import 'utils/locale_provider.dart';
import 'utils/presence_service.dart';
import 'utils/typography_provider.dart';
import 'utils/web/recaptcha_container.dart';

/// ✅ All push UI must show ONLY this title when we build local notifications.
const String kMwOnlyPushTitle = 'MW';

/// ✅ Android channel IDs MUST change when sound/settings change.
const String kMwCallsChannelId = 'mw_calls_v2';
const String kMwChatChannelId = 'mw_chat_v2';
const String kMwAchievementsChannelId = 'mw_achievements_v2';
const String kMwSocialChannelId = 'mw_social_v1';

/// ✅ Keep null unless the file is really bundled in iOS/macOS app resources.
/// Example if bundled: 'mw_pop.caf'
/// ✅ Keep null unless the file is really bundled in iOS/macOS app resources.
const String? kMwAppleChatSound = 'mw_pop.caf';

/// ✅ Enable only when explicitly passed:
/// flutter run --dart-define=MW_FAKE_OTP=true
const bool kUseFakeOtp = bool.fromEnvironment('MW_FAKE_OTP', defaultValue: false);

/// GLOBAL SNACKBAR KEY (FOR FOREGROUND NOTIFICATIONS)
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
GlobalKey<ScaffoldMessengerState>();

/// ✅ GLOBAL NAVIGATOR KEY
final GlobalKey<NavigatorState> rootNavigatorKey =
GlobalKey<NavigatorState>();

/// Global instance of CurrentChatTracker used both by Provider and FCM logic.
final CurrentChatTracker currentChatTracker = CurrentChatTracker.instance;

/// ✅ Prevent duplicate listeners
StreamSubscription<RemoteMessage>? _foregroundMsgSub;
StreamSubscription<RemoteMessage>? _onOpenSub;

/// ✅ Auth debug subscriptions
StreamSubscription<User?>? _idTokenDebugSub;

/// ------------------------------
/// Small helpers for push parsing
/// ------------------------------
String _asString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString().trim();
}

bool _isCallPush(RemoteMessage m) =>
    _asString(m.data['type']).toLowerCase() == 'call';

String _extractCallId(RemoteMessage m) => _asString(m.data['callId']);

String _extractCallType(RemoteMessage m) => _asString(m.data['callType']);

String _extractRoomId(RemoteMessage message) {
  final data = message.data;

  const keys = <String>[
    'roomId',
    'room_id',
    'chatId',
    'chat_id',
    'rid',
    'threadId',
    'thread_id',
  ];

  for (final k in keys) {
    final val = _asString(data[k]);
    if (val.isNotEmpty) return val;
  }
  return '';
}

String _extractSenderId(RemoteMessage message) {
  final data = message.data;
  const keys = <String>[
    'senderId',
    'sender_id',
    'fromUid',
    'from_uid',
    'uid',
  ];
  for (final k in keys) {
    final val = _asString(data[k]);
    if (val.isNotEmpty) return val;
  }
  return '';
}

bool _isChatMessage(RemoteMessage message) {
  final t = _asString(message.data['type']).toLowerCase();
  if (t == 'chat' || t == 'chat_message' || t == 'message') return true;

  final rid = _extractRoomId(message);
  final sid = _extractSenderId(message);
  return rid.isNotEmpty || sid.isNotEmpty;
}

bool _hasSystemNotificationPayload(RemoteMessage message) {
  return message.notification != null;
}

String _extractNotificationTitle(RemoteMessage message) {
  final dataTitle = _asString(message.data['title']);
  if (dataTitle.isNotEmpty) return dataTitle;

  final notifTitle = _asString(message.notification?.title);
  if (notifTitle.isNotEmpty) return notifTitle;

  return kMwOnlyPushTitle;
}

int _stableNotificationIdFromRoom(String roomId) {
  var hash = 0;
  for (final codeUnit in roomId.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash;
}

Future<void> _resetUnreadBadgeCountServerBestEffort() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    await FirebaseFunctions.instance
        .httpsCallable('resetMyUnreadBadgeCount')
        .call();

    debugPrint('✅ Server unread badge count reset');
  } catch (e) {
    debugPrint('⚠️ resetMyUnreadBadgeCount failed: $e');
  }
}

String _extractNotificationBody(RemoteMessage message) {
  final dataBodyCandidates = <String>[
    _asString(message.data['body']),
    _asString(message.data['message']),
    _asString(message.data['text']),
    _asString(message.data['content']),
  ];

  for (final v in dataBodyCandidates) {
    if (v.isNotEmpty) return v;
  }

  final notifBody = _asString(message.notification?.body);
  if (notifBody.isNotEmpty) return notifBody;

  return 'New message';
}

void _showForegroundBanner({required String title}) {
  rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}

/// ✅ Align with AuthScreen behavior:
/// - Reload + getIdToken(true) + reload again
/// - Only ever SET isActive=true
Future<void> _activateIfEmailVerified(User user) async {
  try {
    await user.reload();
  } catch (_) {}

  var refreshed = FirebaseAuth.instance.currentUser;
  if (refreshed == null) return;

  try {
    await refreshed.getIdToken(true);
  } catch (_) {}

  try {
    await refreshed.reload();
  } catch (_) {}

  refreshed = FirebaseAuth.instance.currentUser;
  if (refreshed == null) return;

  if (!refreshed.emailVerified) return;

  await FirebaseFirestore.instance.collection('users').doc(refreshed.uid).set(
    {
      'isActive': true,
      'emailVerified': true,
      'emailVerifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}

/// ---------------------------------------------------------------------------
/// CallKit answer race guard
/// ---------------------------------------------------------------------------
bool isHandlingCallKitAnswer = false;

void setHandlingCallKitAnswer(bool v) => isHandlingCallKitAnswer = v;

/// ------------------------------
/// Firebase Init Guard
/// ------------------------------
Future<FirebaseApp>? _firebaseInitFuture;

Future<FirebaseApp> _ensureFirebaseInitialized() {
  final existing = _firebaseInitFuture;
  if (existing != null) return existing;

  _firebaseInitFuture = () async {
    if (Firebase.apps.isNotEmpty) {
      return Firebase.apps.first;
    }

    try {
      final app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return app;
    } catch (e) {
      if (Firebase.apps.isNotEmpty) {
        return Firebase.apps.first;
      }
      rethrow;
    }
  }();

  return _firebaseInitFuture!;
}

/// ------------------------------
/// Phone Auth Mode
/// ------------------------------
Future<void> _configurePhoneAuthMode() async {
  if (kIsWeb) return;

  await FirebaseAuth.instance.setSettings(
    appVerificationDisabledForTesting: kUseFakeOtp,
  );

  debugPrint(
    kUseFakeOtp
        ? '🧪 Firebase phone auth FAKE testing mode enabled'
        : '✅ Firebase phone auth REAL verification mode enabled',
  );
}

/// ------------------------------
/// Local notifications
/// ------------------------------
final FlutterLocalNotificationsPlugin fln = FlutterLocalNotificationsPlugin();
bool _localNotificationsReady = false;

Future<void> setupMwChannels() async {
  if (kIsWeb) return;
  if (_localNotificationsReady) return;

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
    macOS: iosInit,
  );

  await fln.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse resp) async {
      final payload = (resp.payload ?? '').trim();
      debugPrint('🔔 Local notification tapped payload=$payload');

      if (payload == 'friend_requests') {
        await _openFriendRequestsFromPushIfPossible();
        return;
      }

      if (payload.isNotEmpty) {
        final nav = rootNavigatorKey.currentState;
        if (nav == null) return;

        nav.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              roomId: payload,
              title: 'Chat',
            ),
          ),
        );
      }
    },
  );

  await fln
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await fln
      .resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(
    alert: true,
    badge: true,
    sound: true,
  );

  await fln
      .resolvePlatformSpecificImplementation<
      MacOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(
    alert: true,
    badge: true,
    sound: true,
  );

  const chat = AndroidNotificationChannel(
    kMwChatChannelId,
    'MW Chat',
    description: 'Chat messages',
    importance: Importance.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('mw_pop'),
    enableVibration: true,
  );

  const calls = AndroidNotificationChannel(
    kMwCallsChannelId,
    'MW Calls',
    description: 'Incoming calls',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('mw_ring'),
    enableVibration: true,
  );

  const achievements = AndroidNotificationChannel(
    kMwAchievementsChannelId,
    'MW Achievements',
    description: 'Achievements and rewards',
    importance: Importance.defaultImportance,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('mw_success'),
    enableVibration: true,
  );

  const social = AndroidNotificationChannel(
    kMwSocialChannelId,
    'MW Social',
    description: 'Friend requests and social activity',
    importance: Importance.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('mw_pop'),
    enableVibration: true,
  );

  await fln
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(chat);

  await fln
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(calls);

  await fln
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(achievements);

  await fln
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(social);

  _localNotificationsReady = true;
  debugPrint('✅ Local notifications initialized');
}

NotificationDetails _buildChatNotificationDetails() {
  return NotificationDetails(
    android: const AndroidNotificationDetails(
      kMwChatChannelId,
      'MW Chat',
      channelDescription: 'Chat messages',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('mw_pop'),
      enableVibration: true,
      ticker: 'MW',
      icon: '@mipmap/ic_launcher',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: kMwAppleChatSound,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: kMwAppleChatSound,
    ),
  );
}

bool _isFriendPush(RemoteMessage m) {
  final t = _asString(m.data['type']).toLowerCase();
  return t == 'friend_request' ||
      t == 'friend_accept' ||
      t == 'friend' ||
      t == 'social';
}

String _extractFriendFromUid(RemoteMessage message) {
  final data = message.data;

  const keys = <String>[
    'fromUid',
    'from_uid',
    'senderId',
    'sender_id',
  ];

  for (final k in keys) {
    final val = _asString(data[k]);
    if (val.isNotEmpty) return val;
  }

  return '';
}

NotificationDetails _buildSocialNotificationDetails() {
  return NotificationDetails(
    android: const AndroidNotificationDetails(
      kMwSocialChannelId,
      'MW Social',
      channelDescription: 'Friend requests and social activity',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('mw_pop'),
      enableVibration: true,
      ticker: 'MW',
      icon: '@mipmap/ic_launcher',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: kMwAppleChatSound,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: kMwAppleChatSound,
    ),
  );
}

Future<void> _showBackgroundSocialNotificationIfNeeded(
    RemoteMessage message,
    ) async {
  if (kIsWeb) return;

  // Keep iOS on APNs/system delivery to avoid duplicate behavior.
  if (defaultTargetPlatform == TargetPlatform.iOS) return;

  if (!_isFriendPush(message)) return;

  if (_hasSystemNotificationPayload(message)) {
    debugPrint('ℹ️ BG social push already has notification payload, skip local.');
    return;
  }

  try {
    await setupMwChannels();

    final fromUid = _extractFriendFromUid(message);
    final int id = fromUid.isNotEmpty
        ? fromUid.hashCode
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await fln.show(
      id,
      _extractNotificationTitle(message),
      _extractNotificationBody(message),
      _buildSocialNotificationDetails(),
      payload: 'friend_requests',
    );

    debugPrint('✅ Background local social notification shown. id=$id');
  } catch (e) {
    debugPrint('⚠️ background local social notification failed: $e');
  }
}
Future<void> _showBackgroundChatNotificationIfNeeded(
    RemoteMessage message,
    ) async {
  if (kIsWeb) return;

  // Keep iOS background chat handling with APNs / FCM system delivery.
  // Avoid local background chat notifications on iOS because they can
  // interfere with the flow that was previously working.
  if (defaultTargetPlatform == TargetPlatform.iOS) return;

  if (_isCallPush(message)) return;
  if (!_isChatMessage(message)) return;

  if (_hasSystemNotificationPayload(message)) {
    debugPrint('ℹ️ BG chat push already has notification payload, skip local.');
    return;
  }

  try {
    await setupMwChannels();

    final roomId = _extractRoomId(message);
    final int id = roomId.isNotEmpty
        ? _stableNotificationIdFromRoom(roomId)
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await fln.show(
      id,
      _extractNotificationTitle(message),
      _extractNotificationBody(message),
      _buildChatNotificationDetails(),
      payload: _extractRoomId(message),
    );

    debugPrint('✅ Background local chat notification shown. id=$id');
  } catch (e) {
    debugPrint('⚠️ background local chat notification failed: $e');
  }
}

/// REQUIRED for background notifications (mobile only)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebaseInitialized();

  debugPrint('🔔 BACKGROUND MESSAGE: ${message.messageId}');
  debugPrint('🔔 DATA: ${message.data}');
  debugPrint(
    '🔔 NOTIFICATION PAYLOAD present=${message.notification != null}',
  );

  if (_isCallPush(message)) {
    final callId = _extractCallId(message);
    if (callId.isEmpty) return;

    try {
      await MwCallPushUi.ensureInit();
    } catch (e) {
      debugPrint('⚠️ MwCallPushUi.ensureInit failed in BG: $e');
    }

    await MwCallPushUi.showIncomingCallNotificationFromBg(message.data);
    return;
  }

  if (_isFriendPush(message)) {
    await _showBackgroundSocialNotificationIfNeeded(message);
    return;
  }

  await _showBackgroundChatNotificationIfNeeded(message);
}

/// ------------------------------
/// Firestore helpers (best-effort)
/// ------------------------------
Future<DocumentSnapshot<Map<String, dynamic>>> _getUserDocBestEffort(
    String uid,
    ) async {
  final ref = FirebaseFirestore.instance.collection('users').doc(uid);
  try {
    return await ref.get(const GetOptions(source: Source.server));
  } catch (e) {
    debugPrint('⚠️ _getUserDocBestEffort server failed: $e');
  }

  return ref.get();
}

/// ------------------------------
/// FCM Token Sync (deduped)
/// ------------------------------
String? _lastStoredFcmToken;
String? _lastStoredUid;

StreamSubscription<User?>? _authTokenSyncSub;
StreamSubscription<String>? _tokenRefreshSub;

Future<void> _storeTokenForUserIfChanged({
  required String uid,
  required String token,
}) async {
  if (token.isEmpty) return;

  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  if (currentUid == null) {
    debugPrint('⚠️ Skip storing FCM token: no signed-in user');
    return;
  }

  if (currentUid != uid) {
    debugPrint(
      '⚠️ Skip storing FCM token: uid mismatch currentUid=$currentUid targetUid=$uid',
    );
    return;
  }

  if (_lastStoredUid == uid && _lastStoredFcmToken == token) return;

  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    _lastStoredUid = uid;
    _lastStoredFcmToken = token;

    debugPrint('✅ Stored FCM token for user $uid');
  } on FirebaseException catch (e) {
    debugPrint(
      '⚠️ Failed to store FCM token for user $uid: code=${e.code} message=${e.message}',
    );
  } catch (e) {
    debugPrint('⚠️ Failed to store FCM token for user $uid: $e');
  }
}

Future<void> _syncCurrentTokenIfPossible() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    debugPrint('⚠️ No signed-in user, skipping FCM token sync.');
    return;
  }

  try {
    final apns = await FirebaseMessaging.instance.getAPNSToken();
    debugPrint('🍎 APNs token exists=${apns != null && apns.isNotEmpty}');

    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('📲 FCM token value=${token ?? "(null)"}');

    if (token == null || token.isEmpty) {
      debugPrint('⚠️ FCM token is null/empty.');
      return;
    }

    await _storeTokenForUserIfChanged(uid: user.uid, token: token);
  } on FirebaseException catch (e) {
    if (e.code == 'apns-token-not-set') {
      debugPrint('⏳ APNs token not ready yet, will rely on onTokenRefresh.');
    } else {
      debugPrint('⚠️ FCM getToken failed: ${e.code} ${e.message}');
    }
  } catch (e) {
    debugPrint('⚠️ FCM getToken failed: $e');
  }
}

/// ✅ Ensure token is ready (THROTTLED, NO force refresh)
DateTime? _lastIdTokenAttempt;

Future<void> _ensureIdTokenReady(User user) async {
  final now = DateTime.now();
  if (_lastIdTokenAttempt != null &&
      now.difference(_lastIdTokenAttempt!).inSeconds < 30) {
    return;
  }
  _lastIdTokenAttempt = now;

  try {
    await user.getIdToken();
  } catch (e) {
    debugPrint('⚠️ getIdToken() failed: $e');
  }
}

/// ------------------------------
/// VoIP Token Sync (iOS PushKit)
/// ------------------------------
const MethodChannel _voipChannel = MethodChannel('mw.voip');

String? _pendingVoipToken;
String? _lastStoredVoipToken;
String? _lastStoredVoipUid;
bool _voipBridgeReady = false;

bool get _isIosDevice =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<void> _storeVoipTokenForUserIfChanged({
  required String uid,
  required String token,
}) async {
  if (_lastStoredVoipUid == uid && _lastStoredVoipToken == token) return;

  _lastStoredVoipUid = uid;
  _lastStoredVoipToken = token;

  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'voipToken': token,
        'voipUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    debugPrint('✅ Stored VoIP token for user $uid (len=${token.length})');
  } on FirebaseException catch (e) {
    debugPrint(
      '⚠️ Failed to store VoIP token for user $uid: code=${e.code} message=${e.message}',
    );
  } catch (e) {
    debugPrint('⚠️ Failed to store VoIP token for user $uid: $e');
  }
}

void _initVoipBridgeOnce() {
  if (!_isIosDevice) return;
  if (_voipBridgeReady) return;
  _voipBridgeReady = true;

  _voipChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'voipToken':
        final token = (call.arguments as String?)?.trim() ?? '';
        debugPrint('📞 [VoIP] token from iOS len=${token.length}');

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _pendingVoipToken = token;
          debugPrint('📞 [VoIP] user not logged in → cached token');
          return;
        }

        await _storeVoipTokenForUserIfChanged(uid: user.uid, token: token);
        return;

      case 'voipPushReceived':
        debugPrint('📞 [VoIP] push received args=${call.arguments}');
        return;

      case 'callkitEvent':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        final event = _asString(args['event']).toLowerCase();
        final callId = _asString(args['callId']);

        debugPrint('📞 [CallKit] event=$event callId=$callId args=$args');

        if (event == 'answer') {
          if (callId.isNotEmpty) {
            setHandlingCallKitAnswer(true);
            await MwCallPushUi.handleCallKitAnswer(callId);
          }
          return;
        }

        if (event == 'end') {
          if (callId.isNotEmpty) {
            await MwCallPushUi.handleCallKitEnd(callId);
          }
          return;
        }

        if (event == 'audioactivated') {
          debugPrint('📞 [CallKit] audio activated');
          return;
        }

        if (event == 'audiodeactivated') {
          debugPrint('📞 [CallKit] audio deactivated');
          return;
        }

        debugPrint('⚠️ [CallKit] unhandled event=$event');
        return;

      default:
        debugPrint('⚠️ [VoIP] unhandled method=${call.method}');
        return;
    }
  });
}

Future<void> _flushPendingVoipIfAny(User user) async {
  if (!_isIosDevice) return;
  final pending = _pendingVoipToken;
  if (pending == null) return;

  _pendingVoipToken = null;
  await _storeVoipTokenForUserIfChanged(uid: user.uid, token: pending);
  debugPrint('📞 [VoIP] flushed cached token after login');
}

/// ------------------------------
/// Auth-driven token sync
/// ------------------------------
void _setupAuthDrivenTokenSync() {
  _authTokenSyncSub?.cancel();
  _authTokenSyncSub =
      FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user == null) {
          return;
        }

        unawaited(_syncCurrentTokenIfPossible());
        await _flushPendingVoipIfAny(user);
      });
}

/// ------------------------------
/// ✅ AUTH DEBUG
/// ------------------------------
DateTime? _lastTokenLogAt;

void _setupAuthDebug() {
  if (!kDebugMode) return;

  _idTokenDebugSub?.cancel();
  _idTokenDebugSub = FirebaseAuth.instance.idTokenChanges().listen((user) {
    final now = DateTime.now();
    if (_lastTokenLogAt != null &&
        now.difference(_lastTokenLogAt!).inSeconds < 5) {
      return;
    }
    _lastTokenLogAt = now;
    debugPrint('🧩 [AUTH][idTokenChanges] uid=${user?.uid ?? "null"}');
  });
}

/// ------------------------------
/// ✅ Web persistence
/// ------------------------------
Future<void> _setupWebAuthPersistence() async {
  if (!kIsWeb) return;
  try {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    debugPrint('✅ [AUTH][WEB] persistence=LOCAL');
  } catch (e) {
    debugPrint('⚠️ [AUTH][WEB] setPersistence failed: $e');
  }
}

/// ------------------------------
/// Push init (FCM listeners + dedupe)
/// ------------------------------
String? _lastOpenedPushRoomId;
DateTime? _lastOpenedPushRoomAt;
bool _shouldSuppressDuplicatePushOpen(String roomId) {
  final now = DateTime.now();
  if (_lastOpenedPushRoomId == roomId &&
      _lastOpenedPushRoomAt != null &&
      now.difference(_lastOpenedPushRoomAt!).inSeconds < 2) {
    return true;
  }

  _lastOpenedPushRoomId = roomId;
  _lastOpenedPushRoomAt = now;
  return false;
}

Future<void> _openChatFromPushIfPossible(RemoteMessage message) async {
  final roomId = _extractRoomId(message).trim();
  if (roomId.isEmpty) {
    debugPrint('⚠️ Push chat open skipped: empty roomId');
    return;
  }

  if (_shouldSuppressDuplicatePushOpen(roomId)) {
    debugPrint('ℹ️ Push chat open suppressed as duplicate. roomId=$roomId');
    return;
  }

  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (currentUid.isEmpty) {
    debugPrint('⚠️ Push chat open skipped: no signed-in user');
    return;
  }

  final activeRoomId = (currentChatTracker.activeRoomId ?? '').trim();
  if (activeRoomId == roomId) {
    debugPrint('ℹ️ Push chat open skipped: already in target room. roomId=$roomId');
    return;
  }

  String chatTitle = _extractNotificationTitle(message).trim();
  if (chatTitle.isEmpty || chatTitle == kMwOnlyPushTitle) {
    chatTitle = 'Chat';
  }

  try {
    await FirebaseFirestore.instance
        .collection('privateChats')
        .doc(roomId)
        .get(const GetOptions(source: Source.server));
  } catch (e) {
    debugPrint('⚠️ Push chat prefetch failed for roomId=$roomId: $e');
  }

  await Future<void>.delayed(const Duration(milliseconds: 250));

  final nav = rootNavigatorKey.currentState;
  if (nav == null) {
    debugPrint('⚠️ Push chat open skipped: navigator not ready');
    return;
  }

  try {
    nav.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          roomId: roomId,
          title: chatTitle,
        ),
      ),
    );
    debugPrint('✅ Navigated to chat from push. roomId=$roomId');
  } catch (e) {
    debugPrint('⚠️ push chat failed for roomId=$roomId: $e');
  }
}


Future<void> _initPushNotifications() async {
  final messaging = FirebaseMessaging.instance;

  try {
    await messaging.setAutoInitEnabled(true);
  } catch (e) {
    debugPrint('⚠️ setAutoInitEnabled failed/skipped: $e');
  }

  try {
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔔 Notification permission: ${settings.authorizationStatus}');
  } catch (e) {
    debugPrint('⚠️ requestPermission failed/skipped: $e');
  }

  if (!kIsWeb) {
    try {
      // Keep Apple foreground system presentation off to avoid duplicates.
      // Foreground UI is handled by app logic.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    } catch (e) {
      debugPrint('⚠️ setForegroundNotificationPresentationOptions skipped: $e');
    }
  }

  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final apns = await messaging.getAPNSToken();
      debugPrint('🍎 APNs token ready=${apns != null && apns.isNotEmpty}');
    }
  } catch (e) {
    debugPrint('⚠️ APNs token read failed: $e');
  }

  try {
    final token = await messaging.getToken();
    debugPrint(
      '📲 Initial FCM token ready=${token != null && token.isNotEmpty}',
    );
  } catch (e) {
    debugPrint('⚠️ Initial FCM token read failed: $e');
  }

  await _tokenRefreshSub?.cancel();
  _tokenRefreshSub =
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('🔁 TOKEN REFRESHED');
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;
        await _storeTokenForUserIfChanged(uid: user.uid, token: newToken);
      });

  await _syncCurrentTokenIfPossible();

  await _foregroundMsgSub?.cancel();
  await _onOpenSub?.cancel();

  _foregroundMsgSub =
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('🔔 FOREGROUND MESSAGE: ${message.messageId}');
        debugPrint('🔔 FOREGROUND DATA: ${message.data}');
        debugPrint(
          '🔔 FOREGROUND notification payload present=${message.notification != null}',
        );

        if (_isCallPush(message)) {
          final callId = _extractCallId(message);
          debugPrint(
            '📞 FOREGROUND CALL PUSH callId=$callId type=${_extractCallType(message)}',
          );

          if (callId.isNotEmpty) {
            try {
              MwCallPushUi.handleCallPushInForeground(message.data);
            } catch (e) {
              debugPrint('⚠️ handleCallPushInForeground failed: $e');
            }
          }
          return;
        }

        final pushRoomId = _extractRoomId(message);
        final pushSenderId = _extractSenderId(message);
        final activeRoomId = (currentChatTracker.activeRoomId ?? '').trim();

        debugPrint(
          '🔔 FOREGROUND | inChat=${currentChatTracker.isInChat} '
              'activeRoom=$activeRoomId pushRoom=$pushRoomId sender=$pushSenderId',
        );

        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

        if (currentUid.isNotEmpty &&
            pushSenderId.isNotEmpty &&
            pushSenderId == currentUid) {
          debugPrint('🔕 Self message suppressed.');
          return;
        }

        if (currentChatTracker.isInChat && _isChatMessage(message)) {
          debugPrint('🔕 In chat screen → suppress foreground banner.');
          return;
        }

        if (_isFriendPush(message)) {
          debugPrint('👥 FOREGROUND FRIEND PUSH data=${message.data}');
          _showForegroundBanner(title: _extractNotificationTitle(message));
          return;
        }

        if (_isChatMessage(message)) {
          _showForegroundBanner(title: _extractNotificationTitle(message));

          // No extra local foreground notification for now.
          // This keeps behavior stable and avoids duplicate sounds/banners.
          return;
        }

        _showForegroundBanner(title: _extractNotificationTitle(message));
      });

  _onOpenSub =
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        debugPrint('🔔 OPENED FROM NOTIFICATION');

        if (_isCallPush(message)) {
          final callId = _extractCallId(message);
          debugPrint(
            '📞 OPENED CALL PUSH callId=$callId type=${_extractCallType(message)}',
          );

          try {
            MwCallPushUi.handleCallPushOnOpen(message.data);
          } catch (e) {
            debugPrint('⚠️ handleCallPushOnOpen failed: $e');
          }
          return;
        }

        if (_isFriendPush(message)) {
          debugPrint('👥 OPENED FRIEND PUSH data=${message.data}');
          await _openFriendRequestsFromPushIfPossible();
          return;
        }

        final roomId = _extractRoomId(message);
        debugPrint('💬 Chat notification opened payload roomId=$roomId');

        if (_isChatMessage(message) && roomId.isNotEmpty) {
          await _openChatFromPushIfPossible(message);
        }
      });

  try {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      debugPrint('🔔 APP OPENED FROM TERMINATED PUSH');

      if (_isCallPush(initial)) {
        final callId = _extractCallId(initial);
        debugPrint(
          '📞 TERMINATED CALL PUSH callId=$callId type=${_extractCallType(initial)}',
        );

        try {
          MwCallPushUi.handleCallPushOnOpen(initial.data);
        } catch (e) {
          debugPrint('⚠️ terminated handleCallPushOnOpen failed: $e');
        }
      } else if (_isFriendPush(initial)) {
        debugPrint('👥 TERMINATED FRIEND PUSH data=${initial.data}');
        await _openFriendRequestsFromPushIfPossible();
      } else {
        final roomId = _extractRoomId(initial);
        debugPrint('💬 Terminated chat notification payload roomId=$roomId');

        if (_isChatMessage(initial) && roomId.isNotEmpty) {
          await _openChatFromPushIfPossible(initial);
        }
      }
    }
  } catch (e) {
    debugPrint('⚠️ getInitialMessage skipped: $e');
  }
}

Future<void> _openFriendRequestsFromPushIfPossible() async {
  final nav = rootNavigatorKey.currentState;
  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  if (nav == null) {
    debugPrint('⚠️ Push friend open skipped: navigator not ready');
    return;
  }

  if (currentUid.isEmpty) {
    debugPrint('⚠️ Push friend open skipped: no signed-in user');
    return;
  }

  try {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    nav.push(
      MaterialPageRoute(
        builder: (_) => MwFriendRequestsScreen(
          currentUserId: currentUid,
        ),
      ),
    );

    debugPrint('✅ Navigated to friend requests from push');
  } catch (e) {
    debugPrint('⚠️ push friend requests navigation failed: $e');
  }
}

Future<void> main() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('❌ FlutterError: ${details.exception}');
    if (details.stack != null) {
      debugPrint(details.stack.toString());
    }
  };

  BindingBase.debugZoneErrorsAreFatal = kDebugMode;

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await _ensureFirebaseInitialized();
    await _setupWebAuthPersistence();
    await _configurePhoneAuthMode();

    _initVoipBridgeOnce();

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }

    if (!kIsWeb) {
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
          appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
        );
      } catch (e) {
        debugPrint('⚠️ App Check init skipped: $e');
      }
    }

    if (!kIsWeb) {
      try {
        await setupMwChannels();
      } catch (e) {
        debugPrint('⚠️ setupMwChannels skipped: $e');
      }
    }

    try {
      await MwCallPushUi.ensureInit();
    } catch (e) {
      debugPrint('⚠️ MwCallPushUi.ensureInit skipped: $e');
    }

    NotificationBadgeService.instance.start(fln);
    await _initPushNotifications();
    _setupAuthDrivenTokenSync();
    PresenceService.instance.init();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TypographyProvider>(
            create: (_) {
              final p = TypographyProvider();
              p.start();
              return p;
            },
          ),
          ChangeNotifierProvider<LocaleProvider>(
            create: (ctx) {
              final lp = LocaleProvider(
                typographyProvider: ctx.read<TypographyProvider>(),
              );
              unawaited(lp.start());
              return lp;
            },
          ),
          ChangeNotifierProvider<CurrentChatTracker>.value(
            value: currentChatTracker,
          ),
        ],
        child: const _AppBootstrap(
          child: MyApp(),
        ),
      ),
    );
  }, (error, stack) {
    debugPrint('❌ ZONED ERROR: $error');
    debugPrint(stack.toString());
  });
}

class _AppBootstrap extends StatefulWidget {
  final Widget child;

  const _AppBootstrap({required this.child});

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _setupAuthDebug();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return IncomingCallListener(
      child: Builder(
        builder: (context) {
          final localeProvider = context.watch<LocaleProvider>();
          final typo = context.watch<TypographyProvider>();

          final locale = localeProvider.locale;
          final isArabic = locale.languageCode.toLowerCase() == 'ar';

          final resolvedFamily = typo.fontFamily.trim().isNotEmpty
              ? typo.fontFamily.trim()
              : (isArabic ? 'NotoSansArabic' : 'Poppins');

          return MaterialApp(
            navigatorKey: rootNavigatorKey,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(
              isArabic: isArabic,
              fontScale: typo.fontScale,
              fontFamily: resolvedFamily,
            ),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            onGenerateTitle: (ctx) =>
            AppLocalizations.of(ctx)?.mainTitle ?? 'MW Chat',
            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();

              final mq = MediaQuery.of(context);
              final scaledChild = MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(typo.fontScale)),
                child: child,
              );

              return MwSwipeBack(
                navigatorKey: rootNavigatorKey,
                enabled: true,
                child: scaledChild,
              );
            },
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

/// ✅ AUTH GATE
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastUid;
  Future<void>? _initFuture;

  bool _promptedLinkEmailThisSession = false;
  bool _promptedLinkPhoneThisSession = false;
  bool _linkSheetOpen = false;

  RecaptchaVerifier? _webRecaptchaVerifier;
  bool _webRecaptchaRendered = false;
  bool _webRecaptchaExpired = false;
  bool _webRecaptchaBusy = false;

  static const String _recaptchaParentId = '__mw-recaptcha-container';
  static const String _recaptchaChildId = '__mw-recaptcha-inner';

  String? _serverFetchedUid;
  bool _serverFetchInFlight = false;
  DateTime? _lastActivationAttempt;
  bool _activationInFlight = false;

  Future<void> _maybeActivateIfEmailVerifiedThrottled(User user) async {
    if (_activationInFlight) return;

    final now = DateTime.now();
    if (_lastActivationAttempt != null &&
        now.difference(_lastActivationAttempt!).inSeconds < 45) {
      return;
    }
    _lastActivationAttempt = now;

    _activationInFlight = true;
    try {
      await _activateIfEmailVerified(user);
    } finally {
      _activationInFlight = false;
    }
  }

  bool _needsNamesFromFirestore(Map<String, dynamic> data) {
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    return first.isEmpty || last.isEmpty;
  }

  Future<void> _initWebRecaptcha() async {
    if (!kIsWeb) return;

    if (_webRecaptchaVerifier != null &&
        _webRecaptchaRendered &&
        !_webRecaptchaExpired) {
      return;
    }

    if (_webRecaptchaBusy) return;
    _webRecaptchaBusy = true;

    final rid = DateTime.now().millisecondsSinceEpoch;

    try {
      _webRecaptchaVerifier?.clear();

      final mustRecreate = _webRecaptchaVerifier == null ||
          _webRecaptchaExpired ||
          !_webRecaptchaRendered;

      if (mustRecreate && _webRecaptchaVerifier != null) {
        try {
          _webRecaptchaVerifier!.clear();
        } catch (_) {}
        _webRecaptchaVerifier = null;
      }

      if (_webRecaptchaVerifier != null) {
        return;
      }

      _webRecaptchaRendered = false;
      _webRecaptchaExpired = false;

      final verifier = RecaptchaVerifier(
        container: _recaptchaChildId,
        auth: FirebaseAuthPlatform.instance,
        size: RecaptchaVerifierSize.normal,
        theme: RecaptchaVerifierTheme.dark,
        onError: (e) => debugPrint(
          '[AuthGate] reCAPTCHA onError rid=$rid: ${e.code} ${e.message}',
        ),
        onExpired: () async {
          _webRecaptchaExpired = true;
          _webRecaptchaRendered = false;
          debugPrint('[AuthGate] reCAPTCHA expired rid=$rid');

          if (mounted) setState(() {});

          await _refreshWebRecaptcha();
        },
      );

      _webRecaptchaVerifier = verifier;

      await verifier.render().timeout(const Duration(seconds: 60));
      _webRecaptchaRendered = true;

      debugPrint(
        '[AuthGate] reCAPTCHA rendered rid=$rid container=$_recaptchaChildId',
      );
    } catch (e, st) {
      debugPrint('[AuthGate] _initWebRecaptcha error rid=$rid: $e\n$st');
    } finally {
      _webRecaptchaBusy = false;
    }
  }

  Future<void> _refreshWebRecaptcha() async {
    if (!kIsWeb) return;

    while (_webRecaptchaBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    try {
      _webRecaptchaVerifier?.clear();
    } catch (_) {}

    _webRecaptchaVerifier = null;
    _webRecaptchaRendered = false;
    _webRecaptchaExpired = false;

    await ensureRecaptchaContainer(
      parentId: _recaptchaParentId,
      childId: _recaptchaChildId,
      visible: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 16));

    await _initWebRecaptcha();
  }

  String _webRecaptchaHint(AppLocalizations l10n) {
    return [
      l10n.recaptchaRejected,
      '',
      l10n.fixChecklistTitle,
      l10n.fixChecklistAuthorizedDomains,
      l10n.fixChecklistDisableAdBlockers,
      l10n.fixChecklistAllowCookies,
      l10n.fixChecklistTryIncognito,
      '',
      l10n.devTipTestPhoneNumbers,
    ].join('\n');
  }

  Future<void> _ensureServerDocOnce(String uid) async {
    if (_serverFetchedUid == uid) return;
    if (_serverFetchInFlight) return;
    _serverFetchInFlight = true;

    try {
      await _getUserDocBestEffort(uid);
      _serverFetchedUid = uid;
    } catch (_) {
      // ignore
    } finally {
      _serverFetchInFlight = false;
    }
  }

  Future<void> _linkEmailPasswordToCurrentUser({
    required AppLocalizations l10n,
    required String email,
    required String password,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: l10n.authError,
      );
    }

    final normalizedEmail = email.trim().toLowerCase();
    final credential = EmailAuthProvider.credential(
      email: normalizedEmail,
      password: password.trim(),
    );

    await user.linkWithCredential(credential);

    try {
      await user.sendEmailVerification();
    } catch (_) {}

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'email': normalizedEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _mapLinkEmailError(FirebaseAuthException e, AppLocalizations l10n) {
    switch (e.code) {
      case 'email-already-in-use':
        return l10n.emailAlreadyInUseLinking;
      case 'credential-already-in-use':
        return l10n.credentialAlreadyInUse;
      case 'provider-already-linked':
        return l10n.providerAlreadyLinked;
      case 'invalid-email':
        return l10n.invalidEmail;
      case 'weak-password':
        return l10n.weakPassword;
      default:
        return e.message ?? l10n.authError;
    }
  }

  Future<void> _linkPhoneCredentialToCurrentUser({
    required AppLocalizations l10n,
    required PhoneAuthCredential cred,
    required String e164,
    required String phoneCountryIso2,
    required String phoneCountryDialCode,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: l10n.authError,
      );
    }

    await user.linkWithCredential(cred);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'phoneNumber': e164,
        'phoneCountryIso2': phoneCountryIso2,
        'phoneCountryDialCode': phoneCountryDialCode,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _confirmWebPhoneLink({
    required AppLocalizations l10n,
    required String smsCode,
    required ConfirmationResult cr,
    required String e164,
    required String phoneCountryIso2,
    required String phoneCountryDialCode,
  }) async {
    await cr.confirm(smsCode);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: l10n.authError,
      );
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'phoneNumber': e164,
        'phoneCountryIso2': phoneCountryIso2,
        'phoneCountryDialCode': phoneCountryDialCode,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _maybePromptLinking({
    required User user,
    required Map<String, dynamic> data,
    required AppLocalizations l10n,
  }) async {
    if (!mounted) return;
    if (_linkSheetOpen) return;

    final authEmail = (user.email ?? '').trim();
    final authPhone = (user.phoneNumber ?? '').trim();

    final fsEmail = (data['email'] ?? '').toString().trim();
    final fsPhone = (data['phoneNumber'] ?? '').toString().trim();

    final hasAnyEmail = authEmail.isNotEmpty || fsEmail.isNotEmpty;
    final hasAnyPhone = authPhone.isNotEmpty || fsPhone.isNotEmpty;

    if (hasAnyPhone && !hasAnyEmail && !_promptedLinkEmailThisSession) {
      _promptedLinkEmailThisSession = true;
      _linkSheetOpen = true;

      final ctx = rootNavigatorKey.currentContext ?? context;

      try {
        await showLinkEmailSheet(
          context: ctx,
          l10n: l10n,
          initialEmail: '',
          onLink: (email, pass) async {
            await _linkEmailPasswordToCurrentUser(
              l10n: l10n,
              email: email,
              password: pass,
            );
          },
          mapError: (e) => _mapLinkEmailError(e, l10n),
          alive: () => mounted,
        );
      } finally {
        _linkSheetOpen = false;
      }
      return;
    }

    if (hasAnyEmail && !hasAnyPhone && !_promptedLinkPhoneThisSession) {
      _promptedLinkPhoneThisSession = true;
      _linkSheetOpen = true;

      final ctx = rootNavigatorKey.currentContext ?? context;

      try {
        await showLinkPhoneSheet(
          context: ctx,
          l10n: l10n,
          defaultCountry: null,
          defaultDialIso2: 'US',
          onSkip: () async {},
          onLinkWithCredential: (cred, e164, countryIso2, dialCode) async {
            await _linkPhoneCredentialToCurrentUser(
              l10n: l10n,
              cred: cred,
              e164: e164,
              phoneCountryIso2: countryIso2,
              phoneCountryDialCode: dialCode,
            );
          },
          onLinkWebConfirm: (smsCode, cr, e164, countryIso2, dialCode) async {
            await _confirmWebPhoneLink(
              l10n: l10n,
              smsCode: smsCode,
              cr: cr,
              e164: e164,
              phoneCountryIso2: countryIso2,
              phoneCountryDialCode: dialCode,
            );
          },
          initWebRecaptcha: () async => _initWebRecaptcha(),
          getWebRecaptchaVerifier: () => _webRecaptchaVerifier,
          refreshWebRecaptcha: () async => _refreshWebRecaptcha(),
          isWebRecaptchaReady: () =>
          _webRecaptchaVerifier != null &&
              _webRecaptchaRendered &&
              !_webRecaptchaExpired,
          webRecaptchaHint: () => _webRecaptchaHint(l10n),
        );
      } finally {
        _linkSheetOpen = false;
      }
    }
  }

  void _resetPromptSessionIfUserChanged(String uid) {
    if (_lastUid != uid) {
      _promptedLinkEmailThisSession = false;
      _promptedLinkPhoneThisSession = false;
      _linkSheetOpen = false;
      _serverFetchedUid = null;
      _serverFetchInFlight = false;

      if (kIsWeb) {
        try {
          _webRecaptchaVerifier?.clear();
        } catch (_) {}
        _webRecaptchaVerifier = null;
        _webRecaptchaRendered = false;
        _webRecaptchaExpired = false;
        _webRecaptchaBusy = false;
      }
    }
  }

  bool _authSaysActive(User user) {
    final hasPhone = (user.phoneNumber ?? '').trim().isNotEmpty;
    final emailVerified = user.emailVerified;
    return hasPhone || emailVerified;
  }

  Future<void> _bestEffortEnsureUserDocExists(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref.get(const GetOptions(source: Source.server));
      } catch (_) {
        snap = await ref.get();
      }

      final shouldBeActive = _authSaysActive(user);

      if (!snap.exists) {
        final data = <String, dynamic>{
          'email': (user.email ?? '').trim().toLowerCase(),
          'phoneNumber': user.phoneNumber ?? '',
          if (shouldBeActive) 'isActive': true,
          if (user.emailVerified) 'emailVerified': true,
          if (user.emailVerified)
            'emailVerifiedAt': FieldValue.serverTimestamp(),
          'isOnline': false,
          'hasAcceptedTerms': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
        };

        await ref.set(data, SetOptions(merge: true));
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final fsIsActive = (data['isActive'] == true);

      final patch = <String, dynamic>{
        if ((data['email'] ?? '').toString().trim().isEmpty &&
            (user.email ?? '').trim().isNotEmpty)
          'email': user.email!.trim().toLowerCase(),
        if ((data['phoneNumber'] ?? '').toString().trim().isEmpty &&
            (user.phoneNumber ?? '').trim().isNotEmpty)
          'phoneNumber': user.phoneNumber!.trim(),
        if (shouldBeActive && !fsIsActive) 'isActive': true,
        if (user.emailVerified && data['emailVerified'] != true)
          'emailVerified': true,
        if (user.emailVerified && data['emailVerifiedAt'] == null)
          'emailVerifiedAt': FieldValue.serverTimestamp(),
        if (data['createdAt'] == null) 'createdAt': FieldValue.serverTimestamp(),
      };

      if (patch.isNotEmpty) {
        patch['updatedAt'] = FieldValue.serverTimestamp();
        await ref.set(patch, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('⚠️ _bestEffortEnsureUserDocExists failed: $e');
    }
  }

  Future<void> _prepareUser(User user) async {
    try {
      await user.reload();
    } catch (_) {}

    final refreshed = FirebaseAuth.instance.currentUser ?? user;

    await _ensureIdTokenReady(refreshed);
    await _bestEffortEnsureUserDocExists(refreshed);
  }

  @override
  void dispose() {
    try {
      _webRecaptchaVerifier?.clear();
    } catch (_) {}
    _webRecaptchaVerifier = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;
        if (user == null) return const AuthScreen();

        _resetPromptSessionIfUserChanged(user.uid);

        if (_lastUid != user.uid || _initFuture == null) {
          _lastUid = user.uid;
          _initFuture = _prepareUser(user);
        }

        return FutureBuilder<void>(
          future: _initFuture,
          builder: (context, prepSnap) {
            if (prepSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final docRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: docRef.snapshots(),
              builder: (context, docSnap) {
                if (!docSnap.hasData) {
                  return Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.settingUpProfile,
                            style: const TextStyle(color: kTextSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final doc = docSnap.data!;
                final data = doc.data() ?? <String, dynamic>{};
                final isFromCache = doc.metadata.isFromCache;

                if (isFromCache && _serverFetchedUid != user.uid) {
                  unawaited(_ensureServerDocOnce(user.uid));

                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final rawUnreadBadge = data['unreadBadgeCount'];
                final unreadBadgeCount = rawUnreadBadge is num
                    ? rawUnreadBadge.toInt()
                    : 0;

                if (!kIsWeb) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    unawaited(
                      NotificationBadgeService.instance.setBadgeCount(unreadBadgeCount),
                    );
                  });
                }

                final fsActive = (data['isActive'] == true);

                final hasPhoneAuth = (user.phoneNumber ?? '').trim().isNotEmpty;
                final effectiveActive = fsActive || hasPhoneAuth;

                if (effectiveActive) {
                  final needsNames = _needsNamesFromFirestore(data);
                  if (!needsNames) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      unawaited(
                        _maybePromptLinking(user: user, data: data, l10n: l10n),
                      );
                    });
                  }
                }

                if (!effectiveActive) {
                  unawaited(_maybeActivateIfEmailVerifiedThrottled(user));
                  return _PendingActivationScreen(
                    userId: user.uid,
                    onCheckAgain: () async {
                      try {
                        await user.reload();
                      } catch (_) {}
                      try {
                        await user.getIdToken(true);
                      } catch (_) {}

                      final refreshed = FirebaseAuth.instance.currentUser ?? user;

                      await _activateIfEmailVerified(refreshed);

                      try {
                        await _getUserDocBestEffort(refreshed.uid);
                      } catch (_) {}
                      _serverFetchedUid = null;
                    },
                    onLogout: () async {
                      await FirebaseAuth.instance.signOut();
                    },
                  );
                }

                final needsNames = _needsNamesFromFirestore(data);

                if (needsNames) {
                  return CompleteProfileScreen(uid: user.uid);
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(
                    _maybePromptLinking(user: user, data: data, l10n: l10n),
                  );
                });

                return const HomeScreen();
              },
            );
          },
        );
      },
    );
  }
}

class _PendingActivationScreen extends StatelessWidget {
  final String userId;
  final Future<void> Function() onCheckAgain;
  final Future<void> Function() onLogout;

  const _PendingActivationScreen({
    required this.userId,
    required this.onCheckAgain,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [kPrimaryGold, kGoldDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: Colors.black,
                  size: 34,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.accountNotActive,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.waitForActivation,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSecondary),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.autoUpdateNotice,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => onCheckAgain(),
                icon: const Icon(Icons.refresh_rounded, color: Colors.black),
                label: Text(
                  l10n.checkAgain,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => onLogout(),
                icon: const Icon(Icons.logout, color: kTextSecondary),
                label: Text(
                  l10n.logout,
                  style: const TextStyle(color: kTextSecondary),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}