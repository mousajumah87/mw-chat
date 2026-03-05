// lib/utils/identifier_availability.dart
import 'package:cloud_functions/cloud_functions.dart';

enum IdentifierType { phone, email }

class IdentifierAvailabilityResult {
  final bool available;

  /// Server reasons: "phone_in_use" | "email_in_use"
  /// Client reasons: "invalid_input" | "check_failed"
  final String reason;

  /// Cloud Function returns: uid (string) OR null (only when in-use)
  final String? uid;

  /// Optional client-side error context (not from server response)
  final String? errorCode;
  final String? errorMessage;

  const IdentifierAvailabilityResult({
    required this.available,
    required this.reason,
    required this.uid,
    this.errorCode,
    this.errorMessage,
  });

  bool get inUse => !available; // ✅ the only reliable signal you need

  factory IdentifierAvailabilityResult.fromMap(Map<String, dynamic> m) {
    final available = m['available'] == true;
    final reason = (m['reason'] ?? '').toString();

    final rawUid = m['uid'];
    final uid = rawUid == null ? null : rawUid.toString().trim();
    final cleanedUid = (uid != null && uid.isNotEmpty) ? uid : null;

    return IdentifierAvailabilityResult(
      available: available,
      reason: reason,
      uid: cleanedUid,
    );
  }

  /// Client-side failures (timeout/network/permission/etc.)
  static const IdentifierAvailabilityResult failed = IdentifierAvailabilityResult(
    available: false,
    reason: 'check_failed',
    uid: null,
    errorCode: 'check_failed',
    errorMessage: 'Identifier availability check failed.',
  );

  static IdentifierAvailabilityResult invalidInput(String message) {
    return IdentifierAvailabilityResult(
      available: false,
      reason: 'invalid_input',
      uid: null,
      errorCode: 'invalid-argument',
      errorMessage: message,
    );
  }

  IdentifierAvailabilityResult withError({
    String? errorCode,
    String? errorMessage,
  }) {
    return IdentifierAvailabilityResult(
      available: available,
      reason: reason,
      uid: uid,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }
}

class IdentifierAvailabilityApi {
  static const String _region = 'us-central1';
  static const String _fnName = 'checkIdentifierAvailable';

  static FirebaseFunctions _fx() => FirebaseFunctions.instanceFor(region: _region);

  /// Align with Cloud Function:
  /// - email -> trim + lowercase
  /// - phone -> trim only (expects E.164 "+########")
  static String _normalize(IdentifierType type, String identifier) {
    final trimmed = identifier.trim();
    if (type == IdentifierType.email) return trimmed.toLowerCase();
    return trimmed;
  }

  /// Basic validation aligned with Cloud Function checks.
  /// (Prevents useless CF calls that will fail with invalid-argument.)
  static String? _validate(IdentifierType type, String value) {
    if (value.isEmpty) return 'Missing identifier.';
    if (type == IdentifierType.phone) {
      // Must start with + and be at least 8 chars (same spirit as CF guard)
      if (!value.startsWith('+') || value.length < 8) {
        return 'Phone must be in E.164 format, e.g. +14258664221';
      }
    } else {
      // Minimal email sanity (CF accepts any string, but this avoids obvious mistakes)
      if (!value.contains('@') || !value.contains('.')) {
        return 'Email looks invalid.';
      }
    }
    return null;
  }

  static Future<IdentifierAvailabilityResult> check({
    required IdentifierType type,
    required String identifier,
  }) async {
    final callable = _fx().httpsCallable(
      _fnName,
      options: HttpsCallableOptions(timeout: Duration(seconds: 20)),
    );

    final value = _normalize(type, identifier);

    // Client-side validation aligned with your CF contract
    final validationError = _validate(type, value);
    if (validationError != null) {
      return IdentifierAvailabilityResult.invalidInput(validationError);
    }

    try {
      final resp = await callable.call(<String, dynamic>{
        'type': type == IdentifierType.phone ? 'phone' : 'email',
        'value': value, // ✅ matches Cloud Function exactly
      });

      final data = (resp.data is Map)
          ? Map<String, dynamic>.from(resp.data as Map)
          : <String, dynamic>{};

      // ✅ aligns with CF response:
      // - available: true -> may omit reason/uid (handled)
      // - available: false -> has reason + uid (handled)
      return IdentifierAvailabilityResult.fromMap(data);
    } on FirebaseFunctionsException catch (e) {
      // CF errors:
      // - invalid-argument (e.g. phone not E.164)
      // - internal (lookup failure)
      // - unauthenticated/permission-denied (if you later add auth requirements)
      final code = e.code; // e.g. 'invalid-argument', 'internal'
      final msg = e.message ?? 'Cloud Function error.';

      if (code == 'invalid-argument') {
        return IdentifierAvailabilityResult.invalidInput(msg);
      }

      return IdentifierAvailabilityResult.failed.withError(
        errorCode: code,
        errorMessage: msg,
      );
    } catch (e) {
      return IdentifierAvailabilityResult.failed.withError(
        errorCode: 'exception',
        errorMessage: e.toString(),
      );
    }
  }
}