//lib/screens/profile/widgets/profile_change_password_section.dart

import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class ProfileChangePasswordSection extends StatelessWidget {
  const ProfileChangePasswordSection({super.key});

  Future<void> _openChangePasswordSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => _ChangePasswordSheet(l10n: l10n),
    );

    if (res == true && context.mounted) {
      // Optional: haptic feedback on success
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _openChangePasswordSheet(context),
        icon: Icon(Icons.lock_outline, color: kPrimaryGold.withOpacity(0.95)),
        label: Text(
          l10n.changePassword,
          style: TextStyle(
            color: kTextPrimary.withOpacity(0.95),
            fontWeight: FontWeight.w800,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withOpacity(0.16)),
          backgroundColor: Colors.white.withOpacity(0.04),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({required this.l10n});
  final AppLocalizations l10n;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _currentFocus = FocusNode();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _loading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  AppLocalizations get l10n => widget.l10n;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _currentFocus.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  bool _hasPasswordProvider(User user) {
    return user.providerData.any((p) => p.providerId == 'password');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return l10n.currentPasswordIncorrect;
      case 'weak-password':
        return l10n.weakPassword;
      case 'requires-recent-login':
        return l10n.requiresRecentLogin;
      case 'too-many-requests':
        return l10n.tooManyRequests;
      default:
        return e.message ?? l10n.genericError;
    }
  }

  Future<void> _sendResetEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;

    if (email == null || email.isEmpty) {
      _snack(l10n.noEmailFound);
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack(l10n.resetEmailSent);
      if (mounted) Navigator.of(context).pop(false);
    } on FirebaseAuthException catch (e) {
      _snack(
        e.code == 'too-many-requests'
            ? l10n.tooManyRequests
            : (e.message ?? l10n.genericError),
      );
    } catch (_) {
      _snack(l10n.genericError);
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack(l10n.notSignedIn);
      return;
    }

    if (!_hasPasswordProvider(user)) {
      _snack(l10n.noPasswordProvider);
      return;
    }

    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = user.email;
    if (email == null || email.isEmpty) {
      _snack(l10n.noEmailFound);
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: _currentCtrl.text.trim(),
      );

      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_newCtrl.text.trim());
      await user.reload();

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.passwordUpdatedSuccess)),
      );
    } on FirebaseAuthException catch (e) {
      _snack(_friendlyError(e));
    } catch (_) {
      _snack(l10n.genericError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decoration({
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperStyle: TextStyle(color: kTextSecondary.withOpacity(0.85)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.14)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: kPrimaryGold.withOpacity(0.55), width: 1.2),
      ),
      suffixIcon: IconButton(
        onPressed: onToggle,
        icon: Icon(
          obscure ? Icons.visibility : Icons.visibility_off,
          color: Colors.white.withOpacity(0.75),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.78),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),

                    Row(
                      children: [
                        Icon(Icons.lock_rounded, color: kPrimaryGold.withOpacity(0.95)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.changePasswordDialogTitle,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: kTextPrimary.withOpacity(0.95),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                          icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.8)),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),

                    Text(
                      // Keep this short; modern sheets should be minimal.
                      l10n.passwordMinLength,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: kTextSecondary.withOpacity(0.85),
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 14),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _currentCtrl,
                            focusNode: _currentFocus,
                            obscureText: _obscureCurrent,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _newFocus.requestFocus(),
                            decoration: _decoration(
                              label: l10n.currentPassword,
                              obscure: _obscureCurrent,
                              onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
                            ),
                            validator: (v) =>
                            (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _newCtrl,
                            focusNode: _newFocus,
                            obscureText: _obscureNew,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                            decoration: _decoration(
                              label: l10n.newPassword,
                              obscure: _obscureNew,
                              onToggle: () => setState(() => _obscureNew = !_obscureNew),
                              helper: l10n.passwordMinLength, // “Use at least 8 characters”
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return l10n.requiredField;
                              if (s.length < 8) return l10n.passwordMinLength;
                              if (s == _currentCtrl.text.trim()) return l10n.passwordMustDiffer;
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _confirmCtrl,
                            focusNode: _confirmFocus,
                            obscureText: _obscureConfirm,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.newPassword],
                            onFieldSubmitted: (_) => _loading ? null : _submit(),
                            decoration: _decoration(
                              label: l10n.confirmNewPassword,
                              obscure: _obscureConfirm,
                              onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                            validator: (v) =>
                            (v ?? '') != _newCtrl.text ? l10n.passwordsDoNotMatch : null,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Forgot password card (clean + modern)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.email_outlined, color: kPrimaryGold.withOpacity(0.9)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.forgotPassword,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: kTextPrimary.withOpacity(0.95),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  // If you want a localized string, add one later.
                                  l10n.resetPasswordHelperText,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: kTextSecondary.withOpacity(0.85),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _loading ? null : _sendResetEmail,
                            style: TextButton.styleFrom(
                              foregroundColor: kPrimaryGold.withOpacity(0.95),
                              textStyle: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            child: Text(l10n.send),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Bottom actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.white.withOpacity(0.14)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              l10n.cancel,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.90),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kGoldDeep,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                            ),
                            child: _loading
                                ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : Text(
                              l10n.updatePassword,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
