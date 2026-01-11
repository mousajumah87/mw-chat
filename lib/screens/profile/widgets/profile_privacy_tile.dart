// lib/screens/profile/widgets/profile_privacy_tile.dart
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
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final title = (l10n.onlineStatusTitle.isNotEmpty)
        ? l10n.onlineStatusTitle
        : 'Privacy & visibility';

    final subtitle = (l10n.onlineStatusSubtitle.isNotEmpty)
        ? l10n.onlineStatusSubtitle
        : 'Online status, profile visibility, email visibility';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                color: kPrimaryGold.withOpacity(0.95),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: kTextPrimary.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kTextSecondary.withOpacity(0.95),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.65),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
