// lib/screens/chat/chat_media_service.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as img;

import 'package:path_provider/path_provider.dart';

import '../../utils/io_compat.dart';

// ✅ WEB thumbnail helper (single, correct conditional import)
import '../../utils/web/web_video_thumbnail_stub.dart'
if (dart.library.html) '../../utils/web/web_video_thumbnail.dart';

// ✅ Native (io) thumbnail helper (web-safe via conditional import)
import '../../utils/video_thumbnail_compat_stub.dart'
if (dart.library.io) '../../utils/video_thumbnail_compat_io.dart';

// ✅ IO File wrapper (required for putFile without breaking web builds)
import '../../utils/io/io_file_stub.dart'
if (dart.library.io) '../../utils/io/io_file.dart';

class ChatMediaService {
  final String roomId;
  final String currentUserId;
  final String? otherUserId;

  final bool Function() isBlocked;
  final bool Function() canSendMessages;
  final String? Function(String) validateMessageContent;

  ChatMediaService({
    required this.roomId,
    required this.currentUserId,
    required this.otherUserId,
    required this.isBlocked,
    required this.canSendMessages,
    required this.validateMessageContent,
  });

  final ImagePicker _imagePicker = ImagePicker();

  // =========================
  // Pickers
  // =========================

  Future<PlatformFile?> pickImageFromGallery() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return null;

