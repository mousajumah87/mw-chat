import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/locale_provider.dart';

class MwLanguageButton extends StatelessWidget {
  const MwLanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>().locale;
    final current = locale.languageCode;

    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: DropdownButton<String>(
          value: current,
          icon: const Icon(Icons.language, color: Colors.white),
          dropdownColor: Colors.black87,
          style: const TextStyle(color: Colors.white),
          onChanged: (code) {
            if (code != null) {
              context.read<LocaleProvider>().setLocale(Locale(code));
            }
          },
          items: const [
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'ar', child: Text('العربية')),
          ],
        ),
      ),
    );
  }
}
