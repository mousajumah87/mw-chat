import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

String formatLastSeen(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${dt.year}/${dt.month}/${dt.day}';
}

