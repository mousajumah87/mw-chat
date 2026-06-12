// lib/features/group/services/group_chat_service.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class GroupChatService {
  GroupChatService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('groupChats');

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchRoom(String roomId) {
    return _rooms.doc(roomId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
  }

  Future<String> createGroup({
    required String currentUserId,
    required String name,
    required List<String> memberIds,
    File? imageFile,
    Uint8List? imageBytes,
    String? imageFileName,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Group name is required.');
    }

    final cleanCurrentUserId = currentUserId.trim();
    if (cleanCurrentUserId.isEmpty) {
      throw Exception('Current user is missing.');
    }

    final uniqueMembers = <String>{
      cleanCurrentUserId,
      ...memberIds.map((e) => e.trim()).where((e) => e.isNotEmpty),
    }.toList();

    if (uniqueMembers.length < 3) {
      throw Exception('A group must include you and at least 2 members.');
    }

    final roomRef = _rooms.doc();
    final now = FieldValue.serverTimestamp();

    String? uploadedPhotoUrl;
    if (imageFile != null || imageBytes != null) {
      uploadedPhotoUrl = await _uploadGroupAvatar(
        roomId: roomRef.id,
        imageFile: imageFile,
        imageBytes: imageBytes,
        fileName: imageFileName,
      );
    }

    await roomRef.set({
      'type': 'group',
      'name': cleanName,
      'photoUrl': uploadedPhotoUrl,
      'memberIds': uniqueMembers,
      'participants': uniqueMembers,
      'adminIds': <String>[cleanCurrentUserId],
      'createdBy': cleanCurrentUserId,
      'createdAt': now,
      'updatedAt': now,
      'typingMembers': <String, dynamic>{},
      'lastMessageText': null,
      'lastMessageSenderId': null,
      'lastMessageSenderName': null,
      'lastMessageType': null,
    });

    return roomRef.id;
  }

  Future<void> updateGroupPhoto({
    required String roomId,
    required String userId,
    required String userName,
    File? imageFile,
    Uint8List? imageBytes,
    String? imageFileName,
  }) async {
    final cleanRoomId = roomId.trim();
    final cleanUserId = userId.trim();

    if (cleanRoomId.isEmpty) {
      throw Exception('Room id is required.');
    }
    if (cleanUserId.isEmpty) {
      throw Exception('User id is required.');
    }
    if (imageFile == null && imageBytes == null) {
      throw Exception('Group image is missing.');
    }

    final roomRef = _rooms.doc(cleanRoomId);
    final roomSnap = await roomRef.get();

    if (!roomSnap.exists) {
      throw Exception('Group not found.');
    }

    final data = roomSnap.data() ?? <String, dynamic>{};
    final memberIds = (data['memberIds'] as List? ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (!memberIds.contains(cleanUserId)) {
      throw Exception('Only group members can change the group image.');
    }

    final photoUrl = await _uploadGroupAvatar(
      roomId: cleanRoomId,
      imageFile: imageFile,
      imageBytes: imageBytes,
      fileName: imageFileName,
    );

    final cleanUserName = userName.trim().isEmpty ? 'A member' : userName.trim();
    final systemText = '$cleanUserName changed the group photo';

    final batch = _firestore.batch();

    batch.set(
      roomRef,
      {
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessageText': systemText,
        'lastMessageSenderId': cleanUserId,
        'lastMessageSenderName': cleanUserName,
        'lastMessageType': 'system',
      },
      SetOptions(merge: true),
    );

    final systemMsgRef = roomRef.collection('messages').doc();
    batch.set(systemMsgRef, {
      'type': 'system',
      'text': systemText,
      'senderId': cleanUserId,
      'senderName': cleanUserName,
      'senderPhotoUrl': null,
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.now(),
      'editedAt': null,
      'deletedForEveryone': false,
      'deletedAt': null,
      'deletedBy': null,
      'hiddenFor': <String>[],
      'seenBy': <String>[],
      'replyTo': null,
      'replyToMessageId': null,
    });

    await batch.commit();
  }

  Future<void> sendTextMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    String? senderPhotoUrl,
    required String text,
    Map<String, dynamic>? replyTo,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final roomRef = _rooms.doc(roomId);
    final msgRef = roomRef.collection('messages').doc();

    final batch = _firestore.batch();

    batch.set(msgRef, {
      'type': 'text',
      'text': cleanText,
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': _cleanNullableString(senderPhotoUrl),
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.now(),
      'editedAt': null,
      'deletedForEveryone': false,
      'deletedAt': null,
      'deletedBy': null,
      'seenBy': <String>[senderId],
      'hiddenFor': <String>[],
      if (replyTo != null) 'replyTo': _sanitizeReplyTo(replyTo),
      if (replyTo != null &&
          (replyTo['messageId'] ?? '').toString().trim().isNotEmpty)
        'replyToMessageId': (replyTo['messageId'] ?? '').toString().trim(),
    });

    batch.set(
      roomRef,
      {
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessageText': cleanText,
        'lastMessageSenderId': senderId,
        'lastMessageSenderName': senderName,
        'lastMessageType': 'text',
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<void> deleteMessageForMe({
    required String roomId,
    required String messageId,
    required String userId,
  }) async {
    await _rooms.doc(roomId).collection('messages').doc(messageId).set(
      {
        'hiddenFor': FieldValue.arrayUnion([userId]),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteMessageForEveryone({
    required String roomId,
    required String messageId,
    required String deletedBy,
  }) async {
    await _rooms.doc(roomId).collection('messages').doc(messageId).set(
      {
        'deletedForEveryone': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': deletedBy,
        'text': 'This message was deleted',
      },
      SetOptions(merge: true),
    );
  }

  Future<void> leaveGroup({
    required String roomId,
    required String userId,
    required String userName,
  }) async {
    final roomRef = _rooms.doc(roomId);

    await _firestore.runTransaction((transaction) async {
      final roomSnap = await transaction.get(roomRef);
      if (!roomSnap.exists) {
        throw Exception('Group not found.');
      }

      final data = roomSnap.data() ?? <String, dynamic>{};
      final memberIds = (data['memberIds'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();
      final adminIds = (data['adminIds'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();
      final createdBy = (data['createdBy'] ?? '').toString().trim();

      final updatedMembers = memberIds.where((id) => id != userId).toList();
      final updatedAdmins = adminIds.where((id) => id != userId).toList();

      String? nextCreatedBy = createdBy.isEmpty ? null : createdBy;

      if (nextCreatedBy == userId) {
        nextCreatedBy = updatedAdmins.isNotEmpty
            ? updatedAdmins.first
            : (updatedMembers.isNotEmpty ? updatedMembers.first : null);
      }

      if (updatedMembers.isNotEmpty && updatedAdmins.isEmpty) {
        updatedAdmins.add(nextCreatedBy ?? updatedMembers.first);
      }

      final cleanUserName =
      userName.trim().isEmpty ? 'A member' : userName.trim();
      final systemText = '$cleanUserName left the group';

      transaction.set(
        roomRef,
        {
          'memberIds': updatedMembers,
          'participants': updatedMembers,
          'adminIds': updatedAdmins,
          'createdBy': nextCreatedBy,
          'updatedAt': FieldValue.serverTimestamp(),
          'typingMembers.$userId': FieldValue.delete(),
          'lastMessageText': systemText,
          'lastMessageSenderId': userId,
          'lastMessageSenderName': cleanUserName,
          'lastMessageType': 'system',
        },
        SetOptions(merge: true),
      );

      final systemMsgRef = roomRef.collection('messages').doc();
      transaction.set(systemMsgRef, {
        'type': 'system',
        'text': systemText,
        'senderId': userId,
        'senderName': cleanUserName,
        'senderPhotoUrl': null,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
        'editedAt': null,
        'deletedForEveryone': false,
        'deletedAt': null,
        'deletedBy': null,
        'hiddenFor': <String>[],
        'seenBy': <String>[],
        'replyTo': null,
        'replyToMessageId': null,
      });
    });
  }

  Future<String> _uploadGroupAvatar({
    required String roomId,
    File? imageFile,
    Uint8List? imageBytes,
    String? fileName,
  }) async {
    if (imageFile == null && imageBytes == null) {
      throw Exception('No image data provided.');
    }

    final extension = _normalizeImageExtension(
      fileName ??
          imageFile?.path.split('/').last ??
          'group_avatar.jpg',
    );

    final contentType = _contentTypeForExtension(extension);

    final ref = _storage.ref(
      'group_avatars/$roomId/${DateTime.now().millisecondsSinceEpoch}.$extension',
    );

    final metadata = SettableMetadata(contentType: contentType);

    if (imageBytes != null) {
      final task = await ref.putData(imageBytes, metadata);
      return task.ref.getDownloadURL();
    }

    final task = await ref.putFile(imageFile!, metadata);
    return task.ref.getDownloadURL();
  }

  String _normalizeImageExtension(String fileName) {
    final lower = fileName.toLowerCase().trim();

    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.jpeg')) return 'jpeg';
    if (lower.endsWith('.jpg')) return 'jpg';
    if (lower.endsWith('.heic')) return 'heic';
    if (lower.endsWith('.heif')) return 'heif';

    return 'jpg';
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  Map<String, dynamic> _sanitizeReplyTo(Map<String, dynamic> raw) {
    final messageId = (raw['messageId'] ?? '').toString().trim();
    final senderId = (raw['senderId'] ?? '').toString().trim();
    final senderName = (raw['senderName'] ?? '').toString().trim();
    final text = (raw['text'] ?? '').toString().trim();
    final previewText = (raw['previewText'] ?? '').toString().trim();
    final type = (raw['type'] ?? 'text').toString().trim();
    final fileName = (raw['fileName'] ?? '').toString().trim();

    final createdAt = raw['createdAt'];

    final result = <String, dynamic>{
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'previewText': previewText.isEmpty ? text : previewText,
      'type': type.isEmpty ? 'text' : type,
      if (fileName.isNotEmpty) 'fileName': fileName,
    };

    if (createdAt is Timestamp) {
      result['createdAt'] = createdAt;
    } else if (createdAt is DateTime) {
      result['createdAt'] = Timestamp.fromDate(createdAt);
    }

    return result;
  }

  String? _cleanNullableString(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}