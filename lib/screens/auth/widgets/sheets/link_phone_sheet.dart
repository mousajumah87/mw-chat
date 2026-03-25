// lib/screens/auth/widgets/sheets/link_phone_sheet.dart
import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/phone_format.dart' as pf;

/// ✅ Updated: include country metadata so caller can persist it in Firestore.
typedef LinkPhoneCredHandler = Future<void> Function(
    PhoneAuthCredential cred,
    String e164,
    String countryIso2,
    String dialCode,
    );

/// ✅ Updated: include country metadata so caller can persist it in Firestore.
typedef LinkPhoneWebConfirmHandler = Future<void> Function(
    String smsCode,
    ConfirmationResult cr,
    String e164,
    String countryIso2,
    String dialCode,
    );

Future<String?> showLinkPhoneSheet({
  required BuildContext context,
  required AppLocalizations l10n,
  required Country? defaultCountry,
  required String defaultDialIso2,

  // ✅ Used by auth_screen.dart / AuthGate
  required Future<void> Function() onSkip,
  required LinkPhoneCredHandler onLinkWithCredential,
  required LinkPhoneWebConfirmHandler onLinkWebConfirm,

  // Web reCAPTCHA helpers (wired from AuthScreen/AuthGate)
  required Future<void> Function() initWebRecaptcha,
  required RecaptchaVerifier? Function() getWebRecaptchaVerifier,
  required Future<void> Function() refreshWebRecaptcha,
  required bool Function() isWebRecaptchaReady,
  required String Function() webRecaptchaHint,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _LinkPhoneSheet(
      l10n: l10n,
      defaultCountry: defaultCountry,
      defaultDialIso2: defaultDialIso2,
      isDark: isDark,
      onSkip: onSkip,
      onLinkWithCredential: onLinkWithCredential,
      onLinkWebConfirm: onLinkWebConfirm,
      initWebRecaptcha: initWebRecaptcha,
      getWebRecaptchaVerifier: getWebRecaptchaVerifier,
      refreshWebRecaptcha: refreshWebRecaptcha,
      isWebRecaptchaReady: isWebRecaptchaReady,
      webRecaptchaHint: webRecaptchaHint,
    ),
  );
}

class _LinkPhoneSheet extends StatefulWidget {
  const _LinkPhoneSheet({
    required this.l10n,
    required this.defaultCountry,
    required this.defaultDialIso2,
    required this.isDark,
    required this.onSkip,
    required this.onLinkWithCredential,
    required this.onLinkWebConfirm,
    required this.initWebRecaptcha,
    required this.getWebRecaptchaVerifier,
    required this.refreshWebRecaptcha,
    required this.isWebRecaptchaReady,
    required this.webRecaptchaHint,
  });

  final AppLocalizations l10n;
  final Country? defaultCountry;
  final String defaultDialIso2;
  final bool isDark;

  final Future<void> Function() onSkip;
  final LinkPhoneCredHandler onLinkWithCredential;
  final LinkPhoneWebConfirmHandler onLinkWebConfirm;

  final Future<void> Function() initWebRecaptcha;
  final RecaptchaVerifier? Function() getWebRecaptchaVerifier;
  final Future<void> Function() refreshWebRecaptcha;
  final bool Function() isWebRecaptchaReady;
  final String Function() webRecaptchaHint;

  @override
  State<_LinkPhoneSheet> createState() => _LinkPhoneSheetState();
}

class _LinkPhoneSheetState extends State<_LinkPhoneSheet> {
  final _phoneController = TextEditingController();
  final _smsController = TextEditingController();

  Country? _country;
  late String _dialIso2;

  bool _loading = false;
  String? _error;

  // Mobile state
  String? _mobileVerificationId;

  // Web state (ConfirmationResult for linking)
  ConfirmationResult? _webCr;

  bool get _codeRequested => (_webCr != null) || ((_mobileVerificationId ?? '').isNotEmpty);

  @override
  void initState() {
    super.initState();
    _country = widget.defaultCountry;
    _dialIso2 = widget.defaultDialIso2;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _smsController.dispose();
    super.dispose();
  }

  void _setError(String? e) {
    if (!mounted) return;
    setState(() => _error = e);
  }

  String _countryIso2() => _dialIso2;
  String _dialCode() => _country?.phoneCode ?? '';

