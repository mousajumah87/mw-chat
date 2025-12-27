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

import '../../utils/io_compat.dart';

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

    // Video can be big; try bytes, fallback to path on IO platforms.
    Uint8List bytes = Uint8List(0);
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      bytes = Uint8List(0);
    }

    if (bytes.isNotEmpty) {
      return PlatformFile(
        name: picked.name,
        size: bytes.length,
        bytes: bytes,
        path: kIsWeb ? null : picked.path,
      );
    }

    return PlatformFile(
      name: picked.name,
      size: 0,
      bytes: null,
      path: kIsWeb ? null : picked.path,
    );
  }

  Future<Uint8List> _normalizeCapturedPhotoBytes({
    required Uint8List originalBytes,
    required CameraDevice deviceUsed,
  }) async {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) return originalBytes;

    img.Image fixed = img.bakeOrientation(decoded);

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

    // Save fixed orientation back to disk (IO platforms only)
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

    Uint8List bytes = Uint8List(0);
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      bytes = Uint8List(0);
    }

    return PlatformFile(
      name: picked.name,
      size: bytes.isNotEmpty ? bytes.length : 0,
      bytes: bytes.isNotEmpty ? bytes : null,
      path: normalizedPath,
    );
  }

  Future<PlatformFile?> pickFileFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
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

    if (['mp4', 'mov', 'mkv', 'avi'].contains(ext)) {
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
  // Sending / Upload
  // =========================

  Future<UploadTask?> sendFileMessage(
      PlatformFile file, {
        String? forcedType,
        String? forcedContentType,
        void Function(double progress)? onProgress,

        /// ✅ extra fields merged into message doc (used for Reply, etc.)
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

    // Normalize audio edge cases
    if (msgType == 'audio' && contentType.startsWith('video/')) {
      contentType = 'audio/webm';
    }
    if (msgType == 'audio' && ext == 'm4a') {
      contentType = 'audio/mp4';
    }
    if (msgType == 'audio' && ext == 'webm' && !contentType.startsWith('audio/')) {
      contentType = 'audio/webm';
    }

    final Uint8List? bytes = file.bytes;
    final String? rawPath = file.path;

    final bool hasBytes = bytes != null && bytes.isNotEmpty;
    final bool canUsePath = !kIsWeb && rawPath != null && rawPath.trim().isNotEmpty;

    if (!hasBytes && !canUsePath) {
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

    UploadTask uploadTask;
    StreamSubscription<TaskSnapshot>? sub;

    try {
      if (hasBytes) {
        uploadTask = storageRef.putData(bytes!, metadata);
      } else {
        final normalizedPath = rawPath!.startsWith('file://')
            ? rawPath.replaceFirst('file://', '')
            : rawPath;

        Uint8List diskBytes = Uint8List(0);
        try {
          diskBytes = await XFile(normalizedPath).readAsBytes();
        } catch (e) {
          debugPrint('[ChatMediaService] XFile.readAsBytes failed: $e');
          diskBytes = Uint8List(0);
        }

        if (diskBytes.isEmpty) {
          debugPrint('[ChatMediaService] sendFileMessage: could not read bytes from $normalizedPath');
          return null;
        }

        uploadTask = storageRef.putData(diskBytes, metadata);
      }

      sub = uploadTask.snapshotEvents.listen((event) {
        if (onProgress != null && event.totalBytes > 0) {
          final progress = event.bytesTransferred / event.totalBytes;
          onProgress(progress.clamp(0.0, 1.0));
        }
      });

      final snap = await uploadTask;
      await sub.cancel();

      final downloadUrl = await snap.ref.getDownloadURL();
      final storagePath = snap.ref.fullPath;

      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final profileUrl = userData?['profileUrl'];
      final avatarType = userData?['avatarType'];

      final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(roomId);
      final msgRef = roomRef.collection('messages').doc();

      final batch = FirebaseFirestore.instance.batch();

      final msgPayload = <String, dynamic>{
        'type': msgType,
        'text': '',
        'fileName': file.name,
        'fileUrl': downloadUrl,
        'storagePath': storagePath,
        'fileSize': file.size,
        'mimeType': contentType,
        'senderId': user.uid,
        'senderEmail': user.email,
        'profileUrl': profileUrl,
        'avatarType': avatarType,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
        'seenBy': <String>[],
      };

      if (extraMessageFields != null && extraMessageFields.isNotEmpty) {
        // Do not allow override of critical fields
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
