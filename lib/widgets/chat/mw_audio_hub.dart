import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class MwAudioHub {
  MwAudioHub._() {
    // Keep activeMessageId in-sync with the real player lifecycle.
    _stateSub = player.onPlayerStateChanged.listen((s) {
      // When audio is fully stopped, clear active (prevents stale "active" bubble)
      if (s == PlayerState.stopped) {
        activeMessageId = null;
      }
    });

    _completeSub = player.onPlayerComplete.listen((_) {
      // When playback finishes, clear active (prevents stale active bubble)
      activeMessageId = null;
    });
  }

  static final MwAudioHub instance = MwAudioHub._();

  final AudioPlayer player = AudioPlayer();

  String? activeMessageId;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  bool isActive(String messageId) => activeMessageId == messageId;

  /// Keep for compatibility (your bubbles call it).
  Future<void> setActive(String messageId) async {
    activeMessageId = messageId;
  }

  /// ✅ Preferred: ensures only ONE active message at a time.
  /// Stops the previous active audio (if different), then marks this as active.
  Future<void> activate(String messageId) async {
    final current = activeMessageId;
    if (current != null && current != messageId) {
      try {
        await player.stop();
      } catch (_) {}
    }
    activeMessageId = messageId;
  }

  Future<void> stopIfActive(String messageId) async {
    if (!isActive(messageId)) return;
    try {
      await player.stop();
    } catch (_) {}
    activeMessageId = null;
  }

  /// Optional: call from app dispose if you ever need it.
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _completeSub?.cancel();
    try {
      await player.dispose();
    } catch (_) {}
  }
}
