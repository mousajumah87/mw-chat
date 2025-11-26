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
        // === Profile picture ===
        AuthAvatarPicker(
          imageBytes: imageBytes,
          imageFile: imageFile,
          isSubmitting: isSubmitting,
          onPickImage: onPickImage,
        ),
        const SizedBox(height: 14),

        // Choose Picture Button
        ElevatedButton.icon(
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
            elevation: 6,
            shadowColor: Colors.black.withOpacity(0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),

        const SizedBox(height: 26),

        // === Name fields ===
        Row(
          children: [
            Expanded(child: _buildTextField(
              controller: firstNameCtrl,
              label: l10n.firstName,
              focusColor: kSecondaryAmber,
              validator: (v) => v == null || v.trim().isEmpty
                  ? l10n.requiredField
                  : null,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildTextField(
              controller: lastNameCtrl,
              label: l10n.lastName,
              focusColor: kPrimaryBlue,
              validator: (v) => v == null || v.trim().isEmpty
                  ? l10n.requiredField
                  : null,
            )),
          ],
        ),
        const SizedBox(height: 20),

        // === Birthday ===
        _buildLabel(theme, l10n.birthday),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: isSubmitting ? null : onPickBirthday,
            icon: const Icon(Icons.cake_outlined,
                size: 18, color: Colors.white70),
            label: Text(
              birthdayLabel,
              style: const TextStyle(color: Colors.white),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withOpacity(0.25)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              backgroundColor: Colors.white.withOpacity(0.05),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // === Gender ===
        _buildLabel(theme, l10n.gender),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          children: [
            _genderChip(
              label: l10n.male,
              selected: gender == 'male',
              color: kPrimaryBlue,
              icon: Icons.male,
              onTap: () => onGenderChanged('male'),
            ),
            _genderChip(
              label: l10n.female,
              selected: gender == 'female',
              color: kSecondaryAmber,
              icon: Icons.female,
              onTap: () => onGenderChanged('female'),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // === Helper Widgets ===

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required Color focusColor,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusColor, width: 1.4),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildLabel(ThemeData theme, String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style:
        theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
      ),
    );
  }

  Widget _genderChip({
    required String label,
    required bool selected,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: selected ? Colors.black : Colors.white70),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: selected,
      selectedColor: color,
      backgroundColor: Colors.white.withOpacity(0.08),
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white70,
        fontWeight: FontWeight.w500,
      ),
      onSelected: (_) => onTap(),
      elevation: selected ? 6 : 0,
      shadowColor: selected ? Colors.black.withOpacity(0.4) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
