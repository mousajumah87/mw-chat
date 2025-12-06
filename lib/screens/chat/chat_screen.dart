// lib/screens/chat/chat_screen.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

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

  // Did *I* block the other user?
  bool _isBlocked = false;
  bool _loadingBlockState = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _blockSub;

  // Did *they* block *me*?
  bool _hasBlockedMe = false;
  bool _loadingOtherBlockState = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _otherUserSub;

  // Friendship status between current user and other user:
  // null        => no friendship doc (not friends yet)
  // "accepted"  => full friends, can chat normally
  // "requested" => I sent request, waiting
  // "incoming"  => they sent request to me
  String? _friendStatus;
  bool _loadingFriendship = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _friendSub;

  // lightweight typing debounce (to avoid hammering Firestore)
  Timer? _typingDebounce;
  bool _isMeTypingFlag = false;

  // Basic banned words list – lightweight filter
  static const List<String> _bannedWords = [
    'abuse',
    'hate',
    'insult',
    'threat',
  ];

  final ImagePicker _imagePicker = ImagePicker();

  bool get _isAnyBlock => _isBlocked || _hasBlockedMe;
  bool get _isLoadingBlock => _loadingBlockState || _loadingOtherBlockState;

  /// We now **always** enforce friendship for valid user pairs.
  /// If either id is missing, we skip enforcement.
  bool get _isFriendshipEnforced {
    if (_currentUserId.isEmpty ||
        _otherUserId == null ||
        _otherUserId!.isEmpty) {
      return false;
    }
    return true;
  }

  bool get _canSendMessages {
    if (_isAnyBlock) return false;

    if (!_isFriendshipEnforced) {
      // no valid pair
      return false;
    }

    // Only allow sending when status is explicitly accepted.
    return _friendStatus == 'accepted';
  }

  bool get _hasIncomingFriendRequest => _friendStatus == 'incoming';
  bool get _hasOutgoingFriendRequest => _friendStatus == 'requested';

  // ================= VOICE RECORDING =================

  final Record _audioRecorder = Record();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  // ================= INIT / SUBSCRIPTIONS =================

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    _currentUserId = user?.uid ?? '';

    // Mark myself online when entering a chat.
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

    // Listen to my user doc to know if I blocked the other user.
    _subscribeToBlockState();

    // Listen to the other user's doc to know if they blocked me.
    _subscribeToOtherUserBlockState();

    // Listen to friendship between me and the other user.
    _subscribeToFriendship();

    // Listen for typing flags (other user)
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

  /// Listen to my `users/{uid}` doc and update `_isBlocked` in real time.
  void _subscribeToBlockState() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _otherUserId == null) {
      if (mounted) {
        setState(() {
          _isBlocked = false;
          _loadingBlockState = false;
        });
      }
      return;
    }

    _blockSub?.cancel();
    _blockSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snap) {
        final data = snap.data() ?? {};
        final blockedListDynamic =
            (data['blockedUserIds'] as List<dynamic>?) ?? const [];
        final blockedList =
        blockedListDynamic.map((e) => e.toString()).toList();
        final isBlockedNow = blockedList.contains(_otherUserId);

        if (mounted) {
          setState(() {
            _isBlocked = isBlockedNow;
            _loadingBlockState = false;
          });
        }
      },
      onError: (e, st) {
        debugPrint('[ChatScreen] _subscribeToBlockState error: $e\n$st');
        if (mounted) {
          setState(() {
            _isBlocked = false;
            _loadingBlockState = false;
          });
        }
      },
    );
  }

  /// Listen to the other user's `users/{otherId}` doc and see if they blocked *me*.
  void _subscribeToOtherUserBlockState() {
    final otherId = _otherUserId;
    if (otherId == null || otherId.isEmpty || _currentUserId.isEmpty) {
      if (mounted) {
        setState(() {
          _hasBlockedMe = false;
          _loadingOtherBlockState = false;
        });
      }
      return;
    }

    _otherUserSub?.cancel();
    _otherUserSub = FirebaseFirestore.instance
        .collection('users')
        .doc(otherId)
        .snapshots()
        .listen(
          (snap) {
        final data = snap.data() ?? {};
        final blockedListDynamic =
        data['blockedUserIds'] as List<dynamic>?;
        final hasBlockedMeNow = blockedListDynamic
            ?.whereType<String>()
            .contains(_currentUserId) ??
            false;

        if (mounted) {
          setState(() {
            _hasBlockedMe = hasBlockedMeNow;
            _loadingOtherBlockState = false;
          });
        }
      },
      onError: (e, st) {
        debugPrint(
            '[ChatScreen] _subscribeToOtherUserBlockState error: $e\n$st');
        if (mounted) {
          setState(() {
            _hasBlockedMe = false;
            _loadingOtherBlockState = false;
          });
        }
      },
    );
  }

  /// Listen to friendship doc: `users/{me}/friends/{other}`.
  void _subscribeToFriendship() {
    final me = _currentUserId;
    final other = _otherUserId;

    if (me.isEmpty || other == null || other.isEmpty) {
      if (mounted) {
        setState(() {
          _friendStatus = null;
          _loadingFriendship = false;
        });
      }
      return;
    }

    _friendSub?.cancel();
    _friendSub = FirebaseFirestore.instance
        .collection('users')
        .doc(me)
        .collection('friends')
        .doc(other)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;

        if (!snap.exists) {
          setState(() {
            _friendStatus = null;
            _loadingFriendship = false;
          });
          return;
        }

        final data = snap.data() ?? {};
        final status = data['status'] as String?;
        setState(() {
          _friendStatus = status;
          _loadingFriendship = false;
        });
      },
      onError: (e, st) {
        debugPrint('[ChatScreen] _subscribeToFriendship error: $e\n$st');
        if (mounted) {
          setState(() {
            _friendStatus = null;
            _loadingFriendship = false;
          });
        }
      },
    );
  }

  // =============== FRIEND REQUEST HELPERS =================

  /// Send a new friend request:
  /// me -> other: status "requested"
  /// other -> me: status "incoming"
  Future<void> _sendFriendRequest() async {
    final me = _currentUserId;
    final other = _otherUserId;
    if (me.isEmpty || other == null || other.isEmpty) return;

    // Don’t resend if we already have some relationship.
    if (_friendStatus == 'accepted' ||
        _friendStatus == 'requested' ||
        _friendStatus == 'incoming') {
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    try {
      final batch = FirebaseFirestore.instance.batch();

      final myDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('friends')
          .doc(other);

      final theirDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(other)
          .collection('friends')
          .doc(me);

      final now = FieldValue.serverTimestamp();

      batch.set(
        myDoc,
        {
          'status': 'requested',
          'createdAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      batch.set(
        theirDoc,
        {
          'status': 'incoming',
          'createdAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestSent)),
      );
    } catch (e, st) {
      debugPrint('[ChatScreen] _sendFriendRequest error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestSendFailed)),
      );
    }
  }

  /// Accept an incoming friend request
  Future<void> _acceptFriendRequest() async {
    final me = _currentUserId;
    final other = _otherUserId;
    if (me.isEmpty || other == null || other.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final myDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('friends')
          .doc(other);
      final theirDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(other)
          .collection('friends')
          .doc(me);

      final payload = {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      batch.set(myDoc, payload, SetOptions(merge: true));
      batch.set(theirDoc, payload, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.friendRequestAccepted),
        ),
      );
    } catch (e, st) {
      debugPrint('[ChatScreen] _acceptFriendRequest error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.friendRequestAcceptFailed),
        ),
      );
    }
  }

  /// Decline / cancel friend request by removing both docs.
  Future<void> _declineFriendRequest() async {
    final me = _currentUserId;
    final other = _otherUserId;
    if (me.isEmpty || other == null || other.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final myDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('friends')
          .doc(other);
      final theirDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(other)
          .collection('friends')
          .doc(me);

      batch.delete(myDoc);
      batch.delete(theirDoc);

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.friendRequestDeclined),
        ),
      );
    } catch (e, st) {
      debugPrint('[ChatScreen] _declineFriendRequest error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.friendRequestDeclineFailed),
        ),
      );
    }
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
    ) ??
        false;

    if (!shouldDelete) return;

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

  // ---------- MESSAGE FILTERING ----------

  String? _validateMessageContent(String text) {
    final lower = text.toLowerCase();
    for (final w in _bannedWords) {
      if (w.isNotEmpty && lower.contains(w)) {
        final l10n = AppLocalizations.of(context)!;
        return l10n.messageContainsRestrictedContent;
      }
    }
    return null;
  }

  // ---------- TEXT MESSAGE ----------

  /// Send a text message and atomically update unread count for the other user.
  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    // If there is any block relationship, do not send new messages.
    if (_isAnyBlock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userBlockedInfo)),
      );
      return;
    }

    // Friendship enforcement: must be accepted.
    if (!_canSendMessages) {
      String info;
      if (_hasOutgoingFriendRequest) {
        info = l10n.friendshipInfoOutgoing;
      } else if (_hasIncomingFriendRequest) {
        info = l10n.friendshipInfoIncoming;
      } else {
        info = l10n.friendshipInfoNotFriends;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(info)),
      );
      return;
    }

    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    // Filter for objectionable content
    final error = _validateMessageContent(text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

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

  // ---------- VOICE NOTE HELPERS (Record plugin) ----------

  Future<void> _startVoiceRecording() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    if (_isAnyBlock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userBlockedInfo)),
      );
      return;
    }

    if (!_canSendMessages) {
      String info;
      if (_hasOutgoingFriendRequest) {
        info = l10n.friendshipFileInfoOutgoing;
      } else if (_hasIncomingFriendRequest) {
        info = l10n.friendshipFileInfoIncoming;
      } else {
        info = l10n.friendshipFileInfoNotFriends;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(info)),
      );
      return;
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.voiceNotSupportedWeb),
        ),
      );
      return;
    }

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.microphonePermissionRequired),
          ),
        );
        return;
      }

      await _audioRecorder.start(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        samplingRate: 44100,
      );

      setState(() {
        _isRecording = true;
        _recordDuration = Duration.zero;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _recordDuration =
              Duration(seconds: _recordDuration.inSeconds + 1);
        });
      });
    } catch (e, st) {
      debugPrint('[_startVoiceRecording] error: $e\n$st');
    }
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    if (!_isRecording) return;

    final l10n = AppLocalizations.of(context)!;

    _recordTimer?.cancel();
    setState(() {
      _isRecording = false;
    });

    if (kIsWeb) {
      setState(() {
        _recordDuration = Duration.zero;
      });
      return;
    }

    try {
      final path = await _audioRecorder.stop();
      if (path == null) {
        setState(() {
          _recordDuration = Duration.zero;
        });
        return;
      }

      final file = File(path);
      final bytes = await file.readAsBytes();

      final platformFile = PlatformFile(
        name: p.basename(path),
        size: bytes.length,
        bytes: bytes,
        path: path,
      );

      setState(() {
        _recordDuration = Duration.zero;
      });

      await _sendFileMessage(platformFile);
    } catch (e, st) {
      debugPrint('[_stopVoiceRecordingAndSend] error: $e\n$st');
      setState(() {
        _recordDuration = Duration.zero;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToUploadFile)),
      );
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecording) return;

    _recordTimer?.cancel();

    if (!kIsWeb) {
      try {
        await _audioRecorder.stop();
      } catch (_) {
        // ignore
      }
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordDuration = Duration.zero;
      });
    }
  }

  // ---------- ATTACHMENT UI ----------

  Future<void> _handleAttachPressed() async {
    final l10n = AppLocalizations.of(context)!;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101018),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final maxWidth = media.size.width > 640 ? 520.0 : double.infinity;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SafeArea(
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.attach_file,
                            color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          l10n.attachFile,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 4),
                    ListTile(
                      leading:
                      const Icon(Icons.photo, color: Colors.white70),
                      title: Text(l10n.attachPhotoFromGallery),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickImageFromGallery();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.videocam,
                          color: Colors.white70),
                      title: Text(l10n.attachVideoFromGallery),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickVideoFromGallery();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.camera_alt,
                          color: Colors.white70),
                      title: Text(l10n.attachTakePhoto),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _captureImageWithCamera();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.videocam_outlined,
                          color: Colors.white70),
                      title: Text(l10n.attachRecordVideo),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _captureVideoWithCamera();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file,
                          color: Colors.white70),
                      title: Text(l10n.attachFileFromDevice),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickAndSendFile();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- MEDIA PICKERS (ImagePicker) ----------

  Future<void> _pickImageFromGallery() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final file = PlatformFile(
      name: p.basename(picked.path),
      size: bytes.length,
      bytes: bytes,
      path: picked.path,
    );

    await _sendFileMessage(file);
  }

  Future<void> _pickVideoFromGallery() async {
    final picked = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final file = PlatformFile(
      name: p.basename(picked.path),
      size: bytes.length,
      bytes: bytes,
      path: picked.path,
    );

    await _sendFileMessage(file);
  }

  Future<void> _captureImageWithCamera() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final file = PlatformFile(
      name: p.basename(picked.path),
      size: bytes.length,
      bytes: bytes,
      path: picked.path,
    );

    await _sendFileMessage(file);
  }

  Future<void> _captureVideoWithCamera() async {
    final picked = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 2),
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final file = PlatformFile(
      name: p.basename(picked.path),
      size: bytes.length,
      bytes: bytes,
      path: picked.path,
    );

    await _sendFileMessage(file);
  }

  // ---------- FILE UPLOADS (Files app & voice) ----------

  Future<void> _pickAndSendFile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final l10n = AppLocalizations.of(context)!;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.any, // PDFs/docs/zip etc. from Files app
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

    // If blocked in either direction, do not send uploads.
    if (_isAnyBlock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userBlockedInfo)),
      );
      return;
    }

    // Friendship enforcement: must be accepted.
    if (!_canSendMessages) {
      String info;
      if (_hasOutgoingFriendRequest) {
        info = l10n.friendshipFileInfoOutgoing;
      } else if (_hasIncomingFriendRequest) {
        info = l10n.friendshipFileInfoIncoming;
      } else {
        info = l10n.friendshipFileInfoNotFriends;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(info)),
      );
      return;
    }

    // Light content filter on file name as well
    final nameError = _validateMessageContent(file.name);
    if (nameError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nameError)),
      );
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
    _blockSub?.cancel();
    _otherUserSub?.cancel();
    _friendSub?.cancel();
    _typingDebounce?.cancel();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _updateMyTyping(false); // best-effort
    super.dispose();
  }

  Widget _buildFriendshipBanner(AppLocalizations l10n) {
    if (_loadingFriendship || !_isFriendshipEnforced) {
      return const SizedBox.shrink();
    }

    // Not friends yet, no doc: show "Send request" banner.
    if (_friendStatus == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_add_alt_1_outlined,
                color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.friendshipBannerNotFriends(widget.title),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _sendFriendRequest,
              child: Text(l10n.friendshipBannerSendRequestButton),
            ),
          ],
        ),
      );
    }

    if (_hasIncomingFriendRequest) {
      // Incoming request: show Accept / Decline
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_add_alt_1, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.friendshipBannerIncoming(widget.title),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _acceptFriendRequest,
              child: Text(l10n.friendAcceptTooltip),
            ),
            TextButton(
              onPressed: _declineFriendRequest,
              child: Text(l10n.friendDeclineTooltip),
            ),
          ],
        ),
      );
    }

    if (_hasOutgoingFriendRequest) {
      // Outgoing request: info only
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.friendshipBannerOutgoing(widget.title),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Accepted: no banner.
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final otherUserId = _otherUserId;

    String _cannotSendText() {
      if (_hasOutgoingFriendRequest) {
        return l10n.friendshipCannotSendOutgoing;
      }
      if (_hasIncomingFriendRequest) {
        return l10n.friendshipCannotSendIncoming;
      }
      return l10n.friendshipCannotSendNotFriends;
    }

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
            // Friend request banner (if any)
            _buildFriendshipBanner(l10n),

            Expanded(
              child: _isLoadingBlock
                  ? const Center(child: CircularProgressIndicator())
                  : ChatMessageList(
                roomId: widget.roomId,
                currentUserId: _currentUserId,
                otherUserId: otherUserId,
                // Treat any block (me blocking them OR they blocking me)
                // as a "blocked" relationship for the list.
                isBlocked: _isAnyBlock,
              ),
            ),
            if (!_isAnyBlock)
              TypingIndicator(
                isVisible: _isOtherTyping,
                text: l10n.isTyping(widget.title),
              ),
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _isAnyBlock
                  ? Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 12),
                child: Text(
                  l10n.userBlockedInfo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
                  : _canSendMessages
                  ? ChatInputBar(
                controller: _msgController,
                sending: _sending,
                onAttach: _handleAttachPressed,
                onSend: _sendMessage,
                onTextChanged: _onComposerChanged,
                // NEW: voice note hooks
                isRecording: _isRecording,
                recordDuration: _recordDuration,
                onMicLongPressStart: _startVoiceRecording,
                onMicLongPressEnd: _stopVoiceRecordingAndSend,
                onMicCancel: _cancelVoiceRecording,
              )
                  : Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 12),
                child: Text(
                  _cannotSendText(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
