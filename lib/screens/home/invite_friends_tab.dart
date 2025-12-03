// lib/screens/home/invite_friends_tab.dart

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';

import '../../l10n/app_localizations.dart';
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

  static const String _androidLink =
      'https://play.google.com/store/apps/details?id=com.mw.chat';
  static const String _iosLink =
      'https://apps.apple.com/app/id1234567890'; // TODO: replace with real App Store ID
  static const String _websiteLink = 'https://www.mwchats.com';

  Future<void> _shareInvite(BuildContext context, AppLocalizations l10n) async {
    final message = "${l10n.inviteFromContactsFuture}\n\n"
        "${l10n.inviteShareManual}\n\n"
        "Android: $_androidLink\n"
        "iOS: $_iosLink\n";
    _websiteLink;

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 40);
    }

    // Make sure the share sheet has a valid source rect on iPad
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

  Widget _buildCoreContent(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.group_add_outlined, color: Colors.white, size: 40),
        const SizedBox(height: 16),

        // Title
        Text(
          l10n.inviteFriendsTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        // Future contacts feature text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.inviteFromContactsFuture,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 8),

        // Manual share text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.inviteShareManual,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 20),

        // Invite button
        SizedBox(
          width: 240,
          child: Builder(
            // Use a Builder so we get a context attached to this button for sharePositionOrigin
            builder: (buttonContext) {
              return ElevatedButton.icon(
                onPressed: () => _shareInvite(buttonContext, l10n),
                icon: const Icon(Icons.share, color: Colors.black),
                label: Text(
                  l10n.inviteFriendsTitle,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Website text
        const Text(
          _websiteLink,
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            decoration: TextDecoration.underline,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;

        // ---- MOBILE / NARROW ----
        if (!isWide) {
          return SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(child: _buildCoreContent(context, l10n)),
                  const SizedBox(height: 16),
                  const RepaintBoundary(child: MwSidePanel()),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        }

        // ---- DESKTOP / WIDE / iPad landscape ----
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: _buildCoreContent(context, l10n),
                ),
              ),
            ),
            const SizedBox(width: 16),
            const Flexible(
              flex: 2,
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.only(right: 12, top: 8, bottom: 8),
                  child: RepaintBoundary(child: MwSidePanel()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
