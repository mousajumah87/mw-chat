// lib/screens/profile/widgets/profile_legal_section.dart

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

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool showChevron = true,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: kPrimaryGold.withOpacity(0.95)),
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
                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kTextSecondary.withOpacity(0.95),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron)
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

  Widget _divider() => Divider(
    height: 1,
    thickness: 1,
    color: Colors.white.withOpacity(0.06),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final termsTitle =
    (l10n.termsOfUse.isNotEmpty) ? l10n.termsOfUse : 'Terms of Use';

    final contactTitle =
    (l10n.contactSupport.isNotEmpty) ? l10n.contactSupport : 'Contact support';

    final contactSubtitle = (l10n.contactSupportSubtitle.isNotEmpty)
        ? l10n.contactSupportSubtitle
        : 'support@mwchats.com';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tile(
          context: context,
          icon: Icons.gavel_outlined,
          title: termsTitle,
          onTap: onOpenTerms,
        ),
        _divider(),
        _tile(
          context: context,
          icon: Icons.mail_outline,
          title: contactTitle,
          subtitle: contactSubtitle,
          onTap: null, // read-only (no tap) unless you want to email-launch
          showChevron: false,
        ),
      ],
    );
  }
}
