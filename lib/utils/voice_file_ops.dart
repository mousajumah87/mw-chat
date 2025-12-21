import 'dart:typed_data';
import 'voice_file_ops_stub.dart'
if (dart.library.io) 'voice_file_ops_io.dart'
if (dart.library.html) 'voice_file_ops_web.dart';

/// MW Voice file utilities (platform-safe)
///
/// Uses conditional imports:
/// - IO (iOS/Android/macOS/Windows/Linux): voice_file_ops_io.dart
/// - Web: voice_file_ops_web.dart
/// - Fallback: voice_file_ops_stub.dart
class VoiceFileOps {
  /// For iOS/Android: returns a temp .m4a file path.
  /// For Web: returns a dummy name (ignored by web recorder in most cases).
  static Future<String> makeTempM4aPath() => VoiceFileOpsPlatform.makeTempM4aPath();

  /// Safe deletion:
  /// - iOS/Android: deletes local file if it exists
  /// - Web: no-op (blob/http URLs are not deletable as local files)
  static Future<void> deleteIfExists(String? path) => VoiceFileOpsPlatform.deleteIfExists(path);

  /// Web-only helper to fetch bytes from a URL; returns null on non-web.
  static Future<Uint8List?> readBytesFromUrlIfWeb(String url) =>
      VoiceFileOpsPlatform.readBytesFromUrlIfWeb(url);
}
