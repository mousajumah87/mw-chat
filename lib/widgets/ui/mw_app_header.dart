import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/presence_service.dart';
import '../../utils/locale_provider.dart';
import '../../screens/about/about_screen.dart';
import '../../screens/profile/profile_screen.dart';
import 'mw_language_button.dart';

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
  Size get preferredSize => Size.fromHeight(showTabs ? 112 : 76);

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

  // ✅ Prevent setState during dispose/unmount
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    _slide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _isDisposing = true;

    // ✅ Remove overlay WITHOUT calling setState in dispose
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
        final headerHeight = widget.showTabs ? 112.0 : 76.0;

        final screenW = media.size.width;
        final maxPanelW = screenW < 420 ? screenW - 24 : 420.0;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeMenu,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(color: Colors.black.withOpacity(0.25)),
                ),
              ),
            ),

            // ✅ Position based on START side (LTR=left, RTL=right)
            PositionedDirectional(
              top: topPadding + headerHeight + 8,
              start: 12,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxPanelW),
                child: SlideTransition(
                  position: _slide,
                  child: FadeTransition(
                    opacity: _fade,
                    child: _MenuPanel(
                      // ✅ pass a closer that UPDATES the header state
                      onClose: _removeMenu,
                    ),
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
      } catch (_) {
        // ignore animation cancellation / disposed controller race
      }
    }

    try {
      _menuEntry?.remove();
    } catch (_) {
      // ignore overlay removal races
    }
    _menuEntry = null;

    // ✅ Update state while mounted so hamburger/X updates correctly
    if (updateState && mounted && !_isDisposing) {
      setState(() => _isMenuOpen = false);
    } else {
      _isMenuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
          border: Border.all(color: Colors.white12, width: 0.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _HamburgerButton(isOpen: _isMenuOpen, onTap: _toggleMenu),
                  Expanded(child: Center(child: _FloatingBrandLogo())),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            if (widget.showTabs && widget.tabBar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: widget.tabBar,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FloatingBrandLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo/mw_mark_transparent.png',
      width: 70,
      height: 70,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
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
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12, width: 0.8),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: Icon(
            isOpen ? Icons.close_rounded : Icons.menu_rounded,
            key: ValueKey(isOpen),
            color: Colors.white,
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

    final locale = context.watch<LocaleProvider>().locale;
    final isArabic = locale.languageCode.toLowerCase() == 'ar';

    Future<void> _closeThen(VoidCallback action) async {
      // ✅ IMPORTANT FIX:
      // Close overlay AND update header state so icon returns to hamburger
      await onClose(immediate: true, updateState: true);

      // Run action after overlay is gone
      Future.microtask(() {
        if (!context.mounted) return;
        action();
      });
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _MenuTile(
                leading: const Icon(Icons.language_rounded, color: Colors.white),
                title: l10n?.languageLabel ?? (isArabic ? 'اللغة' : 'Language'),

                // ✅ Reuse your premium language widget + close menu after change
                trailing: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Transform.scale(
                    scale: 0.82, // ✅ fits nicely in the tile on small phones
                    alignment: Alignment.centerRight,
                    child: MwLanguageButton(
                      onChanged: () {
                        // Close overlay after changing language
                        Future.microtask(() => onClose(immediate: true, updateState: true));
                      },
                    ),
                  ),
                ),

                // Optional: keep tap-to-toggle
                onTap: () {
                  Future.microtask(() => onClose(immediate: true, updateState: true));
                  context
                      .read<LocaleProvider>()
                      .setLocale(Locale(isArabic ? 'en' : 'ar'));
                },
              ),
            ),

            if (currentUser != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _ProfileTile(
                  currentUser: currentUser,
                  onTap: () {
                    _closeThen(() {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      );
                    });
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _MenuTile(
                leading: const Icon(Icons.info_outline_rounded, color: Colors.white),
                title: l10n?.aboutTitle ?? 'About MW Chat',
                onTap: () {
                  _closeThen(() {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AboutScreen(),
                      ),
                    );
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _MenuTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.white),
                title: l10n?.logout ?? 'Logout',
                onTap: () {
                  _closeThen(() async {
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

  final bool showChevron;

  const _MenuTile({
    required this.leading,
    required this.title,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    Widget? resolvedTrailing = trailing;

    if (resolvedTrailing == null && showChevron) {
      resolvedTrailing = Icon(
        isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        color: Colors.white.withOpacity(0.7),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 10),
        child: Row(
          children: [
            SizedBox(width: 30, child: Center(child: leading)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (resolvedTrailing != null) resolvedTrailing,
          ],
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
        final avatarType = data?['avatarType'] as String?;

        final emoji = (avatarType == 'smurf') ? '🧜‍♀️' : '🐻';

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  backgroundImage: (profileUrl != null && profileUrl.isNotEmpty)
                      ? NetworkImage(profileUrl)
                      : null,
                  child: (profileUrl == null || profileUrl.isEmpty)
                      ? Text(emoji, style: const TextStyle(fontSize: 14))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n?.profileTitle ?? 'Profile',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LangChip extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;

  const _LangChip({
    required this.text,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: active ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kPrimaryGold.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? kPrimaryGold.withOpacity(0.55)
                : Colors.white.withOpacity(0.16),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: active ? kPrimaryGold : Colors.white.withOpacity(0.70),
          ),
        ),
      ),
    );
  }
}