  Widget _grabHandle(ThemeData theme) {
    return Container(
      width: 46,
      height: 5,
      decoration: BoxDecoration(
        color: theme.dividerColor.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  Widget _errorCard(ThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCountry() async {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      useSafeArea: true,
      onSelect: (c) {
        if (!mounted) return;
        setState(() {
          _country = c;
          _dialIso2 = c.countryCode; // ISO2
          _error = null;
        });
      },
    );
  }

  String _countryDisplay() {
    final c = _country;
    if (c == null) return widget.l10n.searchCountryHint;
    return '${c.flagEmoji} +${c.phoneCode} (${c.countryCode})';
  }

  String? _validateAndToE164() {
    final raw = _phoneController.text.trim();
    final pn = pf.tryParsePhone(raw, dialIso2: _dialIso2);
    if (pn == null) return null;
    return pf.toE164(pn);
  }

  Future<void> _startVerify() async {
    _setError(null);

    final e164 = _validateAndToE164();
    if (e164 == null) {
      _setError(widget.l10n.invalidPhoneNumber);
      return;
    }

    setState(() => _loading = true);
    try {
      if (kIsWeb) {
        // ✅ Web MUST LINK (not sign-in) to avoid switching users.
        await widget.initWebRecaptcha();

        if (!widget.isWebRecaptchaReady()) {
          _setError(widget.webRecaptchaHint());
          return;
        }

        final verifier = widget.getWebRecaptchaVerifier();
        if (verifier == null) {
          _setError(widget.webRecaptchaHint());
          return;
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _setError(widget.l10n.authError);
          return;
        }

        try {
          final cr = await user
              .linkWithPhoneNumber(e164, verifier)
              .timeout(const Duration(seconds: 90));
          if (!mounted) return;
          setState(() => _webCr = cr);
        } on FirebaseAuthException catch (e) {
          debugPrint('[LinkPhoneSheet] web link request error: ${e.code} ${e.message}');
          try {
            await widget.refreshWebRecaptcha();
          } catch (_) {}
          _setError(e.message ?? widget.webRecaptchaHint());
          return;
        } on TimeoutException {
          _setError(widget.l10n.otpTimedOutRefresh);
          return;
        }
      } else {
        // ✅ Mobile: verifyPhoneNumber then link with credential after code
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: e164,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (cred) async {
            try {
              await widget.onLinkWithCredential(
                cred,
                e164,
                _countryIso2(),
                _dialCode(),
              );
              if (mounted) Navigator.of(context).pop(e164);
            } catch (e) {
              _setError(e.toString());
            }
          },
          verificationFailed: (e) {
            _setError(e.message ?? widget.l10n.authError);
          },
          codeSent: (verificationId, resendToken) {
            if (!mounted) return;
            setState(() => _mobileVerificationId = verificationId);
          },
          codeAutoRetrievalTimeout: (verificationId) {
            if (!mounted) return;
            setState(() => _mobileVerificationId = verificationId);
          },
        );
      }
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmCode() async {
    _setError(null);

    final e164 = _validateAndToE164();
    if (e164 == null) {
      _setError(widget.l10n.invalidPhoneNumber);
      return;
    }

    final code = _smsController.text.trim();
    if (code.length < 4) {
      _setError(widget.l10n.invalidOtp);
      return;
    }

    setState(() => _loading = true);
    try {
      if (kIsWeb) {
        final cr = _webCr;
        if (cr == null) {
          _setError(widget.l10n.confirmationNotReadyResend);
          return;
        }

        await widget.onLinkWebConfirm(
          code,
          cr,
          e164,
          _countryIso2(),
          _dialCode(),
        );

        if (mounted) Navigator.of(context).pop(e164);
      } else {
        final vid = _mobileVerificationId;
        if (vid == null || vid.isEmpty) {
          _setError(widget.l10n.confirmationNotReadyResend);
          return;
        }

        final cred = PhoneAuthProvider.credential(
          verificationId: vid,
          smsCode: code,
        );

        await widget.onLinkWithCredential(
          cred,
          e164,
          _countryIso2(),
          _dialCode(),
        );

        if (mounted) Navigator.of(context).pop(e164);
      }
    } on FirebaseAuthException catch (e) {
      _setError(e.message ?? widget.l10n.authError);
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _skip() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onSkip();
      if (mounted) Navigator.of(context).pop('skipped');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _close() {
    if (_loading) return;
    Navigator.of(context).pop('skipped');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg = widget.isDark ? const Color(0xFF141414) : Colors.white;
    final borderColor = theme.dividerColor.withOpacity(widget.isDark ? 0.18 : 0.30);

    return SafeArea(
      child: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _grabHandle(theme),
            const SizedBox(height: 12),

            // Header: title + close
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.l10n.linkPhoneTitle,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: widget.l10n.close ?? 'Close',
                  onPressed: _loading ? null : _close,
                  icon: Icon(Icons.close_rounded, color: theme.iconTheme.color?.withOpacity(0.9)),
                ),
              ],
            ),

            Text(
              widget.l10n.linkPhoneSubtitle ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.70),
                height: 1.2,
              ),
              textAlign: TextAlign.left,
            ),

            const SizedBox(height: 14),

            if (_error != null) ...[
              _errorCard(theme, _error!),
              const SizedBox(height: 12),
            ],

            // Country picker
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _loading ? null : _pickCountry,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _countryDisplay(),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Icon(Icons.expand_more_rounded, color: theme.iconTheme.color?.withOpacity(0.8)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: widget.l10n.phoneNumberLabel,
                hintText: widget.l10n.phoneHintExample,
                prefixIcon: const Icon(Icons.phone_rounded),
                isDense: true,
              ),
              enabled: !_loading,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _startVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _loading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
                    : Text(
                  widget.l10n.sendCode,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _smsController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.l10n.otpCodeLabel,
                hintText: widget.l10n.otpCodeHint,
                prefixIcon: const Icon(Icons.sms_rounded),
              ),
              enabled: !_loading,
              onSubmitted: (_) => _loading ? null : _confirmCode(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_loading || !_codeRequested) ? null : _confirmCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  widget.l10n.verifyCode,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),

            const SizedBox(height: 8),

            TextButton(
              onPressed: _loading ? null : _skip,
              child: Text(
                widget.l10n.skipForNow,
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.70),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}