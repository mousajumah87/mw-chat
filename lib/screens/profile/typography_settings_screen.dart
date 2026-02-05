// lib/screens/profile/typography_settings_screen.dart
//
// MW Chat – Font & Display
// Premium neon-glass (Warm Gold Edition), RTL/LTR safe, iOS/Android/Web friendly.
//
// Best-practice updates in this version:
// ✅ NO duplicated EN/AR preview keys like previewHeadlineAr…
//    - Use normal localized keys: previewHeadline / previewBody / previewMiniLine
//    - Use fixed sample keys: englishSample / arabicSample (only for mismatch preview)
// ✅ Font names are shown as-is (NO localization keys) — same in Arabic & English.
// ✅ Robust on small phones: constrained width, scroll, menuMaxHeight, safe paddings.
// ✅ Web-safe Slider theme to avoid “Cannot hit test render box…” crashes.
// ✅ More defensive:
//    - Catches async provider/Firestore errors (prevents UI from breaking on Web)
//    - Ensures Dropdown value always exists in items (prevents assertion errors)
//    - Uses context.select to reduce rebuild noise

import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/locale_provider.dart';
import '../../utils/typography_provider.dart';
import '../../widgets/ui/mw_background.dart';

class TypographySettingsScreen extends StatefulWidget {
  const TypographySettingsScreen({super.key});

  /// ✅ Display order: Latin first, then Arabic.
  static const List<String> orderedFontChoices = <String>[
    // Latin
    'Poppins',
    'Inter',
    'Rubik',
    'Space Grotesk',
    'Montserrat',
    'Nunito',
    'DM Serif Display',
    'Playfair Display',
    'Dancing Script',

    // Arabic
    'Noto Sans Arabic',
    'Tajawal',
    'Cairo',
    'Almarai',
    'Reem Kufi',
    'Amiri',
  ];

  @override
  State<TypographySettingsScreen> createState() => _TypographySettingsScreenState();
}

class _TypographySettingsScreenState extends State<TypographySettingsScreen> {
  double? _draftScale;
  Timer? _snackDebounce;

  // ------------------------------ constants

  static const String _kDefaultLatin = 'Poppins';
  static const String _kDefaultArabic = 'NotoSansArabic';

  static const Set<String> _arabicFonts = <String>{
    'Noto Sans Arabic',
    'Cairo',
    'Tajawal',
    'Almarai',
    'Reem Kufi',
    'Amiri',
  };

  static const Set<String> _coolFonts = <String>{
    'Rubik',
    'Space Grotesk',
    'Montserrat',
    'Nunito',
  };

  static const Set<String> _fancyFonts = <String>{
    'DM Serif Display',
    'Playfair Display',
    'Reem Kufi',
    'Amiri',
    'Dancing Script',
  };

  static const Set<String> _loveFonts = <String>{
    'Dancing Script',
    'Amiri',
  };

  @override
  void dispose() {
    _snackDebounce?.cancel();
    super.dispose();
  }

  // ------------------------------ helpers

