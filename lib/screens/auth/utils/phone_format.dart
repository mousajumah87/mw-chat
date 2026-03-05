import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Digits only helper used by validators.
String digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

IsoCode isoCodeFromIso2(String iso2) {
  final up = iso2.toUpperCase();
  for (final c in IsoCode.values) {
    if (c.name.toUpperCase() == up) return c;
  }
  return IsoCode.US;
}

/// Tries to parse a phone number using either:
/// - E.164 if starts with '+'
/// - National number using [dialIso2] as destination country
PhoneNumber? tryParsePhone(String raw, {required String dialIso2}) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  final d = digitsOnly(s);
  if (d.length < 7 || d.length > 15) return null;

  try {
    if (s.startsWith('+')) {
      final pn = PhoneNumber.parse(s);
      return pn.isValid() ? pn : null;
    }

    final pn = PhoneNumber.parse(
      s,
      destinationCountry: isoCodeFromIso2(dialIso2),
    );
    return pn.isValid() ? pn : null;
  } catch (_) {
    return null;
  }
}

/// Converts parsed phone to E.164, always starting with '+' and digits.
String toE164(PhoneNumber pn) {
  String s;
  try {
    s = pn.international.trim();
  } catch (_) {
    s = pn.toString().trim();
  }

  final d = digitsOnly(s);
  if (d.isEmpty) return s;

  if (s.startsWith('+') && digitsOnly(s.substring(1)).isNotEmpty) {
    return '+${digitsOnly(s.substring(1))}';
  }
  return '+$d';
}