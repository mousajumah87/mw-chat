// lib/main.dart
// MW Chat – Modern private messaging app
// Copyright © 2025 Mousa Abu Hilal.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show BindingBase, debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb, kProfileMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mw/screens/auth/widgets/sheets/link_email_sheet.dart';
import 'package:mw/screens/auth/widgets/sheets/link_phone_sheet.dart';
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

/// ✅ All push UI must show ONLY this title (no body, no sender).
const String kMwOnlyPushTitle = 'MW';

/// GLOBAL SNACKBAR KEY (FOR FOREGROUND NOTIFICATIONS)
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
GlobalKey<ScaffoldMessengerState>();

/// ✅ GLOBAL NAVIGATOR KEY (CRITICAL for MwSwipeBack when wrapping whole app)
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Global instance of CurrentChatTracker used both by Provider and FCM logic.
final CurrentChatTracker currentChatTracker = CurrentChatTracker.instance;

/// ✅ Prevent duplicate foreground listeners (hot-restart, logout/login, rebuilds)
StreamSubscription<RemoteMessage>? _foregroundMsgSub;
StreamSubscription<RemoteMessage>? _onOpenSub;

/// ✅ Auth debug subscriptions
StreamSubscription<User?>? _authStateDebugSub;
StreamSubscription<User?>? _idTokenDebugSub;

/// ------------------------------
/// Small helpers for push parsing
/// ------------------------------
String _asString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString().trim();
}

bool _isCallPush(RemoteMessage m) => _asString(m.data['type']).toLowerCase() == 'call';
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
/// - Reload + getIdToken(true) + reload again (web sometimes needs token refresh)
/// - Only ever SET isActive=true (never false)
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

/// Small helper to show debug snackbars from anywhere (only works after UI mounts)
void _showDebugSnack(String msg) {
  final s = rootScaffoldMessengerKey.currentState;
  if (s == null) return;
  s.hideCurrentSnackBar();
  s.showSnackBar(
    SnackBar(
      content: Text(msg, maxLines: 3, overflow: TextOverflow.ellipsis),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ),
  );
}

/// ---------------------------------------------------------------------------
/// CallKit answer race guard (shared between CallKit events + Flutter UI)
/// ---------------------------------------------------------------------------
bool isHandlingCallKitAnswer = false;
void setHandlingCallKitAnswer(bool v) => isHandlingCallKitAnswer = v;

/// ------------------------------
/// Firebase Init Guard (FIXES: [DEFAULT] already exists)
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

/// REQUIRED for background notifications (mobile only)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _ensureFirebaseInitialized();

  debugPrint('🔔 BACKGROUND MESSAGE: ${message.messageId}');
  debugPrint('🔔 DATA: ${message.data}');

  if (!_isCallPush(message)) return;

  final callId = _extractCallId(message);
  if (callId.isEmpty) return;

  try {
    await MwCallPushUi.ensureInit();
  } catch (e) {
    debugPrint('⚠️ MwCallPushUi.ensureInit failed in BG: $e');
  }

  await MwCallPushUi.showIncomingCallNotificationFromBg(message.data);
}