  void _showSnack(String text) {
    _snackDebounce?.cancel();
    _snackDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(text)));
    });
  }

  String _fallback(String? value, String fallback) {
    final v = (value ?? '').trim();
    return v.isNotEmpty ? v : fallback;
  }

  bool _isArabicLocale(BuildContext context) {
    // Using select avoids extra rebuild triggers.
    final locale = context.select<LocaleProvider, Locale>((p) => p.locale);
    return locale.languageCode.toLowerCase() == 'ar';
  }

  bool _isArabicFont(String family) => _arabicFonts.contains(family);
  bool _isCoolFont(String family) => _coolFonts.contains(family);
  bool _isFancyFont(String family) => _fancyFonts.contains(family);
  bool _isLoveFont(String family) => _loveFonts.contains(family);

  String _defaultFamilyForLocale(bool isArabic) => isArabic ? _kDefaultArabic : _kDefaultLatin;

  /// If current font isn't in list, insert it in the correct section.
  List<String> _ensureIncludesCurrent(List<String> items, String current) {
    if (items.contains(current)) return items;

    final out = <String>[...items];
    final firstArabicIndex = out.indexOf(_kDefaultArabic);

    // If somehow list doesn't contain Arabic marker, just append.
    if (firstArabicIndex < 0) {
      out.add(current);
      return out;
    }

    if (_isArabicFont(current)) {
      out.add(current);
    } else {
      out.insert(firstArabicIndex, current);
    }
    return out;
  }

  // ✅ Web safety: avoid slider overlay / valueIndicator hit-test issues on some web builds.
  SliderThemeData _safeSliderTheme(BuildContext context) {
    final base = SliderTheme.of(context);
    if (!kIsWeb) return base;

    return base.copyWith(
      overlayShape: SliderComponentShape.noOverlay,
      valueIndicatorShape: SliderComponentShape.noOverlay,
      showValueIndicator: ShowValueIndicator.never,
      trackHeight: (base.trackHeight ?? 4).clamp(2.0, 6.0),
    );
  }

  // Font names are shown as-is (no ARB keys).
  String _fontLabel(String family) => family;

  // Tags are stable and intentionally not localized (short chips).
  String _tagLabel(String tag) => tag;

  /// ✅ Best practice preview:
  /// - Use localized keys for the main preview text (previewHeadline/Body/MiniLine).
  /// - Use fixed sample keys ONLY for mismatch (englishSample/arabicSample).
  ({String headline, String body, String mini, String? altLine}) _previewText({
    required AppLocalizations l10n,
    required bool isArabicLocale,
    required bool isArabicSelectedFont,
  }) {
    final headline = _fallback(l10n.previewHeadline, 'Type something to start ✍️');
    final body = _fallback(
      l10n.previewBody,
      'You can keep it small, or make it more comfortable for your eyes.',
    );
    final mini = _fallback(
      l10n.previewMiniLine,
      'This is how your chat text feels in real use.',
    );

    String? altLine;
    final mismatch = isArabicLocale != isArabicSelectedFont;
    if (mismatch) {
      altLine = isArabicLocale
          ? _fallback(
        l10n.englishSample,
        'English sample: The quick brown fox jumps over the lazy dog.',
      )
          : _fallback(
        l10n.arabicSample,
        'مثال عربي: اللغة العربية جميلة وتبدو رائعة مع الخط المناسب.',
      );
    }

    return (headline: headline, body: body, mini: mini, altLine: altLine);
  }

  Future<void> _safeCall(
      Future<void> Function() action, {
        String? errorSnack,
      }) async {
    try {
      await action();
    } catch (e, st) {
      debugPrint('TypographySettingsScreen action failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      _showSnack(errorSnack ?? 'Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Reduce rebuild noise:
    final typo = context.read<TypographyProvider>();
    final fontScale = context.select<TypographyProvider, double>((p) => p.fontScale);
    final fontFamily = context.select<TypographyProvider, String?>((p) => p.fontFamily);

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final isWide = width >= 900;

    final isArabicLocale = _isArabicLocale(context);

    // Screen strings (localized normally)
    final title = _fallback(l10n.fontAndDisplay, 'Font & Display');

    final fontSizeTitle = _fallback(l10n.fontSizeLabel, 'Font size');
    final fontSizeDesc = _fallback(
      l10n.fontSizeDesc,
      'Change how big text looks across MW Chat (including messages).',
    );

    final fontStyleTitle = _fallback(l10n.fontStyleLabel, 'Font style');
    final fontStyleDesc = _fallback(
      l10n.fontStyleDesc,
      'Pick a clean font style that matches your taste.',
    );

    final previewTitle = _fallback(l10n.previewLabel, 'Preview');
    final resetLabel = _fallback(l10n.resetToDefault, 'Reset to default');
    final resetSnack = _fallback(l10n.backToDefault, 'Back to default.');

    // Current values
    final storedFamily = (fontFamily ?? '').trim();
    final desiredCurrentFamily =
    storedFamily.isNotEmpty ? storedFamily : _defaultFamilyForLocale(isArabicLocale);

    // List items
    final items = _ensureIncludesCurrent(
      TypographySettingsScreen.orderedFontChoices,
      desiredCurrentFamily,
    );

    // ✅ Dropdown value must exist in items
    final currentFamily = items.contains(desiredCurrentFamily)
        ? desiredCurrentFamily
        : (items.isNotEmpty ? items.first : _defaultFamilyForLocale(isArabicLocale));

    final isArabicSelectedFont = _isArabicFont(currentFamily);

    // Slider value (draft while dragging)
    final sliderValue = _draftScale ?? fontScale;

    // Layout spacing tuned for phones
    final cardMargin = EdgeInsets.symmetric(horizontal: isWide ? 32 : 16, vertical: 8);
    final cardPadding = EdgeInsets.symmetric(
      horizontal: isWide ? 48 : 18,
      vertical: isWide ? 28 : 18,
    );

    final p = _previewText(
      l10n: l10n,
      isArabicLocale: isArabicLocale,
      isArabicSelectedFont: isArabicSelectedFont,
    );

    final tipText = _fallback(
      l10n.typographyTip,
      isArabicLocale
          ? 'نصيحة: الخطوط العصرية تناسب الشباب، والخطوط النظيفة أفضل للدردشة الطويلة، وخطوط الحب جميلة للعناوين والبروفايل.'
          : 'Tip: Cool fonts look great for young vibes, clean fonts are best for long chats, and Love fonts are perfect for cute profiles or headings.',
    );

    final webTip = _fallback(
      l10n.typographyWebTip,
      isArabicLocale
          ? 'نصيحة للويب: إذا لم يتغير الخط، جرّب إعادة التشغيل السريع (R) لإعادة تحميل الخط.'
          : 'Web tip: If a font looks unchanged, do a hot restart (R) to reload.',
    );

    // Stable UI font for dropdown labels (so they don't look weird when previewing fonts).
    final uiLabelFont = isArabicLocale ? _kDefaultArabic : _kDefaultLatin;

    // ✅ More robust dropdown height for small screens / web
    final dropdownMaxHeight = (height * 0.55).clamp(240.0, 460.0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        )
            : null,
      ),
      body: MwBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      margin: cardMargin,
                      padding: cardPadding,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: ScrollConfiguration(
                        behavior: const _MwScrollBehavior(),
                        child: SingleChildScrollView(
                          physics: kIsWeb
                              ? const ClampingScrollPhysics()
                              : const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SectionHeader(title: fontSizeTitle, subtitle: fontSizeDesc),
                              const SizedBox(height: 12),
                              _GlassPanel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'A',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: Colors.white.withOpacity(0.75),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: SliderTheme(
                                            data: _safeSliderTheme(context),
                                            child: Slider(
                                              value: sliderValue,
                                              min: TypographyProvider.minScale,
                                              max: TypographyProvider.maxScale,
                                              divisions: 11,
                                              label: '${(sliderValue * 100).round()}%',
                                              onChanged: (v) {
                                                if (!mounted) return;
                                                setState(() => _draftScale = v);
                                              },
                                              onChangeEnd: (v) async {
                                                if (!mounted) return;
                                                setState(() => _draftScale = null);

                                                await _safeCall(
                                                      () => typo.setFontScale(v),
                                                  errorSnack: _fallback(
                                                    l10n.generalErrorMessage,
                                                    'Something went wrong. Please try again.',
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'A',
                                          style: theme.textTheme.titleLarge?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: kSurfaceAltColor.withOpacity(0.75),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                                        ),
                                        child: Text(
                                          '${(sliderValue * 100).round()}%',
                                          style: theme.textTheme.labelLarge?.copyWith(
                                            color: kPrimaryGold,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              Divider(color: Colors.white.withOpacity(0.18)),
                              const SizedBox(height: 16),
                              _SectionHeader(title: fontStyleTitle, subtitle: fontStyleDesc),
                              const SizedBox(height: 12),
                              _GlassPanel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _DropdownField(
                                      value: currentFamily,
                                      items: items,
                                      dropdownMaxHeight: dropdownMaxHeight,
                                      itemBuilder: (f) {
                                        final arFont = _isArabicFont(f);
                                        final label = _fontLabel(f);

                                        return Row(
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 28,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.25),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                                              ),
                                              child: Text(
                                                arFont ? 'أب' : 'Aa',
                                                style: theme.textTheme.labelLarge?.copyWith(
                                                  fontFamily: f,
                                                  fontWeight: FontWeight.w900,
                                                  color: kPrimaryGold,
                                                  height: 1.0,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                label,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontFamily: uiLabelFont,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ),
                                            if (_isLoveFont(f))
                                              _Pill(
                                                text: _tagLabel('LOVE'),
                                                fg: kPrimaryGold,
                                                bg: kPrimaryGold.withOpacity(0.10),
                                                border: kPrimaryGold.withOpacity(0.22),
                                              )
                                            else if (_isCoolFont(f))
                                              _Pill(
                                                text: _tagLabel('COOL'),
                                                fg: kPrimaryGold,
                                                bg: kPrimaryGold.withOpacity(0.08),
                                                border: kPrimaryGold.withOpacity(0.18),
                                              )
                                            else if (_isFancyFont(f))
                                                _Pill(
                                                  text: _tagLabel('FANCY'),
                                                  fg: kPrimaryGold,
                                                  bg: kPrimaryGold.withOpacity(0.10),
                                                  border: kPrimaryGold.withOpacity(0.22),
                                                )
                                              else if (arFont)
                                                  _Pill(
                                                    text: _tagLabel('AR'),
                                                    fg: Colors.white.withOpacity(0.70),
                                                    bg: Colors.white.withOpacity(0.06),
                                                    border: Colors.white.withOpacity(0.10),
                                                  ),
                                          ],
                                        );
                                      },
                                      onChanged: (v) async {
                                        if (v == null) return;

                                        await _safeCall(
                                              () => typo.setFontFamily(v),
                                          errorSnack: _fallback(
                                            l10n.generalErrorMessage,
                                            'Something went wrong. Please try again.',
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      tipText,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.white.withOpacity(0.40),
                                        height: 1.35,
                                      ),
                                      textAlign: TextAlign.start,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      previewTitle,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                      textAlign: TextAlign.start,
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: mwTypingGlassDecoration(radius: 18),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            p.headline,
                                            style: theme.textTheme.bodyLarge?.copyWith(
                                              fontFamily: currentFamily,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.start,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            p.body,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontFamily: currentFamily,
                                              color: Colors.white.withOpacity(0.85),
                                              height: 1.35,
                                            ),
                                            textAlign: TextAlign.start,
                                          ),
                                          if ((p.altLine ?? '').trim().isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.18),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                                              ),
                                              child: Text(
                                                p.altLine!,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  fontFamily: currentFamily,
                                                  color: Colors.white.withOpacity(0.70),
                                                  height: 1.35,
                                                ),
                                                textAlign: TextAlign.start,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 12),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 10,
                                                height: 10,
                                                margin: const EdgeInsets.only(top: 6, right: 10),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: kPrimaryGold.withOpacity(0.9),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: kGoldDeep.withOpacity(0.22),
                                                      blurRadius: 10,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  p.mini,
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    fontFamily: currentFamily,
                                                    color: Colors.white.withOpacity(0.80),
                                                    height: 1.35,
                                                  ),
                                                  textAlign: TextAlign.start,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (kIsWeb) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        webTip,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.white.withOpacity(0.30),
                                          height: 1.35,
                                        ),
                                        textAlign: TextAlign.start,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await _safeCall(
                                          () => typo.reset(),
                                      errorSnack: _fallback(
                                        l10n.generalErrorMessage,
                                        'Something went wrong. Please try again.',
                                      ),
                                    );
                                    if (!context.mounted) return;
                                    _showSnack(resetSnack);
                                  },
                                  icon: const Icon(Icons.restart_alt_rounded),
                                  label: Text(resetLabel),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withOpacity(0.28)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _fallback(l10n.fontHintNote, 'Tip: Font changes apply instantly across the app.'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withOpacity(0.45),
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  final Color border;

  const _Pill({
    required this.text,
    required this.fg,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          height: 1.05,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: kTextSecondary,
            height: 1.35,
          ),
          textAlign: TextAlign.start,
        ),
      ],
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;

  const _GlassPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceAltColor.withOpacity(0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String value;
  final List<String> items;
  final Widget Function(String item) itemBuilder;
  final ValueChanged<String?> onChanged;
  final double dropdownMaxHeight;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.itemBuilder,
    required this.onChanged,
    this.dropdownMaxHeight = 420,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeValue = items.contains(value) ? value : (items.isNotEmpty ? items.first : value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: kSurfaceAltColor.withOpacity(0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: safeValue,
          dropdownColor: kSurfaceAltColor,
          icon: const Icon(Icons.expand_more_rounded),
          borderRadius: BorderRadius.circular(14),
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          menuMaxHeight: dropdownMaxHeight,
          items: items
              .map(
                (f) => DropdownMenuItem<String>(
              value: f,
              child: itemBuilder(f),
            ),
          )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MwScrollBehavior extends MaterialScrollBehavior {
  const _MwScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}
