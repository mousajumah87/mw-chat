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

  Future<void> _shareInvite(AppLocalizations l10n) async {
    final message = "${l10n.inviteFromContactsFuture}\n\n"
        "${l10n.inviteShareManual}\n\n"
        "Android: $_androidLink\n"
        "iOS: $_iosLink";

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 40);
    }

    await Share.share(message, subject: l10n.inviteFriendsTitle);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;

    // ===== Core content shown on ALL platforms =====
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.group_add_outlined, color: Colors.white, size: 40),
        const SizedBox(height: 16),

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

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.inviteFromContactsFuture,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.inviteShareManual,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: 240,
          child: ElevatedButton.icon(
            onPressed: () => _shareInvite(l10n),
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
          ),
        ),

        const SizedBox(height: 24),

        Text(
          _websiteLink,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            decoration: TextDecoration.underline,
          ),
        ),
      ],
    );

    // ===== Layout (mobile / web / desktop) =====
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
                children: const [
                  SizedBox(height: 8),
                  // Centered invite content
                  Center(child: _InviteContentWrapper()),
                  SizedBox(height: 16),
                  // MW side panel below, scrollable with everything
                  RepaintBoundary(child: MwSidePanel()),
                  SizedBox(height: 8),
                ],
              ),
            ),
          );
        }

        // ---- DESKTOP / WIDE ----
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: content,
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

/// Small wrapper so we can reuse the same `content` without rebuilding layout logic.
class _InviteContentWrapper extends StatelessWidget {
  const _InviteContentWrapper();

  @override
  Widget build(BuildContext context) {
    final state =
    context.findAncestorStateOfType<_InviteFriendsTabState>()!;
    final l10n = AppLocalizations.of(context)!;

    // Reuse the "content" built above via a helper method
    return state._buildCoreContent(l10n);
  }
}

extension on _InviteFriendsTabState {
  // Re-expose the core content so _InviteContentWrapper can use it.
  Widget _buildCoreContent(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.group_add_outlined, color: Colors.white, size: 40),
        const SizedBox(height: 16),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.inviteFromContactsFuture,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.inviteShareManual,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 240,
          child: ElevatedButton.icon(
            onPressed: () => _shareInvite(l10n),
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
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          _InviteFriendsTabState._websiteLink,
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            decoration: TextDecoration.underline,
          ),
        ),
      ],
    );
  }
}
