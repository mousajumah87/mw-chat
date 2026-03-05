import 'package:phone_numbers_parser/phone_numbers_parser.dart';

String digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

IsoCode isoCodeFromIso2(String iso2) {
  final up = iso2.toUpperCase();
  for (final c in IsoCode.values) {
    if (c.name.toUpperCase() == up) return c;
  }
  return IsoCode.US;
}

bool isLikelyPhoneCandidate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return false;
  if (s.contains('@')) return false;
  final digits = digitsOnly(s);
  return digits.length >= 7 && digits.length <= 15;
}

PhoneNumber? tryParsePhone(String raw, {required String dialIso2}) {
  final s = raw.trim();
  if (!isLikelyPhoneCandidate(s)) return null;

  try {
    if (s.startsWith('+')) {
      final pn = PhoneNumber.parse(s);
      return pn.isValid() ? pn : null;
    }

    final pn = PhoneNumber.parse(s, destinationCountry: isoCodeFromIso2(dialIso2));
    return pn.isValid() ? pn : null;
  } catch (_) {
    return null;
  }
}

String toE164(PhoneNumber pn) {
  String s;
  try {
    s = pn.international.trim();
  } catch (_) {
    s = pn.toString().trim();
  }

  final digits = digitsOnly(s);
  if (digits.isEmpty) return s;

  if (s.startsWith('+') && digitsOnly(s.substring(1)).isNotEmpty) {
    return '+${digitsOnly(s.substring(1))}';
  }
  return '+$digits';
}