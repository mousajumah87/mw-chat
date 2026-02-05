import 'dart:typed_data';

/// Web-safe stub: native video thumbnail is not available.
/// (Web uses webVideoThumbnailFromBytes instead.)
Future<Uint8List?> nativeVideoThumbnailData({
  required String videoPath,
  int timeMs = 0,
  int maxHeight = 360,
  int quality = 75,
}) async {
  return null;
}
