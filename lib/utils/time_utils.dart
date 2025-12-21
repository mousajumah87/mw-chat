// lib/utils/time_utils.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Chat-friendly timestamp formatting (relative + short).
String formatTimestamp(Timestamp? ts) {
  if (ts == null) return '';
  final date = ts.toDate();
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return DateFormat('hh:mm a').format(date);
  if (diff.inDays == 1) {
    return 'Yesterday ${DateFormat('hh:mm a').format(date)}';
  }
  return DateFormat('MMM d, hh:mm a').format(date);
}

/// Simple relative "last seen" formatting (good for chat lists).
String formatLastSeen(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${dt.year}/${dt.month}/${dt.day}';
}

/// Settings-friendly absolute timestamp (matches your attached Privacy screenshot).
/// Example: "2025-12-19 10:16"
String formatTimestampFull(Timestamp? ts) {
  if (ts == null) return '';
  final dt = ts.toDate();
  return DateFormat('yyyy-MM-dd HH:mm').format(dt);
}

// ----------------------------
// NEW: shared relative parts helper
// ----------------------------

enum RelativeUnit { minutes, hours, days }

class RelativeParts {
  final bool isJustNow;
  final RelativeUnit unit;
  final int value;

  const RelativeParts({
    required this.isJustNow,
    required this.unit,
    required this.value,
  });
}

/// Returns null if ts is null.
/// Used for localized UI (you map to l10n strings in widgets).
RelativeParts? lastSeenPartsFromTimestamp(Timestamp? ts) {
  if (ts == null) return null;

  final now = DateTime.now();
  final dt = ts.toDate();
  final diff = now.difference(dt);

  if (diff.inMinutes < 1) {
    return const RelativeParts(isJustNow: true, unit: RelativeUnit.minutes, value: 0);
  }
  if (diff.inMinutes < 60) {
    return RelativeParts(isJustNow: false, unit: RelativeUnit.minutes, value: diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return RelativeParts(isJustNow: false, unit: RelativeUnit.hours, value: diff.inHours);
  }
  return RelativeParts(isJustNow: false, unit: RelativeUnit.days, value: diff.inDays);
}
