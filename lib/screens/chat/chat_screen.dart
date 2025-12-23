// lib/screens/chat/chat_screen.dart
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart' show UploadTask;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../utils/current_chat_tracker.dart';
import '../../utils/presence_service.dart';

import 'package:mw/utils/voice_recorder_controller.dart' as vrc;

import '../../widgets/chat/mw_emoji_panel.dart';
import '../../widgets/ui/mw_swipe_back.dart';
import 'chat_app_bar.dart';
import 'chat_friendship_service.dart';
import 'chat_media_service.dart';
import 'chat_message_list.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/ui/mw_background.dart';

import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/typing_indicator.dart';

import 'chat_screen_deletion.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String title;

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
  final FocusNode _composerFocusNode = FocusNode(debugLabel: 'mwComposer');

  bool _panelVisible = false;
  static const double _panelHeight = 300.0;

  final ChatFriendshipService _friendshipService = ChatFriendshipService();
  ChatMediaService? _mediaService;

  late final vrc.VoiceRecorderController _voiceCtrl;

  final ImagePicker _picker = ImagePicker();

  double? _uploadProgress;
  bool get _isUploading => _uploadProgress != null && _uploadProgress! < 1.0;

  bool _sending = false;

  late final String _currentUserId;
  String? _otherUserId;

  bool _isOtherTyping = false;
  bool _isOtherRecording = false;

  bool _hasAnyMessages = false;

  String _myAvatarType = 'bear';

  TypingAvatarGender _otherUserGender = TypingAvatarGender.other;
  String _otherUserAvatarType = 'bear';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;

  bool _isBlocked = false;
  bool _loadingBlockState = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _blockSub;

  bool _hasBlockedMe = false;
  bool _loadingOtherBlockState = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _otherUserSub;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myUserSub;

  StreamSubscription<String?>? _friendSub;
  String? _friendStatus;
  bool _loadingFriendship = true;

  Timer? _typingDebounce;
  bool _isMeTypingFlag = false;

  Timer? _seenDebounce;

  bool _disposed = false;
  bool _didPrimeOtherOnce = false;

  static const String _privacyEveryone = 'everyone';
  static const String _privacyFriends = 'friends';
  static const String _privacyNobody = 'nobody';

  static const String _fieldProfileVisibility = 'profileVisibility';
  static const String _fieldAddFriendVisibility = 'addFriendVisibility';
  static const String _legacyFriendRequestsField = 'friendRequests';

  String _otherProfileVisibility = _privacyEveryone;
  String _otherAddFriendVisibility = _privacyEveryone;

  static const List<String> _bannedWords = [
    'abuse',
    'hate',
    'insult',
    'threat',
  ];

  bool get _isFriends => ChatFriendshipService.isFriends(_friendStatus);

  bool get _isAnyBlock => _isBlocked || _hasBlockedMe;
  bool get _isLoadingBlock => _loadingBlockState || _loadingOtherBlockState;

  bool get _isFriendshipEnforced {
    if (_currentUserId.isEmpty) return false;
    final other = _otherUserId;
    if (other == null || other.isEmpty) return false;
    return true;
  }

  bool get _canRequestFriendByPrivacy {
    if (_isAnyBlock) return false;

    if (_friendStatus == 'requested' ||
        _friendStatus == 'incoming' ||
        _friendStatus == 'accepted') {
      return false;
    }

    if (_otherAddFriendVisibility == _privacyNobody) return false;
    if (_otherAddFriendVisibility == _privacyFriends) return false;

    return true;
  }

  // ✅ FIX #2:
  // profileVisibility must NOT block chat for existing friends.
  // It only blocks strangers from opening/starting chat.
  bool get _isChatAccessRestricted {
    // Friends should always be able to chat (unless blocked).
    if (_isFriends) return false;

    // Not friends -> apply privacy restriction
    if (_otherProfileVisibility == _privacyNobody) return true;
    if (_otherProfileVisibility == _privacyFriends && !_isFriends) return true;
    return false;
  }

  bool get _canSendMessages {
    if (_isAnyBlock) return false;
    if (!_isFriendshipEnforced) return false;
    if (_isChatAccessRestricted) return false;
    return ChatFriendshipService.isFriends(_friendStatus);
  }

  bool get _hasIncomingFriendRequest => _friendStatus == 'incoming';
  bool get _hasOutgoingFriendRequest => _friendStatus == 'requested';

  TypingAvatarGender _parseGender(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s == 'female') return TypingAvatarGender.female;
    if (s == 'male') return TypingAvatarGender.male;
    return TypingAvatarGender.other;
  }

  String _parseAvatarType(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s == 'smurf') return 'smurf';
    return 'bear';
  }

  String _normalizePrivacy(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == _privacyFriends) return _privacyFriends;
    if (v == _privacyNobody) return _privacyNobody;
    return _privacyEveryone;
  }

  String _readOtherPrivacyValue(Map<String, dynamic> data, String field) {
    final String? rawNew = data[field] as String?;

    String? rawLegacy;
    if (field == _fieldAddFriendVisibility) {
      rawLegacy = data[_legacyFriendRequestsField] as String?;
    } else if (field == _fieldProfileVisibility) {
      rawLegacy = data[_fieldProfileVisibility] as String?;
    }

    final chosen =
    (rawNew != null && rawNew.trim().isNotEmpty) ? rawNew : rawLegacy;
    return _normalizePrivacy(chosen);
  }

  String? get _typingIndicatorAvatarType {
    if (!_isOtherTyping && !_isOtherRecording) return null;
    return _otherUserAvatarType;
  }

  TypingAvatarGender get _typingIndicatorGender => _otherUserGender;

  ChatActivityIndicatorMode get _typingIndicatorMode {
    if (_isOtherRecording) return ChatActivityIndicatorMode.recording;
    return ChatActivityIndicatorMode.typing;
  }

  void _handleComposerFocus() {
    if (_disposed) return;
    if (_composerFocusNode.hasFocus && _panelVisible) {
      if (mounted) setState(() => _panelVisible = false);
    }
  }

  void _toastSnack(String msg) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _closeSheetThen(
      BuildContext sheetContext,
      Future<void> Function() action,
      ) async {
    Navigator.of(sheetContext, rootNavigator: true).pop();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted || _disposed) return;
    await action();
  }

  void _ensureMediaService({bool forceRecreate = false}) {
    if (_disposed) return;

    if (!forceRecreate && _mediaService != null) return;

    if (forceRecreate) {
      try {
        _mediaService?.dispose();
      } catch (_) {}
      _mediaService = null;
    }

    final other = _otherUserId;
    if (_currentUserId.isEmpty || other == null || other.isEmpty) {
      _mediaService = null;
      return;
    }

    _mediaService = ChatMediaService(
      roomId: widget.roomId,
      currentUserId: _currentUserId,
      otherUserId: other,
      isBlocked: () => _isAnyBlock,
      canSendMessages: () => _canSendMessages,
      validateMessageContent: (s) => _validateMessageContent(s),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final user = FirebaseAuth.instance.currentUser;
    _currentUserId = user?.uid ?? '';

    _voiceCtrl = vrc.VoiceRecorderController();

    _composerFocusNode.addListener(_handleComposerFocus);

    PresenceService.instance.markOnline();

    unawaited(_updateMyTyping(false));
    unawaited(_updateMyRecording(false));

    final parts = widget.roomId.split('_');
    if (parts.length == 2 && _currentUserId.isNotEmpty) {
      if (parts[0] == _currentUserId) {
        _otherUserId = parts[1];
      } else if (parts[1] == _currentUserId) {
        _otherUserId = parts[0];
      }
    }

    _ensureMediaService(forceRecreate: true);

    _subscribeToMyMeta();
    unawaited(_primeOtherUserMetaOnce(force: true));

    CurrentChatTracker.instance.enterRoom(widget.roomId);
    _resetMyUnread();

    _subscribeToBlockState();
    _subscribeToOtherUserBlockState();
    _subscribeToFriendship();
    _subscribeHasAnyMessages();

    _roomSub = FirebaseFirestore.instance
        .collection('privateChats')
        .doc(widget.roomId)
        .snapshots()
        .listen((doc) {
      if (_disposed) return;
      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      final otherId = _otherUserId;
      if (otherId == null || otherId.isEmpty) return;

      final typingKey = 'typing_$otherId';
      final recordingKey = 'recording_$otherId';

      final isTyping = data[typingKey] == true;
      final isRecording = data[recordingKey] == true;

      if (isTyping == _isOtherTyping && isRecording == _isOtherRecording) return;

      if (!mounted) return;
      setState(() {
        _isOtherTyping = isTyping;
        _isOtherRecording = isRecording;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _scheduleMarkSeen();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_updateMyTyping(false));
        unawaited(_updateMyRecording(false));
        _isMeTypingFlag = false;
        _typingDebounce?.cancel();
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;

    WidgetsBinding.instance.removeObserver(this);

    _seenDebounce?.cancel();
    _typingDebounce?.cancel();

    unawaited(_updateMyTyping(false));
    unawaited(_updateMyRecording(false));

    _composerFocusNode.removeListener(_handleComposerFocus);

    _msgController.dispose();
    _composerFocusNode.dispose();

    _roomSub?.cancel();
    _blockSub?.cancel();
    _otherUserSub?.cancel();
    _myUserSub?.cancel();
    _messagesSub?.cancel();

    _friendSub?.cancel();
    _friendSub = null;

    _friendshipService.dispose();

    try {
      _mediaService?.dispose();
    } catch (_) {}
    _mediaService = null;

    _voiceCtrl.disposeController();

    _safeLeaveRoom();

    super.dispose();
  }

  Future<void> _primeOtherUserMetaOnce({bool force = false}) async {
    final otherId = _otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    if (_disposed) return;

    if (!force && _didPrimeOtherOnce) return;
    _didPrimeOtherOnce = true;

    try {
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(otherId).get();
      if (_disposed) return;

      final data = snap.data() ?? {};
      final parsedGender = _parseGender(data['gender']);
      final parsedAvatar = _parseAvatarType(data['avatarType']);

      final profileVis = _readOtherPrivacyValue(data, _fieldProfileVisibility);
      final addFriendVis =
      _readOtherPrivacyValue(data, _fieldAddFriendVisibility);

      if (!mounted) return;
      setState(() {
        _otherUserGender = parsedGender;
        _otherUserAvatarType = parsedAvatar;
        _otherProfileVisibility = profileVis;
        _otherAddFriendVisibility = addFriendVis;
      });
    } catch (_) {}
  }

  void _subscribeToMyMeta() {
    final me = _currentUserId;
    if (me.isEmpty) return;

    _myUserSub?.cancel();
    _myUserSub = FirebaseFirestore.instance
        .collection('users')
        .doc(me)
        .snapshots()
        .listen((snap) {
      if (_disposed) return;
      final data = snap.data() ?? {};
      final parsed = _parseAvatarType(data['avatarType']);
      if (!mounted) return;

      if (parsed != _myAvatarType) {
        setState(() => _myAvatarType = parsed);
      } else {
        _myAvatarType = parsed;
      }
    });
  }

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
      if (!mounted || _disposed) return;

      final visible = snap.docs.any((doc) {
        final data = doc.data();
        final hiddenFor = (data['hiddenFor'] as List?)?.cast<String>() ?? [];
        return !hiddenFor.contains(_currentUserId);
      });

      if (visible != _hasAnyMessages) {
        setState(() => _hasAnyMessages = visible);
      }

      _scheduleMarkSeen();
    });
  }

  void _scheduleMarkSeen() {
    if (!mounted || _disposed) return;
    if (_currentUserId.isEmpty) return;
    if (_otherUserId == null || _otherUserId!.isEmpty) return;
    if (_isAnyBlock) return;

    _seenDebounce?.cancel();
    _seenDebounce = Timer(const Duration(milliseconds: 450), () {
      if (_disposed) return;
      _markRecentMessagesAsSeen();
    });
  }

  Future<void> _markRecentMessagesAsSeen() async {
    if (_disposed) return;

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

      if (_disposed) return;

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
        if (updates >= 20) break;
      }

      if (updates > 0) {
        await batch.commit();
      }

      await _resetMyUnread();
    } catch (_) {}
  }

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
        .listen((snap) {
      if (_disposed) return;
      final data = snap.data() ?? {};
      final blockedListDynamic =
          (data['blockedUserIds'] as List<dynamic>?) ?? const [];
      final blockedList = blockedListDynamic.map((e) => e.toString()).toList();
      final isBlockedNow = blockedList.contains(_otherUserId);

      if (!mounted) return;
      setState(() {
        _isBlocked = isBlockedNow;
        _loadingBlockState = false;
      });
    }, onError: (_, __) {
      if (!mounted || _disposed) return;
      setState(() {
        _isBlocked = false;
        _loadingBlockState = false;
      });
    });
  }

  void _subscribeToOtherUserBlockState() {
    final otherId = _otherUserId;
    if (otherId == null || otherId.isEmpty || _currentUserId.isEmpty) {
      if (mounted) {
        setState(() {
          _hasBlockedMe = false;
          _loadingOtherBlockState = false;
          _otherUserGender = TypingAvatarGender.other;
          _otherUserAvatarType = 'bear';
          _otherProfileVisibility = _privacyEveryone;
          _otherAddFriendVisibility = _privacyEveryone;
        });
      }
      return;
    }

    _otherUserSub?.cancel();
    _otherUserSub = FirebaseFirestore.instance
        .collection('users')
        .doc(otherId)
        .snapshots()
        .listen((snap) {
      if (_disposed) return;

      final data = snap.data() ?? {};
      final raw = data['blockedUserIds'] as List<dynamic>?;
      final blockedIds =
      (raw ?? const <dynamic>[]).map((e) => e.toString()).toList();
      final hasBlockedMeNow = blockedIds.contains(_currentUserId);

      final parsedGender = _parseGender(data['gender']);
      final parsedAvatarType = _parseAvatarType(data['avatarType']);

      final profileVis = _readOtherPrivacyValue(data, _fieldProfileVisibility);
      final addFriendVis =
      _readOtherPrivacyValue(data, _fieldAddFriendVisibility);

      if (!mounted) return;
      setState(() {
        _hasBlockedMe = hasBlockedMeNow;
        _loadingOtherBlockState = false;
        _otherUserGender = parsedGender;
        _otherUserAvatarType = parsedAvatarType;
        _otherProfileVisibility = profileVis;
        _otherAddFriendVisibility = addFriendVis;
      });
    }, onError: (_, __) {
      if (!mounted || _disposed) return;
      setState(() {
        _hasBlockedMe = false;
        _loadingOtherBlockState = false;
        _otherUserGender = TypingAvatarGender.other;
        _otherUserAvatarType = 'bear';
        _otherProfileVisibility = _privacyEveryone;
        _otherAddFriendVisibility = _privacyEveryone;
      });
    });
  }

  void _subscribeToFriendship() {
    final me = _currentUserId;
    final other = _otherUserId;

    _friendSub?.cancel();

    if (me.isEmpty || other == null || other.isEmpty) {
      if (mounted) {
        setState(() {
          _friendStatus = null;
          _loadingFriendship = false;
        });
      }
      return;
    }

    _friendSub = _friendshipService
        .friendshipStatusStream(me: me, other: other)
        .listen((status) {
      if (!mounted || _disposed) return;

      setState(() {
        _friendStatus = status;
        _loadingFriendship = false;
      });

      _scheduleMarkSeen();
    }, onError: (_, __) {
      if (!mounted || _disposed) return;
      setState(() {
        _friendStatus = null;
        _loadingFriendship = false;
      });
    });
  }

  Future<void> _resetMyUnread() async {
    if (_currentUserId.isEmpty) return;

    final roomRef =
    FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);

    try {
      await roomRef.set(
        {'unreadCounts': {_currentUserId: 0}},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _updateMyTyping(bool isTyping) async {
    if (_currentUserId.isEmpty) return;
    if (_disposed) return;

    try {
      await FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId)
          .set({'typing_$_currentUserId': isTyping}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _updateMyRecording(bool isRecording) async {
    if (_currentUserId.isEmpty) return;
    if (_disposed) return;

    try {
      await FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId)
          .set({'recording_$_currentUserId': isRecording},
          SetOptions(merge: true));
    } catch (_) {}
  }

  void _onComposerChanged(String value) {
    if (_isAnyBlock || !_canSendMessages) return;

    final hasText = value.trim().isNotEmpty;

    if (hasText && !_isMeTypingFlag) {
      _isMeTypingFlag = true;
      unawaited(_updateMyTyping(true));
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 600), () {
      _isMeTypingFlag = false;
      unawaited(_updateMyTyping(false));
    });
  }

  String? _validateMessageContent(String text) {
    final lower = text.toLowerCase();
    for (final w in _bannedWords) {
      if (w.isNotEmpty && lower.contains(w)) {
        final l10n = AppLocalizations.of(context);
        return l10n?.messageContainsRestrictedContent ??
            'Message contains restricted content.';
      }
    }
    return null;
  }

  bool _guardCanSendWithSnackbar() {
    final l10n = AppLocalizations.of(context);

    if (_isAnyBlock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n?.userBlockedInfo ?? 'You cannot message this user.')),
      );
      return false;
    }

    if (_isChatAccessRestricted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.profilePrivateChatRestricted ??
                'This user’s profile is private. You must be friends to chat.',
          ),
        ),
      );
      return false;
    }

    if (!_canSendMessages) {
      String info;
      if (_hasOutgoingFriendRequest) {
        info = l10n?.friendshipInfoOutgoing ?? 'Friend request pending.';
      } else if (_hasIncomingFriendRequest) {
        info = l10n?.friendshipInfoIncoming ?? 'Accept the friend request to chat.';
      } else {
        if (!_canRequestFriendByPrivacy) {
          info = l10n?.friendRequestNotAllowed ??
              'This user is not accepting friend requests.';
        } else {
          info = l10n?.friendshipInfoNotFriends ?? 'You must be friends to chat.';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(info)));
      return false;
    }

    return true;
  }

  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_guardCanSendWithSnackbar()) return;

    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();

    final error = _validateMessageContent(text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    if (!mounted || _disposed) return;
    setState(() => _sending = true);

    try {
      await _updateMyTyping(false);
      await _updateMyRecording(false);
      _isMeTypingFlag = false;
      _typingDebounce?.cancel();

      final meta = await _getSenderMeta(user);
      final profileUrl = meta['profileUrl'];
      final avatarType = meta['avatarType'];

      final otherId = _otherUserId;
      if (otherId == null || otherId.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();

      final roomRef =
      FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);
      final msgRef = roomRef.collection('messages').doc();

      batch.set(msgRef, {
        'type': 'text',
        'text': text,
        'senderId': user.uid,
        'senderEmail': user.email,
        'profileUrl': profileUrl,
        'avatarType': avatarType,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
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
      _scheduleMarkSeen();
    } catch (_) {
      // ignore
    } finally {
      if (mounted && !_disposed) setState(() => _sending = false);
    }
  }

  Future<void> _handleVoiceDraftSend(vrc.VoiceDraft draft) async {
    if (!_guardCanSendWithSnackbar()) return;
    if (_isUploading) return;

    _ensureMediaService();
    final media = _mediaService;
    if (media == null) {
      _toastSnack('Unable to send voice note right now.');
      return;
    }

    if (!mounted || _disposed) return;
    setState(() => _uploadProgress = 0.0);

    UploadTask? task;
    try {
      await _updateMyRecording(false);

      final bytes = draft.bytes;
      final path = draft.path;
      final name = draft.fileName;
      final mime = draft.mimeType;

      PlatformFile pf;

      if (bytes != null && bytes.isNotEmpty) {
        pf = PlatformFile(name: name, size: bytes.length, bytes: bytes, path: null);
      } else if (!kIsWeb && path != null && path.trim().isNotEmpty) {
        pf = PlatformFile(name: name, size: 0, path: path.trim());
      } else {
        return;
      }

      task = await media.sendFileMessage(
        pf,
        forcedType: 'audio',
        forcedContentType: mime,
        onProgress: (p) {
          if (!mounted || _disposed) return;
          setState(() => _uploadProgress = p);
        },
      );

      _scheduleMarkSeen();
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _uploadProgress = null);
    }

    if (task == null) {}
  }

  Future<void> _handleAttachPressed() async {
    if (_isUploading) return;
    if (!_guardCanSendWithSnackbar()) return;

    _dismissKeyboardAndPanel();

    _ensureMediaService();
    if (_mediaService == null) {
      _toastSnack('Unable to attach right now.');
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _disposed) return;

    final l10n = AppLocalizations.of(context)!;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF101018),
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final mediaQ = MediaQuery.of(ctx);
        final maxWidth = mediaQ.size.width > 640 ? 520.0 : double.infinity;
        final bool isWeb = kIsWeb;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SafeArea(
              top: false,
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
                        const Icon(Icons.attach_file, color: Colors.white70, size: 20),
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
                      leading: const Icon(Icons.photo, color: Colors.white70),
                      title: Text(l10n.attachPhotoFromGallery),
                      onTap: () => _closeSheetThen(ctx, _pickImageFromGallery),
                    ),
                    ListTile(
                      leading: const Icon(Icons.videocam, color: Colors.white70),
                      title: Text(l10n.attachVideoFromGallery),
                      onTap: () => _closeSheetThen(ctx, _pickVideoFromGallery),
                    ),
                    if (!isWeb) ...[
                      ListTile(
                        leading: const Icon(Icons.camera_alt, color: Colors.white70),
                        title: Text(l10n.attachTakePhoto),
                        onTap: () => _closeSheetThen(
                          ctx,
                              () => _captureImageWithCamera(camera: CameraDevice.rear),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.videocam_outlined, color: Colors.white70),
                        title: Text(l10n.attachRecordVideo),
                        onTap: () => _closeSheetThen(
                          ctx,
                              () => _captureVideoWithCamera(camera: CameraDevice.rear),
                        ),
                      ),
                    ],
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file, color: Colors.white70),
                      title: Text(l10n.attachFileFromDevice),
                      onTap: () => _closeSheetThen(ctx, _pickAndSendFile),
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

  Future<void> _sendPlatformFile(
      PlatformFile? file, {
        String? forcedType,
        String? forcedContentType,
      }) async {
    if (file == null) return;
    if (_isUploading) return;
    if (!_guardCanSendWithSnackbar()) return;

    _ensureMediaService();
    final media = _mediaService;
    if (media == null) {
      _toastSnack('Unable to attach right now.');
      return;
    }

    if (!mounted || _disposed) return;
    setState(() => _uploadProgress = 0.0);

    try {
      await media.sendFileMessage(
        file,
        forcedType: forcedType,
        forcedContentType: forcedContentType,
        onProgress: (p) {
          if (!mounted || _disposed) return;
          setState(() => _uploadProgress = p);
        },
      );

      _scheduleMarkSeen();
    } catch (_) {
      _toastSnack('Failed to attach file.');
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _uploadProgress = null);
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (x == null) return;

      if (kIsWeb) {
        final bytes = await x.readAsBytes();
        final pf = PlatformFile(
          name: x.name,
          size: bytes.length,
          bytes: bytes,
          path: null,
        );
        await _sendPlatformFile(pf,
            forcedType: 'image', forcedContentType: 'image/*');
      } else {
        final pf = PlatformFile(name: x.name, size: 0, path: x.path);
        await _sendPlatformFile(pf,
            forcedType: 'image', forcedContentType: 'image/*');
      }
    } catch (_) {
      _toastSnack('Unable to pick photo.');
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final x = await _picker.pickVideo(source: ImageSource.gallery);
      if (x == null) return;

      if (kIsWeb) {
        final bytes = await x.readAsBytes();
        final pf = PlatformFile(
          name: x.name,
          size: bytes.length,
          bytes: bytes,
          path: null,
        );
        await _sendPlatformFile(pf,
            forcedType: 'video', forcedContentType: 'video/*');
      } else {
        final pf = PlatformFile(name: x.name, size: 0, path: x.path);
        await _sendPlatformFile(pf,
            forcedType: 'video', forcedContentType: 'video/*');
      }
    } catch (_) {
      _toastSnack('Unable to pick video.');
    }
  }

  Future<void> _captureImageWithCamera(
      {CameraDevice camera = CameraDevice.rear}) async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: camera,
        imageQuality: 88,
      );
      if (x == null) return;

      final pf = PlatformFile(name: x.name, size: 0, path: x.path);
      await _sendPlatformFile(pf,
          forcedType: 'image', forcedContentType: 'image/*');
    } catch (_) {
      _toastSnack('Unable to take photo.');
    }
  }

  Future<void> _captureVideoWithCamera(
      {CameraDevice camera = CameraDevice.rear}) async {
    try {
      final x = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: camera,
      );
      if (x == null) return;

      final pf = PlatformFile(name: x.name, size: 0, path: x.path);
      await _sendPlatformFile(pf,
          forcedType: 'video', forcedContentType: 'video/*');
    } catch (_) {
      _toastSnack('Unable to record video.');
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: kIsWeb,
      );
      final pf = res?.files.firstOrNull;
      if (pf == null) return;

      await _sendPlatformFile(pf);
    } catch (_) {
      _toastSnack('Unable to pick file.');
    }
  }

  Future<Map<String, dynamic>> _getSenderMeta(User user) async {
    final snap =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = snap.data() ?? {};
    return {
      'profileUrl': data['profileUrl'] as String?,
      'avatarType': data['avatarType'] as String?,
    };
  }

  void _safeLeaveRoom() {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          CurrentChatTracker.instance.leaveRoom();
        } catch (_) {}
      });
    } catch (_) {
      Future.microtask(() {
        try {
          CurrentChatTracker.instance.leaveRoom();
        } catch (_) {}
      });
    }
  }

  Widget _buildFriendshipBanner(AppLocalizations l10n) {
    return const SizedBox.shrink();
  }

  Widget _buildCustomPanel(BuildContext context) {
    return MwEmojiPanel(
      onInsert: (insert) {
        final text = _msgController.text;
        final sel = _msgController.selection;

        final int start = (sel.start < 0) ? text.length : sel.start;
        final int end = (sel.end < 0) ? text.length : sel.end;

        final newText = text.replaceRange(start, end, insert);
        _msgController.text = newText;
        _msgController.selection =
            TextSelection.collapsed(offset: start + insert.length);

        _onComposerChanged(newText);
      },
    );
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
        Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 4),
      ],
    );

    String cannotSendText() {
      // ✅ For non-friends, show privacy restriction message
      if (_isChatAccessRestricted && !_isFriends) {
        return l10n.profilePrivateChatRestricted ??
            'This user’s profile is private. You must be friends to chat.';
      }
      if (_hasOutgoingFriendRequest) return l10n.friendshipCannotSendOutgoing;
      if (_hasIncomingFriendRequest) return l10n.friendshipCannotSendIncoming;

      if (!_canRequestFriendByPrivacy) {
        return l10n.friendRequestNotAllowed ??
            'This user is not accepting friend requests.';
      }

      return l10n.friendshipCannotSendNotFriends;
    }

    final mq = MediaQuery.of(context);
    final double keyboardInset = mq.viewInsets.bottom;
    final bool keyboardOpen = keyboardInset > 0;

    final bool showIndicator =
        !_isAnyBlock && (_isOtherTyping || _isOtherRecording);

    final bool showPanel = _panelVisible && !keyboardOpen;

    const double indicatorReserve = 112;
    const double composerReserve = 92;

    Widget composerWidget;

    if (_isAnyBlock) {
      composerWidget = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          l10n.userBlockedInfo,
          textAlign: TextAlign.center,
          style: overlayInfoTextStyle,
        ),
      );
    } else if (_canSendMessages) {
      composerWidget = ChatInputBar(
        key: ValueKey('chat_input_${widget.roomId}'),
        controller: _msgController,
        sending: _sending || _isUploading,
        uploadProgress: _uploadProgress,
        onAttach: _handleAttachPressed,
        onSend: _sendMessage,
        onTextChanged: _onComposerChanged,
        voiceController: _voiceCtrl,
        onVoiceSend: _handleVoiceDraftSend,
        focusNode: _composerFocusNode,
        panelVisible: _panelVisible,
        onTogglePanel: () async {
          final newVisible = !_panelVisible;

          if (newVisible) {
            FocusManager.instance.primaryFocus?.unfocus();
          }

          if (!mounted || _disposed) return;
          setState(() => _panelVisible = newVisible);

          if (newVisible) {
            await Future.delayed(const Duration(milliseconds: 90));
            if (!mounted || _disposed) return;
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await Future.delayed(const Duration(milliseconds: 40));
              if (!mounted || _disposed) return;
              _composerFocusNode.requestFocus();
            });
          }
        },
        onVoiceRecordStart: () {
          _typingDebounce?.cancel();
          _isMeTypingFlag = false;
          unawaited(_updateMyTyping(false));
          unawaited(_updateMyRecording(true));

          if (_panelVisible) setState(() => _panelVisible = false);
          FocusManager.instance.primaryFocus?.unfocus();
        },
        onVoiceRecordStop: () {
          unawaited(_updateMyRecording(false));
        },
      );
    } else {
      composerWidget = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          cannotSendText(),
          textAlign: TextAlign.center,
          style: overlayInfoTextStyle,
        ),
      );
    }

    final typingKey =
    ValueKey('typing:${widget.roomId}:${_otherUserId ?? 'unknown'}');

    final double listBottomInset = composerReserve +
        (showIndicator ? indicatorReserve : 0) +
        (showPanel ? _panelHeight : 0);

    final bottomBar = AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isAnyBlock)
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.bottomCenter,
                child: showIndicator
                    ? Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TypingIndicator(
                    key: typingKey,
                    isVisible: true,
                    text: _isOtherRecording
                        ? '${widget.title} is recording...'
                        : l10n.isTyping(widget.title),
                    gender: _typingIndicatorGender,
                    avatarType: _typingIndicatorAvatarType,
                    mode: _typingIndicatorMode,
                  ),
                )
                    : const SizedBox.shrink(),
              ),
            if (showPanel)
              SizedBox(
                height: _panelHeight,
                child: _buildCustomPanel(context),
              ),
            composerWidget,
          ],
        ),
      ),
    );

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
        onClearChat: _hasAnyMessages
            ? () async {
          await ChatScreenDeletion.confirmAndClearChat(
            context: context,
            roomId: widget.roomId,
            currentUserId: _currentUserId,
            otherUserId: _otherUserId,
          );
        }
            : null,
      ),
      body: MwSwipeBack(
        enabled: !_panelVisible && MediaQuery.of(context).viewInsets.bottom == 0,
        onExit: () {
          FocusManager.instance.primaryFocus?.unfocus();
          if (_panelVisible) setState(() => _panelVisible = false);
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).maybePop();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            if (_panelVisible) setState(() => _panelVisible = false);
          },
          child: MwBackground(
            child: Column(
              children: [
                _buildFriendshipBanner(l10n),
                Expanded(
                  child: _isLoadingBlock
                      ? const Center(child: CircularProgressIndicator())
                      : ChatMessageList(
                    roomId: widget.roomId,
                    currentUserId: _currentUserId,
                    otherUserId: otherUserId,
                    isBlocked: _isAnyBlock,
                    bottomInset: listBottomInset,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }

  void _dismissKeyboardAndPanel() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_panelVisible) {
      setState(() => _panelVisible = false);
    }
  }
}

extension _FirstOrNullExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
