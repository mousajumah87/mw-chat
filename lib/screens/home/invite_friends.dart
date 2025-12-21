// lib/screens/home/invite_friends.dart
// MW Chat – Modern private messaging app
// Copyright © 2025 Mousa Abu Hilal. All rights reserved.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_side_panel.dart';

class InviteFriendsTab extends StatefulWidget {
  const InviteFriendsTab({super.key});

  @override
  State<InviteFriendsTab> createState() => _InviteFriendsTabState();
}

class _InviteFriendsTabState extends State<InviteFriendsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ✅ Keep empty if not ready → UI hides the icon automatically
  static const String _androidLink = '';
  // 'https://play.google.com/store/apps/details?id=com.mw.chat';

  // ✅ Canonical App Store link format
  static const String _iosLink = 'https://apps.apple.com/app/id6755662532';

  static const String _websiteLink = 'https://www.mwchats.com';

  // ✅ Bidi isolate markers:
  // LRI ... PDI keeps URLs consistently LTR even inside RTL Arabic UI/text.
  String _bidiIsolateLtr(String s) => '\u2066$s\u2069';

  Future<void> _shareInvite(BuildContext context, AppLocalizations l10n) async {
    final lines = <String>[
      l10n.inviteFromContactsFuture,
      '',
      l10n.inviteShareManual,
      '',
    ];

    if (_androidLink.trim().isNotEmpty) {
      lines.add(
        '${l10n.invitePlatformAndroid}: ${_bidiIsolateLtr(_androidLink)}',
      );
    }
    if (_iosLink.trim().isNotEmpty) {
      lines.add(
        '${l10n.invitePlatformIos}: ${_bidiIsolateLtr(_iosLink)}',
      );
    }
    if (_websiteLink.trim().isNotEmpty) {
      lines.add(
        '${l10n.invitePlatformWeb}: ${_bidiIsolateLtr(_websiteLink)}',
      );
    }

    final message = lines.join('\n');

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 40);
    }

    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);

    await Share.share(
      message,
      subject: l10n.inviteFriendsTitle,
      sharePositionOrigin: origin,
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _headerBadge() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kSurfaceColor.withOpacity(0.80),
        border: Border.all(
          color: Colors.white.withOpacity(0.20),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        Icons.group_add_rounded,
        color: kPrimaryGold.withOpacity(0.95),
        size: 44,
      ),
    );
  }

  // ✅ Small reusable icon button (MW style, cross-platform)
  Widget _platformIconButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required String url,
    bool highlight = false,
  }) {
    if (url.trim().isEmpty) return const SizedBox.shrink();

    final r = BorderRadius.circular(999);
    final theme = Theme.of(context);

    final baseBorder = highlight
        ? kPrimaryGold.withOpacity(0.28)
        : Colors.white.withOpacity(0.14);

    final bg = highlight
        ? kPrimaryGold.withOpacity(0.10)
        : kSurfaceAltColor.withOpacity(0.55);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: () => _openUrl(url),
          child: Ink(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: r,
              color: bg,
              border: Border.all(color: baseBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 24,
              color: highlight
                  ? kPrimaryGold.withOpacity(0.95)
                  : theme.colorScheme.onSurface.withOpacity(0.92),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ Centered icon row that works perfectly for RTL/LTR
  Widget _quickLinksIcons(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    final items = <Widget>[
      // Android (hidden when empty)
      _platformIconButton(
        context: context,
        icon: Icons.android_rounded,
        tooltip: l10n.invitePlatformAndroid,
        url: _androidLink,
      ),
      // iOS
      _platformIconButton(
        context: context,
        icon: Icons.apple_rounded,
        tooltip: l10n.invitePlatformIos,
        url: _iosLink,
      ),
      // Website (highlight)
      _platformIconButton(
        context: context,
        icon: Icons.public_rounded,
        tooltip: l10n.invitePlatformWeb,
        url: _websiteLink,
        highlight: true,
      ),
    ].where((w) => w is! SizedBox).toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceAltColor.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: kBorderColor.withOpacity(0.55),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            l10n.invitePlatformTitle, // If you don’t have this key, it will fail.
            // ✅ Safe fallback if you don't have invitePlatformTitle:
            // l10n.inviteShareManual,
            style: theme.textTheme.titleSmall?.copyWith(
              color: kTextPrimary,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: items,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.tapIconToOpen, // If you don’t have this key, it will fail.
            // ✅ Safe fallback if you don't have tapIconToOpen:
            // l10n.websiteDomain,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white54,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _inviteMainCard(
      BuildContext context,
      AppLocalizations l10n, {
        required bool isWide,
      }) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isWide ? 32 : 16,
        vertical: 8,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 48 : 24,
        vertical: 32,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _headerBadge()),
          const SizedBox(height: 18),
          Center(
            child: Text(
              l10n.inviteFriendsTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: kTextPrimary,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.inviteFromContactsFuture,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.6,
            ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.inviteShareManual,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.6,
            ),
            textAlign: TextAlign.start,
          ),

          const SizedBox(height: 22),
          Divider(color: Colors.white.withOpacity(0.20)),
          const SizedBox(height: 14),

          Builder(
            builder: (buttonContext) {
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _shareInvite(buttonContext, l10n),
                  icon: const Icon(Icons.share_rounded),
                  label: Text(l10n.inviteFriendsTitle),
                ),
              );
            },
          ),

          // ✅ NEW: Icon row instead of link rows
          const SizedBox(height: 12),
          _quickLinksIcons(context, theme, l10n),

          const SizedBox(height: 16),
          Center(
            child: Text(
              l10n.websiteDomain,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
          l10n.inviteFriendsTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
      ),
      body: MwBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 1000 : 900),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  children: [
                    const SizedBox(height: 12),

                    // ✅ Top: Invite card
                    _inviteMainCard(context, l10n, isWide: isWide),

                    const SizedBox(height: 12),

                    // ✅ Below: merged “panel” content as a section card
                    // Padding(
                    //   padding: EdgeInsets.symmetric(
                    //     horizontal: isWide ? 32 : 16,
                    //   ),
                    //   child: const MwSidePanel(
                    //     flat: true,
                    //     embedded: true,
                    //   ),
                    // ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
