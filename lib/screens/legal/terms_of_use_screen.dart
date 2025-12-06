// lib/screens/legal/terms_of_use_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  static const String _appVersion = 'v1.0';
  static const String _websiteUrl = 'https://www.mwchats.com';

  Future<void> _openMwWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildFooter(
      BuildContext context,
      AppLocalizations l10n, {
        required bool isWide,
      }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      fontSize: 11,
    );
    final versionStyle = textStyle?.copyWith(
      color: Colors.white38,
    );

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
          Text(
            l10n.appBrandingBeta,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
          Text(
            _appVersion,
            style: versionStyle,
            textAlign: TextAlign.center,
          ),
          InkWell(
            onTap: () => _openMwWebsite(),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isWide = width >= 900;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.termsOfUse,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(false),
        )
            : null,
      ),
      body: MwBackground(
        child: SafeArea(
          top: false, // AppBar already covers the top
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // ==== BODY: same outer layout as Home/Profile ====
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isWide ? 16 : 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.40),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints:
                            const BoxConstraints(maxWidth: 640),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.termsOfUse,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l10n.termsBody,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                                const SizedBox(height: 32),
                                Center(
                                  child: SizedBox(
                                    width: 260,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kSecondaryAmber,
                                        foregroundColor: Colors.black,
                                        padding:
                                        const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(20),
                                        ),
                                        elevation: 3,
                                      ),
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: Text(
                                        l10n.iAgree,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // ==== FOOTER (same style as Home/Profile) ====
                  _buildFooter(context, l10n, isWide: isWide),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
