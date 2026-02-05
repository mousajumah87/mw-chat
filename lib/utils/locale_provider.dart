// lib/utils/locale_provider.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'typography_provider.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider({
    TypographyProvider? typographyProvider,
  }) : _typographyProvider = typographyProvider;

  final TypographyProvider? _typographyProvider;

  static const List<String> _supported = <String>['en', 'ar'];

  // ✅ Global (logged out) preference for login screen
  static const String _kPrefGlobalLocaleCode = 'mw_ui_locale_code_global';

  // ✅ Per-user (logged in) preference (fallback if Firestore blocked)
  static String _kPrefUserLocaleCode(String uid) => 'mw_ui_locale_code_uid_$uid';

  // ✅ Firestore fields
  static const bool kSyncLocaleToFirestore = true;
  static const String _kUserFieldLocale = 'uiLocale';
  static const String _kUserFieldLocaleUpdatedAt = 'uiLocaleUpdatedAt';

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  bool _loadedGlobal = false;
  bool get isLoaded => _loadedGlobal;

  String? _activeUid;

  StreamSubscription<User?>? _authSub;
  bool _starting = false;

  /// Call once (in main.dart Provider create): loads global + starts auth listener.
  Future<void> start() async {
    if (_starting) return;
    _starting = true;

    // 1) Load global (login screen)
    await _loadGlobalIfNeeded();

    // 2) Listen auth changes and apply user locale when logged in
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      // Fire-and-forget, provider will update locale + notifyListeners
      unawaited(_onAuthChanged(user));
    });

    // 3) Apply immediately for current user (if already logged in)
    unawaited(_onAuthChanged(FirebaseAuth.instance.currentUser));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Called by your language switch.
  /// - Always saves global
  /// - If logged in: also saves per-user and best-effort Firestore
  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode.toLowerCase().trim();
    if (!_supported.contains(code)) return;
    if (_locale.languageCode.toLowerCase() == code) return;

    // Apply immediately for UI responsiveness
    _locale = Locale(code);
    notifyListeners();

    // ✅ Always store global so login screen matches device last selection
    await _writePrefs(_kPrefGlobalLocaleCode, code);

    // ✅ Store per-user if available
    final uid = _activeUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await _writePrefs(_kPrefUserLocaleCode(uid), code);
    }

    // ✅ Typography best-effort
    try {
      await _typographyProvider?.setLocale(_locale);
    } catch (_) {}

    // ✅ Best-effort Firestore
    unawaited(_tryPersistToFirestore(uid: uid, code: code));
  }

  // ----------------------------
  // Internal flow
  // ----------------------------

  Future<void> _loadGlobalIfNeeded() async {
    if (_loadedGlobal) return;

    final code = await _readPrefs(_kPrefGlobalLocaleCode);
    _applyIfValid(code);

    _loadedGlobal = true;
    notifyListeners();

    // Typography alignment best-effort
    try {
      await _typographyProvider?.setLocale(_locale);
    } catch (_) {}
  }

  Future<void> _onAuthChanged(User? user) async {
    // Ensure global is ready (login screen)
    await _loadGlobalIfNeeded();

    if (user == null) {
      _activeUid = null;

      // Stay on global locale when logged out
      final code = await _readPrefs(_kPrefGlobalLocaleCode);
      _applyIfValid(code);
      notifyListeners();
      return;
    }

    final uid = user.uid;
    _activeUid = uid;

    // 1) Firestore (authoritative) if allowed
    final fsCode = await _tryReadLocaleFromFirestore(uid);
    if (_applyIfValid(fsCode)) {
      final applied = _locale.languageCode.toLowerCase();

      // cache locally for reliability
      await _writePrefs(_kPrefUserLocaleCode(uid), applied);
      await _writePrefs(_kPrefGlobalLocaleCode, applied);

      notifyListeners();
      return;
    }

    // 2) Per-user prefs
    final userCode = await _readPrefs(_kPrefUserLocaleCode(uid));
    if (_applyIfValid(userCode)) {
      notifyListeners();
      // best-effort: keep Firestore in sync when possible
      unawaited(_tryPersistToFirestore(uid: uid, code: _locale.languageCode));
      return;
    }

    // 3) Global prefs
    final globalCode = await _readPrefs(_kPrefGlobalLocaleCode);
    _applyIfValid(globalCode);
    notifyListeners();

    // optional: best-effort persist the chosen fallback for this user
    unawaited(_tryPersistToFirestore(uid: uid, code: _locale.languageCode));
  }

  bool _applyIfValid(String? code) {
    final c = (code ?? '').toLowerCase().trim();
    if (!_supported.contains(c)) return false;

    if (_locale.languageCode.toLowerCase() != c) {
      _locale = Locale(c);
      unawaited(_typographyProvider?.setLocale(_locale));
    }
    return true;
  }

  Future<String?> _readPrefs(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePrefs(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<String?> _tryReadLocaleFromFirestore(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));

      final data = doc.data();
      final v = data?[_kUserFieldLocale];
      return v is String ? v : null;
    } on FirebaseException catch (e) {
      debugPrint('LocaleProvider FS read blocked: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('LocaleProvider FS read blocked: $e');
      return null;
    }
  }

  Future<void> _tryPersistToFirestore({
    required String? uid,
    required String code,
  }) async {
    if (!kSyncLocaleToFirestore) return;

    final u = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (u == null || u.isEmpty) return;

    final c = code.toLowerCase().trim();
    if (!_supported.contains(c)) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(u).set(
        {
          _kUserFieldLocale: c,
          _kUserFieldLocaleUpdatedAt: FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      debugPrint('LocaleProvider FS write blocked: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('LocaleProvider FS write blocked: $e');
    }
  }
}
