// lib/widgets/ui/mw_language_button.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/locale_provider.dart';
import '../../theme/app_theme.dart';

/// MW Chat Language Toggle (EN/AR)
/// - LTR locked so layout NEVER flips
/// - Glass + gold accents to match MW theme
/// - Cross-platform (iOS / Android / Web)
class MwLanguageButton extends StatelessWidget {
  final VoidCallback? onChanged; // ✅ optional, keeps existing usage working

  const MwLanguageButton({
    super.key,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>().locale;
    final isArabic = (locale.languageCode ?? 'en') == 'ar';

    void setLang(String code) {
      context.read<LocaleProvider>().setLocale(Locale(code));
      onChanged?.call(); // ✅ notify (ex: close menu overlay)
    }

    return Directionality(
      textDirection: TextDirection.ltr, // 🔒 keep stable
      child: Semantics(
        label: 'Language switch',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: kBorderColor.withOpacity(0.32),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kGoldDeep.withOpacity(0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LangPill(
                    text: 'English',
                    active: !isArabic,
                    onTap: () => setLang('en'),
                  ),
                  const SizedBox(width: 10),
                  Transform.scale(
                    scale: 0.9,
                    child: Switch.adaptive(
                      value: isArabic,
                      onChanged: (v) => setLang(v ? 'ar' : 'en'),
                      activeColor: kPrimaryGold,
                      activeTrackColor: kPrimaryGold.withOpacity(0.55),
                      inactiveThumbColor: Colors.white.withOpacity(0.75),
                      inactiveTrackColor: Colors.white.withOpacity(0.18),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _LangPill(
                    text: 'العربية',
                    active: isArabic,
                    onTap: () => setLang('ar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;

  const _LangPill({
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
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
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
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: active ? kPrimaryGold : Colors.white.withOpacity(0.70),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}
