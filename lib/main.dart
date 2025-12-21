// MW Chat – Modern private messaging app
// Copyright © 2025 Mousa Abu Hilal.
// lib/main.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/home_screen.dart';
import 'theme/app_theme.dart';
import 'utils/presence_service.dart';
import 'l10n/app_localizations.dart';
import 'utils/locale_provider.dart';
import 'utils/current_chat_tracker.dart';

/// GLOBAL SNACKBAR KEY (FOR FOREGROUND NOTIFICATIONS)
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
GlobalKey<ScaffoldMessengerState>();

/// Global instance of CurrentChatTracker used both by Provider and FCM logic.
final CurrentChatTracker currentChatTracker = CurrentChatTracker.instance;

/// REQUIRED for background notifications (mobile only)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  debugPrint('🔔 BACKGROUND MESSAGE: ${message.messageId}');
  debugPrint('🔔 DATA: ${message.data}');
}

/// ------------------------------
/// FCM Token Sync (deduped)
/// ------------------------------
/// We store token only when it changes, and never from widget build() to avoid spam.
String? _lastStoredFcmToken;
String? _lastStoredUid;

StreamSubscription<User?>? _authTokenSyncSub;
StreamSubscription<String>? _tokenRefreshSub;

Future<void> _storeTokenForUserIfChanged({
  required String uid,
  required String token,
}) async {
  if (token.isEmpty) return;

  // ✅ Dedup within process lifetime (prevents spam logs + extra writes)
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
  if (kIsWeb) return;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;

    await _storeTokenForUserIfChanged(uid: user.uid, token: token);
  } on FirebaseException catch (e) {
    if (e.code == 'apns-token-not-set') {
      debugPrint(
        '⏳ APNs token not ready yet, will rely on onTokenRefresh.',
      );
    } else {
      debugPrint('⚠️ FCM getToken failed: ${e.code} ${e.message}');
    }
  } catch (e) {
    debugPrint('⚠️ FCM getToken failed: $e');
  }
}

/// Listen for auth changes: when user logs in, we sync token once.
/// This prevents calling token sync from build() and spamming.
void _setupAuthDrivenTokenSync() {
  if (kIsWeb) return;

  _authTokenSyncSub?.cancel();
  _authTokenSyncSub = FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null) return;
    // Fire-and-forget; safe and deduped.
    unawaited(_syncCurrentTokenIfPossible());
  });
}

Future<void> _configureFirestore() async {
  if (kIsWeb) {
    // Prevent Firestore web IndexedDB from getting corrupted during dev/rules changes
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _configureFirestore();

  // Register background handler (NOT on web)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // App Check (NOT on web)
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

  // Initialize Push Notifications (NOT on web)
  if (!kIsWeb) {
    await _initPushNotifications();
    _setupAuthDrivenTokenSync();
  }

  // Presence tracking (safe for web)
  PresenceService.instance.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
        ),
        ChangeNotifierProvider<CurrentChatTracker>.value(
          value: currentChatTracker,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

/// FULL SAFE FCM INITIALIZATION (MOBILE ONLY)
Future<void> _initPushNotifications() async {
  if (kIsWeb) {
    debugPrint('🌐 Web build → skipping _initPushNotifications');
    return;
  }

  final messaging = FirebaseMessaging.instance;

  // Auto Init
  await messaging.setAutoInitEnabled(true);

  // Permission
  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  debugPrint('🔔 Notification permission: ${settings.authorizationStatus}');

  // Do NOT show OS notification UI in foreground (we show our own banner)
  await messaging.setForegroundNotificationPresentationOptions(
    alert: false,
    badge: false,
    sound: false,
  );

  // Token Refresh (subscribe once)
  await _tokenRefreshSub?.cancel();
  _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) async {
      debugPrint('🔁 TOKEN REFRESHED');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await _storeTokenForUserIfChanged(uid: user.uid, token: newToken);
    },
  );

  // Try to get initial token (deduped)
  await _syncCurrentTokenIfPossible();

  // ✅ FOREGROUND MESSAGE → conditional SnackBar
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final activeRoomId = currentChatTracker.activeRoomId;
    final roomIdFromPush = message.data['roomId'];

    debugPrint(
      '🔔 FOREGROUND MESSAGE | activeRoom=$activeRoomId, pushRoom=$roomIdFromPush',
    );

    // If push is for the chat the user is currently viewing → suppress UI
    if (roomIdFromPush != null &&
        roomIdFromPush.isNotEmpty &&
        roomIdFromPush == activeRoomId) {
      debugPrint('ℹ️ User is already in this chat room → no banner shown.');
      return;
    }

    final title = message.notification?.title?.trim();
    final safeTitle = (title == null || title.isEmpty) ? 'MW Chat' : title;

    rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_active_rounded, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                safeTitle,
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
  });

  // BACKGROUND → APP OPENED
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('🔔 OPENED FROM NOTIFICATION');
    // Optional: navigate to message.data['roomId']
  });

  // TERMINATED LAUNCH
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    debugPrint('🔔 APP OPENED FROM TERMINATED PUSH');
    // Optional: navigate based on initial.data['roomId']
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final locale = localeProvider.locale;
    final bool isArabic = locale.languageCode == 'ar';

    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(isArabic: isArabic),
      locale: localeProvider.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (ctx) =>
      AppLocalizations.of(ctx)?.mainTitle ?? 'MW Chat',
      home: const AuthGate(),
    );
  }
}

/// AUTH GATE — prevents "not active" flash for active users
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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

        // Confirm activation from SERVER once
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

            // If server fetch fails (offline), fall back to stream behavior safely.
            if (serverSnap.hasError) {
              return _UserDocStreamGate(userId: user.uid);
            }

            final serverDoc = serverSnap.data;
            if (serverDoc == null || !serverDoc.exists) {
              return Scaffold(
                body: Center(child: Text(l10n.settingUpProfile)),
              );
            }

            final serverData = serverDoc.data() ?? {};
            final serverIsActive = serverData['isActive'] == true;

            // If server says ACTIVE → go directly Home (no inactive flash)
            if (serverIsActive) {
              return const HomeScreen();
            }

            // If server says NOT active → keep listening for activation
            return _UserDocStreamGate(userId: user.uid);
          },
        );
      },
    );
  }
}

/// After initial server confirmation, listen for live changes (auto-updates when admin activates).
class _UserDocStreamGate extends StatelessWidget {
  final String userId;
  const _UserDocStreamGate({required this.userId});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      // ✅ Less noise than includeMetadataChanges:true
      stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData || !userSnap.data!.exists) {
          return Scaffold(
            body: Center(child: Text(l10n.settingUpProfile)),
          );
        }

        final snap = userSnap.data!;
        final data = snap.data() ?? {};
        final isActive = data['isActive'] == true;

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

/// Modern inactive UI (no infinite spinner) + manual check + logout
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
