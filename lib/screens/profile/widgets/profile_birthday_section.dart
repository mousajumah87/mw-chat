// lib/screens/profile/widgets/profile_birthday_section.dart

import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

class ProfileBirthdaySection extends StatelessWidget {
  final DateTime? birthday;
  final bool saving;
  final bool isRtl;
  final TextDirection textDirection;
  final VoidCallback onPickBirthday;

  const ProfileBirthdaySection({
    super.key,
    required this.birthday,
    required this.saving,
    required this.isRtl,
    required this.textDirection,
    required this.onPickBirthday,
  });

  String _birthdayLabel(AppLocalizations l10n) {
    if (birthday == null) return l10n.selectBirthday;
    return '${birthday!.year}-${birthday!.month.toString().padLeft(2, '0')}-${birthday!.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            '${l10n.birthday} ${l10n.optional}',
            textDirection: textDirection,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: saving ? null : onPickBirthday,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withOpacity(0.3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          ),
          child: Row(
            textDirection: textDirection,
            children: [
              const Icon(Icons.cake_outlined, color: Colors.white70),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _birthdayLabel(l10n),
                  style: const TextStyle(color: Colors.white),
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
