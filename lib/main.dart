// lib/main.dart
// MW Chat – Modern private messaging app
// Copyright © 2025 Mousa Abu Hilal.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:mw/widgets/ui/mw_swipe_back.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/home_screen.dart';
import 'theme/app_theme.dart';
import 'theme/mw_text_theme.dart';
import 'utils/current_chat_tracker.dart';
import 'utils/locale_provider.dart';
import 'utils/presence_service.dart';
import 'utils/typography_provider.dart';

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
      return await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') {
        return Firebase.app();
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
    if (kIsWeb) {
      // ✅ If you configure Web Push (VAPID), you can pass it here.
      // If not configured, getToken() may throw; we just skip safely.
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _storeTokenForUserIfChanged(uid: user.uid, token: token);
      return;
    }

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

void _setupAuthDrivenTokenSync() {
  _authTokenSyncSub?.cancel();
  _authTokenSyncSub = FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null) return;
    unawaited(_syncCurrentTokenIfPossible());
  });
}

/// ✅ Fix for Web “refresh needed”
/// Ensure token is ready BEFORE we run Firestore-heavy screens/queries.
Future<void> _ensureIdTokenReady(User user) async {
  try {
    // Web benefits from forcing a token refresh once after login.
    await user.getIdToken(true);
  } catch (e) {
    debugPrint('⚠️ getIdToken(true) failed: $e');
    // Still continue; we’ll rely on idTokenChanges + Firestore retry paths.
  }
}

/// ------------------------------
/// Foreground notification helpers
/// ------------------------------

String _asString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString().trim();
}

/// Try hard to extract roomId from common backend payload keys.
String _extractRoomId(RemoteMessage message) {
  final data = message.data;

  // Common key variants (add more if your backend differs)
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

String _extractSenderName(RemoteMessage message) {
  final data = message.data;
  const keys = <String>[
    'senderName',
    'sender_name',
    'fromName',
    'from_name',
    'name',
  ];
  for (final k in keys) {
    final val = _asString(data[k]);
    if (val.isNotEmpty) return val;
  }
  // fallback to notification title
  final title = (message.notification?.title ?? '').trim();
  return title.isNotEmpty ? title : 'MW Chat';
}

bool _isChatMessage(RemoteMessage message) {
  // If your backend sets a type, use it. Otherwise treat any payload with roomId/senderId as chat-ish.
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _ensureFirebaseInitialized();

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // AppCheck:
  // - Web: depends on your setup; keep your current behavior (skip).
  // - Mobile: keep.
  if (!kIsWeb) {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      );
    } catch (e) {
      debugPrint('⚠️ App Check init skipped: $e');
    }
  }

  // ✅ Init push on all platforms, but web stays safe (won’t crash if not configured)
  await _initPushNotifications();
  _setupAuthDrivenTokenSync();

  PresenceService.instance.init();

  runApp(
    MultiProvider(
      providers: [
        // ✅ TypographyProvider first (needed by LocaleProvider)
        ChangeNotifierProvider<TypographyProvider>(
          create: (_) {
            final p = TypographyProvider();
            p.start(); // IMPORTANT
            return p;
          },
        ),

        // ✅ LocaleProvider gets TypographyProvider injected
        ChangeNotifierProvider<LocaleProvider>(
          create: (ctx) => LocaleProvider(
            typographyProvider: ctx.read<TypographyProvider>(),
          ),
        ),

        ChangeNotifierProvider<CurrentChatTracker>.value(
          value: currentChatTracker,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

/// FULL SAFE FCM INITIALIZATION (ALL PLATFORMS)
Future<void> _initPushNotifications() async {
  final messaging = FirebaseMessaging.instance;

  try {
    await messaging.setAutoInitEnabled(true);
  } catch (e) {
    debugPrint('⚠️ setAutoInitEnabled failed/skipped: $e');
  }

  // Permissions (no-op on many web setups, safe)
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

  // iOS: ensure foreground system alerts are off (you show your own banner)
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
  _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) async {
      debugPrint('🔁 TOKEN REFRESHED');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await _storeTokenForUserIfChanged(uid: user.uid, token: newToken);
    },
  );

  // Initial token sync (safe on web; if not configured it will just fail gracefully)
  await _syncCurrentTokenIfPossible();

  // ✅ Prevent duplicate listeners
  await _foregroundMsgSub?.cancel();
  await _onOpenSub?.cancel();

  // ✅ Foreground messages (in-app banner)
  _foregroundMsgSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final String pushRoomId = _extractRoomId(message);
    final String pushSenderId = _extractSenderId(message);
    final String pushSenderName = _extractSenderName(message);

    final String activeRoomId = (currentChatTracker.activeRoomId ?? '').trim();

    debugPrint(
      '🔔 FOREGROUND | inChat=${currentChatTracker.isInChat} '
          'activeRoom=$activeRoomId pushRoom=$pushRoomId sender=$pushSenderId',
    );

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // ❌ Never show banner for own messages
    if (currentUid.isNotEmpty &&
        pushSenderId.isNotEmpty &&
        pushSenderId == currentUid) {
      debugPrint('🔕 Self message suppressed.');
      return;
    }

    // ❌ HARD RULE: if user is inside ANY chat, suppress all chat banners
    if (currentChatTracker.isInChat && _isChatMessage(message)) {
      debugPrint('🔕 In chat screen → suppress foreground banner.');
      return;
    }

    // System / non-chat pushes are allowed
    if (!_isChatMessage(message)) {
      _showForegroundBanner(title: pushSenderName);
      return;
    }

    // Default case: user is not in chat, show banner
    _showForegroundBanner(title: pushSenderName);
  });

  _onOpenSub =
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 OPENED FROM NOTIFICATION');
      });

  // Terminated state open (mobile + web when supported)
  try {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      debugPrint('🔔 APP OPENED FROM TERMINATED PUSH');
    }
  } catch (e) {
    debugPrint('⚠️ getInitialMessage skipped: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final locale = localeProvider.locale;
    final bool isArabic = locale.languageCode == 'ar';

    // ✅ Global typography (scale + family)
    final typo = context.watch<TypographyProvider>();

    final String rawFamily = (typo.fontFamily ?? '').trim();
    final String? selected = rawFamily.isNotEmpty ? rawFamily : null;

    final String resolvedFamily = resolveMwFontFamily(
      isArabic: isArabic,
      override: selected,
    );

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        isArabic: isArabic,
        fontScale: 1.0, // keep 1.0; MediaQuery handles scaling
        fontFamily: resolvedFamily,
      ),
      locale: localeProvider.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx)?.mainTitle ?? 'MW Chat',
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();

        final mq = MediaQuery.of(context);
        final scaledChild = MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(typo.fontScale),
          ),
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
  }
}

