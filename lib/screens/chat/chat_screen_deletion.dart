// lib/screens/chat/chat_screen_deletion.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../l10n/app_localizations.dart';

enum _DeleteMode { me, both, cancel }

class ChatScreenDeletion {
  static Future<void> confirmAndClearChat({
    required BuildContext context,
    required String roomId,
    required String currentUserId,
    required String? otherUserId,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    // ✅ MODE SELECTION (Delete for me / Delete for both)
    final mode = await showDialog<_DeleteMode>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.deleteChatTitle),
          content: Text(l10n.deleteChatDescription),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_DeleteMode.cancel),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_DeleteMode.me),
              child: Text(l10n.deleteChatForMe),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_DeleteMode.both),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: Text(l10n.deleteChatForBoth),
            ),
          ],
        );
      },
    );

    if (mode == null || mode == _DeleteMode.cancel) return;

    final roomRef =
    FirebaseFirestore.instance.collection('privateChats').doc(roomId);

    // ✅ LOAD MESSAGES
    final msgsSnap = await roomRef.collection('messages').get();
    final totalMessages = msgsSnap.docs.length;

    // If there is nothing to delete, just return silently.
    if (totalMessages == 0) {
      return;
    }

    final ValueNotifier<int> progress = ValueNotifier<int>(0);
    int deletedFiles = 0;

    // ✅ LIVE PROGRESS DIALOG (SAFE ON ALL PLATFORMS)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, value, __) {
            return AlertDialog(
              title: Text(l10n.deletingChatInProgressTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: value / totalMessages,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.deletingChatProgress(
                      value,
                      totalMessages,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    try {
      const int batchLimit = 450;
      final docs = msgsSnap.docs;

      for (int i = 0; i < docs.length; i += batchLimit) {
        final batch = FirebaseFirestore.instance.batch();
        final chunk = docs.skip(i).take(batchLimit);

        final List<Future<void>> storageDeletes = [];

        for (final doc in chunk) {
          final data = doc.data();

          // ✅ DELETE FOR ME ONLY → HIDE MESSAGE
          if (mode == _DeleteMode.me) {
            batch.update(doc.reference, {
              'hiddenFor': FieldValue.arrayUnion([currentUserId])
            });
          }
          // ✅ DELETE FOR BOTH → DELETE MESSAGE + FILE
          else {
            final fileUrl = data['fileUrl'] as String?;
            if (fileUrl != null && fileUrl.isNotEmpty) {
              try {
                final ref = FirebaseStorage.instance.refFromURL(fileUrl);
                storageDeletes.add(
                  ref.delete().then((_) => deletedFiles++).catchError((_) {
                    debugPrint(
                      '[ChatScreenDeletion] File already missing → skip',
                    );
                  }),
                );
              } catch (_) {
                debugPrint(
                  '[ChatScreenDeletion] Invalid storage URL → skip',
                );
              }
            }

            batch.delete(doc.reference);
          }

          progress.value++;
        }

        await Future.wait(storageDeletes);
        await batch.commit();
      }

      // ✅ RESET UNREAD COUNTS ONLY WHEN DELETING FOR BOTH
      if (mode == _DeleteMode.both) {
        final Map<String, dynamic> unread = {};
        if (currentUserId.isNotEmpty) unread[currentUserId] = 0;
        if (otherUserId != null) unread[otherUserId] = 0;

        if (unread.isNotEmpty) {
          await roomRef.set(
            {'unreadCounts': unread},
            SetOptions(merge: true),
          );
        }
      }

      // ✅ CLOUD FUNCTION SAFETY CLEAN (DELETE FOR BOTH ONLY)
      if (mode == _DeleteMode.both) {
        try {
          await FirebaseFunctions.instance
              .httpsCallable('purgeChatRoom')
              .call({'roomId': roomId});
        } catch (e) {
          debugPrint(
            '[ChatScreenDeletion] Cloud purger failed (non-fatal): $e',
          );
        }
      }

      // ✅ FORCE CLOSE PROGRESS DIALOG
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      debugPrint(
        '[ChatScreenDeletion] Deleted ${progress.value} messages & $deletedFiles files (mode=$mode)',
      );

      // ✅ No success SnackBar → UI already reflects “No messages yet”
    } catch (e, st) {
      debugPrint('[ChatScreenDeletion] clearChat error: $e\n$st');

      // ✅ ALWAYS CLOSE DIALOG EVEN ON ERROR
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // ❗ Keep error feedback — this is important
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chatHistoryDeleteFailed)),
      );
    }
  }

}
