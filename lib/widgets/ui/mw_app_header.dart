// lib/widgets/ui/mw_app_header.dart
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../screens/home/invite_friends.dart';
import '../../screens/profile/presence_privacy_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/presence_service.dart';
import '../../utils/locale_provider.dart';
import '../../screens/about/about_screen.dart';
import '../../screens/profile/profile_screen.dart';
import 'mw_language_button.dart';
import 'mw_avatar.dart';

class MwAppHeader extends StatefulWidget implements PreferredSizeWidget {
  final String? title; // kept for compatibility (not displayed)
  final bool showTabs;
  final TabBar? tabBar;

  const MwAppHeader({
    super.key,
    this.title,
    this.showTabs = false,
    this.tabBar,
  });

  @override
  Size get preferredSize => Size.fromHeight(showTabs ? 118 : 78);

  @override
  State<MwAppHeader> createState() => _MwAppHeaderState();
}

class _MwAppHeaderState extends State<MwAppHeader>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _menuEntry;
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _isMenuOpen = false;
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 170),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _isDisposing = true;
    _removeMenu(immediate: true, updateState: false);
    _controller.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (!mounted || _isDisposing) return;
    if (_isMenuOpen) {
      _removeMenu();
    } else {
      _showMenu();
    }
  }

  void _showMenu() {
    if (!mounted || _isDisposing) return;
    if (_menuEntry != null) return;

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    setState(() => _isMenuOpen = true);

    _menuEntry = OverlayEntry(
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final topPadding = media.padding.top;
        final headerHeight = widget.showTabs ? 118.0 : 78.0;

        final screenW = media.size.width;
        final maxPanelW = screenW < 420 ? screenW - 24 : 420.0;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeMenu,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                  child: Container(color: Colors.black.withOpacity(0.28)),
                ),
              ),
            ),
            PositionedDirectional(
              top: topPadding + headerHeight + 10,
              start: 12,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxPanelW),
                child: SlideTransition(
                  position: _slide,
                  child: FadeTransition(
                    opacity: _fade,
                    child: _MenuPanel(onClose: _removeMenu),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_menuEntry!);
    if (!_isDisposing) {
      _controller.forward(from: 0);
    }
  }

  Future<void> _removeMenu({
    bool immediate = false,
    bool updateState = true,
  }) async {
    if (_menuEntry == null) return;

    if (!immediate) {
      try {
        await _controller.reverse();
      } catch (_) {}
    }

    try {
      _menuEntry?.remove();
    } catch (_) {}
    _menuEntry = null;

    if (updateState && mounted && !_isDisposing) {
      setState(() => _isMenuOpen = false);
    } else {
      _isMenuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = widget.tabBar;

    return SafeArea(
      bottom: false,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: kBgColor.withOpacity(0.92),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
            border: Border.all(color: kBorderColor.withOpacity(0.60), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.50),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: kGoldDeep.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _HamburgerButton(isOpen: _isMenuOpen, onTap: _toggleMenu),
                    const Expanded(child: Center(child: _FloatingBrandLogo())),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
              if (widget.showTabs && tabBar != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: kSurfaceAltColor.withOpacity(0.58),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: kBorderColor.withOpacity(0.70),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                        ),
                        child: tabBar,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingBrandLogo extends StatelessWidget {
  const _FloatingBrandLogo();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Image.asset(
        'assets/logo/mw_mark_transparent.png',
        width: 56,
        height: 56,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _HamburgerButton extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onTap;

  const _HamburgerButton({required this.isOpen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      splashColor: kPrimaryGold.withOpacity(0.10),
      highlightColor: kPrimaryGold.withOpacity(0.06),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: kSurfaceAltColor.withOpacity(0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorderColor.withOpacity(0.70), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: Icon(
            isOpen ? Icons.close_rounded : Icons.menu_rounded,
            key: ValueKey(isOpen),
            color: kOffWhite.withOpacity(0.92),
          ),
        ),
      ),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  final Future<void> Function({bool immediate, bool updateState}) onClose;

  const _MenuPanel({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final l10n = AppLocalizations.of(context);

    Future<void> closeThen(VoidCallback action) async {
      await onClose(immediate: true, updateState: true);
      Future.microtask(() {
        if (!context.mounted) return;
        action();
      });
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: kSurfaceAltColor.withOpacity(0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kBorderColor.withOpacity(0.75), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: kGoldDeep.withOpacity(0.10),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ Language row: no overflow + consistent row sizing/alignment
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _MenuTile(
                leading: Icon(
                  Icons.language_rounded,
                  color: kOffWhite.withOpacity(0.92),
                  size: 22,
                ),
                title: '',
                isLanguageRow: true,
                trailing: MwLanguageButton(
                  onChanged: () {
                    Future.microtask(() => onClose(immediate: true, updateState: true));
                  },
                ),
                onTap: () {
                  // tapping the row does nothing now (toggle handles changes)
                  // keep it safe (avoid accidental double toggle)
                },
              ),
            ),

            if (currentUser != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _ProfileTile(
                  currentUser: currentUser,
                  onTap: () {
                    closeThen(() {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    });
                  },
                ),
              ),

            // ✅ Privacy
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _MenuTile(
                leading: Icon(
                  Icons.privacy_tip_outlined,
                  color: kOffWhite.withOpacity(0.92),
                  size: 22,
                ),
                title: l10n?.privacyTitle ?? 'Privacy',
                onTap: () {
                  closeThen(() {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PresencePrivacyScreen()),
                    );
                  });
                },
              ),
            ),

            // ✅ NEW: Invite Friends (place it here: after Privacy, before About)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _MenuTile(
                leading: Icon(
                  Icons.group_add_outlined,
                  color: kOffWhite.withOpacity(0.92),
                  size: 22,
                ),
                title: l10n?.inviteFriendsTitle ?? 'Invite Friends',
                onTap: () {
                  closeThen(() {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InviteFriendsTab()),
                    );
                  });
                },
              ),
            ),

            // ✅ About
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _MenuTile(
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: kOffWhite.withOpacity(0.92),
                  size: 22,
                ),
                title: l10n?.aboutTitle ?? 'About MW Chat',
                onTap: () {
                  closeThen(() {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    );
                  });
                },
              ),
            ),

            // ✅ Logout (keep last)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _MenuTile(
                leading: Icon(
                  Icons.logout_rounded,
                  color: kOffWhite.withOpacity(0.92),
                  size: 22,
                ),
                title: l10n?.logout ?? 'Logout',
                onTap: () {
                  closeThen(() async {
                    await PresenceService.instance.markOffline();
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  });
                },
              ),
            ),
          ],
        ),

      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// When true: trailing expands into remaining width (language row)
  final bool isLanguageRow;

  const _MenuTile({
    required this.leading,
    required this.title,
    this.trailing,
    this.onTap,
    this.isLanguageRow = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasTitle = title.trim().isNotEmpty;

    const double leadingSlotW = 34.0;
    const double rowMinH = 48.0;
    const double hPad = 12.0;

    final double gapAfterLeading = hasTitle ? 10.0 : 8.0;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      splashColor: kPrimaryGold.withOpacity(0.10),
      highlightColor: kPrimaryGold.withOpacity(0.06),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: rowMinH),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(hPad, 10, hPad, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: leadingSlotW, child: Center(child: leading)),
              SizedBox(width: gapAfterLeading),

              if (hasTitle)
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: kOffWhite.withOpacity(0.92),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),

              if (trailing != null)
                if (isLanguageRow)
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FittedBox(
                        // ✅ prevents overflow on extremely tiny widths while keeping good size normally
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: trailing!,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: trailing!,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final User currentUser;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.currentUser,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<Map<String, dynamic>?>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots()
          .map((snap) => snap.data()),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final profileUrl = data?['profileUrl'] as String?;
        final avatarType = (data?['avatarType'] as String?) ?? 'bear';

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          splashColor: kPrimaryGold.withOpacity(0.10),
          highlightColor: kPrimaryGold.withOpacity(0.06),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Center(
                      child: MwAvatar(
                        radius: 14,
                        avatarType: avatarType,
                        profileUrl: profileUrl,
                        hideRealAvatar: false,
                        backgroundColor: kOffWhite,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n?.profileTitle ?? 'Profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kOffWhite.withOpacity(0.92),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
