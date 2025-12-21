import 'dart:typed_data';

class VoiceFileOpsPlatform {
  static Future<String> makeTempM4aPath() async {
    // Fallback (rarely used)
    return 'mw_voice.m4a';
  }

  static Future<void> deleteIfExists(String? path) async {
    return;
  }

  static Future<Uint8List?> readBytesFromUrlIfWeb(String url) async {
    return null;
  }
}
