// lib/utils/locale_provider.dart
import 'package:flutter/material.dart';
import 'typography_provider.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider({TypographyProvider? typographyProvider})
      : _typographyProvider = typographyProvider;

  final TypographyProvider? _typographyProvider;

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  static const List<String> _supported = <String>['en', 'ar'];

  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode.toLowerCase();
    if (!_supported.contains(code)) return;

    // No-op if same
    if (_locale.languageCode.toLowerCase() == code) return;

    _locale = Locale(code);
    notifyListeners();

    // ✅ Keep typography defaults aligned to locale (only applies if user didn't pick a font)
    try {
      await _typographyProvider?.setLocale(_locale);
    } catch (_) {
      // never let this break UI
    }
  }

  Future<void> clearLocale() async {
    _locale = const Locale('en');
    notifyListeners();

    try {
      await _typographyProvider?.setLocale(_locale);
    } catch (_) {}
  }
}