/// ------------------------------
/// Firestore helpers (best-effort)
/// ------------------------------
Future<DocumentSnapshot<Map<String, dynamic>>> _getUserDocBestEffort(String uid) async {
  final ref = FirebaseFirestore.instance.collection('users').doc(uid);
  try {
    return await ref.get(const GetOptions(source: Source.server));
  } catch (e) {
    debugPrint('⚠️ _getUserDocBestEffort server failed: $e');
  }

  return ref.get(); // serverAndCache
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

  if (_lastStoredUid == uid && _lastStoredFcmToken == token) return;
  _lastStoredUid = uid;
  _lastStoredFcmToken = token;

  await FirebaseFirestore.instance.collection('users').doc(uid).set(
    {
      'fcmToken': token,
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  debugPrint('✅ Stored FCM token for user $uid');
}

Future<void> _syncCurrentTokenIfPossible() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
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
  if (_lastIdTokenAttempt != null && now.difference(_lastIdTokenAttempt!).inSeconds < 30) {
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

bool get _isIosDevice => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<void> _storeVoipTokenForUserIfChanged({
  required String uid,
  required String token,
}) async {
  if (_lastStoredVoipUid == uid && _lastStoredVoipToken == token) return;

  _lastStoredVoipUid = uid;
  _lastStoredVoipToken = token;

  await FirebaseFirestore.instance.collection('users').doc(uid).set(
    {
      'voipToken': token,
      'voipUpdatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  debugPrint('✅ Stored VoIP token for user $uid (len=${token.length})');
}

final FlutterLocalNotificationsPlugin fln = FlutterLocalNotificationsPlugin();

Future<void> setupMwChannels() async {
  if (kIsWeb) return;

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  const initSettings = InitializationSettings(
    android: androidInit,
  );

  await fln.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse resp) {},
  );

  final androidPlugin =
  fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin == null) return;

  const calls = AndroidNotificationChannel(
    'mw_calls_v1',
    'MW Calls',
    description: 'Incoming calls',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('mw_ring'),
    enableVibration: true,
  );

  const chat = AndroidNotificationChannel(
    'mw_chat_v1',
    'MW Chat',
    description: 'Chat messages',
    importance: Importance.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('mw_pop'),
    enableVibration: true,
  );

  const achievements = AndroidNotificationChannel(
    'mw_achievements_v1',
    'MW Achievements',
    description: 'Achievements and rewards',
    importance: Importance.defaultImportance,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('mw_success'),
    enableVibration: true,
  );

  await androidPlugin.createNotificationChannel(calls);
  await androidPlugin.createNotificationChannel(chat);
  await androidPlugin.createNotificationChannel(achievements);
}

void _initVoipBridgeOnce() {
  if (!_isIosDevice) return;
  if (_voipBridgeReady) return;
  _voipBridgeReady = true;

  _voipChannel.setMethodCallHandler((call) async {
    if (call.method != 'voipToken') return;

    final token = (call.arguments as String?)?.trim() ?? '';
    debugPrint('📞 [VoIP] token from iOS len=${token.length}');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _pendingVoipToken = token;
      debugPrint('📞 [VoIP] user not logged in → cached token');
      return;
    }

    await _storeVoipTokenForUserIfChanged(uid: user.uid, token: token);
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
  _authTokenSyncSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;

    unawaited(_syncCurrentTokenIfPossible());
    await _flushPendingVoipIfAny(user);
    unawaited(PresenceService.instance.markOnline());
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
    if (_lastTokenLogAt != null && now.difference(_lastTokenLogAt!).inSeconds < 5) {
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
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    } catch (e) {
      debugPrint('⚠️ setForegroundNotificationPresentationOptions skipped: $e');
    }
  }

  await _tokenRefreshSub?.cancel();
  _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    debugPrint('🔁 TOKEN REFRESHED');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _storeTokenForUserIfChanged(uid: user.uid, token: newToken);
  });

  await _syncCurrentTokenIfPossible();

  await _foregroundMsgSub?.cancel();
  await _onOpenSub?.cancel();

  _foregroundMsgSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (_isCallPush(message)) {
      final callId = _extractCallId(message);
      debugPrint('📞 FOREGROUND CALL PUSH callId=$callId type=${_extractCallType(message)}');
      if (callId.isNotEmpty) {
        MwCallPushUi.handleCallPushInForeground(message.data);
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

    if (currentUid.isNotEmpty && pushSenderId.isNotEmpty && pushSenderId == currentUid) {
      debugPrint('🔕 Self message suppressed.');
      return;
    }

    if (currentChatTracker.isInChat && _isChatMessage(message)) {
      debugPrint('🔕 In chat screen → suppress foreground banner.');
      return;
    }

    _showForegroundBanner(title: kMwOnlyPushTitle);
  });

  _onOpenSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('🔔 OPENED FROM NOTIFICATION');

    if (_isCallPush(message)) {
      final callId = _extractCallId(message);
      debugPrint('📞 OPENED CALL PUSH callId=$callId type=${_extractCallType(message)}');
      MwCallPushUi.handleCallPushOnOpen(message.data);
      return;
    }
  });

  try {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      debugPrint('🔔 APP OPENED FROM TERMINATED PUSH');
      if (_isCallPush(initial)) {
        final callId = _extractCallId(initial);
        debugPrint('📞 TERMINATED CALL PUSH callId=$callId type=${_extractCallType(initial)}');
        MwCallPushUi.handleCallPushOnOpen(initial.data);
      }
    }
  } catch (e) {
    debugPrint('⚠️ getInitialMessage skipped: $e');
  }
}

