// lib/screens/auth/widgets/auth_header.dart
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class AuthHeader extends StatefulWidget {
  final bool isRegister;

  const AuthHeader({
    super.key,
    required this.isRegister,
  });

  @override
  State<AuthHeader> createState() => _AuthHeaderState();
}

class _AuthHeaderState extends State<AuthHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.88, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // === Animated MW Logo Halo ===
          ScaleTransition(
            scale: _pulse,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kPrimaryGold.withOpacity(0.45),
                    kGoldDeep.withOpacity(0.35),
                    Colors.transparent,
                  ],
                  stops: const [0.35, 0.8, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryGold.withOpacity(0.22),
                    blurRadius: 25,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: kGoldDeep.withOpacity(0.18),
                    blurRadius: 25,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kSurfaceColor.withOpacity(0.8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
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
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo/mw_mark.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // === MW App Name (Gold Gradient Text) ===
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [kPrimaryGold, kGoldDeep], // ✅ no const
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Text(
              l10n.sidePanelAppName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                fontSize: 26,
                // ✅ no need for color when using ShaderMask
                shadows: [
                  Shadow(
                    color: kPrimaryGold.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                  Shadow(
                    color: kGoldDeep.withOpacity(0.28),
                    blurRadius: 8,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // === Subtitle (Login/Register) ===
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOut),
                ),
                child: child,
              ),
            ),
            child: Text(
              widget.isRegister ? l10n.createAccount : l10n.loginTitle,
              key: ValueKey(widget.isRegister),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: kTextSecondary,
                fontSize: 14.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