/// AUTH GATE — web-safe and token-safe
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  bool _coerceIsActive(Map<String, dynamic> data) {
    final v = data['isActive'];
    if (v is bool) return v;
    // Backward compatible: if missing, treat as active
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // ✅ IMPORTANT:
    // idTokenChanges() is safer for Web because it only emits when a usable token exists.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.idTokenChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;
        if (user == null) return const AuthScreen();

        // ✅ Ensure token is actually ready before heavy Firestore screens run.
        return FutureBuilder<void>(
          future: _ensureIdTokenReady(user),
          builder: (context, tokenSnap) {
            if (tokenSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get(const GetOptions(source: Source.server)),
              builder: (context, serverSnap) {
                if (serverSnap.connectionState == ConnectionState.waiting) {
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

                if (serverSnap.hasError) {
                  return _UserDocStreamGate(userId: user.uid);
                }

                final doc = serverSnap.data;
                if (doc == null || !doc.exists) {
                  return _UserDocStreamGate(userId: user.uid);
                }

                final data = doc.data() ?? {};
                final isActive = _coerceIsActive(data);

                if (isActive) return const HomeScreen();
                return _UserDocStreamGate(userId: user.uid);
              },
            );
          },
        );
      },
    );
  }
}

class _UserDocStreamGate extends StatelessWidget {
  final String userId;
  const _UserDocStreamGate({required this.userId});

  bool _coerceIsActive(Map<String, dynamic> data) {
    final v = data['isActive'];
    if (v is bool) return v;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return Scaffold(
            body: Center(child: Text(l10n.settingUpProfile)),
          );
        }

        final data = snap.data!.data() ?? {};
        final isActive = _coerceIsActive(data);

        if (!isActive) {
          return _PendingActivationScreen(
            userId: userId,
            onCheckAgain: () async {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .get(const GetOptions(source: Source.server));
            },
            onLogout: () async {
              await FirebaseAuth.instance.signOut();
            },
          );
        }

        return const HomeScreen();
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
                  side: BorderSide(color: Colors.white.withOpacity(0.18)),
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
