// lib/widgets/ui/mw_language_button.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../utils/locale_provider.dart';

/// MW Chat Language Toggle (EN/AR)
/// - LTR locked so the control itself NEVER flips
/// - Responsive: full mode when enough width, compact mode when tight
/// - Cross-platform: consistent look on iOS/Android/Web
/// - Visually equal label sizing EN/AR (Arabic font often renders larger)
///
/// IMPORTANT:
/// This widget assumes LocaleProvider.setLocale(...) persists BOTH:
///  - local prefs (so it survives logout/login even if Firestore denied)
///  - Firestore best-effort (optional)
class MwLanguageButton extends StatefulWidget {
  final VoidCallback? onChanged;
  final bool forceCompact;

  const MwLanguageButton({
    super.key,
    this.onChanged,
    this.forceCompact = false,
  });

  @override
  State<MwLanguageButton> createState() => _MwLanguageButtonState();
}

class _MwLanguageButtonState extends State<MwLanguageButton> {
  bool _saving = false;

  Future<void> _setLang(String code) async {
    if (_saving) return;

    final localeProvider = context.read<LocaleProvider>();
    final current = localeProvider.locale.languageCode.toLowerCase().trim();

    final next = code.toLowerCase().trim();
    if (next != 'en' && next != 'ar') return;
    if (current == next) {
      // Still close menu if caller wants.
      widget.onChanged?.call();
      return;
    }

    setState(() => _saving = true);

    try {
      // ✅ Wait for persistence (prefs + any server best-effort) before closing menu.
      await localeProvider.setLocale(Locale(next));
    } catch (e) {
      // Do not crash UI if persistence failed (permission-denied etc.).
      // LocaleProvider should still keep in-memory locale consistent.
      debugPrint('⚠️ MwLanguageButton setLocale failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>().locale;
    final isArabic = locale.languageCode.toLowerCase() == 'ar';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, c) {
          final bool compact = widget.forceCompact || c.maxWidth < 260;

          return Semantics(
            label: 'Language switch',
            value: isArabic ? 'Arabic' : 'English',
            button: true,
            enabled: !_saving,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: compact ? 8 : 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: kBorderColor.withOpacity(0.32),
                      width: 1,
                    ),
                  ),
                  child: IgnorePointer(
                    ignoring: _saving,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!compact) ...[
                          _LangPill(
                            text: 'English',
                            active: !isArabic,
                            onTap: () => _setLang('en'),
                          ),
                          const SizedBox(width: 10),
                        ] else ...[
                          _MiniLangChip(
                            active: !isArabic,
                            label: 'EN',
                            onTap: () => _setLang('en'),
                          ),
                          const SizedBox(width: 8),
                        ],

                        // Switch stays interactive but disabled while saving.
                        Transform.translate(
                          offset: const Offset(0, -0.5),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Switch(
                                value: isArabic,
                                onChanged: _saving
                                    ? null
                                    : (v) => _setLang(v ? 'ar' : 'en'),
                                activeColor: kPrimaryGold,
                                activeTrackColor: kPrimaryGold.withOpacity(0.55),
                                inactiveThumbColor:
                                Colors.white.withOpacity(0.78),
                                inactiveTrackColor:
                                Colors.white.withOpacity(0.20),
                                materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                              ),
                              if (_saving)
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      kPrimaryGold.withOpacity(0.9),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        if (!compact) ...[
                          const SizedBox(width: 10),
                          _LangPill(
                            text: 'العربية',
                            active: isArabic,
                            onTap: () => _setLang('ar'),
                          ),
                        ] else ...[
                          const SizedBox(width: 8),
                          _MiniLangChip(
                            active: isArabic,
                            label: 'AR',
                            onTap: () => _setLang('ar'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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

  bool _isArabicText(String s) {
    // Arabic Unicode blocks
    for (final rune in s.runes) {
      if ((rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = _isArabicText(text);

    // ✅ Make EN/AR visually equal:
    // Arabic fonts typically render larger at same point size → scale slightly down.
    final double base = 12.8;
    final double fontSize = isAr ? base * 0.92 : base;

    final String? fontFamily = isAr ? 'NotoSansArabic' : 'Poppins';

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
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            height: 1.05,
            color: active ? kPrimaryGold : Colors.white.withOpacity(0.70),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}

/// Small chip used only in compact mode (prevents overflow everywhere)
class _MiniLangChip extends StatelessWidget {
  final bool active;
  final String label;
  final VoidCallback onTap;

  const _MiniLangChip({
    required this.active,
    required this.label,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kPrimaryGold.withOpacity(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? kPrimaryGold.withOpacity(0.50)
                : Colors.white.withOpacity(0.16),
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11.8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            height: 1.05,
            color: active ? kPrimaryGold : Colors.white.withOpacity(0.70),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
