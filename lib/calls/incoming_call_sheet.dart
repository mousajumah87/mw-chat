// lib/calls/incoming_call_sheet.dart

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class IncomingCallSheet extends StatelessWidget {
  /// Primary display label (e.g., caller name). Kept as `title` for compatibility.
  final String title;

  /// Optional secondary line (e.g., "MW Chat" / "Calling…" / phone/email).
  final String? subtitle;

  final String type; // 'audio' | 'video'
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.type,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final isVideo = type == 'video';
    final t = title.trim();
    final sub = (subtitle ?? '').trim();

    final heading = isVideo
        ? (l?.incomingCall_video ?? 'Incoming video call')
        : (l?.incomingCall_voice ?? 'Incoming voice call');

    final acceptLabel = l?.incomingCall_accept ?? 'Accept';
    final declineLabel = l?.incomingCall_decline ?? 'Decline';

    final unknownCaller = l?.incomingCall_unknownCaller ?? 'Unknown caller';

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: const BoxDecoration(
          color: Color(0xFF101018),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            Text(
              heading,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),

            if (sub.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                sub,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 10),

            Text(
              t.isNotEmpty ? t : unknownCaller,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onDecline,
                    icon: const Icon(Icons.call_end_rounded),
                    label: Text(declineLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.withOpacity(0.18),
                      foregroundColor: Colors.greenAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onAccept,
                    icon: Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded),
                    label: Text(acceptLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
