// lib/features/stories/data/story_repository.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../utils/io/io_file_stub.dart'
if (dart.library.io) '../../../utils/io/io_file.dart';

import '../models/story_model.dart';

import '../../../utils/web/web_video_thumbnail_stub.dart'
if (dart.library.html) '../../../utils/web/web_video_thumbnail.dart';

import '../../../utils/video_thumbnail_compat_stub.dart'
if (dart.library.io) '../../../utils/video_thumbnail_compat_io.dart';

class StoryRepository {
  StoryRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _stories =>
      _firestore.collection('stories');

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user found.');
    }
    return user;
  }

  String get currentUserId => _currentUser.uid;

  Future<void> createTextStory({
    required String text,
    StoryVisibility visibility = StoryVisibility.public,
    List<String> allowedViewerIds = const [],
    String? backgroundColor,
    String? textColor,
    String? linkUrl,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      throw ArgumentError('Story text cannot be empty.');
    }

    final now = DateTime.now();
    final doc = _stories.doc();

    final story = StoryModel(
      id: doc.id,
      ownerId: currentUserId,
      mediaUrl: null,
      mediaType: StoryMediaType.text,
      text: clean,
      visibility: visibility,
      allowedViewerIds: visibility == StoryVisibility.custom
          ? _cleanViewerIds(allowedViewerIds)
          : const [],
      viewerIds: const [],
      viewerCount: 0,
      backgroundColor: _normalizeHexColor(backgroundColor) ?? '#1C1F2A',
      textColor: _normalizeHexColor(textColor) ?? '#FFFFFF',
      linkUrl: _normalizeLinkUrl(linkUrl),
      createdAt: now,
      updatedAt: now,
      expiresAt: StoryModel.defaultExpiresAt(),
    );

    await doc.set(story.toMap());
  }

  Future<StoryModel> createMediaStory({
    required PlatformFile file,
    required StoryMediaType mediaType,
    StoryVisibility visibility = StoryVisibility.public,
    List<String> allowedViewerIds = const [],
    String? text,
    String? backgroundColor,
    String? textColor,
    String? linkUrl,
    void Function(double progress)? onProgress,
  }) async {
    if (mediaType == StoryMediaType.text) {
      throw ArgumentError('Use createTextStory for text stories.');
    }

    final user = _currentUser;
    final now = DateTime.now();

    final prepared = await _preparePlatformFileForUpload(
      file,
      forcedType: mediaType == StoryMediaType.video ? 'video' : 'image',
    );

    final ext = _readExtension(
      prepared,
      fallback: mediaType == StoryMediaType.video ? 'mp4' : 'jpg',
    );

    final baseName = p
        .basenameWithoutExtension(prepared.name)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');

    final safeBase = baseName.trim().isEmpty ? 'story' : baseName.trim();
    final storageFileName =
        '${DateTime.now().millisecondsSinceEpoch}_${safeBase}.$ext';

    final storyRef = _stories.doc();
    final mediaRef = _storage
        .ref()
        .child('story_uploads')
        .child(user.uid)
        .child(storyRef.id)
        .child(storageFileName);

    final metadata = SettableMetadata(
      contentType: _contentTypeFor(mediaType, ext),
    );

    UploadTask uploadTask;
    StreamSubscription<TaskSnapshot>? sub;

    debugPrint(
      '[StoryRepository] createMediaStory upload start '
          'uid=${user.uid}, storyId=${storyRef.id}, path=${mediaRef.fullPath}, '
          'mediaType=${mediaType.value}, fileName=${prepared.name}',
    );
    try {
      final normalizedPath = _normalizePath(prepared.path);

      if (!kIsWeb && normalizedPath != null && normalizedPath.isNotEmpty) {
        uploadTask = mediaRef.putFile(ioFile(normalizedPath), metadata);
      } else {
        final bytes = await _bytesForUpload(prepared);
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Unable to read file bytes for story upload.');
        }
        uploadTask = mediaRef.putData(bytes, metadata);
      }

      sub = uploadTask.snapshotEvents.listen((event) {
        if (onProgress != null && event.totalBytes > 0) {
          onProgress(
            (event.bytesTransferred / event.totalBytes).clamp(0.0, 1.0),
          );
        }
      });

      final snap = await uploadTask;
      final mediaUrl = await snap.ref.getDownloadURL();
      debugPrint(
        '[StoryRepository] createMediaStory upload success '
            'uid=${user.uid}, storyId=${storyRef.id}, mediaUrl=$mediaUrl',
      );

      try {
        await sub.cancel();
      } catch (_) {}

      final story = StoryModel(
        id: storyRef.id,
        ownerId: user.uid,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        text: text?.trim().isEmpty ?? true ? null : text!.trim(),
        visibility: visibility,
        allowedViewerIds: visibility == StoryVisibility.custom
            ? _cleanViewerIds(allowedViewerIds)
            : const [],
        viewerIds: const [],
        viewerCount: 0,
        backgroundColor: _normalizeHexColor(backgroundColor),
        textColor: _normalizeHexColor(textColor),
        linkUrl: _normalizeLinkUrl(linkUrl),
        createdAt: now,
        updatedAt: now,
        expiresAt: StoryModel.defaultExpiresAt(),
      );

      await storyRef.set(story.toMap());
      return story;
    } on FirebaseException catch (e, st) {
      try {
        await sub?.cancel();
      } catch (_) {}

      debugPrint(
        '[StoryRepository] createMediaStory FirebaseException '
            'code=${e.code}, message=${e.message}, '
            'uid=${user.uid}, path=${mediaRef.fullPath}',
      );
      debugPrintStack(stackTrace: st);
      rethrow;
    } catch (e, st) {
      try {
        await sub?.cancel();
      } catch (_) {}

      debugPrint(
        '[StoryRepository] createMediaStory unexpected error '
            'uid=${user.uid}, path=${mediaRef.fullPath}, error=$e',
      );
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  Future<List<StoryModel>> fetchActiveStories({
    int limit = 100,
  }) async {
    final snap = await _stories
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return _normalizeVisibleStories(
      snap.docs.map(StoryModel.fromDoc).toList(),
    );
  }

  Stream<List<StoryModel>> watchActiveStories({
    int limit = 100,
  }) {
    return _stories
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => _normalizeVisibleStories(
        snap.docs.map(StoryModel.fromDoc).toList(),
      ),
    );
  }

  Stream<List<StoryModel>> watchMyActiveStories({
    int limit = 50,
  }) {
    return _stories
        .where('ownerId', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => _normalizeStories(
        snap.docs.map(StoryModel.fromDoc).toList(),
      ).where((s) => !s.isExpired).toList(),
    );
  }

  Future<void> markStorySeen(StoryModel story) async {
    final viewerId = currentUserId;

    debugPrint(
      '[StoryRepository] markStorySeen called -> storyId=${story.id}, ownerId=${story.ownerId}, viewerId=$viewerId',
    );

    if (viewerId == story.ownerId) {
      debugPrint('[StoryRepository] skipped -> viewer is owner');
      return;
    }

    if (!_canCurrentUserViewStory(story)) {
      debugPrint(
        '[StoryRepository] skipped -> viewer is not allowed to view storyId=${story.id}',
      );
      return;
    }

    final ref = _stories.doc(story.id);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);

      if (!snap.exists) {
        debugPrint('[StoryRepository] story not found -> ${story.id}');
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final ownerId = (data['ownerId'] ?? '').toString().trim();

      if (ownerId.isEmpty) {
        debugPrint(
          '[StoryRepository] transaction skip -> missing ownerId for storyId=${story.id}',
        );
        return;
      }

      if (ownerId == viewerId) {
        debugPrint('[StoryRepository] transaction skip -> viewer is owner');
        return;
      }

      final visibility = _readVisibility(data['visibility']);
      final allowedViewerIds = _readStringList(data['allowedViewerIds']);

      if (!_canUserViewRawStory(
        ownerId: ownerId,
        visibility: visibility,
        allowedViewerIds: allowedViewerIds,
        viewerId: viewerId,
      )) {
        debugPrint(
          '[StoryRepository] transaction skip -> viewer is not allowed for storyId=${story.id}',
        );
        return;
      }

      final currentViewerIds = _readStringList(data['viewerIds']);
      if (currentViewerIds.contains(viewerId)) {
        debugPrint('[StoryRepository] transaction skip -> already seen');
        return;
      }

      final nextViewerIds = <String>[
        ...currentViewerIds,
        viewerId,
      ].toSet().toList();

      final nextViewerCount = nextViewerIds.length;

      tx.update(ref, {
        'viewerIds': nextViewerIds,
        'viewerCount': nextViewerCount,
        'viewerTimestamps.$viewerId': FieldValue.serverTimestamp(),
        'viewedAt.$viewerId': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
        '[StoryRepository] transaction update -> storyId=${story.id}, viewerId=$viewerId, viewerCount=$nextViewerCount, viewerIds=${nextViewerIds.length}',
      );
    });

    debugPrint('[StoryRepository] markStorySeen success -> storyId=${story.id}');
  }

  Future<List<StoryModel>> markStoriesSeen(List<StoryModel> stories) async {
    if (stories.isEmpty) return stories;

    final viewerId = currentUserId;
    final updated = <StoryModel>[];

    for (final story in stories) {
      if (story.ownerId == viewerId || story.viewerIds.contains(viewerId)) {
        updated.add(story);
        continue;
      }

      try {
        await markStorySeen(story);

        final nextViewerIds = <String>[
          ...story.viewerIds,
          viewerId,
        ].toSet().toList();

        updated.add(
          story.copyWith(
            viewerIds: nextViewerIds,
            viewerCount: nextViewerIds.length,
          ),
        );
      } catch (e, st) {
        debugPrint(
          '[StoryRepository] markStoriesSeen item failed -> storyId=${story.id}, error=$e',
        );
        debugPrintStack(stackTrace: st);
        updated.add(story);
      }
    }

    return updated;
  }

  bool isStorySeen(StoryModel story, String viewerId) {
    return story.viewerIds.contains(viewerId);
  }

  bool isStoryGroupFullySeen(List<StoryModel> stories, String viewerId) {
    if (stories.isEmpty) return false;

    final visibleStories = stories
        .where((story) => _canUserViewStoryFor(story, viewerId))
        .toList();

    if (visibleStories.isEmpty) return false;

    for (final story in visibleStories) {
      if (story.ownerId == viewerId) continue;
      if (!story.viewerIds.contains(viewerId)) return false;
    }
    return true;
  }

  int unseenCountForGroup(List<StoryModel> stories, String viewerId) {
    int count = 0;

    for (final story in stories) {
      if (!_canUserViewStoryFor(story, viewerId)) continue;
      if (story.ownerId == viewerId) continue;
      if (!story.viewerIds.contains(viewerId)) {
        count++;
      }
    }

    return count;
  }

  Future<void> deleteStory(StoryModel story) async {
    if (story.ownerId != currentUserId) {
      throw StateError('You can only delete your own stories.');
    }

    final docRef = _stories.doc(story.id);

    try {
      if (story.mediaUrl != null && story.mediaUrl!.trim().isNotEmpty) {
        try {
          await _storage.refFromURL(story.mediaUrl!.trim()).delete();
        } catch (e, st) {
          debugPrint(
            '[StoryRepository] failed deleting media file for storyId=${story.id}: $e',
          );
          debugPrintStack(stackTrace: st);
        }
      }
    } finally {
      await docRef.delete();
    }
  }

  Future<Uint8List?> buildVideoThumbnailBytes(PlatformFile file) async {
    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return null;

      try {
        Uint8List? thumb =
        await webVideoThumbnailFromBytes(bytes, timeMs: 500);
        thumb ??= await webVideoThumbnailFromBytes(bytes, timeMs: 0);
        return (thumb == null || thumb.isEmpty) ? null : thumb;
      } catch (_) {
        return null;
      }
    }

    final localPath = await _ensureLocalPath(file, forcedType: 'video');
    if (localPath == null || localPath.isEmpty) return null;

    try {
      final thumb = await nativeVideoThumbnailData(
        videoPath: localPath,
        timeMs: 0,
        maxHeight: 360,
        quality: 75,
      );
      return (thumb == null || thumb.isEmpty) ? null : thumb;
    } catch (_) {
      return null;
    }
  }

  List<StoryModel> _normalizeVisibleStories(List<StoryModel> stories) {
    return _normalizeStories(stories)
        .where((s) => !s.isExpired)
        .where(_canCurrentUserViewStory)
        .toList();
  }

  List<StoryModel> _normalizeStories(List<StoryModel> stories) {
    final normalized = stories.where((s) => !s.isExpired).toList();

    normalized.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bTime.compareTo(aTime);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });

    return normalized;
  }

  bool _canCurrentUserViewStory(StoryModel story) {
    return _canUserViewStoryFor(story, currentUserId);
  }

  bool _canUserViewStoryFor(StoryModel story, String viewerId) {
    if (story.ownerId == viewerId) return true;

    switch (story.visibility) {
      case StoryVisibility.public:
        return true;
      case StoryVisibility.friends:
        return true;
      case StoryVisibility.custom:
        return story.allowedViewerIds.contains(viewerId);
    }
  }

  bool _canUserViewRawStory({
    required String ownerId,
    required StoryVisibility visibility,
    required List<String> allowedViewerIds,
    required String viewerId,
  }) {
    if (ownerId == viewerId) return true;

    switch (visibility) {
      case StoryVisibility.public:
        return true;
      case StoryVisibility.friends:
        return true;
      case StoryVisibility.custom:
        return allowedViewerIds.contains(viewerId);
    }
  }

  StoryVisibility _readVisibility(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';

    for (final item in StoryVisibility.values) {
      if (item.name.toLowerCase() == value) {
        return item;
      }
    }

    return StoryVisibility.public;
  }

  List<String> _cleanViewerIds(List<String> ids) {
    final me = currentUserId;
    return ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != me)
        .toSet()
        .toList();
  }

  List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const <String>[];

    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  String _readExtension(PlatformFile file, {required String fallback}) {
    final fromField = (file.extension ?? '').trim().toLowerCase();
    if (fromField.isNotEmpty) return fromField;

    final fromName =
    p.extension(file.name).replaceFirst('.', '').trim().toLowerCase();
    if (fromName.isNotEmpty) return fromName;

    return fallback;
  }

  String _contentTypeFor(StoryMediaType type, String ext) {
    final e = ext.toLowerCase();

    switch (type) {
      case StoryMediaType.image:
        if (e == 'png') return 'image/png';
        if (e == 'webp') return 'image/webp';
        if (e == 'gif') return 'image/gif';
        if (e == 'heic') return 'image/heic';
        return 'image/jpeg';

      case StoryMediaType.video:
        if (e == 'mov') return 'video/quicktime';
        if (e == 'm4v') return 'video/x-m4v';
        if (e == 'webm') return 'video/webm';
        if (e == 'mkv') return 'video/x-matroska';
        if (e == 'avi') return 'video/x-msvideo';
        return 'video/mp4';

      case StoryMediaType.text:
        return 'text/plain';
    }
  }

  String? _normalizePath(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('file://')) {
      return value.replaceFirst('file://', '');
    }
    return value;
  }

  String? _normalizeLinkUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    return 'https://$value';
  }

  String? _normalizeHexColor(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;

    final normalized = value.startsWith('#') ? value : '#$value';
    final hex = normalized.substring(1);

    if (hex.length != 6 && hex.length != 8) return null;
    final valid = RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
    if (!valid) return null;

    return normalized.toUpperCase();
  }

  Future<Uint8List?> _bytesForUpload(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return file.bytes!;
    }

    if (kIsWeb) return null;

    final path = _normalizePath(file.path);
    if (path == null || path.isEmpty) return null;

    try {
      return await ioFile(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _ensureLocalPath(
      PlatformFile file, {
        required String forcedType,
      }) async {
    final normalized = _normalizePath(file.path);
    if (!kIsWeb && normalized != null && normalized.isNotEmpty) {
      return normalized;
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty || kIsWeb) return null;

    try {
      final dir = await getTemporaryDirectory();
      final ext = _readExtension(
        file,
        fallback: forcedType == 'video' ? 'mp4' : 'jpg',
      );
      final tempPath = p.join(
        dir.path,
        'mw_story_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );

      await ioFile(tempPath).writeAsBytes(bytes, flush: true);
      return tempPath;
    } catch (_) {
      return null;
    }
  }

  Future<PlatformFile> _preparePlatformFileForUpload(
      PlatformFile pf, {
        required String forcedType,
      }) async {
    if (kIsWeb) return pf;

    final normalized = _normalizePath(pf.path);
    if (normalized != null && normalized.isNotEmpty) {
      if (normalized == pf.path) return pf;

      return PlatformFile(
        name: pf.name,
        size: pf.size,
        bytes: pf.bytes,
        path: normalized,
        readStream: pf.readStream,
      );
    }

    final bytes = pf.bytes;
    if (bytes == null || bytes.isEmpty) return pf;

    try {
      final dir = await getTemporaryDirectory();
      String ext = _readExtension(
        pf,
        fallback: forcedType == 'video' ? 'mp4' : 'jpg',
      );

      if (ext.isEmpty) {
        ext = forcedType == 'video' ? 'mp4' : 'jpg';
      }

      final path = p.join(
        dir.path,
        'mw_story_pick_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );

      await ioFile(path).writeAsBytes(bytes, flush: true);

      return PlatformFile(
        name: pf.name,
        size: bytes.length,
        path: path,
        bytes: null,
      );
    } catch (_) {
      return pf;
    }
  }
}