// MW Chat – Modern private messaging app
// Copyright © 2025 Mousa Abu Hilal. All rights reserved.
// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'theme/app_theme.dart';
import 'utils/presence_service.dart';
import 'l10n/app_localizations.dart';
import 'utils/locale_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.debug,
      // Later you can switch to:
      // appleProvider: AppleProvider.appAttest,
      // webProvider: ReCaptchaV3Provider('your-site-key'),
    );
  }

  // Start presence tracking once Firebase is ready.
  PresenceService.instance.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to locale changes from your provider
    final localeProvider = context.watch<LocaleProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),

      // Use the locale from your provider
      locale: localeProvider.locale,

      // Localization setup
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,

      // Safely get the localized app title AFTER MaterialApp creates
      // a proper localization context.
      onGenerateTitle: (ctx) =>
      AppLocalizations.of(ctx)?.mainTitle ?? 'MW Chat',

      // Decide which screen to show based on auth + profile state
      home: const AuthGate(),
    );
  }
}

/// Redirects user depending on login state + profile completeness + activation.
/// Terms of Use acceptance is enforced inside HomeScreen via a full-screen
/// TermsOfUseScreen shown after login, before the user can use chats.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  /// Profile is considered complete with ONLY:
  /// - firstName
  /// - lastName
  ///
  /// Birthday and gender are BOTH optional and are **not required**
  /// for the app to function, to comply with App Store guideline 5.1.1.
  bool _isProfileComplete(Map<String, dynamic>? data) {
    if (data == null) return false;

    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();

    final hasFirstName = firstName.isNotEmpty;
    final hasLastName = lastName.isNotEmpty;

    return hasFirstName && hasLastName;
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
        if (user == null) {
          // Not logged in → go to auth screen
          return const AuthScreen();
        }

        // Logged in → watch user doc (profile + isActive)
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!userSnap.hasData || !userSnap.data!.exists) {
              // User doc not yet created (small window after registration)
              return Scaffold(
                body: Center(
                  child: Text(l10n.settingUpProfile),
                ),
              );
            }

            final data = userSnap.data!.data() ?? {};

            // 1) If profile is missing REQUIRED fields (name only) → ProfileScreen
            // if (!_isProfileComplete(data)) {
            //   // User can fill first/last name here.
            //   // Birthday and gender are OPTIONAL and not required.
            //   return const ProfileScreen();
            // }

            // 2) Profile is complete; check activation flag
            final isActive = data['isActive'] == true;
            if (!isActive) {
              // Account created but not activated yet
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.accountNotActive,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.waitForActivation,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await FirebaseAuth.instance.signOut();
                          },
                          icon: const Icon(Icons.logout),
                          label: Text(l10n.logout),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // 3) Active + profile complete → go to main user list
            return const HomeScreen();
          },
        );
      },
    );
  }
}
