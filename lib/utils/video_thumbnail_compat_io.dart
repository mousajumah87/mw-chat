import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

Future<Uint8List?> nativeVideoThumbnailData({
  required String videoPath,
  int timeMs = 0,
  int maxHeight = 360,
  int quality = 75,
}) async {
  try {
    final thumb = await VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      maxHeight: maxHeight,
      quality: quality,
      timeMs: timeMs,
    );
    if (thumb == null || thumb.isEmpty) return null;
    return thumb;
  } catch (_) {
    return null;
  }
}
