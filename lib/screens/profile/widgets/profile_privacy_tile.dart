import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class ProfilePrivacyTile extends StatelessWidget {
  final VoidCallback onTap;

  const ProfilePrivacyTile({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            l10n.privacySectionTitle,
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
            leading: const Icon(Icons.privacy_tip_outlined, color: Colors.white70),
            title: Text(l10n.onlineStatusTitle, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              l10n.onlineStatusSubtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            trailing: Icon(
              isRtl ? Icons.chevron_left : Icons.chevron_right,
              color: Colors.white54,
            ),
            onTap: onTap,
          ),
        ),
      ],
    );
  }
}
