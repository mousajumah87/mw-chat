// lib/screens/chat/chat_screen.dart

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../utils/current_chat_tracker.dart';
import '../../utils/presence_service.dart';

// split-out widgets
import 'chat_app_bar.dart';
import 'chat_friendship_service.dart';
import 'chat_media_service.dart';
import 'chat_message_list.dart';

// Localization
import '../../l10n/app_localizations.dart';

// Shared MW background
import '../../widgets/ui/mw_background.dart';

// chat widgets
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/typing_indicator.dart';

import 'chat_screen_deletion.dart';

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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _msgController = TextEditingController();
  final ChatFriendshipService _friendshipService = ChatFriendshipService();
  late final ChatMediaService _mediaService;

  double? _uploadProgress;
  bool get _isUploading =>
      _uploadProgress != null && _uploadProgress! < 1.0;

  bool _sending = false;

  late final String _currentUserId;
  String? _otherUserId;

  bool _isOtherTyping = false;
  bool _hasAnyMessages = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
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

  // Voice recording UI tick timer (ChatMediaService owns the actual state)
  Timer? _recordTimer;

  // Read-receipt debounce to avoid spamming writes
  Timer? _seenDebounce;

  // Basic banned words list – lightweight filter
  static const List<String> _bannedWords = [
    'abuse',
    'hate',
    'insult',
    'threat',
  ];

  bool get _isAnyBlock => _isBlocked || _hasBlockedMe;
  bool get _isLoadingBlock => _loadingBlockState || _loadingOtherBlockState;

  /// We now **always** enforce friendship for valid user pairs.
  /// If either id is missing, we skip enforcement.
  bool get _isFriendshipEnforced {
    if (_currentUserId.isEmpty || _otherUserId == null || _otherUserId!.isEmpty) {
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

  // ================= INIT / SUBSCRIPTIONS =================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

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

    // Tell the tracker: user is now inside this chat room.
    CurrentChatTracker.instance.enterRoom(widget.roomId);

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

      // Avoid rebuilding the whole screen if nothing changed
      if (isTyping == _isOtherTyping) return;

      if (mounted) {
        setState(() {
          _isOtherTyping = isTyping;
        });
      }
    });

    _mediaService = ChatMediaService(
      roomId: widget.roomId,
      currentUserId: _currentUserId,
      otherUserId: _otherUserId,
      isBlocked: () => _isAnyBlock,
      canSendMessages: () => _canSendMessages,
      validateMessageContent: _validateMessageContent,
    );

    // ✅ lightweight "has any messages" subscription (avoid streaming entire chat)
    _subscribeHasAnyMessages();

    // ✅ mark recent visible messages as seen (read receipts) after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleMarkSeen();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app resumes and this chat is on screen, mark messages as seen again
    if (state == AppLifecycleState.resumed) {
      _scheduleMarkSeen();
    }
  }

  // --------- Lightweight "has any messages" ----------
  void _subscribeHasAnyMessages() {
    _messagesSub?.cancel();

    _messagesSub = FirebaseFirestore.instance
        .collection('privateChats')
        .doc(widget.roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;

      final visible = snap.docs.any((doc) {
        final data = doc.data();
        final hiddenFor = (data['hiddenFor'] as List?)?.cast<String>() ?? [];
        return !hiddenFor.contains(_currentUserId);
      });

      if (visible != _hasAnyMessages) {
        setState(() => _hasAnyMessages = visible);
      }

      // Also: if new messages arrive while screen is open, mark seen (debounced)
      _scheduleMarkSeen();
    });
  }

  // --------- Read receipts / seenBy ----------
  void _scheduleMarkSeen() {
    if (!mounted) return;
    if (_currentUserId.isEmpty) return;
    if (_otherUserId == null || _otherUserId!.isEmpty) return;
    if (_isAnyBlock) return;

    // Debounce to avoid rapid writes when snapshots fire quickly
    _seenDebounce?.cancel();
    _seenDebounce = Timer(const Duration(milliseconds: 450), () {
      _markRecentMessagesAsSeen();
    });
  }

  Future<void> _markRecentMessagesAsSeen() async {
    final me = _currentUserId;
    final other = _otherUserId;
    if (me.isEmpty || other == null || other.isEmpty) return;
    if (_isAnyBlock) return;

    final roomRef =
    FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);

    try {
      final snap = await roomRef
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(40)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      int updates = 0;

      for (final doc in snap.docs) {
        final data = doc.data();

        final senderId = data['senderId'] as String?;
        if (senderId == null || senderId == me) continue;

        final hiddenFor = (data['hiddenFor'] as List?)?.cast<String>() ?? [];
        if (hiddenFor.contains(me)) continue;

        final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? const [];
        if (seenBy.contains(me)) continue;

        batch.update(doc.reference, {
          'seenBy': FieldValue.arrayUnion([me]),
        });

        updates++;
        if (updates >= 20) break; // cap per call
      }

      if (updates > 0) {
        await batch.commit();
      }

      // Best effort: keep unread count reset while chat is open
      await _resetMyUnread();
    } catch (e, st) {
      debugPrint('[ChatScreen] _markRecentMessagesAsSeen error: $e\n$st');
    }
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
        final blockedListDynamic = data['blockedUserIds'] as List<dynamic>?;
        final hasBlockedMeNow =
            blockedListDynamic?.whereType<String>().contains(_currentUserId) ??
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

    _friendshipService.subscribe(
      me: me,
      other: other,
      onUpdate: (status) {
        if (!mounted) return;
        setState(() {
          _friendStatus = status;
          _loadingFriendship = false;
        });

        // If user becomes accepted while already on screen,
        // mark messages as seen.
        _scheduleMarkSeen();
      },
    );
  }

  // =============== FRIEND REQUEST HELPERS =================

  Future<void> _sendFriendRequest() =>
      _friendshipService.sendRequest(
        me: _currentUserId,
        other: _otherUserId!,
      );

  Future<void> _acceptFriendRequest() =>
      _friendshipService.acceptRequest(
        me: _currentUserId,
        other: _otherUserId!,
      );

  Future<void> _declineFriendRequest() =>
      _friendshipService.declineRequest(
        me: _currentUserId,
        other: _otherUserId!,
      );

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
    await ChatScreenDeletion.confirmAndClearChat(
      context: context,
      roomId: widget.roomId,
      currentUserId: _currentUserId,
      otherUserId: _otherUserId,
    );
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

    if (_isAnyBlock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userBlockedInfo)),
      );
      return;
    }

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

    /// ✅ ✅ ✅ CRITICAL iOS FIX → CLEAR IMMEDIATELY (BEFORE ASYNC)
    _msgController.clear();

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

      // If I send a message while screen is open, keep seen state synced
      _scheduleMarkSeen();
    } catch (e, st) {
      debugPrint('[ChatScreen] _sendMessage error: $e\n$st');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------- VOICE NOTE HELPERS (Record via ChatMediaService) ----------

  Future<void> _startVoiceRecording() async {
    final ok = await _mediaService.startVoiceRecording();
    if (ok) {
      // Tick UI every second so the red pill timer updates
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    _recordTimer?.cancel();
    final file = await _mediaService.stopVoiceRecording();
    if (file != null) {
      await _mediaService.sendFileMessage(
        file,
        forcedType: 'audio',
        // ✅ Do NOT force content type here. Let classifier decide by extension.
      );
    }
    if (mounted) setState(() {});
    _scheduleMarkSeen();
  }

  Future<void> _cancelVoiceRecording() async {
    _recordTimer?.cancel();
    _mediaService.cancelVoiceRecording();
    if (mounted) setState(() {});
  }

  // ---------- ATTACHMENT UI ----------
  Future<void> _handleAttachPressed() async {
    // Don’t allow opening the attach sheet while an upload is in progress
    if (_isUploading) return;

    // ✅ iOS/Android: close keyboard before opening the sheet
    FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

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
        final bool isWeb = kIsWeb;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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

                    // 📷 From gallery (works on all platforms)
                    ListTile(
                      leading: const Icon(Icons.photo, color: Colors.white70),
                      title: Text(l10n.attachPhotoFromGallery),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickImageFromGallery();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.videocam, color: Colors.white70),
                      title: Text(l10n.attachVideoFromGallery),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickVideoFromGallery();
                      },
                    ),

                    // 📸 Camera actions → MOBILE ONLY
                    if (!isWeb) ...[
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
                    ],

                    // 📄 Generic file (works on all platforms)
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

  Future<void> _sendPlatformFile(PlatformFile? file) async {
    if (file == null) return;

    setState(() {
      _uploadProgress = 0.0;
    });

    try {
      await _mediaService.sendFileMessage(
        file,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = p; // 0.0 .. 1.0
          });
        },
      );

      // After sending media, mark seen for state consistency
      _scheduleMarkSeen();
    } finally {
      if (!mounted) return;
      setState(() {
        _uploadProgress = null; // hide bar when finished / error
      });
    }
  }

  // ---------- MEDIA PICKERS (delegating to ChatMediaService) ----------

  Future<void> _pickImageFromGallery() async {
    final file = await _mediaService.pickImageFromGallery();
    await _sendPlatformFile(file);
  }

  Future<void> _pickVideoFromGallery() async {
    final file = await _mediaService.pickVideoFromGallery();
    await _sendPlatformFile(file);
  }

  Future<void> _captureImageWithCamera({CameraDevice camera = CameraDevice.rear}) async {
    final file =
    await _mediaService.captureImageWithCamera(preferredCamera: camera);
    if (file == null) return; // user canceled
    await _sendPlatformFile(file);
  }

  Future<void> _captureVideoWithCamera({CameraDevice camera = CameraDevice.rear}) async {
    final file =
    await _mediaService.captureVideoWithCamera(preferredCamera: camera);
    if (file == null) return; // user canceled
    await _sendPlatformFile(file);
  }

  Future<void> _pickAndSendFile() async {
    final file = await _mediaService.pickFileFromDevice();
    await _sendPlatformFile(file);
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
    WidgetsBinding.instance.removeObserver(this);

    _seenDebounce?.cancel();
    _msgController.dispose();
    _roomSub?.cancel();
    _blockSub?.cancel();
    _otherUserSub?.cancel();
    _friendSub?.cancel();
    _messagesSub?.cancel();
    _friendshipService.dispose();
    _typingDebounce?.cancel();
    _recordTimer?.cancel();
    _mediaService.dispose();

    _updateMyTyping(false); // best-effort
    CurrentChatTracker.instance.leaveRoom();
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

    const TextStyle overlayInfoTextStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
      shadows: [
        Shadow(
          color: Colors.black54,
          offset: Offset(0, 1),
          blurRadius: 4,
        ),
      ],
    );

    String cannotSendText() {
      if (_hasOutgoingFriendRequest) {
        return l10n.friendshipCannotSendOutgoing;
      }
      if (_hasIncomingFriendRequest) {
        return l10n.friendshipCannotSendIncoming;
      }
      return l10n.friendshipCannotSendNotFriends;
    }

    // Build the bottom area in a single, consistent way (prevents iOS padding/keyboard glitches)
    Widget bottomArea;
    if (_isAnyBlock) {
      bottomArea = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          l10n.userBlockedInfo,
          textAlign: TextAlign.center,
          style: overlayInfoTextStyle,
        ),
      );
    } else if (_canSendMessages) {
      // IMPORTANT: do NOT wrap ChatInputBar in extra padding
      bottomArea = ChatInputBar(
        key: ValueKey('chat_input_${widget.roomId}'),
        controller: _msgController,
        sending: _sending || _isUploading,
        uploadProgress: _uploadProgress,
        onAttach: _handleAttachPressed,
        onSend: _sendMessage,
        onTextChanged: _onComposerChanged,

        // Voice note hooks (state from ChatMediaService)
        isRecording: _mediaService.isRecording,
        recordDuration: _mediaService.recordDuration,
        onMicLongPressStart: _startVoiceRecording,
        onMicLongPressEnd: _stopVoiceRecordingAndSend,
        onMicCancel: _cancelVoiceRecording,
      );
    } else {
      bottomArea = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          cannotSendText(),
          textAlign: TextAlign.center,
          style: overlayInfoTextStyle,
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
        onClearChat: _hasAnyMessages ? _confirmAndClearChat : null,
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
                isBlocked: _isAnyBlock,
              ),
            ),

            // Typing indicator (only when not blocked)
            if (!_isAnyBlock)
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _isOtherTyping
                    ? TypingIndicator(
                  isVisible: true,
                  text: l10n.isTyping(widget.title),
                )
                    : const SizedBox(height: 0),
              ),
            // Bottom area (input / blocked / cannot-send)
            bottomArea,
          ],
        ),
      ),
    );
  }
}
