import 'dart:io';
import 'dart:typed_data';

class VoiceFileOpsPlatform {
  static Future<String> makeTempM4aPath() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory.systemTemp;
    return '${dir.path}/mw_voice_$ts.m4a';
  }

  static Future<void> deleteIfExists(String? path) async {
    final p = (path ?? '').trim();
    if (p.isEmpty) return;

    // Don't try to delete URLs / blob refs as files
    final isUrl = p.startsWith('http://') || p.startsWith('https://') || p.startsWith('blob:');
    if (isUrl) return;

    try {
      final f = File(p);
      final exists = await f.exists();
      if (exists) {
        await f.delete();
      }
    } catch (_) {
      // ignore (safe cleanup)
    }
  }

  static Future<Uint8List?> readBytesFromUrlIfWeb(String url) async {
    // Not web => always null
    return null;
  }
}
