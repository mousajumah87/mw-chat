// lib/utils/typography_provider.dart
//
// MW Chat – Typography Provider (Font + Scale)
//
// ✅ Web/iOS/Android safe updates in this version:
// - Uses idTokenChanges() (Web token-ready stream)
// - Creates user doc once when missing (no snapshot-loop writes)
// - Debounced + serialized Firestore writes (prevents churn)
// - Fixes broken _persistInFlight logic
// - Keeps in-memory invariants: fontFamily is never empty

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class TypographyProvider extends ChangeNotifier {
  // Firestore keys (keep stable)
  static const String kFieldFontScale = 'uiFontScale';
  static const String kFieldFontFamily = 'uiFontFamily';
  static const String kFieldUserPickedFont = 'uiFontUserPicked';

  // Reasonable limits
  static const double minScale = 0.85;
  static const double maxScale = 1.40;

  static const String kDefaultLatin = 'Poppins';
  static const String kDefaultArabic = 'Noto Sans Arabic';

  double _fontScale = 1.0;

  /// Keep non-empty in memory to avoid edge cases.
  String _fontFamily = kDefaultLatin;

  /// If true, locale changes should NOT auto-swap the font.
  bool _userPickedFont = false;

  /// Latest locale from app.
  Locale _locale = const Locale('en');

  double get fontScale => _fontScale;
  String get fontFamily => _fontFamily;
  bool get userPickedFont => _userPickedFont;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  bool _started = false;
  bool _disposed = false;

  // --- write control
  Timer? _persistDebounce;
  Future<void> _writeChain = Future<void>.value(); // serialize writes
  bool _ensuredUserDoc = false; // ensure doc exists once per login

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Call once (e.g. from main.dart provider creation).
  ///
  /// IMPORTANT:
  /// - Call setLocale() at least once at app startup (or on locale changes)
  ///   so defaults are correct for AR/EN.
  void start() {
    if (_started) return;
    _started = true;

    // ✅ Web-safe: token-ready stream
    _authSub = FirebaseAuth.instance.idTokenChanges().listen(
          (user) async {
        _userDocSub?.cancel();
        _userDocSub = null;
        _ensuredUserDoc = false;

        if (user == null) {
          // Signed out => deterministic defaults locally, no persistence.
          _applyLocal(
            scale: 1.0,
            family: _defaultFamilyForLocale(_locale),
            userPicked: false,
            notify: true,
          );
          return;
        }

        // ✅ Ensure user doc exists ONCE (avoid doing it inside snapshot callback)
        await _ensureUserDocExists(user.uid);

        final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

        _userDocSub = ref.snapshots().listen(
              (doc) {
            if (!doc.exists) {
              // If still missing for any reason, keep local defaults but don't loop-write.
              _applyLocal(
                scale: 1.0,
                family: _defaultFamilyForLocale(_locale),
                userPicked: false,
                notify: true,
              );
              return;
            }

            final data = doc.data() ?? {};

            final rawScale = data[kFieldFontScale];
            final rawFamily = data[kFieldFontFamily];
            final rawPicked = data[kFieldUserPickedFont];

            final nextScale = _clampScale(_toDouble(rawScale) ?? 1.0);

            final parsedFamily =
            (rawFamily is String && rawFamily.trim().isNotEmpty)
                ? rawFamily.trim()
                : null;

            // Backward compatible:
            // - no flag => treat as picked if family existed
            final nextPicked =
            (rawPicked is bool) ? rawPicked : (parsedFamily != null);

            // Deterministic default if missing family
            final effectiveFamily = parsedFamily ?? _defaultFamilyForLocale(_locale);

            final changed = nextScale != _fontScale ||
                effectiveFamily != _fontFamily ||
                nextPicked != _userPickedFont;

            if (!changed) return;

            _fontScale = nextScale;
            _fontFamily = effectiveFamily;
            _userPickedFont = nextPicked;

            if (!_disposed) notifyListeners();
          },
          onError: (e, st) {
            debugPrint('TypographyProvider user doc stream error: $e');
            debugPrint('$st');

            // Keep app usable with current local values.
            _applyLocal(
              scale: _fontScale,
              family: _fontFamily,
              userPicked: _userPickedFont,
              notify: true,
            );
          },
        );
      },
      onError: (e, st) {
        debugPrint('TypographyProvider auth stream error: $e');
        debugPrint('$st');

        _applyLocal(
          scale: 1.0,
          family: _defaultFamilyForLocale(_locale),
          userPicked: false,
          notify: true,
        );
      },
    );
  }

  /// Tell the provider what the current app locale is.
  ///
  /// Behavior:
  /// - If user DID NOT pick a font => auto-apply locale default (and persist if logged in).
  /// - If user DID pick a font => keep their choice.
  Future<void> setLocale(Locale locale) async {
    _locale = locale;

    if (_userPickedFont) return;

    final desired = _defaultFamilyForLocale(_locale);
    if (_fontFamily == desired) return;

    _fontFamily = desired;
    if (!_disposed) notifyListeners();

    if (FirebaseAuth.instance.currentUser != null) {
      _schedulePersist();
    }
  }

  /// Update scale and persist to Firestore (if logged in).
  Future<void> setFontScale(double value) async {
    final next = _clampScale(value);
    if (next == _fontScale) return;

    _fontScale = next;
    if (!_disposed) notifyListeners();
    _schedulePersist();
  }

  /// Update family and persist to Firestore (if logged in).
  Future<void> setFontFamily(String? family) async {
    final next =
    (family != null && family.trim().isNotEmpty) ? family.trim() : null;

    // If caller passes null/empty, revert to default and mark as not user-picked.
    if (next == null) {
      final desired = _defaultFamilyForLocale(_locale);
      final changed = (_fontFamily != desired) || _userPickedFont != false;
      if (!changed) return;

      _fontFamily = desired;
      _userPickedFont = false;
      if (!_disposed) notifyListeners();
      _schedulePersist();
      return;
    }

    final changed = next != _fontFamily || _userPickedFont != true;
    if (!changed) return;

    _fontFamily = next;
    _userPickedFont = true;
    if (!_disposed) notifyListeners();
    _schedulePersist();
  }

  /// Reset to defaults:
  Future<void> reset() async {
    _fontScale = 1.0;
    _fontFamily = _defaultFamilyForLocale(_locale);
    _userPickedFont = false;
    if (!_disposed) notifyListeners();
    _schedulePersist();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  String _defaultFamilyForLocale(Locale locale) {
    return locale.languageCode.toLowerCase() == 'ar' ? kDefaultArabic : kDefaultLatin;
  }

  Future<void> _ensureUserDocExists(String uid) async {
    if (_disposed) return;
    if (_ensuredUserDoc) return;

    _ensuredUserDoc = true;

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get(const GetOptions(source: Source.server));

      if (snap.exists) return;

      // Create minimal doc fields needed for typography (merge-safe)
      await ref.set(
        {
          kFieldFontScale: _fontScale,
          kFieldFontFamily: _fontFamily.trim().isEmpty
              ? _defaultFamilyForLocale(_locale)
              : _fontFamily.trim(),
          kFieldUserPickedFont: _userPickedFont,
          'uiUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('TypographyProvider ensureUserDocExists error: $e');
      debugPrint('$st');
    }
  }

  void _schedulePersist() {
    if (_disposed) return;

    // Avoid persisting while signed out
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Debounce small bursts (e.g., multiple settings changes quickly)
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      _writeChain = _writeChain.then((_) => _persistNow());
    });
  }

  Future<void> _persistNow() async {
    if (_disposed) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final family = _fontFamily.trim().isNotEmpty
        ? _fontFamily.trim()
        : _defaultFamilyForLocale(_locale);

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

      await ref.set(
        {
          kFieldFontScale: _fontScale,
          kFieldFontFamily: family,
          kFieldUserPickedFont: _userPickedFont,
          'uiUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('TypographyProvider persist error: $e');
      debugPrint('$st');
    }
  }

  void _applyLocal({
    required double scale,
    required String? family,
    required bool userPicked,
    required bool notify,
  }) {
    _fontScale = _clampScale(scale);

    final fam = (family ?? '').trim();
    _fontFamily = fam.isNotEmpty ? fam : _defaultFamilyForLocale(_locale);

    _userPickedFont = userPicked;

    // If we had to force default, the user didn't pick.
    if (fam.isEmpty) _userPickedFont = false;

    if (notify && !_disposed) notifyListeners();
  }

  double _clampScale(double v) => v.clamp(minScale, maxScale);

  double? _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _persistDebounce?.cancel();
    _userDocSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
