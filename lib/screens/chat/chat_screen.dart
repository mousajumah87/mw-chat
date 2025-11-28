// lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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

  // lightweight typing debounce (to avoid hammering Firestore)
  Timer? _typingDebounce;
  bool _isMeTypingFlag = false;

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

    // When the chat is opened, reset my unread counter for this room.
    _resetMyUnread();

    // listen for typing flags (other user)
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
            _otherUserId!: FieldValue.increment(1),
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

  /// Debounced handler for text changes in the composer.
  void _onComposerChanged(String value) {
    final hasText = value.trim().isNotEmpty;

    // only send "true" when transitioning from not-typing -> typing
    if (hasText && !_isMeTypingFlag) {
      _isMeTypingFlag = true;
      _updateMyTyping(true);
    }

    // reset timer; when user stops for 600ms, send "false"
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 600), () {
      _isMeTypingFlag = false;
      _updateMyTyping(false);
    });
  }

  // ---------- CLEAR CHAT / DELETE HISTORY ----------

  Future<void> _confirmAndClearChat() async {
    final l10n = AppLocalizations.of(context)!;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.deleteChatTitle),
          content: Text(l10n.deleteChatDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: Text(l10n.delete),
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
        SnackBar(content: Text(l10n.chatHistoryDeleted)),
      );
    } catch (e, st) {
      debugPrint('[ChatScreen] clearChat error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chatHistoryDeleteFailed)),
      );
    }
  }

  // ---------- TEXT MESSAGE ----------

  /// Send a text message and atomically update unread count for the other user.
  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      await _updateMyTyping(false);
      _isMeTypingFlag = false;
      _typingDebounce?.cancel();

      // Load my profile / avatar info
      final meta = await _getSenderMeta(user);
      final profileUrl = meta['profileUrl'];
      final avatarType = meta['avatarType'];

      final otherId = _otherUserId;
      if (otherId == null || otherId.isEmpty) {
        debugPrint('[ChatScreen] Cannot send message: otherUserId is null');
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      final roomRef = FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId);
      final msgRef = roomRef.collection('messages').doc();

      // message
      batch.set(msgRef, {
        'type': 'text',
        'text': text,
        'senderId': user.uid,
        'senderEmail': user.email,
        'profileUrl': profileUrl,
        'avatarType': avatarType,
        'createdAt': FieldValue.serverTimestamp(),
        'seenBy': <String>[],
      });

      // unread counts
      batch.set(
        roomRef,
        {
          'participants': [user.uid, otherId],
          'unreadCounts': {
            otherId: FieldValue.increment(1),
            user.uid: 0,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      _msgController.clear();
    } catch (e, st) {
      debugPrint('[ChatScreen] _sendMessage error: $e\n$st');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------- FILE UPLOADS ----------

  Future<void> _pickAndSendFile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
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

  (String type, String? contentType) _classifyFile(PlatformFile file) {
    final ext = (file.extension ?? '').toLowerCase();

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
      contentType = 'video/mp4';
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
          '[_sendFileMessage] File bytes are null – ensure withData: true');
      return;
    }

    final (msgType, rawContentType) = _classifyFile(file);
    final contentType = rawContentType ?? 'application/octet-stream';

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_uploads')
        .child(widget.roomId)
        .child('${DateTime.now().millisecondsSinceEpoch}_${file.name}');

    String? downloadUrl;

    try {
      final metadata = SettableMetadata(contentType: contentType);
      await storageRef.putData(bytes, metadata);
      downloadUrl = await storageRef.getDownloadURL();
    } on FirebaseException catch (e, st) {
      debugPrint(
          '[_sendFileMessage] STORAGE error [${e.code}]: ${e.message}\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.uploadFailedStorage)),
      );
      return;
    } catch (e, st) {
      debugPrint('[_sendFileMessage] Unknown STORAGE error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.uploadFailedStorage)),
      );
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data();
      final profileUrl = userData?['profileUrl'];
      final avatarType = userData?['avatarType'];

      if (_otherUserId == null) {
        debugPrint('[ChatScreen] _otherUserId is null, cannot bump unread');
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      final roomRef = FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId);
      final msgRef = roomRef.collection('messages').doc();

      batch.set(msgRef, {
        'type': msgType,
        'text': '',
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

      batch.set(
        roomRef,
        {
          'participants': [user.uid, _otherUserId],
          'unreadCounts': {
            _otherUserId!: FieldValue.increment(1),
            user.uid: 0,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (e, st) {
      debugPrint('[_sendFileMessage] FIRESTORE error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.uploadFailedMessageSave)),
      );
    }
  }

  Future<Map<String, dynamic>> _getSenderMeta(User user) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = snap.data() ?? {};
    final profileUrl = data['profileUrl'] as String?;
    final avatarType = data['avatarType'] as String?;

    return {
      'profileUrl': profileUrl,
      'avatarType': avatarType,
    };
  }

  @override
  void dispose() {
    _msgController.dispose();
    _roomSub?.cancel();
    _typingDebounce?.cancel();
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
        onClearChat: _confirmAndClearChat,
      ),
      body: MwBackground(
        child: Column(
          children: [
            Expanded(
              child: ChatMessageList(
                roomId: widget.roomId,
                currentUserId: _currentUserId,
                otherUserId: otherUserId,
              ),
            ),

            TypingIndicator(
              isVisible: _isOtherTyping,
              text: l10n.isTyping(widget.title),
            ),

            // bottom composer – no extra SafeArea (ChatInputBar already has it)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ChatInputBar(
                controller: _msgController,
                sending: _sending,
                onAttach: _pickAndSendFile,
                onSend: _sendMessage,
                onTextChanged: _onComposerChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
