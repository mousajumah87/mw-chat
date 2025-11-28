import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

class AuthHeader extends StatelessWidget {
  final bool isRegister;

  const AuthHeader({
    super.key,
    required this.isRegister,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // === MW Logo Halo ===
          Container(
            width: 110,
            height: 110,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0x55256EFF), // softer MW blue glow
                  Color(0x55FFB300), // softer MW amber glow
                  Colors.transparent,
                ],
                stops: [0.4, 0.8, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: 94,
                height: 94,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  border: Border.all(color: Colors.white12, width: 1),
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
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // === App Name ===
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF0057FF), Color(0xFFFFB300)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Text(
              l10n.sidePanelAppName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                color: Colors.white,
                shadows: [
                  const Shadow(
                    color: Colors.black54,
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // === Subtitle (Login/Register) ===
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                    begin: const Offset(0, 0.3), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: Text(
              key: ValueKey(isRegister),
              isRegister ? l10n.createAccount : l10n.loginTitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