Future<void> main() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('❌ FlutterError: ${details.exception}');
    if (details.stack != null) debugPrint(details.stack.toString());
  };

  BindingBase.debugZoneErrorsAreFatal = kDebugMode;

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await _ensureFirebaseInitialized();
    await _setupWebAuthPersistence();

    _initVoipBridgeOnce();

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }

    if (!kIsWeb) {
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
          appleProvider: (kDebugMode || kProfileMode) ? AppleProvider.debug : AppleProvider.appAttest,
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

    _setupAuthDrivenTokenSync();
    PresenceService.instance.init();

    await _initPushNotifications();

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
        child: const _AppBootstrap(child: MyApp()),
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAuthDebug();
      unawaited(PresenceService.instance.markOnline());
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
            onGenerateTitle: (ctx) => AppLocalizations.of(ctx)?.mainTitle ?? 'MW Chat',
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

/// ✅ AUTH GATE — aligns with AuthScreen rules:
/// - Never “auto-heal” isActive to true in build
/// - Never route to Home when user is not active
/// - Active = (hasPhone) OR (emailVerified from FirebaseAuth)
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastUid;
  Future<void>? _initFuture;

  // ✅ Prevent spamming prompts
  bool _promptedLinkEmailThisSession = false;
  bool _promptedLinkPhoneThisSession = false;
  bool _linkSheetOpen = false;

  // ✅ Web reCAPTCHA (needed for link phone on Web)
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

  // -----------------------------
  // Web reCAPTCHA init / refresh
  // -----------------------------
  Future<void> _initWebRecaptcha() async {
    if (!kIsWeb) return;

    if (_webRecaptchaVerifier != null && _webRecaptchaRendered && !_webRecaptchaExpired) return;
    if (_webRecaptchaBusy) return;
    _webRecaptchaBusy = true;

    final rid = DateTime.now().millisecondsSinceEpoch;

    try {
      await ensureRecaptchaContainer(
        parentId: _recaptchaParentId,
        childId: _recaptchaChildId,
        visible: true,
      );

      try {
        _webRecaptchaVerifier?.clear();
      } catch (_) {}

      _webRecaptchaVerifier = null;
      _webRecaptchaRendered = false;
      _webRecaptchaExpired = false;

      final verifier = RecaptchaVerifier(
        container: _recaptchaChildId,
        auth: FirebaseAuthPlatform.instance,
        size: RecaptchaVerifierSize.normal,
        theme: RecaptchaVerifierTheme.dark,
        onError: (e) => debugPrint('[AuthGate] reCAPTCHA onError rid=$rid: ${e.code} ${e.message}'),
        onExpired: () {
          _webRecaptchaExpired = true;
          debugPrint('[AuthGate] reCAPTCHA expired rid=$rid');
        },
      );

      _webRecaptchaVerifier = verifier;
      await verifier.render().timeout(const Duration(seconds: 60));
      _webRecaptchaRendered = true;

      debugPrint('[AuthGate] reCAPTCHA rendered rid=$rid container=$_recaptchaChildId');
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

      if (mounted) setState(() {}); // ✅ important
    } catch (_) {
    } finally {
      _serverFetchInFlight = false;
    }
  }

  // -----------------------------
  // Link email to current user
  // -----------------------------
  Future<void> _linkEmailPasswordToCurrentUser({
    required AppLocalizations l10n,
    required String email,
    required String password,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: l10n.authError);
    }

    final normalizedEmail = email.trim().toLowerCase();
    final credential = EmailAuthProvider.credential(
      email: normalizedEmail,
      password: password.trim(),
    );

    await user.linkWithCredential(credential);

    // Best-effort: send verification email
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

  // -----------------------------
  // Link phone to current user
  // -----------------------------
  // -----------------------------
// Link phone to current user
// -----------------------------
  Future<void> _linkPhoneCredentialToCurrentUser({
    required AppLocalizations l10n,
    required PhoneAuthCredential cred,
    required String e164,

    // ✅ NEW (store in Firestore so profile/setup is consistent)
    required String phoneCountryIso2,
    required String phoneCountryDialCode,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: l10n.authError);
    }

    await user.linkWithCredential(cred);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'phoneNumber': e164,
        'phoneCountryIso2': phoneCountryIso2,
        'phoneCountryDialCode': phoneCountryDialCode,
        'isActive': true, // ✅ phone users are active immediately
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

    // ✅ NEW (store in Firestore so profile/setup is consistent)
    required String phoneCountryIso2,
    required String phoneCountryDialCode,
  }) async {
    await cr.confirm(smsCode);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: l10n.authError);
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

