import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'voice_file_ops.dart';

class VoiceDraft {
  /// On mobile/desktop: real local path (m4a)
  /// On web: may be blob: URL (optional) but we primarily use bytes
  final String? path;

  /// On web: recorded bytes (webm/opus usually)
  /// On mobile/desktop: null (we use path)
  final Uint8List? bytes;

  final Duration duration;
  final String fileName;
  final String mimeType;

  const VoiceDraft({
    required this.duration,
    required this.fileName,
    required this.mimeType,
    this.path,
    this.bytes,
  });
}

class VoiceRecorderController extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isPreparing = false;
  bool _hasDraft = false;

  Duration _elapsed = Duration.zero;
  Timer? _tick;

  String? _currentPath;
  VoiceDraft? _draft;

  // Web streaming buffers (if startStream exists)
  StreamSubscription<Uint8List>? _webStreamSub;
  final List<Uint8List> _webChunks = <Uint8List>[];

  bool _disposed = false;

  bool get isRecording => _isRecording;
  bool get isPreparing => _isPreparing;
  bool get hasDraft => _hasDraft;
  Duration get elapsed => _elapsed;
  VoiceDraft? get draft => _draft;

  bool get isActive => _isRecording || _isPreparing;

  void _safeNotify() {
    if (_disposed) return;
    if (!hasListeners) return;
    notifyListeners();
  }

  bool _looksLikeUrl(String p) {
    final s = p.trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://') || s.startsWith('blob:');
  }

  bool _shouldDeletePath(String? p) {
    if (p == null) return false;
    final s = p.trim();
    if (s.isEmpty) return false;
    // On web, "path" might be a blob URL or http URL, never delete those.
    if (_looksLikeUrl(s)) return false;
    return true;
  }

  Future<void> start() async {
    if (_disposed) return;
    if (_isPreparing || _isRecording) return;

    // If there is an old draft, clear it (UX: starting a new recording replaces it)
    _draft = null;
    _hasDraft = false;

    _isPreparing = true;
    _safeNotify();

    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        _resetAll();
        return;
      }

      // Reset state
      _elapsed = Duration.zero;
      _currentPath = null;

      _tick?.cancel();
      _tick = null;

      await _webStreamSub?.cancel();
      _webStreamSub = null;
      _webChunks.clear();

      final RecordConfig config = RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: kIsWeb ? 48000 : 44100,
      );

      if (kIsWeb) {
        // Try startStream first (best). If not available, fallback to start().
        final dynamic rec = _recorder;
        bool streamStarted = false;

        try {
          final dynamic stream = await rec.startStream(config);
          if (stream is Stream<Uint8List>) {
            _webStreamSub = stream.listen(
                  (chunk) {
                if (_disposed) return;
                if (chunk.isNotEmpty) _webChunks.add(chunk);
              },
              onError: (e, st) {
                debugPrint('[VoiceRecorderController] web stream error: $e\n$st');
              },
            );
            streamStarted = true;
          }
        } catch (_) {
          streamStarted = false;
        }

        if (!streamStarted) {
          // Some record versions require path: even on web
          await _recorder.start(config, path: 'mw_voice.webm');
        }
      } else {
        final path = await VoiceFileOps.makeTempM4aPath();
        _currentPath = path;
        await _recorder.start(config, path: path);
      }

      _isPreparing = false;
      _isRecording = true;

      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_disposed) return;
        if (!_isRecording) return;
        _elapsed += const Duration(milliseconds: 200);
        _safeNotify();
      });

      _safeNotify();
    } catch (e, st) {
      debugPrint('[VoiceRecorderController] start failed: $e\n$st');
      _resetAll();
    }
  }

  Future<void> stopToPreview() async {
    if (_disposed) return;

    // If user tries to stop while permissions/init still running, just reset.
    if (_isPreparing && !_isRecording) {
      _resetAll();
      return;
    }

    if (!_isRecording) return;

    try {
      _tick?.cancel();
      _tick = null;

      final stoppedPathOrUrl = await _recorder.stop();
      _isRecording = false;

      final fileName =
          'voice_${DateTime.now().millisecondsSinceEpoch}${kIsWeb ? '.webm' : '.m4a'}';

      if (kIsWeb) {
        await _webStreamSub?.cancel();
        _webStreamSub = null;

        // Prefer streamed chunks; if empty, fallback to reading bytes from stop() URL
        Uint8List bytes = _combineChunks(_webChunks);
        _webChunks.clear();

        final stopUrl = (stoppedPathOrUrl ?? '').trim();
        if (bytes.isEmpty && stopUrl.isNotEmpty) {
          final fetched = await VoiceFileOps.readBytesFromUrlIfWeb(stopUrl);
          if (fetched != null && fetched.isNotEmpty) {
            bytes = fetched;
          }
        }

        if (bytes.isEmpty) {
          _resetAll();
          return;
        }

        _draft = VoiceDraft(
          duration: _elapsed,
          fileName: fileName,
          mimeType: 'audio/webm',
          bytes: bytes,
          path: stopUrl.isEmpty ? null : stopUrl,
        );
        _hasDraft = true;
        _safeNotify();
        return;
      }

      final p = (stoppedPathOrUrl ?? _currentPath ?? '').trim();
      if (p.isEmpty) {
        _resetAll();
        return;
      }

      _draft = VoiceDraft(
        duration: _elapsed,
        fileName: fileName,
        mimeType: 'audio/mp4', // m4a container
        path: p,
        bytes: null,
      );
      _hasDraft = true;
      _safeNotify();
    } catch (e, st) {
      debugPrint('[VoiceRecorderController] stopToPreview failed: $e\n$st');
      _resetAll();
    } finally {
      // Ensure preparing flag can't remain true here
      _isPreparing = false;
      _safeNotify();
    }
  }

  Future<void> cancel() async {
    if (_disposed) return;

    try {
      _tick?.cancel();
      _tick = null;

      // If we're preparing or recording, best-effort stop.
      if (_isRecording || _isPreparing) {
        try {
          await _recorder.stop();
        } catch (_) {
          // ignore
        }
      }

      await _webStreamSub?.cancel();
      _webStreamSub = null;
      _webChunks.clear();
    } catch (_) {}

    // Only delete real local paths
    if (_shouldDeletePath(_currentPath)) {
      await VoiceFileOps.deleteIfExists(_currentPath);
    }

    _resetAll();
  }

  Future<void> discardDraft() async {
    if (_disposed) return;

    final p = _draft?.path;
    if (_shouldDeletePath(p)) {
      await VoiceFileOps.deleteIfExists(p);
    }

    _draft = null;
    _hasDraft = false;
    _elapsed = Duration.zero;
    _safeNotify();
  }

  Future<void> markSentAndCleanup() async {
    if (_disposed) return;

    final p = _draft?.path;
    if (_shouldDeletePath(p)) {
      await VoiceFileOps.deleteIfExists(p);
    }

    _resetAll();
  }

  void _resetAll() {
    if (_disposed) return;

    _isPreparing = false;
    _isRecording = false;
    _hasDraft = false;

    _elapsed = Duration.zero;
    _currentPath = null;
    _draft = null;

    _tick?.cancel();
    _tick = null;

    _safeNotify();
  }

  /// Keeps your existing async cleanup API (safe to call from parent).
  Future<void> disposeController() async {
    if (_disposed) return;
    _disposed = true;

    _tick?.cancel();
    _tick = null;

    try {
      if (_isRecording || _isPreparing) {
        await _recorder.stop();
      }
    } catch (_) {}

    try {
      await _webStreamSub?.cancel();
    } catch (_) {}
    _webStreamSub = null;
    _webChunks.clear();

    try {
      if (_shouldDeletePath(_currentPath)) {
        await VoiceFileOps.deleteIfExists(_currentPath);
      }
      if (_shouldDeletePath(_draft?.path)) {
        await VoiceFileOps.deleteIfExists(_draft?.path);
      }
    } catch (_) {}

    try {
      _recorder.dispose();
    } catch (_) {}
  }

  /// ✅ Also implement ChangeNotifier dispose so you don’t leak listeners/timers.
  @override
  void dispose() {
    // best-effort async cleanup
    disposeController();
    super.dispose();
  }

  Uint8List _combineChunks(List<Uint8List> chunks) {
    if (chunks.isEmpty) return Uint8List(0);
    final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final out = Uint8List(total);
    int offset = 0;
    for (final c in chunks) {
      out.setRange(offset, offset + c.length, c);
      offset += c.length;
    }
    return out;
  }
}
