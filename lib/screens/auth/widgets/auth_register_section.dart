import 'dart:io';
import 'dart:typed_data';
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
  final VoidCallback onPickBirthday;
  final ValueChanged<String> onGenderChanged;

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
    required this.onPickBirthday,
    required this.onGenderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // === Avatar Picker ===
        AuthAvatarPicker(
          imageBytes: imageBytes,
          imageFile: imageFile,
          isSubmitting: isSubmitting,
          onPickImage: onPickImage,
        ),
        const SizedBox(height: 12),

        // Choose Picture
        _buildPickImageButton(l10n),
        const SizedBox(height: 20),

        // === Name Fields (lightweight row rebuild) ===
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: firstNameCtrl,
                label: l10n.firstName,
                focusColor: kSecondaryAmber,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTextField(
                controller: lastNameCtrl,
                label: l10n.lastName,
                focusColor: kPrimaryBlue,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // === Birthday ===
        _buildLabel(theme, l10n.birthday),
        const SizedBox(height: 6),
        _buildBirthdayButton(l10n),

        const SizedBox(height: 20),

        // === Gender Selection (optional) ===
        _buildLabel(theme, '${l10n.gender} (optional)'),
        const SizedBox(height: 8),
        _buildGenderChips(l10n),
        const SizedBox(height: 20),
      ],
    );
  }

  // ===== UI Helpers =====

  Widget _buildPickImageButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isSubmitting ? null : onPickImage,
        icon: const Icon(Icons.photo_outlined, color: Colors.black),
        label: Text(
          l10n.choosePicture,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required Color focusColor,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: focusColor, width: 1.3),
        ),
      ),
      validator: (v) =>
      v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _buildLabel(ThemeData theme, String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: Colors.white70, fontSize: 13),
      ),
    );
  }

  Widget _buildBirthdayButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isSubmitting ? null : onPickBirthday,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white.withOpacity(0.07),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cake_outlined, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  birthdayLabel,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Icon(Icons.calendar_today_outlined,
                  color: Colors.white54, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderChips(AppLocalizations l10n) {
    // Wrap instead of Row so 3 chips fit nicely on small screens
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        _genderOption(
          label: l10n.male,
          selected: gender == 'male',
          color: kPrimaryBlue,
          icon: Icons.male,
          onTap: () => onGenderChanged('male'),
        ),
        _genderOption(
          label: l10n.female,
          selected: gender == 'female',
          color: kSecondaryAmber,
          icon: Icons.female,
          onTap: () => onGenderChanged('female'),
        ),
        // Optional choice – maps to 'none' in AuthScreen
        _genderOption(
          label: 'Prefer not to say',
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
    return GestureDetector(
      onTap: isSubmitting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.transparent : Colors.white.withOpacity(0.3),
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10)]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
