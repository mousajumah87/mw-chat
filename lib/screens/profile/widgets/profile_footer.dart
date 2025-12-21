import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

class ProfileFooter extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isWide;
  final String appVersion;
  final VoidCallback onOpenWebsite;

  const ProfileFooter({
    super.key,
    required this.l10n,
    required this.isWide,
    required this.appVersion,
    required this.onOpenWebsite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      fontSize: 11,
    );
    final versionStyle = textStyle?.copyWith(color: Colors.white38);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 16 : 12,
        vertical: 8,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.appBrandingBeta, style: textStyle, textAlign: TextAlign.center),
          Text(appVersion, style: versionStyle, textAlign: TextAlign.center),
          InkWell(
            onTap: onOpenWebsite,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'mwchats.com',
                style: textStyle?.copyWith(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
