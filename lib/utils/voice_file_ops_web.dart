import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class VoiceFileOpsPlatform {
  static Future<String> makeTempM4aPath() async {
    // On web, record plugin may require a "path" argument but it’s not a real file.
    return 'mw_voice.webm';
  }

  static Future<void> deleteIfExists(String? path) async {
    // Web: local file deletion doesn't apply; blobs/urls are managed by browser.
    return;
  }

  static Future<Uint8List?> readBytesFromUrlIfWeb(String url) async {
    if (!kIsWeb) return null;

    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    try {
      final res = await http.get(uri);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return res.bodyBytes;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }
}