// -----------------------------
// Decide whether to prompt
// -----------------------------
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

    // 1) Phone login -> missing email => prompt link email
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

    // 2) Email login -> missing phone => prompt link phone
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

          // ✅ UPDATED signature: (cred, e164, countryIso2, dialCode)
          onLinkWithCredential: (cred, e164, countryIso2, dialCode) async {
            await _linkPhoneCredentialToCurrentUser(
              l10n: l10n,
              cred: cred,
              e164: e164,
              phoneCountryIso2: countryIso2,
              phoneCountryDialCode: dialCode,
            );
          },

          // ✅ UPDATED signature: (smsCode, cr, e164, countryIso2, dialCode)
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
          _webRecaptchaVerifier != null && _webRecaptchaRendered && !_webRecaptchaExpired,
          webRecaptchaHint: () => _webRecaptchaHint(l10n),
        );
      } finally {
        _linkSheetOpen = false;
      }
    }
  }

  // ✅ Reset prompt flags per user session
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

  // -----------------------------
  // Safe ensure user doc exists
  // -----------------------------
  Future<void> _bestEffortEnsureUserDocExists(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      // ✅ IMPORTANT: check SERVER first so we don't "recreate" due to cache cold-start
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref.get(const GetOptions(source: Source.server));
      } catch (_) {
        snap = await ref.get(); // fallback: serverAndCache
      }

      final shouldBeActive = _authSaysActive(user);

      // If doc missing -> create minimal doc
      if (!snap.exists) {
        final data = <String, dynamic>{
          'email': user.email ?? '',
          'phoneNumber': user.phoneNumber ?? '',
          if (shouldBeActive) 'isActive': true,
          if (user.emailVerified) 'emailVerified': true,
          if (user.emailVerified) 'emailVerifiedAt': FieldValue.serverTimestamp(),
          'isOnline': false,
          'hasAcceptedTerms': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
        };

        await ref.set(data, SetOptions(merge: true));
        return;
      }

      // ✅ Doc exists -> PATCH legacy users safely (only set TRUE fields)
      final data = snap.data() ?? <String, dynamic>{};
      final fsIsActive = (data['isActive'] == true);

      final patch = <String, dynamic>{
        // keep these fresh if missing
        if ((data['email'] ?? '').toString().trim().isEmpty && (user.email ?? '').trim().isNotEmpty)
          'email': user.email!.trim().toLowerCase(),
        if ((data['phoneNumber'] ?? '').toString().trim().isEmpty && (user.phoneNumber ?? '').trim().isNotEmpty)
          'phoneNumber': (user.phoneNumber ?? '').trim(),

        // legacy: if auth says active, ensure Firestore isActive true
        if (shouldBeActive && !fsIsActive) 'isActive': true,

        // legacy: sync emailVerified flag into Firestore
        if (user.emailVerified && data['emailVerified'] != true) 'emailVerified': true,
        if (user.emailVerified && data['emailVerifiedAt'] == null) 'emailVerifiedAt': FieldValue.serverTimestamp(),

        // ensure timestamps exist
        if (data['createdAt'] == null) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (patch.isNotEmpty) {
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

    // For web email verification refresh
    try {
      await user.getIdToken(true);
    } catch (_) {}

    try {
      await FirebaseAuth.instance.currentUser?.reload();
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnap.data;
        if (user == null) return const AuthScreen();

        _resetPromptSessionIfUserChanged(user.uid); // ✅ move here

        // ✅ memoize per user
        if (_lastUid != user.uid || _initFuture == null) {
          _lastUid = user.uid;
          _initFuture = _prepareUser(user);
        }

        return FutureBuilder<void>(
          future: _initFuture,
          builder: (context, prepSnap) {
            if (prepSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: docRef.snapshots(includeMetadataChanges: true),
              builder: (context, docSnap) {
                if (!docSnap.hasData) {
                  return Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 44, height: 44, child: CircularProgressIndicator()),
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
                final isFromCache = doc.metadata.isFromCache;

                // ✅ Force at least one server fetch after login to avoid stale cache gating
                if (isFromCache && _serverFetchedUid != user.uid) {
                  unawaited(_ensureServerDocOnce(user.uid));

                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final data = doc.data() ?? <String, dynamic>{};
                final fsActive = (data['isActive'] == true);

                // ✅ Allow phone-auth users immediately even if legacy Firestore not updated yet.
                // Email users still require Firestore activation (or verification flow).
                final hasPhoneAuth = (user.phoneNumber ?? '').trim().isNotEmpty;
                final effectiveActive = fsActive || hasPhoneAuth;

                if (effectiveActive) {
                  final needsNames = _needsNamesFromFirestore(data);
                  if (!needsNames) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      unawaited(_maybePromptLinking(user: user, data: data, l10n: l10n));
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

                      // If they verified email, activate.
                      await _activateIfEmailVerified(refreshed);

                      // Touch doc (forces fresh fetch / UI refresh)
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

                // ✅ Active -> must have required names before Home
                final needsNames = _needsNamesFromFirestore(data);

                // If names missing, force CompleteProfileScreen (no skipping).
                if (needsNames) {
                  return CompleteProfileScreen(uid: user.uid);
                }

                // Only prompt linking after profile names are complete (avoids stacking flows).
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(_maybePromptLinking(user: user, data: data, l10n: l10n));
                });

                // ✅ Active + names OK -> Home
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
                child: const Icon(Icons.lock_clock_rounded, color: Colors.black, size: 34),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.accountNotActive,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => onCheckAgain(),
                icon: const Icon(Icons.refresh_rounded, color: Colors.black),
                label: Text(
                  l10n.checkAgain,
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => onLogout(),
                icon: const Icon(Icons.logout, color: kTextSecondary),
                label: Text(l10n.logout, style: const TextStyle(color: kTextSecondary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.18)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}