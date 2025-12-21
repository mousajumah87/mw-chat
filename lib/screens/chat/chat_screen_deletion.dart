// lib/screens/chat/chat_screen_deletion.dart

import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/ui/mw_feedback.dart';

enum _DeleteMode { me, both, cancel }

class ChatScreenDeletion {
  // =========================
  // ✅ Public: clear entire chat
  // =========================
  static Future<void> confirmAndClearChat({
    required BuildContext context,
    required String roomId,
    required String currentUserId,
    required String? otherUserId,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    final mode = await showDialog<_DeleteMode>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.deleteChatTitle),
          content: Text(l10n.deleteChatDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_DeleteMode.cancel),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_DeleteMode.me),
              child: Text(l10n.deleteChatForMe),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_DeleteMode.both),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              child: Text(l10n.deleteChatForBoth),
            ),
          ],
        );
      },
    );

    if (mode == null || mode == _DeleteMode.cancel) return;

    final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(roomId);
    final messagesRef = roomRef.collection('messages');

    // Count (optional)
    int? totalMessages;
    try {
      final agg = await messagesRef.count().get();
      totalMessages = agg.count;
    } catch (_) {
      totalMessages = null;
    }

    if (totalMessages == 0) return;
    if (totalMessages == null) {
      final first = await messagesRef.limit(1).get();
      if (first.docs.isEmpty) return;
    }

    final ValueNotifier<int> processed = ValueNotifier<int>(0);
    int deletedFilesClientSide = 0;

    // Progress dialog
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) {
        return PopScope(
          canPop: false,
          child: ValueListenableBuilder<int>(
            valueListenable: processed,
            builder: (_, value, __) {
              final hasTotal = totalMessages != null && totalMessages! > 0;
              final double? pct = hasTotal ? (value / totalMessages!).clamp(0.0, 1.0) : null;

              return AlertDialog(
                title: Text(l10n.deletingChatInProgressTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pct != null) LinearProgressIndicator(value: pct) else const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    if (hasTotal) Text(l10n.deletingChatProgress(value, totalMessages!))
                    else Text('${l10n.deletingChatInProgressTitle} ($value)'),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    void closeProgressDialogIfOpen() {
      if (!context.mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }

    // -------------------------
    // Extractors (shared)
    // -------------------------
    Set<String> extractStoragePaths(Map<String, dynamic> data) {
      final paths = <String>{};

      void add(dynamic v) {
        if (v is String && v.trim().isNotEmpty) paths.add(v.trim());
      }

      add(data['storagePath']);
      add(data['thumbStoragePath']);
      add(data['thumbnailStoragePath']);

      final attachments = data['attachments'];
      if (attachments is List) {
        for (final item in attachments) {
          if (item is Map) {
            add(item['storagePath']);
            add(item['thumbStoragePath']);
            add(item['thumbnailStoragePath']);
          }
        }
      }

      final media = data['media'];
      if (media is Map) {
        add(media['storagePath']);
        add(media['thumbStoragePath']);
        add(media['thumbnailStoragePath']);
      }

      return paths;
    }

    Set<String> extractStorageUrls(Map<String, dynamic> data) {
      final urls = <String>{};

      void add(dynamic v) {
        if (v is String && v.trim().isNotEmpty) urls.add(v.trim());
      }

      add(data['fileUrl']);
      add(data['mediaUrl']);
      add(data['imageUrl']);
      add(data['videoUrl']);
      add(data['audioUrl']);
      add(data['voiceUrl']);
      add(data['thumbnailUrl']);
      add(data['thumbUrl']);
      add(data['url']);

      final attachments = data['attachments'];
      if (attachments is List) {
        for (final item in attachments) {
          if (item is String) {
            add(item);
          } else if (item is Map) {
            add(item['url']);
            add(item['fileUrl']);
            add(item['mediaUrl']);
            add(item['imageUrl']);
            add(item['videoUrl']);
            add(item['audioUrl']);
            add(item['voiceUrl']);
            add(item['thumbUrl']);
            add(item['thumbnailUrl']);
          }
        }
      }

      final media = data['media'];
      if (media is Map) {
        add(media['url']);
        add(media['fileUrl']);
        add(media['mediaUrl']);
        add(media['imageUrl']);
        add(media['videoUrl']);
        add(media['audioUrl']);
        add(media['voiceUrl']);
        add(media['thumbUrl']);
        add(media['thumbnailUrl']);
      }

      return urls;
    }

    String? storagePathFromUrl(String url) {
      try {
        final u = Uri.parse(url);

        if (u.scheme == 'gs') {
          final p = u.path;
          if (p.isEmpty) return null;
          return p.startsWith('/') ? p.substring(1) : p;
        }

        // https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<encodedPath>
        if (u.host.contains('firebasestorage.googleapis.com')) {
          final seg = u.pathSegments;
          final oIndex = seg.indexOf('o');
          if (oIndex != -1 && oIndex + 1 < seg.length) {
            return Uri.decodeComponent(seg[oIndex + 1]);
          }
        }

        // https://storage.googleapis.com/download/storage/v1/b/<bucket>/o/<encodedPath>
        if (u.host.contains('storage.googleapis.com')) {
          final seg = u.pathSegments;
          final oIndex = seg.indexOf('o');
          if (oIndex != -1 && oIndex + 1 < seg.length) {
            return Uri.decodeComponent(seg[oIndex + 1]);
          }
        }

        return null;
      } catch (_) {
        return null;
      }
    }

    Future<void> deleteOneStoragePathClient(String path) async {
      try {
        await FirebaseStorage.instance.ref().child(path).delete();
        deletedFilesClientSide++;
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found' || e.code == 'unauthorized') {
          debugPrint('[ChatScreenDeletion] Client Storage delete skipped: ${e.code} (path=$path)');
          return;
        }
        debugPrint('[ChatScreenDeletion] Client Storage delete failed: ${e.code} ${e.message} (path=$path)');
      } catch (e) {
        debugPrint('[ChatScreenDeletion] Client Storage delete failed: $e (path=$path)');
      }
    }

    Future<void> deleteOneStorageUrlClient(String url) async {
      final path = storagePathFromUrl(url);
      if (path != null && path.isNotEmpty) {
        await deleteOneStoragePathClient(path);
        return;
      }
      try {
        final ref = FirebaseStorage.instance.refFromURL(url);
        await ref.delete();
        deletedFilesClientSide++;
      } catch (e) {
        debugPrint('[ChatScreenDeletion] Client Storage delete failed: $e (url=$url)');
      }
    }

    Future<void> deleteStoragePathsClient(Set<String> paths) async {
      if (paths.isEmpty) return;
      const int chunkSize = 15;
      final list = paths.toList(growable: false);
      for (int i = 0; i < list.length; i += chunkSize) {
        final slice = list.sublist(i, (i + chunkSize) > list.length ? list.length : (i + chunkSize));
        await Future.wait(slice.map(deleteOneStoragePathClient));
      }
    }

    Future<void> deleteStorageUrlsClient(Set<String> urls) async {
      if (urls.isEmpty) return;
      const int chunkSize = 15;
      final list = urls.toList(growable: false);
      for (int i = 0; i < list.length; i += chunkSize) {
        final slice = list.sublist(i, (i + chunkSize) > list.length ? list.length : (i + chunkSize));
        await Future.wait(slice.map(deleteOneStorageUrlClient));
      }
    }

    // -------------------------
    // Main deletion
    // -------------------------
    try {
      const int pageSize = 400;
      DocumentSnapshot<Map<String, dynamic>>? lastDoc;

      // ✅ collect ALL storage paths for server-side deletion
      final allServerPaths = HashSet<String>();

      while (true) {
        Query<Map<String, dynamic>> q =
        messagesRef.orderBy(FieldPath.documentId).limit(pageSize);

        if (lastDoc != null) {
          q = q.startAfterDocument(lastDoc);
        }

        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        lastDoc = snap.docs.last;

        final batch = FirebaseFirestore.instance.batch();
        final pagePaths = HashSet<String>();
        final pageUrls = HashSet<String>();

        for (final doc in snap.docs) {
          final data = doc.data();

          if (mode == _DeleteMode.me) {
            batch.update(doc.reference, {
              'hiddenFor': FieldValue.arrayUnion([currentUserId]),
            });
            continue;
          }

          // ✅ For BOTH: collect per-doc paths + urls (covers video too)
          final p = extractStoragePaths(data);
          final u = extractStorageUrls(data);

          pagePaths.addAll(p);
          pageUrls.addAll(u);

          allServerPaths.addAll(p);

          // also convert urls -> path for server list (helps old messages)
          for (final url in u) {
            final path = storagePathFromUrl(url);
            if (path != null && path.isNotEmpty) allServerPaths.add(path);
          }

          batch.delete(doc.reference);
        }

        await batch.commit();

        // Best-effort client delete
        if (mode == _DeleteMode.both) {
          if (pagePaths.isNotEmpty) await deleteStoragePathsClient(pagePaths);
          if (pageUrls.isNotEmpty) await deleteStorageUrlsClient(pageUrls);
        }

        processed.value += snap.docs.length;
      }

      if (mode == _DeleteMode.both) {
        final Map<String, dynamic> unread = {};
        if (currentUserId.isNotEmpty) unread[currentUserId] = 0;
        if (otherUserId != null && otherUserId.isNotEmpty) unread[otherUserId] = 0;

        if (unread.isNotEmpty) {
          await roomRef.set({'unreadCounts': unread}, SetOptions(merge: true));
        }

        // ✅ Server-side purge (reliable)
        try {
          final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('purgeChatRoom');

          final res = await fn.call({
            'roomId': roomId,
            'paths': allServerPaths.toList(growable: false),
          });

          debugPrint('[ChatScreenDeletion] purgeChatRoom result: ${res.data}');
        } catch (e) {
          debugPrint('[ChatScreenDeletion] purgeChatRoom failed (non-fatal): $e');
        }
      }

      closeProgressDialogIfOpen();

      debugPrint(
        '[ChatScreenDeletion] Processed ${processed.value} messages; '
            'client-deleted=$deletedFilesClientSide; '
            'serverPaths=${allServerPaths.length} (mode=$mode)',
      );
    } catch (e, st) {
      debugPrint('[ChatScreenDeletion] clearChat error: $e\n$st');
      closeProgressDialogIfOpen();
      if (context.mounted) {
        await MwFeedback.error(context, message: l10n.chatHistoryDeleteFailed);
      }
    }
  }

  // =========================
  // ✅ NEW: delete ONE message (this fixes video delete UX)
  // =========================
  static Future<void> confirmAndDeleteMessage({
    required BuildContext context,
    required String roomId,
    required String messageId,
    required String currentUserId,
    required String? otherUserId,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    final mode = await showDialog<_DeleteMode>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.deleteMessageTitle), // make sure this key exists
          content: Text(l10n.deleteMessageDescription), // make sure this key exists
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_DeleteMode.cancel),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_DeleteMode.me),
              child: Text(l10n.deleteForMe),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_DeleteMode.both),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              child: Text(l10n.deleteForEveryone),
            ),
          ],
        );
      },
    );

    if (mode == null || mode == _DeleteMode.cancel) return;

    final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(roomId);
    final msgRef = roomRef.collection('messages').doc(messageId);

    // Small in-progress modal (so user sees “loading bar” for video too)
    final ValueNotifier<bool> inProgress = ValueNotifier<bool>(true);

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<bool>(
          valueListenable: inProgress,
          builder: (_, __, ___) {
            return AlertDialog(
              title: Text(l10n.deletingMessageInProgressTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(l10n.pleaseWait),
                ],
              ),
            );
          },
        ),
      ),
    );

    void closeProgressDialogIfOpen() {
      if (!context.mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }

    // ---- extractors (same logic as clear chat; keep consistent)
    Set<String> extractStoragePaths(Map<String, dynamic> data) {
      final paths = <String>{};

      void add(dynamic v) {
        if (v is String && v.trim().isNotEmpty) paths.add(v.trim());
      }

      add(data['storagePath']);
      add(data['thumbStoragePath']);
      add(data['thumbnailStoragePath']);

      final attachments = data['attachments'];
      if (attachments is List) {
        for (final item in attachments) {
          if (item is Map) {
            add(item['storagePath']);
            add(item['thumbStoragePath']);
            add(item['thumbnailStoragePath']);
          }
        }
      }

      final media = data['media'];
      if (media is Map) {
        add(media['storagePath']);
        add(media['thumbStoragePath']);
        add(media['thumbnailStoragePath']);
      }

      return paths;
    }

    Set<String> extractStorageUrls(Map<String, dynamic> data) {
      final urls = <String>{};

      void add(dynamic v) {
        if (v is String && v.trim().isNotEmpty) urls.add(v.trim());
      }

      add(data['fileUrl']);
      add(data['mediaUrl']);
      add(data['imageUrl']);
      add(data['videoUrl']);
      add(data['audioUrl']);
      add(data['voiceUrl']);
      add(data['thumbnailUrl']);
      add(data['thumbUrl']);
      add(data['url']);

      final attachments = data['attachments'];
      if (attachments is List) {
        for (final item in attachments) {
          if (item is String) {
            add(item);
          } else if (item is Map) {
            add(item['url']);
            add(item['fileUrl']);
            add(item['mediaUrl']);
            add(item['imageUrl']);
            add(item['videoUrl']);
            add(item['audioUrl']);
            add(item['voiceUrl']);
            add(item['thumbUrl']);
            add(item['thumbnailUrl']);
          }
        }
      }

      final media = data['media'];
      if (media is Map) {
        add(media['url']);
        add(media['fileUrl']);
        add(media['mediaUrl']);
        add(media['imageUrl']);
        add(media['videoUrl']);
        add(media['audioUrl']);
        add(media['voiceUrl']);
        add(media['thumbUrl']);
        add(media['thumbnailUrl']);
      }

      return urls;
    }

    String? storagePathFromUrl(String url) {
      try {
        final u = Uri.parse(url);

        if (u.scheme == 'gs') {
          final p = u.path;
          if (p.isEmpty) return null;
          return p.startsWith('/') ? p.substring(1) : p;
        }

        if (u.host.contains('firebasestorage.googleapis.com')) {
          final seg = u.pathSegments;
          final oIndex = seg.indexOf('o');
          if (oIndex != -1 && oIndex + 1 < seg.length) {
            return Uri.decodeComponent(seg[oIndex + 1]);
          }
        }

        if (u.host.contains('storage.googleapis.com')) {
          final seg = u.pathSegments;
          final oIndex = seg.indexOf('o');
          if (oIndex != -1 && oIndex + 1 < seg.length) {
            return Uri.decodeComponent(seg[oIndex + 1]);
          }
        }

        return null;
      } catch (_) {
        return null;
      }
    }

    Future<void> deleteOneStoragePathClient(String path) async {
      try {
        await FirebaseStorage.instance.ref().child(path).delete();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found' || e.code == 'unauthorized') {
          debugPrint('[ChatScreenDeletion] Client Storage delete skipped: ${e.code} (path=$path)');
          return;
        }
        debugPrint('[ChatScreenDeletion] Client Storage delete failed: ${e.code} ${e.message} (path=$path)');
      } catch (e) {
        debugPrint('[ChatScreenDeletion] Client Storage delete failed: $e (path=$path)');
      }
    }

    Future<void> deleteOneStorageUrlClient(String url) async {
      final path = storagePathFromUrl(url);
      if (path != null && path.isNotEmpty) {
        await deleteOneStoragePathClient(path);
        return;
      }
      try {
        final ref = FirebaseStorage.instance.refFromURL(url);
        await ref.delete();
      } catch (e) {
        debugPrint('[ChatScreenDeletion] Client Storage delete failed: $e (url=$url)');
      }
    }

    // ---- main
    try {
      final snap = await msgRef.get();
      if (!snap.exists) {
        closeProgressDialogIfOpen();
        if (context.mounted) {
          await MwFeedback.success(context, message: l10n.messageAlreadyDeleted);
        }
        return;
      }

      final data = (snap.data() as Map<String, dynamic>?) ?? <String, dynamic>{};

      if (mode == _DeleteMode.me) {
        await msgRef.update({
          'hiddenFor': FieldValue.arrayUnion([currentUserId]),
        });

        closeProgressDialogIfOpen();
        if (context.mounted) {
          await MwFeedback.success(context, message: l10n.deletedForMeSuccess);
        }
        return;
      }

      // BOTH:
      final paths = extractStoragePaths(data);
      final urls = extractStorageUrls(data);

      // serverPaths = paths + derived-from-urls
      final serverPaths = HashSet<String>()..addAll(paths);
      for (final u in urls) {
        final p = storagePathFromUrl(u);
        if (p != null && p.isNotEmpty) serverPaths.add(p);
      }

      // delete Firestore doc
      await msgRef.delete();

      // client best-effort delete (helps your UX)
      await Future.wait([
        ...paths.map(deleteOneStoragePathClient),
        ...urls.map(deleteOneStorageUrlClient),
      ]);

      // server purge (best)
      if (serverPaths.isNotEmpty) {
        try {
          final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('purgeChatRoom');

          final res = await fn.call({
            'roomId': roomId,
            'paths': serverPaths.toList(growable: false),
          });

          debugPrint('[ChatScreenDeletion] purgeChatRoom(single) result: ${res.data}');
        } catch (e) {
          debugPrint('[ChatScreenDeletion] purgeChatRoom(single) failed (non-fatal): $e');
        }
      }

      // Optional: keep unreadCounts sane when deleting for both
      final Map<String, dynamic> unread = {};
      if (currentUserId.isNotEmpty) unread[currentUserId] = 0;
      if (otherUserId != null && otherUserId.isNotEmpty) unread[otherUserId] = 0;
      if (unread.isNotEmpty) {
        await roomRef.set({'unreadCounts': unread}, SetOptions(merge: true));
      }

      closeProgressDialogIfOpen();
      if (context.mounted) {
        await MwFeedback.success(context, message: l10n.deletedForEveryoneSuccess);
      }
    } catch (e, st) {
      debugPrint('[ChatScreenDeletion] deleteMessage error: $e\n$st');
      closeProgressDialogIfOpen();
      if (context.mounted) {
        await MwFeedback.error(context, message: l10n.deleteMessageFailed);
      }
    } finally {
      inProgress.value = false;
    }
  }
}
