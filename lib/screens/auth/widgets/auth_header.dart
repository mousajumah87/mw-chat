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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo with soft blue–amber glowing halo
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [
                Color(0x80256EFF), // soft MW blue glow
                Color(0x80FFB300), // soft MW amber glow
                Colors.transparent,
              ],
              stops: [0.3, 0.8, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0057FF).withOpacity(0.45),
                blurRadius: 25,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: const Color(0xFFFFB300).withOpacity(0.35),
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
                color: Colors.black,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Image.asset(
                  'assets/logo/mw_mark.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),

        // App name
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0057FF), Color(0xFFFFB300)],
          ).createShader(bounds),
          child: Text(
            l10n.sidePanelAppName,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(height: 4),

        // Subtitle (login/register)
        Text(
          isRegister ? l10n.createAccount : l10n.loginTitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
