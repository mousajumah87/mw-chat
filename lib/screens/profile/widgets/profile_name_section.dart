import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

class ProfileNameSection extends StatelessWidget {
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;

  const ProfileNameSection({
    super.key,
    required this.firstNameCtrl,
    required this.lastNameCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: firstNameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: l10n.firstName),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: lastNameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: l10n.lastName),
          ),
        ),
      ],
    );
  }
}
