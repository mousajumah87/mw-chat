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

/// Returns a normalized Jordan mobile number in E.164 if possible.
/// Accepts:
/// - 07XXXXXXXX
/// - 7XXXXXXXX
/// - +9627XXXXXXXX
///
/// Returns null if not a Jordan mobile candidate.
String? _normalizeJordanMobileToE164(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  // Keep leading + only if user entered it
  final hasPlus = s.startsWith('+');
  final d = digitsOnly(s);

  // Already E.164-ish Jordan: +9627XXXXXXXX or 9627XXXXXXXX
  if ((hasPlus && d.startsWith('962')) || d.startsWith('962')) {
    if (d.length == 12 && d.startsWith('9627')) {
      return '+$d';
    }
    return null;
  }

  // Local with leading 0: 07XXXXXXXX
  if (d.length == 10 && d.startsWith('07')) {
    return '+962${d.substring(1)}'; // remove local 0
  }

  // Local without leading 0: 7XXXXXXXX
  if (d.length == 9 && d.startsWith('7')) {
    return '+962$d';
  }

  return null;
}

/// Country-aware normalization before parsing.
/// For Jordan, accepts mobile input with or without leading 0.
String? _normalizeForParsing(String raw, {required String dialIso2}) {
  final iso2 = dialIso2.trim().toUpperCase();
  final s = raw.trim();
  if (s.isEmpty) return null;

  if (iso2 == 'JO') {
    return _normalizeJordanMobileToE164(s);
  }

  // For other countries keep original behavior
  return s;
}

/// Tries to parse a phone number using either:
/// - E.164 if starts with '+'
/// - National number using [dialIso2] as destination country
///
/// Jordan special handling:
/// - accepts 07XXXXXXXX
/// - accepts 7XXXXXXXX
/// - accepts +9627XXXXXXXX
PhoneNumber? tryParsePhone(String raw, {required String dialIso2}) {
  final normalized = _normalizeForParsing(raw, dialIso2: dialIso2);
  if (normalized == null) return null;

  final d = digitsOnly(normalized);
  if (d.length < 7 || d.length > 15) return null;

  try {
    if (normalized.startsWith('+')) {
      final pn = PhoneNumber.parse(normalized);
      return pn.isValid() ? pn : null;
    }

    final pn = PhoneNumber.parse(
      normalized,
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

/// Optional helper if you want a direct validator for Jordan mobile input.
bool isValidJordanMobileInput(String raw) {
  final normalized = _normalizeJordanMobileToE164(raw);
  if (normalized == null) return false;

  try {
    final pn = PhoneNumber.parse(normalized);
    return pn.isValid();
  } catch (_) {
    return false;
  }
}