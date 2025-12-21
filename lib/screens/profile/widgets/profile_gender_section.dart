import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class ProfileGenderSection extends StatelessWidget {
  final String gender; // 'male' | 'female' | 'none'
  final bool isRtl;
  final TextDirection textDirection;
  final ValueChanged<String> onGenderChanged;

  const ProfileGenderSection({
    super.key,
    required this.gender,
    required this.isRtl,
    required this.textDirection,
    required this.onGenderChanged,
  });

  // ✅ Safe localized lookup:
  // - Tries dynamic getters if they exist (male/female/...)
  // - Falls back to keys via l10n string map if available
  // - Final fallback is English text (won’t crash)
  String _t(AppLocalizations l10n, String key, String fallback) {
    try {
      // Many generated l10n classes expose a `String operator [](String key)`
      // or a `Map` internally, but not always. We'll try dynamic getter first.
      final dyn = l10n as dynamic;
      final value = dyn?.noSuchMethod == null ? null : null; // no-op
      // Try getter like l10n.male / l10n.female / l10n.preferNotToSay
      final got = dyn[key];
      if (got is String && got.trim().isNotEmpty) return got;
    } catch (_) {}

    // Try standard generated getters if your l10n has them.
    try {
      switch (key) {
        case 'male':
        // ignore: undefined_getter
          return (l10n as dynamic).male as String;
        case 'female':
        // ignore: undefined_getter
          return (l10n as dynamic).female as String;
        case 'preferNotToSay':
        // ignore: undefined_getter
          return (l10n as dynamic).preferNotToSay as String;
        case 'gender':
        // ignore: undefined_getter
          return (l10n as dynamic).gender as String;
        case 'optional':
        // ignore: undefined_getter
          return (l10n as dynamic).optional as String;
      }
    } catch (_) {}

    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final maleLabel = _t(l10n, 'male', 'Male');
    final femaleLabel = _t(l10n, 'female', 'Female');
    final preferNotLabel = _t(l10n, 'preferNotToSay', 'Prefer not to say');
    final genderLabel = _t(l10n, 'gender', 'Gender');
    final optionalLabel = _t(l10n, 'optional', '(optional)');

    final maleChip = ChoiceChip(
      label: Text(maleLabel),
      selected: gender == 'male',
      selectedColor: kPrimaryGold,
      backgroundColor: kSurfaceColor,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: gender == 'male' ? Colors.black : Colors.white70,
      ),
      onSelected: (_) => onGenderChanged('male'),
    );

    final femaleChip = ChoiceChip(
      label: Text(femaleLabel),
      selected: gender == 'female',
      selectedColor: kGoldDeep,
      backgroundColor: kSurfaceColor,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: gender == 'female' ? Colors.black : Colors.white70,
      ),
      onSelected: (_) => onGenderChanged('female'),
    );

    final preferNotChip = ChoiceChip(
      label: Text(preferNotLabel),
      selected: gender == 'none',
      selectedColor: kSurfaceAltColor,
      backgroundColor: kSurfaceColor,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w500,
        color: gender == 'none' ? Colors.white : Colors.white70,
      ),
      onSelected: (_) => onGenderChanged('none'),
    );

    final chips = isRtl
        ? <Widget>[femaleChip, maleChip, preferNotChip]
        : <Widget>[maleChip, femaleChip, preferNotChip];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            '$genderLabel $optionalLabel',
            textDirection: textDirection,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          textDirection: textDirection,
          children: chips,
        ),
      ],
    );
  }
}
