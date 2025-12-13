// lib/screens/auth/widgets/auth_register_section.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import 'auth_avatar_picker.dart';

class AuthRegisterSection extends StatelessWidget {
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final String birthdayLabel;
  final String gender;
  final bool isSubmitting;

  final Uint8List? imageBytes;
  final File? imageFile;
  final VoidCallback onPickImage;

  // Upload (optional)
  final bool isUploading;
  final double uploadProgress;
  final VoidCallback? onRemoveImage;

  final VoidCallback onPickBirthday;
  final ValueChanged<String> onGenderChanged;

  final bool agreedToTerms;
  final ValueChanged<bool> onAgreeChanged;
  final VoidCallback onViewTerms;

  const AuthRegisterSection({
    super.key,
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.birthdayLabel,
    required this.gender,
    required this.isSubmitting,
    required this.imageBytes,
    required this.imageFile,
    required this.onPickImage,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.onRemoveImage,
    required this.onPickBirthday,
    required this.onGenderChanged,
    required this.agreedToTerms,
    required this.onAgreeChanged,
    required this.onViewTerms,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AuthAvatarPicker(
          imageBytes: imageBytes,
          imageFile: imageFile,
          isSubmitting: isSubmitting,
          onPickImage: onPickImage,
          isUploading: isUploading,
          uploadProgress: uploadProgress,
          onRemoveImage: onRemoveImage,
        ),
        const SizedBox(height: 12),

        _buildPickImageButton(context, l10n),
        const SizedBox(height: 24),

        Row(
          textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Expanded(
              child: _buildTextField(
                controller: firstNameCtrl,
                label: l10n.firstName,
                focusColor: kGoldDeep,
                isRTL: isRTL,
                requiredError: l10n.requiredField,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTextField(
                controller: lastNameCtrl,
                label: l10n.lastName,
                focusColor: kPrimaryGold,
                isRTL: isRTL,
                requiredError: l10n.requiredField,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        _buildLabel(theme, '${l10n.birthday} ${l10n.optional}'),
        const SizedBox(height: 6),
        _buildBirthdayButton(l10n),

        const SizedBox(height: 20),

        _buildLabel(theme, '${l10n.gender} ${l10n.optional}'),
        const SizedBox(height: 8),
        _buildGenderChips(l10n, isRTL),

        const SizedBox(height: 24),

        _buildTermsAcceptance(l10n),
      ],
    );
  }

  // -----------------------
  // PICK IMAGE BUTTON (GOLD + BLACK TEXT)
  // -----------------------
  Widget _buildPickImageButton(BuildContext context, AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isSubmitting
            ? null
            : () async {
          try {
            await Future<void>.sync(onPickImage);
          } catch (e, st) {
            debugPrint('[AuthRegisterSection] onPickImage error: $e\n$st');
          }
        },
        icon: const Icon(Icons.photo_outlined, color: Colors.black), // ✅ BLACK
        label: Text(
          l10n.choosePicture,
          style: const TextStyle(
            color: Colors.black, // ✅ BLACK
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryGold,
          foregroundColor: Colors.black, // ✅ ensures icon/text default black too
          elevation: 6,
          shadowColor: kGoldDeep.withOpacity(0.3),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required Color focusColor,
    required bool isRTL,
    required String requiredError,
  }) {
    return TextFormField(
      controller: controller,
      textAlign: isRTL ? TextAlign.right : TextAlign.left,
      style: const TextStyle(color: Colors.white),
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
      ),
      validator: (v) => v == null || v.trim().isEmpty ? requiredError : null,
    );
  }

  Widget _buildLabel(ThemeData theme, String text) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: kTextSecondary,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildBirthdayButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: isSubmitting
            ? null
            : () async {
          try {
            await Future<void>.sync(onPickBirthday);
          } catch (e, st) {
            debugPrint('[AuthRegisterSection] _pickBirthday error: $e\n$st');
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                kSurfaceAltColor.withOpacity(0.8),
                kSurfaceColor.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: kGoldDeep.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.cake_outlined, color: kTextSecondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  birthdayLabel,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Icon(Icons.calendar_today_outlined,
                  color: kTextSecondary, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------
  // GENDER CHIPS (SELECTED GOLD => BLACK TEXT)
  // -----------------------
  Widget _buildGenderChips(AppLocalizations l10n, bool isRTL) {
    return Wrap(
      alignment: isRTL ? WrapAlignment.end : WrapAlignment.start,
      spacing: 10,
      runSpacing: 8,
      children: [
        _genderOption(
          label: l10n.male,
          selected: gender == 'male',
          color: kPrimaryGold,
          icon: Icons.male,
          onTap: () => onGenderChanged('male'),
        ),
        _genderOption(
          label: l10n.female,
          selected: gender == 'female',
          color: kGoldDeep,
          icon: Icons.female,
          onTap: () => onGenderChanged('female'),
        ),
        _genderOption(
          label: l10n.preferNotToSay,
          selected: gender == 'none',
          color: Colors.grey,
          icon: Icons.remove_circle_outline,
          onTap: () => onGenderChanged('none'),
        ),
      ],
    );
  }

  Widget _genderOption({
    required String label,
    required bool selected,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // Gold chips look best with black when selected; grey chip can stay white.
    final bool wantsBlackOnSelected =
        selected && (color == kPrimaryGold || color == kGoldDeep);

    final Color selectedTextColor =
    wantsBlackOnSelected ? Colors.black : Colors.white;

    return GestureDetector(
      onTap: isSubmitting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
            colors: [
              color.withOpacity(0.98),
              color.withOpacity(0.82),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: selected ? null : kSurfaceAltColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? color.withOpacity(0.55)
                : Colors.white.withOpacity(0.2),
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? selectedTextColor : kTextSecondary, // ✅
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? selectedTextColor : kTextSecondary, // ✅
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------
  // TERMS (GOLD CHECK + BLACK CHECKMARK)
  // -----------------------
  Widget _buildTermsAcceptance(AppLocalizations l10n) {
    return Row(
      children: [
        Checkbox(
          value: agreedToTerms,
          activeColor: kPrimaryGold,
          checkColor: Colors.black, // ✅ BLACK check mark
          side: BorderSide(color: Colors.white.withOpacity(0.5)),
          onChanged: isSubmitting ? null : (v) => onAgreeChanged(v ?? false),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onViewTerms,
            child: Text.rich(
              TextSpan(
                text: l10n.iAgreeTo,
                style: const TextStyle(color: kTextSecondary),
                children: [
                  TextSpan(
                    text: " ${l10n.termsOfUse}",
                    style: const TextStyle(
                      color: kGoldDeep,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w700,
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