    return PlatformFile(
      name: picked.name,
      size: bytes.length,
      bytes: bytes,
      path: kIsWeb ? null : picked.path,
    );
  }

  Future<PlatformFile?> pickVideoFromGallery() async {
    final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return null;

    // ✅ Web needs bytes. Mobile should rely on path (avoid loading huge video into RAM).
    Uint8List? bytes;
    if (kIsWeb) {
      try {
        final b = await picked.readAsBytes();
        bytes = b.isNotEmpty ? b : null;
      } catch (_) {
        bytes = null;
      }
    } else {
      bytes = null;
    }

    final path = kIsWeb ? null : picked.path;

    return PlatformFile(
      name: picked.name,
      size: bytes?.length ?? 0,
      bytes: bytes,
      path: path,
    );
  }

  Future<Uint8List> _normalizeCapturedPhotoBytes({
    required Uint8List originalBytes,
    required CameraDevice deviceUsed,
  }) async {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) return originalBytes;

    img.Image fixed = img.bakeOrientation(decoded);

    // Front camera mirroring fix
    if (deviceUsed == CameraDevice.front) {
      fixed = img.flipHorizontal(fixed);
    }

    return Uint8List.fromList(img.encodeJpg(fixed, quality: 92));
  }

  Future<PlatformFile?> captureImageWithCamera({
    CameraDevice preferredCamera = CameraDevice.rear,
  }) async {
    if (kIsWeb) return null;

    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: preferredCamera,
    );
    if (picked == null) return null;

    final originalBytes = await picked.readAsBytes();
    if (originalBytes.isEmpty) return null;

    final fixedBytes = await _normalizeCapturedPhotoBytes(
      originalBytes: originalBytes,
      deviceUsed: preferredCamera,
    );

    try {
      await writeFileBytes(picked.path, fixedBytes);
    } catch (_) {}

    return PlatformFile(
      name: picked.name,
      size: fixedBytes.length,
      bytes: fixedBytes,
      path: picked.path,
    );
  }

  Future<PlatformFile?> captureVideoWithCamera({
    CameraDevice preferredCamera = CameraDevice.rear,
  }) async {
    if (kIsWeb) return null;

    final picked = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 2),
      preferredCameraDevice: preferredCamera,
    );
    if (picked == null) return null;

    final normalizedPath = picked.path.startsWith('file://')
        ? picked.path.replaceFirst('file://', '')
        : picked.path;

    // ✅ Do NOT read bytes on mobile (huge). Upload will use putFile(path).
    return PlatformFile(
      name: picked.name,
      size: 0,
      bytes: null,
      path: normalizedPath,
    );
  }

  Future<PlatformFile?> pickFileFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true, // ✅ keep true (iOS/web reliability)
      withReadStream: false,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  // =========================
  // Classification
  // =========================

  (String type, String contentType) classifyFile(PlatformFile file) {
    String ext = (file.extension ?? '').trim();
    if (ext.isEmpty) ext = p.extension(file.name).replaceFirst('.', '');
    ext = ext.toLowerCase();

    final lowerName = file.name.toLowerCase();

    final looksLikeVoice = lowerName.contains('voice_') ||
        lowerName.contains('voice-message') ||
        lowerName.contains('voice_message') ||
        lowerName.contains('audio_message') ||
        lowerName.contains('record');

    if (ext == 'webm' && looksLikeVoice) {
      return ('audio', 'audio/webm');
    }

    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) {
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
      return ('image', mime);
    }

    if (['mp4', 'mov', 'mkv', 'avi', 'm4v'].contains(ext)) {
      // Keep mp4 content-type for wide compatibility
      return ('video', 'video/mp4');
    }

    if (ext == 'webm') {
      return ('video', 'video/webm');
    }

    if (['mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus'].contains(ext)) {
      if (ext == 'mp3') return ('audio', 'audio/mpeg');
      if (ext == 'wav') return ('audio', 'audio/wav');
      if (ext == 'm4a') return ('audio', 'audio/mp4');
      if (ext == 'aac') return ('audio', 'audio/aac');
      if (ext == 'ogg') return ('audio', 'audio/ogg');
      if (ext == 'opus') return ('audio', 'audio/opus');
      return ('audio', 'audio/mpeg');
    }

    if (ext == 'pdf') return ('file', 'application/pdf');

    return ('file', 'application/octet-stream');
  }

  // =========================
  // Video thumb generation (web + native)
  // =========================

  Future<String?> _ensureLocalVideoPath(PlatformFile file) async {
    if (kIsWeb) return null;

    final rawPath = (file.path ?? '').trim();
    if (rawPath.isNotEmpty) {
      return rawPath.startsWith('file://')
          ? rawPath.replaceFirst('file://', '')
          : rawPath;
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;

    try {
      final dir = await getTemporaryDirectory();
      final ext = (file.extension ?? p.extension(file.name).replaceFirst('.', '')).trim();
      final safeExt = ext.isNotEmpty ? ext : 'mp4';
      final tmpPath = p.join(
        dir.path,
        'mw_vid_${DateTime.now().millisecondsSinceEpoch}.$safeExt',
      );
      await writeFileBytes(tmpPath, bytes);
      return tmpPath;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _tryBuildVideoThumbBytes(PlatformFile file) async {
    // ✅ WEB: generate thumbnail from bytes
    if (kIsWeb) {
      final b = file.bytes;
      if (b == null || b.isEmpty) return null;

      try {
        Uint8List? thumb = await webVideoThumbnailFromBytes(b, timeMs: 500);
        thumb ??= await webVideoThumbnailFromBytes(b, timeMs: 0);
        if (thumb == null || thumb.isEmpty) return null;
        return thumb;
      } catch (_) {
        return null;
      }
    }

    // ✅ iOS/Android/Desktop
    final localPath = await _ensureLocalVideoPath(file);
    if (localPath == null || localPath.isEmpty) return null;

    // Uses conditional import wrapper (safe for web builds)
    final thumb = await nativeVideoThumbnailData(
      videoPath: localPath,
      timeMs: 0,
      maxHeight: 360,
      quality: 75,
    );
    if (thumb == null || thumb.isEmpty) return null;
    return thumb;
  }

  // =========================
  // Bytes helpers (upload from bytes or from path)
  // =========================

  Future<Uint8List?> _bytesForUpload(PlatformFile file) async {
    final b = file.bytes;
    if (b != null && b.isNotEmpty) return b;

    if (kIsWeb) return null;

    final rawPath = (file.path ?? '').trim();
    if (rawPath.isEmpty) return null;

    final normalizedPath =
    rawPath.startsWith('file://') ? rawPath.replaceFirst('file://', '') : rawPath;

    try {
      final diskBytes = await XFile(normalizedPath).readAsBytes();
      if (diskBytes.isEmpty) return null;
      return diskBytes;
    } catch (e) {
      debugPrint('[ChatMediaService] _bytesForUpload failed: $e');
      return null;
    }
  }

  int _effectiveFileSize(PlatformFile file) {
    final s = file.size;
    if (s > 0) return s;
    final b = file.bytes;
    if (b != null) return b.length;
    return 0;
  }

  // =========================
  // Sending / Upload
  // =========================

  Future<UploadTask?> sendFileMessage(
      PlatformFile file, {
        String? forcedType,
        String? forcedContentType,
        void Function(double progress)? onProgress,
        Map<String, dynamic>? extraMessageFields,
      }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    if (isBlocked() || !canSendMessages()) return null;

    final nameError = validateMessageContent(file.name);
    if (nameError != null) return null;

    final other = otherUserId;
    if (other == null || other.isEmpty) return null;

    final (autoType, autoContentType) = classifyFile(file);
    final msgType = forcedType ?? autoType;

    String ext = (file.extension ?? '').trim();
    if (ext.isEmpty) ext = p.extension(file.name).replaceFirst('.', '');
    ext = ext.toLowerCase();

    String contentType = forcedContentType ?? autoContentType;

    // Safety normalizations
    if (msgType == 'audio' && contentType.startsWith('video/')) {
      contentType = 'audio/webm';
    }
    if (msgType == 'audio' && ext == 'm4a') {
      contentType = 'audio/mp4';
    }
    if (msgType == 'audio' && ext == 'webm' && !contentType.startsWith('audio/')) {
      contentType = 'audio/webm';
    }

    final canUsePath = !kIsWeb && (file.path ?? '').trim().isNotEmpty;
    final hasBytes = (file.bytes != null && file.bytes!.isNotEmpty);

    // ✅ For web: must have bytes
    if (kIsWeb && !hasBytes) {
      debugPrint('[ChatMediaService] sendFileMessage(web): missing bytes for ${file.name}');
      return null;
    }

    // ✅ For mobile/desktop: require path OR bytes
    if (!kIsWeb && !hasBytes && !canUsePath) {
      debugPrint('[ChatMediaService] sendFileMessage: no bytes/path for ${file.name}');
      return null;
    }

    final safeExt = ext.isNotEmpty ? ext : 'bin';
    final base = p
        .basenameWithoutExtension(file.name)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');
    final storageName =
        '${DateTime.now().millisecondsSinceEpoch}_${base.isEmpty ? 'file' : base}.$safeExt';

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_uploads')
        .child(roomId)
        .child(storageName);

    final metadata = SettableMetadata(contentType: contentType);

    StreamSubscription<TaskSnapshot>? sub;

    // ✅ Prepare video thumb (best effort) BEFORE committing message
    Uint8List? thumbBytes;
    if (msgType == 'video') {
      thumbBytes = await _tryBuildVideoThumbBytes(file);
    }

    String? thumbUrl;
    String? thumbStoragePath;

    try {
      UploadTask uploadTask;

      // ✅ Prefer putFile on non-web when we have a path (prevents huge memory usage)
      final rawPath = (file.path ?? '').trim();
      final normalizedPath =
      rawPath.startsWith('file://') ? rawPath.replaceFirst('file://', '') : rawPath;

      final canUsePathUpload = !kIsWeb && normalizedPath.isNotEmpty;

      if (canUsePathUpload) {
        uploadTask = storageRef.putFile(ioFile(normalizedPath), metadata);
      } else {
        final data = await _bytesForUpload(file);
        if (data == null || data.isEmpty) {
          debugPrint('[ChatMediaService] sendFileMessage: could not read bytes for ${file.name}');
          return null;
        }
        uploadTask = storageRef.putData(data, metadata);
      }

      sub = uploadTask.snapshotEvents.listen((event) {
        if (onProgress != null && event.totalBytes > 0) {
          final progress = event.bytesTransferred / event.totalBytes;
          onProgress(progress.clamp(0.0, 1.0));
        }
      });

      final snap = await uploadTask;
      try {
        await sub.cancel();
      } catch (_) {}

      final downloadUrl = await snap.ref.getDownloadURL();
      final storagePath = snap.ref.fullPath;

      // ✅ Upload thumb if we have it (web/native)
      if (thumbBytes != null && thumbBytes.isNotEmpty) {
        try {
          final thumbRef = FirebaseStorage.instance
              .ref()
              .child('chat_uploads')
              .child(roomId)
              .child('thumbs')
              .child('${p.basenameWithoutExtension(storageName)}.jpg');

          final thumbSnap = await thumbRef.putData(
            thumbBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );

          thumbUrl = await thumbSnap.ref.getDownloadURL();
          thumbStoragePath = thumbSnap.ref.fullPath;
        } catch (e) {
          debugPrint('[ChatMediaService] thumb upload failed (non-fatal): $e');
          thumbUrl = null;
          thumbStoragePath = null;
        }
      }

      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final profileUrl = userData?['profileUrl'];
      final avatarType = userData?['avatarType'];

      final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(roomId);
      final msgRef = roomRef.collection('messages').doc();

      final batch = FirebaseFirestore.instance.batch();

      final cleanedThumbUrl = (thumbUrl ?? '').trim().isEmpty ? null : thumbUrl!.trim();
      final cleanedThumbPath =
      (thumbStoragePath ?? '').trim().isNotEmpty ? thumbStoragePath!.trim() : null;

      final msgPayload = <String, dynamic>{
        'type': msgType,
        'text': '',
        'fileName': file.name,
        'fileUrl': downloadUrl,
        'storagePath': storagePath,
        'fileSize': _effectiveFileSize(file),
        'mimeType': contentType,
        'senderId': user.uid,
        'senderEmail': user.email,
        'profileUrl': profileUrl,
        'avatarType': avatarType,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
        'seenBy': <String>[],

        // ✅ Store thumb under multiple keys for backward/forward compatibility
        if (msgType == 'video' && cleanedThumbUrl != null) ...{
          'thumbUrl': cleanedThumbUrl,
          'thumbnailUrl': cleanedThumbUrl,
          'videoThumbUrl': cleanedThumbUrl,
        },
        if (msgType == 'video' && cleanedThumbPath != null)
          'thumbStoragePath': cleanedThumbPath,
      };

      if (extraMessageFields != null && extraMessageFields.isNotEmpty) {
        extraMessageFields.forEach((k, v) {
          if (!msgPayload.containsKey(k)) {
            msgPayload[k] = v;
          }
        });
      }

      batch.set(msgRef, msgPayload);

      batch.set(
        roomRef,
        {
          'participants': [user.uid, other],
          'unreadCounts': {
            other: FieldValue.increment(1),
            user.uid: 0,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      // Return the (already-finished) task for compatibility with your existing workflow.
      return uploadTask;
    } catch (e, st) {
      debugPrint('[ChatMediaService] sendFileMessage error: $e\n$st');
      try {
        await sub?.cancel();
      } catch (_) {}
      return null;
    }
  }

  void dispose() {}
}
