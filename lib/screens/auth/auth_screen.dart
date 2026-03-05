// lib/screens/auth/auth_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/identifier_availability.dart';
import '../../utils/web/recaptcha_container.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_language_button.dart';
import '../legal/terms_of_use_screen.dart';
import 'utils/phone_format.dart' as pf;
import 'widgets/auth_header.dart';
import 'widgets/auth_register_section.dart';
import 'widgets/sheets/link_email_sheet.dart';
import 'widgets/sheets/link_phone_sheet.dart';

enum _IdentifierMode { phone, email }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();

  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  bool _isLogin = true;
  bool _submitting = false;
  bool _agreedToTerms = false;
  String? _errorText;

  Country? _selectedCountry;
  String _dialIso2 = 'US';
  String _dialCode = '+1';

  Country? _defaultCountry;
  String _defaultDialIso2 = 'US';
  String _defaultDialCode = '+1';

  final _smsCtrl = TextEditingController();
  String? _verificationId;
  int? _forceResendToken;
  bool _codeSent = false;

  ConfirmationResult? _webConfirmationResult;

  RecaptchaVerifier? _webRecaptchaVerifier;
  bool _webRecaptchaRendered = false;
  bool _webRecaptchaExpired = false;

  static const String _recaptchaParentId = '__ff-recaptcha-container';
  static const String _recaptchaChildId = '__ff-recaptcha-inner';

  bool _disposed = false;
  bool get _alive => mounted && !_disposed;

  Timer? _otpCooldownTimer;
  int _otpCooldownSeconds = 0;
  bool get _canSendOtp => !_submitting && _otpCooldownSeconds == 0;

  bool _webOtpRequestInFlight = false;
  Completer<void>? _sendOtpCompleter;
  bool _webRecaptchaBusy = false;

  // ✅ Link prompts guards + cooldown
  bool _linkEmailPromptedThisSession = false;
  bool _linkPhonePromptedThisSession = false;
  static const int _reminderCooldownDays = 7;

  String? _pendingFirstName;
  String? _pendingLastName;

  bool _localeApplied = false;

  // WhatsApp-like selector
  _IdentifierMode _registerMode = _IdentifierMode.phone;
  _IdentifierMode _loginMode = _IdentifierMode.phone;

  // Email verify state
  bool _emailVerifyPending = false;
  DateTime? _emailVerifySentAt;
  Timer? _emailVerifyCooldownTimer;
  int _emailVerifyCooldownSeconds = 0;

  bool _emailVerifyPromptedThisSession = false;
  Timer? _emailVerifyPollTimer;
  bool _emailVerifyPolling = false;

  String get _regFirstName => _firstNameCtrl.text.trim();
  String get _regLastName => _lastNameCtrl.text.trim();

  void _safeSetState(VoidCallback fn) {
    if (!_alive) return;
    setState(fn);
  }

  void _setError(String? message) => _safeSetState(() => _errorText = message);

  _IdentifierMode _effectiveMode() => _isLogin ? _loginMode : _registerMode;

  String _formatCooldown(int seconds) {
    if (seconds <= 0) return '';
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool _isRateLimited(FirebaseAuthException e) {
    final msg = (e.message ?? '').toLowerCase();
    return e.code == 'too-many-requests' ||
        msg.contains('unusual activity') ||
        msg.contains('too many requests');
  }

  void _startRateLimitCooldown() => _startOtpCooldown(15 * 60);

  // ---------------------------
  // Locale → default country once
  // ---------------------------
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localeApplied) return;

    final loc = Localizations.localeOf(context);
    final cc = (loc.countryCode ?? 'US').toUpperCase();

    try {
      _defaultCountry = CountryParser.parseCountryCode(cc);
      _defaultDialIso2 = cc;
      _defaultDialCode = '+${_defaultCountry!.phoneCode}';
    } catch (_) {
      _defaultCountry = CountryParser.parseCountryCode('US');
      _defaultDialIso2 = 'US';
      _defaultDialCode = '+${_defaultCountry!.phoneCode}';
    }

    _selectedCountry = _defaultCountry;
    _dialIso2 = _defaultDialIso2;
    _dialCode = _defaultDialCode;

    _localeApplied = true;
  }

  void _resetCountryToDefault() {
    _selectedCountry = _defaultCountry;
    _dialIso2 = _defaultDialIso2;
    _dialCode = _defaultDialCode;
  }

  // ---------------------------
  // Init/Dispose
  // ---------------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_alive && _loginMode == _IdentifierMode.phone) _initWebRecaptcha();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;

    WidgetsBinding.instance.removeObserver(this);

    _otpCooldownTimer?.cancel();
    _emailVerifyCooldownTimer?.cancel();
    _stopEmailVerifyPolling();

    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _smsCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();

    if (kIsWeb) {
      try {
        _webRecaptchaVerifier?.clear();
      } catch (_) {}
    }
    _webRecaptchaVerifier = null;

    super.dispose();
  }


  // ---------------------------
  // Auth refresh helper (important on web)
  // ---------------------------
  Future<User?> _refreshAuthUser([User? input]) async {
    final u = input ?? FirebaseAuth.instance.currentUser;
    if (u == null) return null;

    try {
      await u.reload();
      try {
        await u.getIdToken(true);
      } catch (_) {}
      await FirebaseAuth.instance.currentUser?.reload();
    } catch (_) {}

    return FirebaseAuth.instance.currentUser ?? u;
  }

  // ---------------------------
  // OTP / state resets
  // ---------------------------
  void _resetOtpUi() {
    _otpCooldownTimer?.cancel();
    _otpCooldownSeconds = 0;
    _smsCtrl.clear();
    _webOtpRequestInFlight = false;
    _sendOtpCompleter = null;
  }

  void _resetPhoneState() {
    _verificationId = null;
    _forceResendToken = null;
    _codeSent = false;
    _webConfirmationResult = null;
    _smsCtrl.clear();
  }

  void _resetRegisterState() {
    _agreedToTerms = false;
    _firstNameCtrl.clear();
    _lastNameCtrl.clear();
    _pendingFirstName = null;
    _pendingLastName = null;
    _registerMode = _IdentifierMode.phone;
  }

  void _startOtpCooldown([int seconds = 45]) {
    _otpCooldownTimer?.cancel();
    _safeSetState(() => _otpCooldownSeconds = seconds);

    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_alive) return t.cancel();
      if (_otpCooldownSeconds <= 1) {
        t.cancel();
        _safeSetState(() => _otpCooldownSeconds = 0);
      } else {
        _safeSetState(() => _otpCooldownSeconds--);
      }
    });
  }

  // ---------------------------
  // Terms
  // ---------------------------
  Future<void> _openTerms() async {
    if (!_alive) return;

    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TermsOfUseScreen()),
    );

    if (!_alive) return;
    if (accepted == true) {
      _safeSetState(() {
        _agreedToTerms = true;
        _errorText = null;
      });
    }
  }

  // ---------------------------
  // Pending names cache for phone register
  // ---------------------------
  void _cachePendingNamesIfRegister() {
    if (_isLogin) {
      _pendingFirstName = null;
      _pendingLastName = null;
      return;
    }
    final fn = _regFirstName;
    final ln = _regLastName;
    _pendingFirstName = fn.isEmpty ? null : fn;
    _pendingLastName = ln.isEmpty ? null : ln;
  }

  // ---------------------------
  // Email verify UI + polling (same behavior as your current)
  // ---------------------------
  void _stopEmailVerifyPolling() {
    _emailVerifyPollTimer?.cancel();
    _emailVerifyPollTimer = null;
    _emailVerifyPolling = false;
  }

  void _startEmailVerifyPolling() {
    if (_emailVerifyPolling) return;
    _emailVerifyPolling = true;

    _emailVerifyPollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!_alive) {
        t.cancel();
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final refreshed = await _refreshAuthUser(user) ?? user;
      if (refreshed.emailVerified) {
        _stopEmailVerifyPolling();
        await _activateEmailIfVerifiedSilently(refreshed);
      }
    });
  }

  Future<void> _activateEmailIfVerifiedSilently(User user) async {
    final refreshed = await _refreshAuthUser(user) ?? user;
    if (!refreshed.emailVerified) {
      // keep polling; do NOT touch UI with context-dependent text
      _safeSetState(() => _emailVerifyPending = true);
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(refreshed.uid).set(
      {
        'isActive': true,
        'emailVerified': true,
        'emailVerifiedAt': FieldValue.serverTimestamp(),
        'emailVerifySkippedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    _stopEmailVerifyPolling();
    _safeSetState(() {
      _emailVerifyPending = false;
      _errorText = null;
    });

    // Best-effort post-activation work (safe; no context reads)
    try {
      await _ensureUserDocAfterAuth(refreshed, fallbackError: ''); // won't show (safeSetState gated)
    } catch (_) {}
    try {
      await _warmUserDocFromServer(refreshed.uid);
    } catch (_) {}

    // Only show sheets if still alive (these require context)
    if (_alive) {
      await _maybeShowLinkPhoneSheetIfNeeded();
    }
  }

  void _clearEmailVerifyUi() {
    _emailVerifyPending = false;
    _emailVerifySentAt = null;
    _emailVerifyCooldownTimer?.cancel();
    _emailVerifyCooldownTimer = null;
    _emailVerifyCooldownSeconds = 0;
    _emailVerifyPromptedThisSession = false;
    _stopEmailVerifyPolling();
  }

  void _startEmailVerifyCooldown([int seconds = 60]) {
    _emailVerifyCooldownTimer?.cancel();
    _safeSetState(() => _emailVerifyCooldownSeconds = seconds);

    _emailVerifyCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_alive) return t.cancel();
      if (_emailVerifyCooldownSeconds <= 1) {
        t.cancel();
        _safeSetState(() => _emailVerifyCooldownSeconds = 0);
      } else {
        _safeSetState(() => _emailVerifyCooldownSeconds--);
      }
    });
  }

  Future<Timestamp?> _getEmailVerifySkippedAt(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final v = snap.data()?['emailVerifySkippedAt'];
      return v is Timestamp ? v : null;
    } catch (_) {
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final v = snap.data()?['emailVerifySkippedAt'];
        return v is Timestamp ? v : null;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _recordEmailVerifySkipped() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'emailVerifySkippedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<bool> _shouldShowEmailVerifyPrompt(User user) async {
    if (_emailVerifyPromptedThisSession) return false;

    final refreshed = await _refreshAuthUser(user) ?? user;
    if (refreshed.emailVerified) return false;

    final skippedAt = await _getEmailVerifySkippedAt(user.uid);
    if (skippedAt != null) {
      final diff = DateTime.now().difference(skippedAt.toDate()).inDays;
      if (diff < _reminderCooldownDays) return false;
    }

    return true;
  }

  Future<void> _sendEmailVerificationIfPossible(
      AppLocalizations l10n, {
        bool force = false,
      }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final refreshed = await _refreshAuthUser(user);
    if (refreshed == null) return;

    if (refreshed.emailVerified) {
      _safeSetState(() => _emailVerifyPending = false);
      return;
    }

    final now = DateTime.now();
    final last = _emailVerifySentAt;
    if (!force && last != null && now.difference(last).inSeconds < 30) return;

    try {
      await refreshed.sendEmailVerification();
      _emailVerifySentAt = now;
      _safeSetState(() => _emailVerifyPending = true);
      _startEmailVerifyCooldown(60);
    } on FirebaseAuthException catch (e) {
      _setError(e.message ?? l10n.authError);
    } catch (_) {
      _setError(l10n.authError);
    }
  }

  // ---------------------------
  // Firestore warm
  // ---------------------------
  Future<void> _warmUserDocFromServer(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
    } catch (_) {}
  }

  // ✅ isActive logic identical to old:
  // - Phone users => active
  // - Email users => active only when verified
  bool _shouldBeActive(User user) {
    final hasPhone = (user.phoneNumber ?? '').trim().isNotEmpty;
    if (hasPhone) return true;
    return user.emailVerified;
  }

  // ✅ This restores old "sticky flags" behavior exactly:
  // - isActive never downgrades
  // - emailVerified never downgrades
  // - ALSO: writes isActive false for new/unverified email users (so field exists)
  Future<void> _ensureUserDocAfterAuth(
      User? user, {
        required String fallbackError,
        String? firstName,
        String? lastName,
      }) async {
    if (user == null) {
      _setError(fallbackError);
      return;
    }

    final refreshed = await _refreshAuthUser(user) ?? user;
    final ref = FirebaseFirestore.instance.collection('users').doc(refreshed.uid);

    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref.get(const GetOptions(source: Source.server));
    } catch (_) {
      snap = await ref.get();
    }

    final data = snap.data() ?? <String, dynamic>{};

    final existingActive = (data['isActive'] is bool) ? (data['isActive'] as bool) : false;
    final computedActive = _shouldBeActive(refreshed);
    final effectiveActive = existingActive || computedActive;

    final existingEmailVerified =
    (data['emailVerified'] is bool) ? (data['emailVerified'] as bool) : false;
    final effectiveEmailVerified = existingEmailVerified || refreshed.emailVerified;

    final authEmail = (refreshed.email ?? '').trim().toLowerCase();
    final authPhone = (refreshed.phoneNumber ?? '').trim();

    final fsPhoneCountryIso2 = (data['phoneCountryIso2'] ?? '').toString().trim();
    final fsPhoneCountryDialCode = (data['phoneCountryDialCode'] ?? '').toString().trim();

    final patch = <String, dynamic>{
      if (authEmail.isNotEmpty) 'email': authEmail,
      if (authPhone.isNotEmpty) 'phoneNumber': authPhone,

      // ✅ IMPORTANT: write boolean always (old behavior)
      'isActive': effectiveActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (authPhone.isNotEmpty) {
      // ✅ Fill ONLY if missing (don’t overwrite a real stored value)
      if (fsPhoneCountryIso2.isEmpty) {
        patch['phoneCountryIso2'] = _defaultDialIso2; // stable default
      }
      if (fsPhoneCountryDialCode.isEmpty) {
        patch['phoneCountryDialCode'] = _defaultDialCode; // stable default
      }
    }
    // Email verification fields (sticky)
    if (authEmail.isNotEmpty || (data['email'] ?? '').toString().trim().isNotEmpty) {
      patch['emailVerified'] = effectiveEmailVerified;
      if (effectiveEmailVerified) {
        if (data['emailVerifiedAt'] == null) {
          patch['emailVerifiedAt'] = FieldValue.serverTimestamp();
        }
        patch['emailVerifySkippedAt'] = FieldValue.delete();
      }
    }

    // Terms
    final alreadyAccepted = (data['hasAcceptedTerms'] == true);
    if (_agreedToTerms || alreadyAccepted) {
      patch['hasAcceptedTerms'] = true;
      if (data['termsAcceptedAt'] == null) {
        patch['termsAcceptedAt'] = FieldValue.serverTimestamp();
      }
    }

    // Names (only fill if missing)
    final fn = (firstName ?? '').trim();
    final ln = (lastName ?? '').trim();
    final existingFirst = (data['firstName'] ?? '').toString().trim();
    final existingLast = (data['lastName'] ?? '').toString().trim();
    if (existingFirst.isEmpty && fn.isNotEmpty) patch['firstName'] = fn;
    if (existingLast.isEmpty && ln.isNotEmpty) patch['lastName'] = ln;

    // Defaults
    if ((data['profileUrl'] ?? '').toString().trim().isEmpty) patch['profileUrl'] = '';
    if ((data['avatarType'] ?? '').toString().trim().isEmpty) patch['avatarType'] = 'bear';

    // Create defaults
    if (!snap.exists) {
      patch.addAll(<String, dynamic>{
        if (fn.isNotEmpty) 'firstName': fn,
        if (ln.isNotEmpty) 'lastName': ln,
        'profileUrl': '',
        'avatarType': 'bear',
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'blockedUserIds': <String>[],
      });
    }

    await ref.set(patch, SetOptions(merge: true));
  }

  Future<void> _markUserActiveIfEmailVerified(User user, AppLocalizations l10n) async {
    final refreshed = await _refreshAuthUser(user);
    if (refreshed == null) return;

    if (!refreshed.emailVerified) {
      _setError(l10n.emailNotVerifiedYet);
      _safeSetState(() => _emailVerifyPending = true);
      _startEmailVerifyPolling();
      return;
    }

    await _activateEmailIfVerifiedSilently(refreshed);
  }

  // ---------------------------
  // Country picker
  // ---------------------------
  void _openCountryPicker() {
    if (_submitting) return;

    final l10n = AppLocalizations.of(context)!;

    showCountryPicker(
      context: context,
      showPhoneCode: true,
      useSafeArea: true,
      countryListTheme: CountryListThemeData(
        backgroundColor: Colors.black,
        textStyle: const TextStyle(color: Colors.white),
        borderRadius: BorderRadius.circular(18),
        inputDecoration: InputDecoration(
          hintText: l10n.searchCountryHint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
          prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.8)),
          filled: true,
          fillColor: kSurfaceAltColor.withOpacity(0.65),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPrimaryGold, width: 1.2),
          ),
        ),
      ),
      onSelect: (c) {
        _safeSetState(() {
          _selectedCountry = c;
          _dialIso2 = c.countryCode;
          _dialCode = '+${c.phoneCode}';
          _errorText = null;
        });

        if (_codeSent) {
          _safeSetState(() {
            _resetPhoneState();
            _resetOtpUi();
          });
        }
      },
    );
  }

  Widget _buildCountryPrefixChip() {
    final c = _selectedCountry;
    final flag = c?.flagEmoji ?? '🇺🇸';
    final dial = _dialCode;

    return InkWell(
      onTap: _openCountryPicker,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: kSurfaceAltColor.withOpacity(0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              dial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.85)),
          ],
        ),
      ),
    );
  }

  // ---------------------------
  // Cloud function guard (register only)
  // ---------------------------
  Future<bool> _guardRegisterIdentifierAvailable({
    required bool isPhone,
    required String rawIdentifier,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    try {
      final value = isPhone ? rawIdentifier.trim() : rawIdentifier.trim().toLowerCase();

      final res = await IdentifierAvailabilityApi.check(
        type: isPhone ? IdentifierType.phone : IdentifierType.email,
        identifier: value,
      );

      if (res.available) return true;

      _setError(
        isPhone ? l10n.phoneAlreadyRegisteredPleaseLogin : l10n.emailAlreadyRegisteredPleaseLogin,
      );

      _safeSetState(() {
        _isLogin = true;
        _loginMode = isPhone ? _IdentifierMode.phone : _IdentifierMode.email;

        _registerMode = _IdentifierMode.phone;
        _resetPhoneState();
        _resetOtpUi();
        _showPassword = false;
        _resetCountryToDefault();
        _clearEmailVerifyUi();
      });

      return false;
    } catch (_) {
      _setError(l10n.authError);
      return false;
    }
  }

  // ---------------------------
  // Web reCAPTCHA init
  // ---------------------------
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
        onError: (e) => debugPrint('[AuthScreen] reCAPTCHA onError rid=$rid: ${e.code} ${e.message}'),
        onExpired: () {
          _webRecaptchaExpired = true;
          debugPrint('[AuthScreen] reCAPTCHA expired rid=$rid');
          if (_alive) _safeSetState(() {});
        },
      );

      _webRecaptchaVerifier = verifier;

      await verifier.render().timeout(const Duration(seconds: 60));
      _webRecaptchaRendered = true;

      debugPrint('[AuthScreen] reCAPTCHA rendered rid=$rid container=$_recaptchaChildId');
    } catch (e, st) {
      debugPrint('[AuthScreen] _initWebRecaptcha error rid=$rid: $e\n$st');
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

  String _webRecaptchaSetupHint(AppLocalizations l10n) {
    return [
      l10n.recaptchaRejected,
      '',
      l10n.fixChecklistTitle,
      l10n.fixChecklistAuthorizedDomains,
      l10n.fixChecklistDisableAdBlockers,
      l10n.fixChecklistAllowCookies,
      l10n.fixChecklistTryIncognito,
      l10n.fixChecklistAvoidRetries,
      '',
      l10n.devTipTestPhoneNumbers,
    ].join('\n');
  }

  // ---------------------------
  // ✅ Link Email (RESTORED fully from old)
  // ---------------------------
  bool _hasPasswordProvider(User user) {
    try {
      return user.providerData.any((p) => p.providerId == 'password');
    } catch (_) {
      return false;
    }
  }

  Future<String> _getFirestoreEmailForUid(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      return (snap.data()?['email'] ?? '').toString().trim().toLowerCase();
    } catch (_) {
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        return (snap.data()?['email'] ?? '').toString().trim().toLowerCase();
      } catch (_) {
        return '';
      }
    }
  }

  Future<Timestamp?> _getEmailLinkSkippedAt(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final v = snap.data()?['emailLinkSkippedAt'];
      return v is Timestamp ? v : null;
    } catch (_) {
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final v = snap.data()?['emailLinkSkippedAt'];
        return v is Timestamp ? v : null;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _recordEmailLinkSkipped() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'emailLinkSkippedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<bool> _shouldPromptLinkEmail(User user) async {
    if (_linkEmailPromptedThisSession) return false;

    final hasAuthEmail = (user.email ?? '').trim().isNotEmpty;
    final hasPassword = _hasPasswordProvider(user);
    if (hasAuthEmail && hasPassword) return false;

    final fsEmail = await _getFirestoreEmailForUid(user.uid);
    if (fsEmail.isNotEmpty) return false;

    final skippedAt = await _getEmailLinkSkippedAt(user.uid);
    if (skippedAt != null) {
      final diff = DateTime.now().difference(skippedAt.toDate()).inDays;
      if (diff < _reminderCooldownDays) return false;
    }

    return true;
  }

  Future<void> _maybeShowLinkEmailSheetIfNeeded() async {
    if (!_alive) return;

    await _refreshAuthUser();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!await _shouldPromptLinkEmail(user)) return;

    _linkEmailPromptedThisSession = true;
    await _showLinkEmailSheet();
  }

  Future<void> _showLinkEmailSheet() async {
    if (!_alive) return;
    final l10n = AppLocalizations.of(context)!;

    final result = await showLinkEmailSheet(
      context: context,
      l10n: l10n,
      initialEmail: (_identifierCtrl.text.trim().contains('@')) ? _identifierCtrl.text.trim() : '',
      onLink: (email, pass) async {
        await _linkEmailPasswordToCurrentUser(email: email, password: pass);
      },
      mapError: (e) => _mapLinkEmailError(e, l10n),
      alive: () => _alive,
    );

    if (result == 'skipped') {
      await _recordEmailLinkSkipped();
    }
  }

  Future<void> _linkEmailPasswordToCurrentUser({
    required String email,
    required String password,
  }) async {
    final l10n = AppLocalizations.of(context)!;
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

    // Start verification for linked email (best effort)
    try {
      await user.sendEmailVerification();
    } catch (_) {}

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'email': normalizedEmail,
        'emailLinkSkippedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await _refreshAuthUser(user);
    await _ensureUserDocAfterAuth(user, fallbackError: l10n.authError);
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

  // ---------------------------
  // ✅ Link Phone (your current version kept)
  // ---------------------------
  Future<void> _recordPhoneLinkSkipped() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'phoneLinkSkippedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<Timestamp?> _getPhoneLinkSkippedAt(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final v = snap.data()?['phoneLinkSkippedAt'];
      return v is Timestamp ? v : null;
    } catch (_) {
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final v = snap.data()?['phoneLinkSkippedAt'];
        return v is Timestamp ? v : null;
      } catch (_) {
        return null;
      }
    }
  }

  Future<String> _getFirestorePhoneForUid(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      return (snap.data()?['phoneNumber'] ?? '').toString().trim();
    } catch (_) {
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        return (snap.data()?['phoneNumber'] ?? '').toString().trim();
      } catch (_) {
        return '';
      }
    }
  }

  Future<bool> _shouldPromptLinkPhone(User user) async {
    if (_linkPhonePromptedThisSession) return false;

    final authPhone = (user.phoneNumber ?? '').trim();
    if (authPhone.isNotEmpty) return false;

    final fsPhone = await _getFirestorePhoneForUid(user.uid);
    if (fsPhone.isNotEmpty) return false;

    final skippedAt = await _getPhoneLinkSkippedAt(user.uid);
    if (skippedAt != null) {
      final diff = DateTime.now().difference(skippedAt.toDate()).inDays;
      if (diff < _reminderCooldownDays) return false;
    }

    return true;
  }

  Future<void> _maybeShowLinkPhoneSheetIfNeeded() async {
    if (!_alive) return;

    await _refreshAuthUser();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!await _shouldPromptLinkPhone(user)) return;

    _linkPhonePromptedThisSession = true;
    await _showLinkPhoneSheet();
  }

  Future<void> _showLinkPhoneSheet() async {
    if (!_alive) return;

    final l10n = AppLocalizations.of(context)!;

    final result = await showLinkPhoneSheet(
      context: context,
      l10n: l10n,
      defaultCountry: _defaultCountry,
      defaultDialIso2: _defaultDialIso2,
      onSkip: () async => _recordPhoneLinkSkipped(),

      // ✅ UPDATED signature: (cred, e164, countryIso2, dialCode)
      onLinkWithCredential: (cred, e164, countryIso2, dialCode) async {
        await _linkPhoneCredentialToCurrentUser(
          cred: cred,
          e164: e164,
          phoneCountryIso2: countryIso2,
          phoneCountryDialCode: dialCode,
        );
      },

      // ✅ UPDATED signature: (smsCode, cr, e164, countryIso2, dialCode)
      onLinkWebConfirm: (smsCode, cr, e164, countryIso2, dialCode) async {
        await _confirmWebPhoneLink(
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
      webRecaptchaHint: () => _webRecaptchaSetupHint(l10n),
    );

    if (result == 'skipped') {
      await _recordPhoneLinkSkipped();
    }
  }

  Future<void> _linkPhoneCredentialToCurrentUser({
    required PhoneAuthCredential cred,
    required String e164,
    required String phoneCountryIso2,
    required String phoneCountryDialCode,
  }) async {
    final l10n = AppLocalizations.of(context)!;
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
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _confirmWebPhoneLink({
    required String smsCode,
    required ConfirmationResult cr,
    required String e164,
    required String phoneCountryIso2,
    required String phoneCountryDialCode,
  }) async {
    final l10n = AppLocalizations.of(context)!;

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

  // ---------------------------
  // Phone OTP: send + verify
  // ---------------------------
  Future<void> _sendOtpFromIdentifier() async {
    if (!_alive) return;

    if (_sendOtpCompleter != null) return;
    _sendOtpCompleter = Completer<void>();

    final l10n = AppLocalizations.of(context)!;

    try {
      if (!_isLogin && !_agreedToTerms) {
        _setError(l10n.mustAcceptTerms);
        return;
      }

      final ok = _formKey.currentState?.validate() ?? false;
      if (!ok) return;

      final raw = _identifierCtrl.text.trim();
      final pn = pf.tryParsePhone(raw, dialIso2: _dialIso2);
      if (pn == null) {
        _setError(l10n.invalidPhoneNumber);
        return;
      }

      _cachePendingNamesIfRegister();
      final phone = pf.toE164(pn);

      if (!_isLogin) {
        final ok = await _guardRegisterIdentifierAvailable(
          isPhone: true,
          rawIdentifier: phone,
        );
        if (!ok) return;
      }

      if (!_canSendOtp) return;
      if (kIsWeb && _webOtpRequestInFlight) return;

      _safeSetState(() {
        _submitting = true;
        _errorText = null;
      });

      if (kIsWeb) {
        _webOtpRequestInFlight = true;

        try {
          try {
            await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
          } catch (_) {}

          await _initWebRecaptcha();
          if (_webRecaptchaExpired) await _refreshWebRecaptcha();

          final verifier = _webRecaptchaVerifier;
          if (verifier == null || !_webRecaptchaRendered) {
            _setError(l10n.recaptchaFailedRefresh);
            return;
          }

          _webConfirmationResult = await FirebaseAuth.instance
              .signInWithPhoneNumber(phone, verifier)
              .timeout(const Duration(seconds: 90));

          _safeSetState(() => _codeSent = true);
          _startOtpCooldown();
          return;
        } on FirebaseAuthException catch (e) {
          if (_isRateLimited(e)) {
            _startRateLimitCooldown();
            _setError(l10n.otpRateLimited15Min);
            return;
          }

          if (e.code == 'invalid-app-credential' ||
              e.code == 'captcha-check-failed' ||
              e.code == 'argument-error') {
            await _refreshWebRecaptcha();
            _setError(_webRecaptchaSetupHint(l10n));
            return;
          }

          if (e.code == 'unauthorized-domain') {
            _setError(l10n.unauthorizedDomainFix);
            return;
          }

          _setError(e.message ?? l10n.authError);
          return;
        } on TimeoutException {
          _setError(l10n.otpTimedOutRefresh);
          return;
        } catch (_) {
          _setError(l10n.authError);
          return;
        } finally {
          _webOtpRequestInFlight = false;
        }
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _forceResendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final cred = await FirebaseAuth.instance.signInWithCredential(credential);

            await _ensureUserDocAfterAuth(
              cred.user,
              fallbackError: l10n.authError,
              firstName: _isLogin ? null : (_pendingFirstName ?? _regFirstName),
              lastName: _isLogin ? null : (_pendingLastName ?? _regLastName),
            );

            final uid = cred.user?.uid;
            if (uid != null) await _warmUserDocFromServer(uid);

            // ✅ Phone sign-in => remind to add email if missing
            await _maybeShowLinkEmailSheetIfNeeded();
          } catch (_) {}
        },
        verificationFailed: (FirebaseAuthException e) {
          _setError(e.message ?? l10n.authError);
        },
        codeSent: (String verificationId, int? resendToken) {
          _safeSetState(() {
            _verificationId = verificationId;
            _forceResendToken = resendToken;
            _codeSent = true;
          });
          _startOtpCooldown();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } finally {
      _safeSetState(() => _submitting = false);
      _sendOtpCompleter?.complete();
      _sendOtpCompleter = null;
    }
  }

  Future<void> _verifyOtpCodeWeb() async {
    if (!_alive) return;
    final l10n = AppLocalizations.of(context)!;

    final code = _smsCtrl.text.trim();
    if (code.length < 4) {
      _setError(l10n.invalidOtp);
      return;
    }

    final cr = _webConfirmationResult;
    if (cr == null) {
      _setError(l10n.confirmationNotReadyResend);
      return;
    }

    _safeSetState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final userCred = await cr.confirm(code).timeout(const Duration(seconds: 60));
      final user = userCred.user;
      if (user == null) {
        _setError(l10n.authError);
        return;
      }

      await _refreshAuthUser(user);

      await _ensureUserDocAfterAuth(
        user,
        fallbackError: l10n.authError,
        firstName: _isLogin ? null : (_pendingFirstName ?? _regFirstName),
        lastName: _isLogin ? null : (_pendingLastName ?? _regLastName),
      );

      await _warmUserDocFromServer(user.uid);

      await _maybeShowLinkEmailSheetIfNeeded();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        _setError(l10n.invalidOtp);
        return;
      }
      if (e.code == 'session-expired') {
        _setError(l10n.sessionExpiredResend);
        return;
      }
      _setError(e.message ?? l10n.authError);
    } on TimeoutException {
      _setError(l10n.timedOutTryAgain);
    } catch (_) {
      _setError(l10n.authError);
    } finally {
      _safeSetState(() => _submitting = false);
    }
  }

  Future<void> _verifyOtpAndLogin() async {
    if (!_alive) return;
    final l10n = AppLocalizations.of(context)!;

    if (!_isLogin && !_agreedToTerms) {
      _setError(l10n.mustAcceptTerms);
      return;
    }

    final sms = _smsCtrl.text.trim();
    if (sms.length < 4) {
      _setError(l10n.invalidOtp);
      return;
    }

    _safeSetState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      if (kIsWeb) {
        await _verifyOtpCodeWeb();
        return;
      }

      final vid = _verificationId;
      if (vid == null || vid.isEmpty) {
        _setError(l10n.authError);
        return;
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: vid,
        smsCode: sms,
      );

      final cred = await FirebaseAuth.instance.signInWithCredential(credential);

      await _ensureUserDocAfterAuth(
        cred.user,
        fallbackError: l10n.authError,
        firstName: _isLogin ? null : (_pendingFirstName ?? _regFirstName),
        lastName: _isLogin ? null : (_pendingLastName ?? _regLastName),
      );

      final uid = cred.user?.uid;
      if (uid != null) await _warmUserDocFromServer(uid);

      await _maybeShowLinkEmailSheetIfNeeded();
    } on FirebaseAuthException catch (e) {
      _setError(e.message ?? l10n.authError);
    } catch (_) {
      _setError(l10n.authError);
    } finally {
      _safeSetState(() => _submitting = false);
    }
  }

  // ---------------------------
  // Submit unified
  // ---------------------------
  Future<void> _submitUnified() async {
    if (!_alive) return;
    final l10n = AppLocalizations.of(context)!;

    if (!_isLogin && !_agreedToTerms) {
      _setError(l10n.mustAcceptTerms);
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final raw = _identifierCtrl.text.trim();
    final mode = _effectiveMode();
    final isPhone = mode == _IdentifierMode.phone;

    final pn = isPhone ? pf.tryParsePhone(raw, dialIso2: _dialIso2) : null;
    if (isPhone && pn == null) {
      _setError(l10n.invalidPhoneNumber);
      return;
    }

    if (!_isLogin) {
      if (isPhone) _cachePendingNamesIfRegister();

      final ok = await _guardRegisterIdentifierAvailable(
        isPhone: isPhone,
        rawIdentifier: isPhone ? pf.toE164(pn!) : raw,
      );
      if (!ok) return;
    }

    if (isPhone) {
      if (kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_alive) _initWebRecaptcha();
        });
      }

      if (!_codeSent) {
        await _sendOtpFromIdentifier();
      } else {
        await _verifyOtpAndLogin();
      }
      return;
    }

    // EMAIL
    _safeSetState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final email = raw.trim().toLowerCase();
      final pass = _passwordCtrl.text.trim();

      if (_isLogin) {
        if (_emailVerifyPending) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await _markUserActiveIfEmailVerified(user, l10n);
            return;
          }
        }

        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );

        final user = cred.user;
        if (user == null) {
          _setError(l10n.authError);
          return;
        }

        final refreshed = await _refreshAuthUser(user) ?? user;

        if (!refreshed.emailVerified) {
          await _ensureUserDocAfterAuth(refreshed, fallbackError: l10n.authError);

          if (await _shouldShowEmailVerifyPrompt(refreshed)) {
            _emailVerifyPromptedThisSession = true;
            _safeSetState(() => _emailVerifyPending = true);
            await _sendEmailVerificationIfPossible(l10n, force: false);
            _setError(l10n.verifyEmailToActivate);
          } else {
            _setError(l10n.verifyEmailToActivate);
          }
          return;
        }

        await _ensureUserDocAfterAuth(refreshed, fallbackError: l10n.authError);
        await _warmUserDocFromServer(refreshed.uid);

        // ✅ Email sign-in => remind to add phone if missing
        await _maybeShowLinkPhoneSheetIfNeeded();
        return;
      }

      // Register (Email) - restore old behavior including isActive:false
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );

      final user = cred.user;
      if (user == null) {
        _setError(l10n.authError);
        return;
      }

      try {
        await user.sendEmailVerification();
      } catch (_) {}

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'email': user.email ?? '',
          'phoneNumber': user.phoneNumber ?? '',
          'firstName': _regFirstName,
          'lastName': _regLastName,
          'profileUrl': '',
          'avatarType': 'bear',
          'isOnline': false,

          // ✅ IMPORTANT: explicit field like old
          'isActive': false,

          'emailVerified': user.emailVerified,
          'emailVerifiedAt': null,
          'emailVerifySkippedAt': null,
          'lastSeen': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'blockedUserIds': <String>[],
          'hasAcceptedTerms': true,
          'termsAcceptedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await _ensureUserDocAfterAuth(user, fallbackError: l10n.authError);
      await _warmUserDocFromServer(user.uid);

      await _sendEmailVerificationIfPossible(l10n, force: true);

      _safeSetState(() {
        _emailVerifyPending = true;
        _emailVerifyPromptedThisSession = true;
      });

      _setError(l10n.checkYourEmailToVerify);
    } on FirebaseAuthException catch (e) {
      _setError(e.message ?? l10n.authError);
    } catch (e, st) {
      debugPrint('[AuthScreen] _submitUnified email flow error: $e\n$st');
      _setError(l10n.authError);
    } finally {
      _safeSetState(() => _submitting = false);
    }
  }

  String _primaryButtonLabel(
      AppLocalizations l10n, {
        required bool isRegister,
        required bool isPhone,
        required bool emailVerifyPending,
      }) {
    if (isPhone) {
      if (!_codeSent) return l10n.sendCode;
      return l10n.verifyCode;
    }
    if (emailVerifyPending) return l10n.iVerifiedMyEmail;
    return isRegister ? l10n.register : l10n.login;
  }

  // ---------------------------
  // UI widgets
  // ---------------------------
  Widget _buildModeChips({
    required String leftText,
    required IconData leftIcon,
    required bool leftSelected,
    required VoidCallback onLeftTap,
    required String rightText,
    required IconData rightIcon,
    required bool rightSelected,
    required VoidCallback onRightTap,
  }) {
    Widget chip({
      required String text,
      required bool selected,
      required VoidCallback onTap,
      required IconData icon,
    }) {
      return Expanded(
        child: InkWell(
          onTap: _submitting ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? kPrimaryGold.withOpacity(0.92) : kSurfaceAltColor.withOpacity(0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(selected ? 0.0 : 0.16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? Colors.black : Colors.white.withOpacity(0.85)),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.black : Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(text: leftText, icon: leftIcon, selected: leftSelected, onTap: onLeftTap),
        const SizedBox(width: 10),
        chip(text: rightText, icon: rightIcon, selected: rightSelected, onTap: onRightTap),
      ],
    );
  }

  Widget _buildRegisterIdentifierToggle(AppLocalizations l10n) {
    if (_isLogin) return const SizedBox.shrink();

    final isPhoneSelected = _registerMode == _IdentifierMode.phone;
    final isEmailSelected = _registerMode == _IdentifierMode.email;

    return _buildModeChips(
      leftText: l10n.phoneNumberLabel,
      leftIcon: Icons.phone_outlined,
      leftSelected: isPhoneSelected,
      onLeftTap: () {
        if (_registerMode == _IdentifierMode.phone) return;
        _safeSetState(() {
          _registerMode = _IdentifierMode.phone;
          _identifierCtrl.clear();
          _passwordCtrl.clear();
          _resetPhoneState();
          _resetOtpUi();
          _errorText = null;
          _showPassword = false;
          _clearEmailVerifyUi();
        });
      },
      rightText: l10n.email,
      rightIcon: Icons.alternate_email_rounded,
      rightSelected: isEmailSelected,
      onRightTap: () {
        if (_registerMode == _IdentifierMode.email) return;
        _safeSetState(() {
          _registerMode = _IdentifierMode.email;
          _identifierCtrl.clear();
          _passwordCtrl.clear();
          _resetPhoneState();
          _resetOtpUi();
          _errorText = null;
          _showPassword = false;
          _clearEmailVerifyUi();
        });
      },
    );
  }

  Widget _buildLoginIdentifierToggle(AppLocalizations l10n) {
    if (!_isLogin) return const SizedBox.shrink();

    final isPhoneSelected = _loginMode == _IdentifierMode.phone;
    final isEmailSelected = _loginMode == _IdentifierMode.email;

    return _buildModeChips(
      leftText: l10n.phoneNumberLabel,
      leftIcon: Icons.phone_outlined,
      leftSelected: isPhoneSelected,
      onLeftTap: () {
        if (_loginMode == _IdentifierMode.phone) return;
        _safeSetState(() {
          _loginMode = _IdentifierMode.phone;
          _errorText = null;
          _identifierCtrl.clear();
          _passwordCtrl.clear();
          _smsCtrl.clear();
          _showPassword = false;
          _resetPhoneState();
          _resetOtpUi();
          _resetCountryToDefault();
          _clearEmailVerifyUi();
        });

        if (kIsWeb) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_alive) _initWebRecaptcha();
          });
        }
      },
      rightText: l10n.email,
      rightIcon: Icons.alternate_email_rounded,
      rightSelected: isEmailSelected,
      onRightTap: () {
        if (_loginMode == _IdentifierMode.email) return;
        _safeSetState(() {
          _loginMode = _IdentifierMode.email;
          _errorText = null;
          _identifierCtrl.clear();
          _passwordCtrl.clear();
          _smsCtrl.clear();
          _showPassword = false;
          _resetPhoneState();
          _resetOtpUi();
          _clearEmailVerifyUi();
        });
      },
    );
  }

  Widget _buildPhoneRow(AppLocalizations l10n) {
    return Row(
      children: [
        _buildCountryPrefixChip(),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _identifierCtrl,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(
              labelText: l10n.phoneNumberLabel,
              hintText: l10n.phoneHintExample,
              prefixIcon: const Icon(Icons.phone_outlined),
            ),
            onChanged: (_) {
              if (_errorText != null) _safeSetState(() => _errorText = null);
              if (_codeSent) _smsCtrl.clear();

              if (kIsWeb) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_alive && _loginMode == _IdentifierMode.phone) _initWebRecaptcha();
                });
              }
            },
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return l10n.requiredField;

              final digits = pf.digitsOnly(s);
              if (digits.isNotEmpty && digits.length < 7) return null;

              if (pf.tryParsePhone(s, dialIso2: _dialIso2) != null) return null;
              return l10n.invalidPhoneNumber;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmailVerifyPanel(AppLocalizations l10n) {
    if (!_emailVerifyPending) return const SizedBox.shrink();

    final authEmail = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    final typed = _identifierCtrl.text.trim();
    final email = authEmail.isNotEmpty ? authEmail : typed;

    final cooldown =
    _emailVerifyCooldownSeconds > 0 ? ' (${_formatCooldown(_emailVerifyCooldownSeconds)})' : '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_read_outlined, color: kPrimaryGold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.verifyYourEmailTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            email.isEmpty ? l10n.verifyEmailPanelBodyNoEmail : l10n.verifyEmailPanelBodyWithEmail(email),
            style: TextStyle(
              color: kTextSecondary.withOpacity(0.95),
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (_submitting || _emailVerifyCooldownSeconds > 0)
                      ? null
                      : () async {
                    _safeSetState(() {
                      _errorText = null;
                      _submitting = true;
                    });
                    try {
                      await _sendEmailVerificationIfPossible(l10n, force: true);
                    } finally {
                      _safeSetState(() => _submitting = false);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withOpacity(0.18)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    '${l10n.resend}$cooldown',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting
                      ? null
                      : () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      _setError(l10n.authError);
                      return;
                    }
                    _safeSetState(() {
                      _errorText = null;
                      _submitting = true;
                    });
                    try {
                      await _markUserActiveIfEmailVerified(user, l10n);
                    } finally {
                      _safeSetState(() => _submitting = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(l10n.iVerified, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _submitting
                  ? null
                  : () async {
                await _recordEmailVerifySkipped();
                if (!_alive) return;
                _stopEmailVerifyPolling();
                _safeSetState(() {
                  _emailVerifyPending = false;
                  _errorText = null;
                });
              },
              child: Text(
                l10n.skipForNow,
                style: const TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Build
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRegister = !_isLogin;

    final mode = _effectiveMode();
    final isPhoneMode = mode == _IdentifierMode.phone;

    final cooldownLabel =
    _otpCooldownSeconds > 0 ? ' (${_formatCooldown(_otpCooldownSeconds)})' : '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: MwBackground(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: kSurfaceAltColor.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: kBorderColor.withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: kGoldDeep.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        children: [
                          AuthHeader(isRegister: isRegister),
                          const SizedBox(height: 18),

                          if (isRegister) ...[
                            AuthRegisterSection(
                              firstNameCtrl: _firstNameCtrl,
                              lastNameCtrl: _lastNameCtrl,
                              isSubmitting: _submitting,
                              agreedToTerms: _agreedToTerms,
                              onAgreeChanged: (v) {
                                _safeSetState(() {
                                  _agreedToTerms = v;
                                  if (v) _errorText = null;
                                });
                              },
                              onViewTerms: _openTerms,
                            ),
                            const SizedBox(height: 14),
                            _buildRegisterIdentifierToggle(l10n),
                            const SizedBox(height: 12),
                          ] else ...[
                            _buildLoginIdentifierToggle(l10n),
                            const SizedBox(height: 12),
                          ],

                          if (!isPhoneMode) _buildEmailVerifyPanel(l10n),

                          if (isPhoneMode) ...[
                            _buildPhoneRow(l10n),
                          ] else ...[
                            TextFormField(
                              controller: _identifierCtrl,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username],
                              decoration: InputDecoration(
                                labelText: l10n.email,
                                hintText: l10n.emailHintExample,
                                prefixIcon: const Icon(Icons.alternate_email_rounded),
                              ),
                              onChanged: (_) {
                                if (_errorText != null) _safeSetState(() => _errorText = null);

                                if (_codeSent) {
                                  _safeSetState(() {
                                    _resetPhoneState();
                                    _resetOtpUi();
                                  });
                                }

                                if (_emailVerifyPending) {
                                  _safeSetState(() => _emailVerifyPending = false);
                                }
                              },
                              validator: (v) {
                                final s = (v ?? '').trim();
                                if (s.isEmpty) return l10n.requiredField;
                                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                                  return l10n.invalidEmail;
                                }
                                return null;
                              },
                            ),
                          ],

                          const SizedBox(height: 14),

                          if (!isPhoneMode) ...[
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: !_showPassword,
                              autofillHints: isRegister
                                  ? const [AutofillHints.newPassword]
                                  : const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: l10n.password,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showPassword ? Icons.visibility : Icons.visibility_off,
                                    color: kTextSecondary,
                                  ),
                                  onPressed: () => _safeSetState(() => _showPassword = !_showPassword),
                                ),
                              ),
                              validator: (v) {
                                if (_effectiveMode() != _IdentifierMode.email) return null;
                                if (v == null || v.isEmpty) return l10n.requiredField;
                                if (v.length < 6) return l10n.minPassword;
                                return null;
                              },
                            ),
                          ] else ...[
                            if (_codeSent) ...[
                              TextFormField(
                                controller: _smsCtrl,
                                keyboardType: TextInputType.number,
                                autofillHints: const [AutofillHints.oneTimeCode],
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: l10n.otpCodeLabel,
                                  hintText: l10n.otpCodeHint,
                                  prefixIcon: const Icon(Icons.sms_outlined),
                                ),
                                onFieldSubmitted: (_) => _submitting ? null : _submitUnified(),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton(
                                  onPressed: _canSendOtp ? _sendOtpFromIdentifier : null,
                                  child: Text(
                                    '${l10n.resendCode}$cooldownLabel',
                                    style: const TextStyle(
                                      color: kTextSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                l10n.enterOtpToContinue,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: kTextSecondary.withOpacity(0.9),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else ...[
                              Text(
                                l10n.sendOtpToContinue,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: kTextSecondary.withOpacity(0.9),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (_otpCooldownSeconds > 0)
                                Text(
                                  '${l10n.cooldownLabel}$cooldownLabel',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                                ),
                            ],
                          ],

                          if (_errorText != null) ...[
                            const SizedBox(height: 10),
                            Text(_errorText!, style: const TextStyle(color: kErrorColor)),
                          ],

                          const SizedBox(height: 18),
                          ElevatedButton(
                            onPressed: _submitting ? null : _submitUnified,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryGold,
                              foregroundColor: Colors.black,
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 40),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _submitting
                                  ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2,
                                ),
                              )
                                  : Text(
                                _primaryButtonLabel(
                                  l10n,
                                  isRegister: isRegister,
                                  isPhone: isPhoneMode,
                                  emailVerifyPending: !isPhoneMode && _emailVerifyPending,
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () {
                              _safeSetState(() {
                                _isLogin = !_isLogin;
                                _errorText = null;

                                _resetPhoneState();
                                _resetOtpUi();

                                _identifierCtrl.clear();
                                _passwordCtrl.clear();
                                _smsCtrl.clear();

                                if (_isLogin) {
                                  _loginMode = _IdentifierMode.phone;
                                  _resetCountryToDefault();
                                } else {
                                  _resetRegisterState();
                                }

                                _showPassword = false;

                                _linkEmailPromptedThisSession = false;
                                _linkPhonePromptedThisSession = false;

                                _clearEmailVerifyUi();
                              });

                              if (kIsWeb && _isLogin && _loginMode == _IdentifierMode.phone) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (_alive) _initWebRecaptcha();
                                });
                              }
                            },
                            child: Text(
                              isRegister ? l10n.alreadyHaveAccount : l10n.createNewAccount,
                              style: const TextStyle(
                                color: kTextSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: MwLanguageButton(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}