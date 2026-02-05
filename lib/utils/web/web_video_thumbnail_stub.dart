import 'dart:typed_data';

Future<Uint8List?> webVideoThumbnailFromBytes(
    Uint8List bytes, {
      int timeMs = 0,
      int maxWidth = 360,
      int quality = 75, // keep identical to web impl
      String mimeType = 'video/mp4', // keep identical to web impl
    }) async {
  return null; // non-web fallback
}
