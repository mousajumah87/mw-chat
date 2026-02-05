// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> webVideoThumbnailFromBytes(
    Uint8List bytes, {
      int timeMs = 0,
      int maxWidth = 360,
      int quality = 75, // 0..100 (we map to 0..1 for canvas)
      String mimeType = 'video/mp4', // ✅ allow caller to pass real mime when known
    }) async {
  if (bytes.isEmpty) return null;

  String? url;
  try {
    // ✅ Use the provided mimeType (mp4/webm/etc.)
    final blob = html.Blob(<dynamic>[bytes], mimeType);
    url = html.Url.createObjectUrlFromBlob(blob);

    final video = html.VideoElement()
      ..src = url
      ..muted = true
      ..autoplay = false
      ..controls = false
      ..preload = 'auto'
      ..crossOrigin = 'anonymous';

    // critical for iOS Safari inline playback
    video.setAttribute('playsinline', 'true');
    video.setAttribute('webkit-playsinline', 'true');
    // Ensure it starts loading
    try {
      video.load();
    } catch (_) {}

    // 1) Wait metadata (dimensions, duration)
    await video.onLoadedMetadata.first.timeout(const Duration(seconds: 4));

    // 2) Wait until at least one frame is decodable
    // loadeddata = first frame available; canplay is also acceptable.
    try {
      await video.onLoadedData.first.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      // fallback: canplay
      await video.onCanPlay.first.timeout(const Duration(seconds: 4));
    }

    // 3) Seek to requested time (best effort)
    final targetSeconds = (timeMs <= 0) ? 0.0 : (timeMs / 1000.0);

    // Clamp to duration if known
    final dur = video.duration;
    final safeSeconds = (dur.isFinite && dur > 0)
        ? targetSeconds.clamp(0.0, (dur - 0.05).clamp(0.0, dur))
        : targetSeconds;

    try {
      video.currentTime = safeSeconds;
    } catch (_) {}

    // 4) Wait for seek completion (not always fired reliably, so timeout)
    try {
      await video.onSeeked.first.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // fallback: still try to draw
    }

    final vw = video.videoWidth;
    final vh = video.videoHeight;
    if (vw == 0 || vh == 0) return null;

    final scale = (vw > maxWidth) ? (maxWidth / vw) : 1.0;
    final w = (vw * scale).round().clamp(1, 4096);
    final h = (vh * scale).round().clamp(1, 4096);

    final canvas = html.CanvasElement(width: w, height: h);
    final ctx = canvas.context2D;

    // Some browsers need a tiny delay after seek to ensure frame is ready
    await Future<void>.delayed(const Duration(milliseconds: 16));

    ctx.drawImageScaled(video, 0, 0, w.toDouble(), h.toDouble());

    // quality: 0..1 for canvas
    final q = (quality.clamp(1, 100)) / 100.0;
    final dataUrl = canvas.toDataUrl('image/jpeg', q);

    final parts = dataUrl.split(',');
    if (parts.length != 2) return null;

    final raw = html.window.atob(parts[1]);
    final out = Uint8List(raw.length);
    for (var i = 0; i < raw.length; i++) {
      out[i] = raw.codeUnitAt(i);
    }
    return out;
  } catch (_) {
    return null;
  } finally {
    if (url != null) {
      try {
        html.Url.revokeObjectUrl(url);
      } catch (_) {}
    }
  }
}
