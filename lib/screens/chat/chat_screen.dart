// lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../utils/presence_service.dart';

// split-out widgets
import 'chat_app_bar.dart';
import 'chat_message_list.dart';

// Localization
import '../../l10n/app_localizations.dart';

// Shared MW background
import '../../widgets/ui/mw_background.dart';

// chat widgets
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String title; // other user email/name

  const ChatScreen({
    super.key,
    required this.roomId,
    required this.title,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgController = TextEditingController();
  bool _sending = false;

  late final String _currentUserId;
  String? _otherUserId;

  bool _isOtherTyping = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    _currentUserId = user?.uid ?? '';

    // Make sure *I* am marked online when entering a chat.
    PresenceService.instance.markOnline();

    // Infer other user from "uidA_uidB"
    final parts = widget.roomId.split('_');
    if (parts.length == 2 && _currentUserId.isNotEmpty) {
      if (parts[0] == _currentUserId) {
        _otherUserId = parts[1];
      } else if (parts[1] == _currentUserId) {
        _otherUserId = parts[0];
      }
    }

    debugPrint(
      '[ChatScreen] roomId=${widget.roomId}, '
          'currentUserId=$_currentUserId, otherUserId=$_otherUserId',
    );

    // ✅ When the chat is opened, reset my unread counter for this room.
    _resetMyUnread();

    // listen for typing flags
    _roomSub = FirebaseFirestore.instance
        .collection('privateChats')
        .doc(widget.roomId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || _otherUserId == null) return;
      final data = doc.data();
      if (data == null) return;

      final key = 'typing_${_otherUserId!}';
      final isTyping = data[key] == true;

      if (mounted) {
        setState(() {
          _isOtherTyping = isTyping;
        });
      }
    });
  }

  /// Reset my unread counter for this room to 0.
  Future<void> _resetMyUnread() async {
    if (_currentUserId.isEmpty) return;

    final roomRef =
    FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);

    try {
      await roomRef.set(
        {
          'unreadCounts': {_currentUserId: 0},
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('[ChatScreen] _resetMyUnread error: $e\n$st');
    }
  }

  /// Increase unread counter for the *other* user when I send a message.
  Future<void> _bumpUnreadForOther() async {
    if (_currentUserId.isEmpty || _otherUserId == null) return;

    final roomRef =
    FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);

    try {
      await roomRef.set(
        {
          'participants': [_currentUserId, _otherUserId],
          'unreadCounts': {
            // other user gets +1 unread
            _otherUserId!: FieldValue.increment(1),
            // my counter stays at 0 for this room
            _currentUserId: 0,
          },
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('[ChatScreen] _bumpUnreadForOther error: $e\n$st');
    }
  }

  Future<void> _updateMyTyping(bool isTyping) async {
    if (_currentUserId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('privateChats')
        .doc(widget.roomId)
        .set(
      {
        'typing_$_currentUserId': isTyping,
      },
      SetOptions(merge: true),
    );
  }

  // ---------- CLEAR CHAT / DELETE HISTORY ----------

  Future<void> _confirmAndClearChat() async {
    final l10n = AppLocalizations.of(context)!;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete chat'),
          content: const Text(
            'This will permanently delete all messages in this conversation '
                'for both of you. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      final roomRef = FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId);

      final msgsSnap = await roomRef.collection('messages').get();
      final batch = FirebaseFirestore.instance.batch();

      for (final doc in msgsSnap.docs) {
        batch.delete(doc.reference);
      }

      // Reset unread counts for both sides (if known)
      final Map<String, dynamic> unread = {};
      if (_currentUserId.isNotEmpty) unread[_currentUserId] = 0;
      if (_otherUserId != null) unread[_otherUserId!] = 0;

      if (unread.isNotEmpty) {
        batch.set(
          roomRef,
          {'unreadCounts': unread},
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat history deleted')),
      );
    } catch (e, st) {
      debugPrint('[ChatScreen] clearChat error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete chat. Please try again.'),
        ),
      );
    }
  }

  // ---------- TEXT MESSAGE ----------

  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      await _updateMyTyping(false);

      // load my profile / avatar info
      final meta = await _getSenderMeta(user);
      final profileUrl = meta['profileUrl'];
      final avatarType = meta['avatarType'];

      await FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId)
          .collection('messages')
          .add({
        'type': 'text',
        'text': text,
        'senderId': user.uid,
        'senderEmail': user.email,
        'profileUrl': profileUrl,
        'avatarType': avatarType,
        'createdAt': FieldValue.serverTimestamp(),
        'seenBy': <String>[],
      });

      // 🔔 increase unread for the other user
      await _bumpUnreadForOther();

      _msgController.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------- FILE UPLOADS ----------

  /// Pick a file from the device and send it as a message.
  Future<void> _pickAndSendFile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true, // important so we can upload bytes on web
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) return;

      final PlatformFile file = result.files.first;
      await _sendFileMessage(file);
    } catch (e, st) {
      debugPrint('Error picking/sending file: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToUploadFile)),
      );
    }
  }

  /// Classify file extension into message type + basic contentType for Storage.
  (String type, String? contentType) _classifyFile(PlatformFile file) {
    final ext = (file.extension ?? '').toLowerCase();

    // default
    String type = 'file';
    String? contentType;

    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) {
      type = 'image';
      if (ext == 'png') {
        contentType = 'image/png';
      } else if (ext == 'gif') {
        contentType = 'image/gif';
      } else {
        contentType = 'image/jpeg';
      }
    } else if (['mp4', 'mov', 'mkv', 'avi', 'webm'].contains(ext)) {
      type = 'video';
      contentType = 'video/mp4'; // generic, still matches video/.*
    } else if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(ext)) {
      type = 'audio';
      if (ext == 'wav') {
        contentType = 'audio/wav';
      } else if (ext == 'ogg') {
        contentType = 'audio/ogg';
      } else {
        contentType = 'audio/mpeg';
      }
    } else if (ext == 'pdf') {
      type = 'file';
      contentType = 'application/pdf';
    }

    return (type, contentType);
  }

  /// Upload file bytes to Firebase Storage and create a Firestore message.
  Future<void> _sendFileMessage(PlatformFile file) async {
    final user = FirebaseAuth.instance.currentUser;
    final l10n = AppLocalizations.of(context)!;

    if (user == null) {
      debugPrint('[_sendFileMessage] No user, aborting upload');
      return;
    }

    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      debugPrint(
        '[_sendFileMessage] File bytes are null – ensure withData: true on FilePicker',
      );
      return;
    }

    final (msgType, rawContentType) = _classifyFile(file);
    // Fallback so Storage rules don’t choke on null contentType
    final contentType = rawContentType ?? 'application/octet-stream';

    // path in Storage: chat_uploads/<roomId>/<timestamp>_<filename>
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_uploads')
        .child(widget.roomId)
        .child('${DateTime.now().millisecondsSinceEpoch}_${file.name}');

    String? downloadUrl;

    // 1) STORAGE UPLOAD
    try {
      debugPrint('[_sendFileMessage] Uploading as uid=${user.uid}');
      debugPrint('[_sendFileMessage] RoomId=${widget.roomId}');
      debugPrint(
        '[_sendFileMessage] File=${file.name}, size=${file.size}, contentType=$contentType',
      );

      final metadata = SettableMetadata(
        contentType: contentType,
      );

      await storageRef.putData(bytes, metadata);
      downloadUrl = await storageRef.getDownloadURL();

      debugPrint('[_sendFileMessage] Upload OK, url=$downloadUrl');
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[_sendFileMessage] STORAGE error '
            '[plugin=${e.plugin}, code=${e.code}]: ${e.message}\n$st',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.uploadFailedStorage)),
      );
      return; // don’t try to create Firestore message if upload failed
    } catch (e, st) {
      debugPrint('[_sendFileMessage] Unknown STORAGE error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.uploadFailedStorage)),
      );
      return;
    }

    // 2) FIRESTORE MESSAGE
    try {
      // sender profile info
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data();
      final profileUrl = userData?['profileUrl'];
      final avatarType = userData?['avatarType'];

      await FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId)
          .collection('messages')
          .add({
        'type': msgType, // text / image / video / audio / file
        'text': '', // label is derived in UI if empty
        'fileName': file.name,
        'fileUrl': downloadUrl,
        'fileSize': file.size,
        'mimeType': contentType,
        'senderId': user.uid,
        'senderEmail': user.email,
        'profileUrl': profileUrl,
        'avatarType': avatarType,
        'createdAt': FieldValue.serverTimestamp(),
        'seenBy': <String>[],
      });

      debugPrint('[_sendFileMessage] Firestore message created successfully');

      // 🔔 increase unread for the other user
      await _bumpUnreadForOther();
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[_sendFileMessage] FIRESTORE error '
            '[plugin=${e.plugin}, code=${e.code}]: ${e.message}\n$st',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.uploadFailedMessageSave)),
      );
    } catch (e, st) {
      debugPrint('[_sendFileMessage] Unknown FIRESTORE error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.uploadFailedMessageSave)),
      );
    }
  }

  /// Helper: load sender profile metadata (profileUrl + avatarType)
  Future<Map<String, dynamic>> _getSenderMeta(User user) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = snap.data() ?? {};

    final profileUrl = data['profileUrl'] as String?; // may be null
    final avatarType = data['avatarType'] as String?; // "smurf" / "bear" / etc.

    return {
      'profileUrl': profileUrl,
      'avatarType': avatarType,
    };
  }

  @override
  void dispose() {
    _msgController.dispose();
    _roomSub?.cancel();
    _updateMyTyping(false); // best-effort
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final otherUserId = _otherUserId;

    return Scaffold(
      appBar: ChatAppBar(
        title: widget.title,
        currentUserId: _currentUserId,
        otherUserId: otherUserId,
        onLogout: () async {
          await PresenceService.instance.markOffline();
          await FirebaseAuth.instance.signOut();
          if (context.mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
        // NEW: hook clear-chat button
        onClearChat: _confirmAndClearChat,
      ),
      body: MwBackground(
        child: Column(
          children: [
            // messages
            Expanded(
              child: ChatMessageList(
                roomId: widget.roomId,
                currentUserId: _currentUserId,
                otherUserId: otherUserId,
              ),
            ),

            // typing indicator
            TypingIndicator(
              isVisible: _isOtherTyping,
              text: l10n.isTyping(widget.title),
            ),

            // fancy composer bar
            SafeArea(
              top: false,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ChatInputBar(
                  controller: _msgController,
                  sending: _sending,
                  onAttach: _pickAndSendFile,
                  onSend: _sendMessage,
                  onTextChanged: (value) {
                    final hasText = value.trim().isNotEmpty;
                    _updateMyTyping(hasText);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
