import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class MwSidePanel extends StatelessWidget {
  const MwSidePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xCC0057FF), // MW Blue
              Color(0xCCFFB300), // MW Amber
            ],
          ),
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              // ===== Header =====
              Text(
                l10n.sidePanelAppName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.sidePanelTagline,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // Mascot placeholder
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 4,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
              const SizedBox(height: 24),

              // ===== Features =====
              _sectionTitle(
                l10n.sidePanelFeatureTitle,
                isRtl,
                theme,
              ),
              const SizedBox(height: 8),
              _featureRow(
                context,
                text: l10n.sidePanelFeaturePrivate,
                isRtl: isRtl,
              ),
              const SizedBox(height: 6),
              _featureRow(
                context,
                text: l10n.sidePanelFeatureStatus,
                isRtl: isRtl,
              ),
              const SizedBox(height: 6),
              _featureRow(
                context,
                text: l10n.sidePanelFeatureInvite,
                isRtl: isRtl,
              ),

              const SizedBox(height: 16),

              // ===== Tip =====
              Align(
                alignment:
                isRtl ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  l10n.sidePanelTip,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                ),
              ),

              const SizedBox(height: 24),

              // ===== Social =====
              _sectionTitle(
                l10n.sidePanelFollowTitle,
                isRtl,
                theme,
              ),
              const SizedBox(height: 10),

              Align(
                alignment:
                isRtl ? Alignment.centerRight : Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment:
                  isRtl ? WrapAlignment.end : WrapAlignment.start,
                  children: [
                    _socialChip(
                      icon: Icons.facebook,
                      label: l10n.socialFacebook,
                      color: const Color(0xFF1778F2),
                      onTap: () {},
                    ),
                    _socialChip(
                      icon: Icons.camera_alt_outlined,
                      label: l10n.socialInstagram,
                      color: const Color(0xFFE4405F),
                      onTap: () {},
                    ),
                    _socialChip(
                      icon: Icons.alternate_email,
                      label: l10n.socialX,
                      color: const Color(0xFF1DA1F2),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, bool isRtl, ThemeData theme) {
    return Align(
      alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.white,
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
      mainAxisSize: MainAxisSize.max,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: Color(0xFF22C55E),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
          ),
        ),
      ],
    );
  }

  Widget _socialChip({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      hoverColor: Colors.white.withOpacity(0.08),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.4),
              Colors.white.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
