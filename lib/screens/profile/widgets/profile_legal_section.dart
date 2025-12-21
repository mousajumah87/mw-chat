import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class ProfileLegalSection extends StatelessWidget {
  final bool isRtl;
  final VoidCallback onOpenTerms;

  const ProfileLegalSection({
    super.key,
    required this.isRtl,
    required this.onOpenTerms,
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
            l10n.legalTitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorderColor),
          ),
          child: ListTile(
            leading: const Icon(Icons.gavel_outlined, color: Colors.white70),
            title: Text(l10n.termsTitle, style: const TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: onOpenTerms,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorderColor),
          ),
          child: ListTile(
            leading: const Icon(Icons.mail_outline, color: Colors.white70),
            title: Text(l10n.contactSupport, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              l10n.contactSupportSubtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
