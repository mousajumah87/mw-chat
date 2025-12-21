import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

class ProfileDangerZoneSection extends StatelessWidget {
  final bool isRtl;
  final bool deletingAccount;
  final VoidCallback onDeletePressed;

  const ProfileDangerZoneSection({
    super.key,
    required this.isRtl,
    required this.deletingAccount,
    required this.onDeletePressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            l10n.dangerZone,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            l10n.deleteAccountDescription,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.delete_forever),
            label: Text(
              deletingAccount ? l10n.deletingAccount : l10n.deleteMyAccount,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
            onPressed: deletingAccount ? null : onDeletePressed,
          ),
        ),
      ],
    );
  }
}
