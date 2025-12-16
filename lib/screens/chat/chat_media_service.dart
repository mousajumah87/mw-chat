// lib/screens/chat/chat_media_service.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
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

  // ================= PICKERS =================

  final ImagePicker _imagePicker = ImagePicker();

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

    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return null;

    return PlatformFile(
      name: picked.name,
      size: bytes.length,
      bytes: bytes,
      path: kIsWeb ? null : picked.path,
    );
  }

  // ✅ Normalize captured photo bytes (EXIF + optional mirror for front camera)
  Future<Uint8List> _normalizeCapturedPhotoBytes({
    required Uint8List originalBytes,
    required CameraDevice deviceUsed,
  }) async {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) return originalBytes;

    // Fix EXIF rotation (iOS/Android)
    img.Image fixed = img.bakeOrientation(decoded);

    // Mirror ONLY front camera photos
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

    // ✅ Overwrite local file safely (mobile/desktop only via io_compat)
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

    final bytes = await XFile(normalizedPath).readAsBytes();
    if (bytes.isEmpty) return null;

    return PlatformFile(
      name: picked.name,
      size: bytes.length,
      bytes: bytes,
      path: normalizedPath,
    );
  }

  // ================= FILE PICKER =================
  Future<PlatformFile?> pickFileFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  // ================= FILE CLASSIFIER (FIXED MIME TYPES) =================
  (String type, String contentType) classifyFile(PlatformFile file) {
    String ext = (file.extension ?? '').trim();
    if (ext.isEmpty) {
      ext = p.extension(file.name).replaceFirst('.', '');
    }
    ext = ext.toLowerCase();

    final lowerName = file.name.toLowerCase();
    final looksLikeVoice =
        lowerName.contains('voice_message') ||
            lowerName.contains('voice') ||
            lowerName.contains('record') ||
            lowerName.contains('audio_message');

    // ✅ Web voice notes are often .webm (opus)
    if (ext == 'webm' && looksLikeVoice) {
      return ('audio', 'audio/webm');
    }

    // Images
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) {
      return ('image', 'image/$ext');
    }

    // Videos
    if (['mp4', 'mov', 'mkv', 'avi'].contains(ext)) {
      return ('video', 'video/mp4');
    }

    // webm as video ONLY when not a voice-note
    if (ext == 'webm') {
      return ('video', 'video/webm');
    }

    // Audios
    if (['mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus'].contains(ext)) {
      if (ext == 'mp3') return ('audio', 'audio/mpeg');
      if (ext == 'wav') return ('audio', 'audio/wav');
      if (ext == 'm4a') return ('audio', 'audio/mp4'); // ✅ best for iOS
      if (ext == 'aac') return ('audio', 'audio/aac');
      if (ext == 'ogg') return ('audio', 'audio/ogg');
      if (ext == 'opus') return ('audio', 'audio/opus');
      return ('audio', 'audio/mpeg');
    }

    if (ext == 'pdf') return ('file', 'application/pdf');

    return ('file', 'application/octet-stream');
  }

  // ================= SEND FILE MESSAGE =================
  Future<UploadTask?> sendFileMessage(
      PlatformFile file, {
        String? forcedType,
        String? forcedContentType,
        void Function(double progress)? onProgress,
      }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || isBlocked() || !canSendMessages()) return null;

    final nameError = validateMessageContent(file.name);
    if (nameError != null) return null;

    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;

    final (autoType, autoContentType) = classifyFile(file);
    final msgType = forcedType ?? autoType;

    String ext = (file.extension ?? '').trim();
    if (ext.isEmpty) {
      ext = p.extension(file.name).replaceFirst('.', '');
    }
    ext = ext.toLowerCase();

    String contentType = forcedContentType ?? autoContentType;

    // ✅ Safety: force audio/* if msgType is audio
    if (msgType == 'audio' && contentType.startsWith('video/')) {
      contentType = 'audio/webm';
    }
    if (msgType == 'audio' && ext == 'm4a') {
      contentType = 'audio/mp4';
    }
    if (msgType == 'audio' && ext == 'webm' && !contentType.startsWith('audio/')) {
      contentType = 'audio/webm';
    }

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_uploads')
        .child(roomId)
        .child('${DateTime.now().millisecondsSinceEpoch}_${file.name}');

    final metadata = SettableMetadata(contentType: contentType);
    final uploadTask = storageRef.putData(bytes, metadata);

    uploadTask.snapshotEvents.listen((event) {
      if (onProgress != null && event.totalBytes > 0) {
        final progress = event.bytesTransferred / event.totalBytes;
        onProgress(progress);
      }
    });

    final snap = await uploadTask;
    final downloadUrl = await snap.ref.getDownloadURL();
    final storagePath = snap.ref.fullPath;

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final userData = userDoc.data();
    final profileUrl = userData?['profileUrl'];
    final avatarType = userData?['avatarType'];

    if (otherUserId == null) return uploadTask;

    final batch = FirebaseFirestore.instance.batch();
    final roomRef =
    FirebaseFirestore.instance.collection('privateChats').doc(roomId);
    final msgRef = roomRef.collection('messages').doc();

    batch.set(msgRef, {
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
      'seenBy': <String>[],
    });

    batch.set(
      roomRef,
      {
        'participants': [user.uid, otherUserId],
        'unreadCounts': {
          otherUserId!: FieldValue.increment(1),
          user.uid: 0,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
    return uploadTask;
  }

  // ================= VOICE RECORDING (MORE RELIABLE) =================

  final Record _audioRecorder = Record();

  bool isRecording = false;
  Timer? recordTimer;
  Duration recordDuration = Duration.zero;

  DateTime? _recordStartAt;

  static const int _minRecordMs = 700;
  static const int _minBytes = 2048;

  Future<bool> startVoiceRecording() async {
    if (isRecording) return false;

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      debugPrint('❌ Mic permission denied');
      return false;
    }

    try {
      if (kIsWeb) {
        await _audioRecorder.start();
      } else {
        await _audioRecorder.start(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          samplingRate: 44100,
        );
      }
    } catch (e) {
      debugPrint('❌ start recording failed: $e');
      return false;
    }

    isRecording = true;
    _recordStartAt = DateTime.now();
    recordDuration = Duration.zero;

    recordTimer?.cancel();
    recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      recordDuration = Duration(seconds: recordDuration.inSeconds + 1);
    });

    return true;
  }

  Future<PlatformFile?> stopVoiceRecording() async {
    if (!isRecording) return null;

    recordTimer?.cancel();
    isRecording = false;

    final startedAt = _recordStartAt;
    _recordStartAt = null;

    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (e) {
      debugPrint('⚠️ stop() error: $e');
      recordDuration = Duration.zero;
      return null;
    }

    recordDuration = Duration.zero;

    if (path == null || path.isEmpty) {
      debugPrint('🛑 Recording path is empty');
      return null;
    }

    final normalizedPath =
    path.startsWith('file://') ? path.replaceFirst('file://', '') : path;

    if (startedAt != null) {
      final ms = DateTime.now().difference(startedAt).inMilliseconds;
      if (ms < _minRecordMs) {
        debugPrint('🛑 Recording too short (${ms}ms) — ignoring');
        try {
          await deleteFileIfExists(normalizedPath);
        } catch (_) {}
        return null;
      }
    }

    try {
      final bytes = await XFile(normalizedPath).readAsBytes();
      if (bytes.isEmpty || bytes.length < _minBytes) {
        debugPrint('🛑 Recording bytes too small (${bytes.length}) — ignoring');
        try {
          await deleteFileIfExists(normalizedPath);
        } catch (_) {}
        return null;
      }

      String name;
      if (kIsWeb) {
        name = 'voice_message.webm';
      } else {
        name = p.basename(normalizedPath);
        if (!name.contains('.')) {
          name = '$name.m4a';
        }
      }

      return PlatformFile(
        name: name,
        size: bytes.length,
        bytes: bytes,
        path: kIsWeb ? null : normalizedPath,
      );
    } catch (e) {
      debugPrint('❌ Failed to read recorded file: $e');
      return null;
    }
  }

  Future<void> cancelVoiceRecording() async {
    if (!isRecording) return;

    recordTimer?.cancel();
    isRecording = false;
    _recordStartAt = null;
    recordDuration = Duration.zero;

    try {
      await _audioRecorder.stop();
    } catch (_) {}
  }

  void dispose() {
    recordTimer?.cancel();
    _audioRecorder.dispose();
  }
}
