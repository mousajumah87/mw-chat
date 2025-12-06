// lib/screens/about/about_screen.dart
// MW Chat – Modern private messaging app
// Copyright © 2025 Mousa Abu Hilal. All rights reserved.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/ui/mw_background.dart';
import '../legal/terms_of_use_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _appVersion = 'v1.0';
  static const String _websiteUrl = 'https://www.mwchats.com';
  static const String _supportEmail = 'support@mwchats.com';

  Future<void> _openMwWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openSupportEmail() async {
    final uri = Uri.parse('mailto:$_supportEmail');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildFooter(
      BuildContext context,
      AppLocalizations l10n, {
        required bool isWide,
      }) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      fontSize: 11,
    );
    final versionStyle = base?.copyWith(color: Colors.white38);

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
          Text(l10n.appBrandingBeta, style: base),
          Text(_appVersion, style: versionStyle),
          InkWell(
            onTap: _openMwWebsite,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'mwchats.com',
                style: base?.copyWith(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w500,
                ),
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
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.mainTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        )
            : null,
      ),
      body: MwBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // ===== MAIN GLASS CARD =====
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 16,
                        vertical: 8,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(0.10),
                                  Colors.white.withOpacity(0.02),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.45),
                                  blurRadius: 28,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.symmetric(
                                horizontal: isWide ? 48 : 24,
                                vertical: 40,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // === LOGO ===
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.8, end: 1.0),
                                    duration:
                                    const Duration(milliseconds: 1500),
                                    curve: Curves.easeInOut,
                                    builder: (context, scale, child) {
                                      return Transform.scale(
                                          scale: scale, child: child);
                                    },
                                    child: Container(
                                      width: 110,
                                      height: 110,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [
                                            Color(0x80256EFF),
                                            Color(0x80FFB300),
                                            Colors.transparent,
                                          ],
                                          stops: [0.3, 0.8, 1.0],
                                        ),
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 88,
                                          height: 88,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.black,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.5),
                                                blurRadius: 20,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: ClipOval(
                                              child: Image.asset(
                                                'assets/logo/mw_mark.png',
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  Text(
                                    l10n.mainTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),

                                  const SizedBox(height: 8),

                                  Text(
                                    l10n.aboutDescription.split('\n').first,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.white70),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 26),

                                  Text(
                                    l10n.aboutDescription,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white),
                                  ),

                                  const SizedBox(height: 30),
                                  Divider(
                                      color:
                                      Colors.white.withOpacity(0.2)),
                                  const SizedBox(height: 14),

                                  // === LEGAL ===
                                  Text(
                                    l10n.legalTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.copyrightText,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.white70),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 18),

                                  // ✅ CENTERED + CLICKABLE SUPPORT EMAIL ✅
                                  Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        l10n.contactSupport,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      InkWell(
                                        onTap: _openSupportEmail,
                                        borderRadius:
                                        BorderRadius.circular(8),
                                        child: Text(
                                          _supportEmail,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                            color: Colors.lightBlueAccent,
                                            decoration:
                                            TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 18),

                                  // === TERMS BUTTON ===
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(
                                          Icons.gavel_outlined),
                                      label: Text(l10n.termsTitle),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                            const TermsOfUseScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ===== FOOTER =====
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
