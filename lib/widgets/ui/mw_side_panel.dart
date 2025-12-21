// lib/widgets/ui/mw_side_panel.dart
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

class MwSidePanel extends StatelessWidget {
  const MwSidePanel({
    super.key,
    this.flat = false,
    this.embedded = false,
  });

  /// ✅ When true: match About/Invite flat card language (NO blur/glow)
  /// When false: keep your premium glass blur style
  final bool flat;

  /// ✅ When true: this widget is placed INSIDE another scroll view (page scroll),
  /// so it should NOT create its own scrolling or width constraints.
  final bool embedded;

  static const String _websiteUrl = 'https://mwchats.com';

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) debugPrint('Could not launch $url');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    const r = 26.0;
    final radius = BorderRadius.circular(r);
    final double blurSigma = kIsWeb ? 12 : 14;

    Widget content() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(theme, l10n),
            const SizedBox(height: 12),

            _divider(flat: flat),
            const SizedBox(height: 14),

            _sectionTitle(
              theme: theme,
              text: l10n.sidePanelFeatureTitle,
              isRtl: isRtl,
            ),
            const SizedBox(height: 10),

            _featureRow(context, text: l10n.sidePanelFeaturePrivate, isRtl: isRtl),
            const SizedBox(height: 8),
            _featureRow(context, text: l10n.sidePanelFeatureStatus, isRtl: isRtl),
            const SizedBox(height: 8),
            _featureRow(context, text: l10n.sidePanelFeatureInvite, isRtl: isRtl),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: flat ? _miniFlatCard() : _miniGlassCard(),
              child: Text(
                l10n.sidePanelTip,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: kOffWhite.withOpacity(0.82),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
            ),

            const SizedBox(height: 16),

            _sectionTitle(
              theme: theme,
              text: l10n.sidePanelFollowTitle,
              isRtl: isRtl,
            ),
            const SizedBox(height: 10),

            // ✅ NEW: centered icon row (better than chips, perfect for RTL/LTR)
            Center(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _followIcon(
                    context,
                    icon: Icons.public_rounded,
                    label: l10n.website,
                    onTap: () => _openUrl(_websiteUrl),
                    highlight: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget flatPanel() {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: radius,
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: content(),
        ),
      );
    }

    Widget glassPanel() {
      return ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.15,
                    colors: [
                      kPrimaryGold.withOpacity(0.18),
                      kGoldDeep.withOpacity(0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Container(
                decoration: BoxDecoration(
                  color: kSurfaceAltColor.withOpacity(0.62),
                  borderRadius: radius,
                  border: Border.all(color: kBorderColor.withOpacity(0.95)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.68),
                      blurRadius: 46,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: kGoldDeep.withOpacity(0.10),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.all(0.6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(r - 0.6),
                            border: Border.all(
                              color: kPrimaryGold.withOpacity(0.16),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.all(1.4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(r - 1.4),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                kOffWhite.withOpacity(0.14),
                                Colors.transparent,
                                Colors.transparent,
                                kGoldDeep.withOpacity(0.05),
                              ],
                              stops: const [0.0, 0.32, 0.72, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      top: 12,
                      child: IgnorePointer(
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                kOffWhite.withOpacity(0.12),
                                kPrimaryGold.withOpacity(0.22),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    content(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final panel = flat ? flatPanel() : glassPanel();

    if (embedded) return RepaintBoundary(child: panel);

    final width = MediaQuery.of(context).size.width;
    final maxPanelWidth = width > 600 ? 540.0 : width * 0.92;

    return RepaintBoundary(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxPanelWidth),
          child: panel,
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, AppLocalizations l10n) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kSurfaceColor.withOpacity(0.78),
            border: Border.all(color: kPrimaryGold.withOpacity(0.26), width: 1),
            boxShadow: [
              BoxShadow(
                color: kGoldDeep.withOpacity(0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            Icons.person_add_alt_1_rounded,
            color: kPrimaryGold.withOpacity(0.95),
            size: 22,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.sidePanelAppName,
          style: theme.textTheme.titleMedium?.copyWith(
            color: kTextPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 0.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          l10n.sidePanelTagline,
          style: theme.textTheme.bodySmall?.copyWith(
            color: kTextSecondary.withOpacity(0.95),
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _divider({required bool flat}) {
    if (flat) return Container(height: 1, color: Colors.white.withOpacity(0.14));
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            kBorderColor.withOpacity(0.95),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  BoxDecoration _miniGlassCard() {
    return BoxDecoration(
      color: kSurfaceColor.withOpacity(0.42),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kBorderColor.withOpacity(0.75), width: 1),
      boxShadow: [
        BoxShadow(
          color: kGoldDeep.withOpacity(0.06),
          blurRadius: 16,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  BoxDecoration _miniFlatCard() {
    return BoxDecoration(
      color: kSurfaceAltColor.withOpacity(0.55),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
    );
  }

  Widget _sectionTitle({
    required ThemeData theme,
    required String text,
    required bool isRtl,
  }) {
    return Align(
      alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: 14.5,
          fontWeight: FontWeight.w900,
          color: kTextPrimary,
          letterSpacing: 0.15,
        ),
        textAlign: isRtl ? TextAlign.right : TextAlign.left,
      ),
    );
  }

  Widget _featureRow(
      BuildContext context, {
        required String text,
        required bool isRtl,
      }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kAccentColor.withOpacity(0.14),
            border: Border.all(color: kAccentColor.withOpacity(0.35), width: 1),
          ),
          child: Icon(Icons.check_rounded, size: 16, color: kAccentColor.withOpacity(0.95)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: kOffWhite.withOpacity(0.90),
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
          ),
        ),
      ],
    );
  }

  // ✅ NEW: follow icon style (same MW look as Invite icons)
  Widget _followIcon(
      BuildContext context, {
        required IconData icon,
        required String label,
        required VoidCallback onTap,
        bool highlight = false,
      }) {
    final r = BorderRadius.circular(999);

    final baseBorder = highlight
        ? kPrimaryGold.withOpacity(0.28)
        : Colors.white.withOpacity(0.14);

    final bg = highlight
        ? kPrimaryGold.withOpacity(0.10)
        : kSurfaceAltColor.withOpacity(0.55);

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: r,
              color: bg,
              border: Border.all(color: baseBorder, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: kPrimaryGold.withOpacity(0.95),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: kOffWhite.withOpacity(0.92),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
