// lib/screens/auth/widgets/auth_register_section.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class AuthRegisterSection extends StatelessWidget {
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final bool isSubmitting;

  final bool agreedToTerms;
  final ValueChanged<bool> onAgreeChanged;
  final VoidCallback onViewTerms;

  const AuthRegisterSection({
    super.key,
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.isSubmitting,
    required this.agreedToTerms,
    required this.onAgreeChanged,
    required this.onViewTerms,
  });

  static const int _nameMinLen = 2;
  static const int _nameMaxLen = 30;

  static final RegExp _allowedNameChars = RegExp(
    r"^[A-Za-z\u00C0-\u024F\u1E00-\u1EFF"
    r"\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF"
    r" '\-’]+$",
  );

  static final RegExp _nameStructureOk = RegExp(
    r"^(?!.*[ '\-’]{2})"
    r"[A-Za-z\u00C0-\u024F\u1E00-\u1EFF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]"
    r"(?:[A-Za-z\u00C0-\u024F\u1E00-\u1EFF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]|[ '\-’](?=[A-Za-z\u00C0-\u024F\u1E00-\u1EFF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]))*"
    r"$",
  );

  static final RegExp _multiSpace = RegExp(r"\s{2,}");
  static final RegExp _leadingSpace = RegExp(r"^\s+");

  String? _validateName(
      AppLocalizations l10n, {
        required String? value,
        required String requiredError,
      }) {
    final raw = value ?? '';
    final v = raw.trim();

    if (v.isEmpty) return requiredError;

    if (v.length < _nameMinLen) {
      return l10n.minLengthError(_nameMinLen);
    }
    if (v.length > _nameMaxLen) {
      return l10n.maxLengthError(_nameMaxLen);
    }

    if (!_allowedNameChars.hasMatch(v)) {
      return l10n.invalidNameCharacters;
    }

    if (!_nameStructureOk.hasMatch(v)) {
      return l10n.invalidNameFormat;
    }

    return null;
  }

  List<TextInputFormatter> _nameInputFormatters() {
    return <TextInputFormatter>[
      LengthLimitingTextInputFormatter(_nameMaxLen),
      FilteringTextInputFormatter.allow(
        RegExp(
          r"[A-Za-z\u00C0-\u024F\u1E00-\u1EFF"
          r"\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF"
          r" '\-’]",
        ),
      ),
    ];
  }

  /// ✅ Better UX:
  /// - remove leading spaces
  /// - collapse multi-space into single
  /// - DO NOT trim trailing single space while user is typing
  void _normalizeSpaces(TextEditingController c) {
    final oldText = c.text;
    final oldSel = c.selection;

    if (oldText.isEmpty) return;

    var newText = oldText;

    newText = newText.replaceAll(_multiSpace, ' ');
    newText = newText.replaceAll(_leadingSpace, '');

    if (newText == oldText) return;

    final delta = newText.length - oldText.length;
    final base = oldSel.baseOffset;
    final extent = oldSel.extentOffset;

    int clamp(int v) => v < 0 ? 0 : (v > newText.length ? newText.length : v);

    final newBase = clamp(base + delta);
    final newExtent = clamp(extent + delta);

    c.value = c.value.copyWith(
      text: newText,
      selection: TextSelection(baseOffset: newBase, extentOffset: newExtent),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            l10n.profileDetailsHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: kTextSecondary.withOpacity(0.9),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Expanded(
              child: _buildTextField(
                l10n: l10n,
                controller: firstNameCtrl,
                label: l10n.firstName,
                focusColor: kGoldDeep,
                isRTL: isRTL,
                requiredError: l10n.requiredField,
                autofillHints: const [AutofillHints.givenName],
                textCapitalization: TextCapitalization.words,
                enabled: !isSubmitting,
                inputFormatters: _nameInputFormatters(),
                onChanged: (_) => _normalizeSpaces(firstNameCtrl),
                onEditingComplete: () => _normalizeSpaces(firstNameCtrl),
                validator: (v) => _validateName(
                  l10n,
                  value: v,
                  requiredError: l10n.requiredField,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTextField(
                l10n: l10n,
                controller: lastNameCtrl,
                label: l10n.lastName,
                focusColor: kPrimaryGold,
                isRTL: isRTL,
                requiredError: l10n.requiredField,
                autofillHints: const [AutofillHints.familyName],
                textCapitalization: TextCapitalization.words,
                enabled: !isSubmitting,
                inputFormatters: _nameInputFormatters(),
                textInputAction: TextInputAction.done,
                onChanged: (_) => _normalizeSpaces(lastNameCtrl),
                onEditingComplete: () => _normalizeSpaces(lastNameCtrl),
                validator: (v) => _validateName(
                  l10n,
                  value: v,
                  requiredError: l10n.requiredField,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _buildTermsAcceptance(l10n, isRTL),
      ],
    );
  }

  Widget _buildTextField({
    required AppLocalizations l10n,
    required TextEditingController controller,
    required String label,
    required Color focusColor,
    required bool isRTL,
    required String requiredError,
    required List<String> autofillHints,
    required TextCapitalization textCapitalization,
    required bool enabled,
    TextInputAction textInputAction = TextInputAction.next,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    VoidCallback? onEditingComplete,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      textAlign: isRTL ? TextAlign.right : TextAlign.left,
      textInputAction: textInputAction,
      keyboardType: TextInputType.name,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      style: const TextStyle(color: Colors.white),
      // ✅ Fix “error stuck” per-field too
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kTextSecondary),
        filled: true,
        fillColor: kSurfaceAltColor.withOpacity(0.7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusColor, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
      ),
      validator: validator ?? (v) => (v == null || v.trim().isEmpty) ? requiredError : null,
    );
  }

  Widget _buildTermsAcceptance(AppLocalizations l10n, bool isRTL) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 2),
          child: Checkbox(
            value: agreedToTerms,
            activeColor: kPrimaryGold,
            checkColor: Colors.black,
            side: BorderSide(color: Colors.white.withOpacity(0.5)),
            onChanged: isSubmitting ? null : (v) => onAgreeChanged(v ?? false),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            onTap: isSubmitting ? null : onViewTerms,
            child: Text.rich(
              TextSpan(
                text: l10n.iAgreeTo,
                style: const TextStyle(
                  color: kTextSecondary,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  TextSpan(
                    text: " ${l10n.termsOfUse}",
                    style: const TextStyle(
                      color: kGoldDeep,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}