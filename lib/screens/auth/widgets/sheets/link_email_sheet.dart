// lib/screens/auth/widgets/sheets/link_email_sheet.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../theme/app_theme.dart';

typedef LinkEmailHandler = Future<void> Function(String email, String password);

Future<String?> showLinkEmailSheet({
  required BuildContext context,
  required AppLocalizations l10n,
  required String initialEmail,
  required LinkEmailHandler onLink,
  required String Function(FirebaseAuthException e) mapError,

  /// Optional safety for snackbars if caller is outside widget lifecycle.
  bool Function()? alive,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true, // ✅ important when called from AuthGate or overlays
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) {
      return _LinkEmailBottomSheet(
        initialEmail: initialEmail,
        l10n: l10n,
        onLink: onLink,
        mapError: mapError,
        alive: alive ?? () => true,
      );
    },
  );
}

class _LinkEmailBottomSheet extends StatefulWidget {
  const _LinkEmailBottomSheet({
    required this.initialEmail,
    required this.l10n,
    required this.onLink,
    required this.mapError,
    required this.alive,
  });

  final String initialEmail;
  final AppLocalizations l10n;
  final LinkEmailHandler onLink;
  final String Function(FirebaseAuthException e) mapError;
  final bool Function() alive;

  @override
  State<_LinkEmailBottomSheet> createState() => _LinkEmailBottomSheetState();
}

class _LinkEmailBottomSheetState extends State<_LinkEmailBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController emailCtrl;
  late final TextEditingController passCtrl;
  late final TextEditingController confirmCtrl;

  bool loading = false;
  String? error;

  bool _showPass = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    emailCtrl = TextEditingController(text: widget.initialEmail);
    passCtrl = TextEditingController();
    confirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    super.dispose();
  }

  void _clearErrorIfAny() {
    if (error != null && mounted) setState(() => error = null);
  }

  Future<void> _submit() async {
    if (loading) return;

    final l10n = widget.l10n;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final email = emailCtrl.text.trim().toLowerCase();
    final pass = passCtrl.text.trim();
    final confirm = confirmCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty || confirm.isEmpty) {
      setState(() => error = l10n.requiredField);
      return;
    }
    if (pass != confirm) {
      setState(() => error = l10n.passwordsDoNotMatch);
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      await widget.onLink(email, pass);

      if (!mounted) return;
      Navigator.of(context).pop('linked');

      if (widget.alive()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.emailLinkedSuccess)),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = widget.mapError(e));
    } catch (_) {
      if (mounted) setState(() => error = l10n.authError);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _grabHandle(Color color) {
    return Container(
      width: 46,
      height: 5,
      decoration: BoxDecoration(
        color: color.withOpacity(0.55),
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

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final sheetBg = Colors.black.withOpacity(0.92);
    final border = Colors.white.withOpacity(0.12);
    final divider = Colors.white.withOpacity(0.22);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _grabHandle(divider),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.addEmailTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.close ?? 'Close',
                        onPressed: loading ? null : () => Navigator.of(context).pop('skipped'),
                        icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.85)),
                      ),
                    ],
                  ),

                  Text(
                    l10n.addEmailSubtitle,
                    style: TextStyle(color: kTextSecondary.withOpacity(0.92)),
                  ),

                  const SizedBox(height: 14),

                  if (error != null) ...[
                    _errorCard(theme, error!),
                    const SizedBox(height: 12),
                  ],

                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    enabled: !loading,
                    decoration: InputDecoration(
                      labelText: l10n.email,
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                    ),
                    onChanged: (_) => _clearErrorIfAny(),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return l10n.requiredField;
                      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
                      if (!ok) return l10n.invalidEmail;
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  TextFormField(
                    controller: passCtrl,
                    obscureText: !_showPass,
                    textInputAction: TextInputAction.next,
                    enabled: !loading,
                    decoration: InputDecoration(
                      labelText: l10n.password,
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        onPressed: loading ? null : () => setState(() => _showPass = !_showPass),
                        icon: Icon(
                          _showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        ),
                      ),
                    ),
                    onChanged: (_) => _clearErrorIfAny(),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return l10n.requiredField;
                      if (t.length < 6) return l10n.minPassword;
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: !_showConfirm,
                    textInputAction: TextInputAction.done,
                    enabled: !loading,
                    decoration: InputDecoration(
                      labelText: l10n.confirmPassword,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: loading ? null : () => setState(() => _showConfirm = !_showConfirm),
                        icon: Icon(
                          _showConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        ),
                      ),
                    ),
                    onChanged: (_) => _clearErrorIfAny(),
                    onFieldSubmitted: (_) => loading ? null : _submit(),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return l10n.requiredField;
                      if (t != passCtrl.text.trim()) return l10n.passwordsDoNotMatch;
                      return null;
                    },
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: loading
                          ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : Text(
                        l10n.linkEmailButton,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  TextButton(
                    onPressed: loading ? null : () => Navigator.of(context).pop('skipped'),
                    child: Text(
                      l10n.skipForNow,
                      style: const TextStyle(color: kTextSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}