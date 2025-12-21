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

// ✅ IMPORTANT: keep ONLY ONE import for voice controller, with alias
import 'package:mw/utils/voice_recorder_controller.dart' as vrc;

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

  // ✅ Shared friendship service (now stream-based)
  final ChatFriendshipService _friendshipService = ChatFriendshipService();

  ChatMediaService? _mediaService;

  // ✅ voice controller (alias)
  late final vrc.VoiceRecorderController _voiceCtrl;

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

  // ✅ FIX: friendship subscription is StreamSubscription<String?>
  StreamSubscription<String?>? _friendSub;
  String? _friendStatus;
  bool _loadingFriendship = true;

  Timer? _typingDebounce;
  bool _isMeTypingFlag = false;

  Timer? _seenDebounce;

  bool _disposed = false;
  bool _didPrimeOtherOnce = false;

  // ────────────────────────────────────────────────────────────────────────────
  // ✅ Privacy fields (align with MwFriendsTab)
  // ────────────────────────────────────────────────────────────────────────────
  static const String _privacyEveryone = 'everyone';
  static const String _privacyFriends = 'friends';
  static const String _privacyNobody = 'nobody';

  static const String _fieldProfileVisibility = 'profileVisibility';
  static const String _fieldAddFriendVisibility = 'addFriendVisibility';

  // legacy/backward compatible
  static const String _legacyFriendRequestsField = 'friendRequests';

  String _otherProfileVisibility = _privacyEveryone; // default
  String _otherAddFriendVisibility = _privacyEveryone; // default

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
      // Your DB screenshot shows "friendRequests"
      rawLegacy = data[_legacyFriendRequestsField] as String?;
    } else if (field == _fieldProfileVisibility) {
      rawLegacy = data[_fieldProfileVisibility] as String?;
    }

    final chosen = (rawNew != null && rawNew.trim().isNotEmpty) ? rawNew : rawLegacy;
    return _normalizePrivacy(chosen);
  }

  bool get _isFriends => ChatFriendshipService.isFriends(_friendStatus);

  bool get _canRequestFriendByPrivacy {
    // If blocked, never allow.
    if (_isAnyBlock) return false;

    // If already has any relationship, don't show "send request"
    if (_friendStatus == 'requested' ||
        _friendStatus == 'incoming' ||
        _friendStatus == 'accepted') {
      return false;
    }

    // "friends" means only friends can add -> practically blocks new requests.
    if (_otherAddFriendVisibility == _privacyNobody) return false;
    if (_otherAddFriendVisibility == _privacyFriends) return false;

    // everyone
    return true;
  }

  // If profile is "nobody" (or friends-only and not friends), show a locked UI.
  bool get _isChatAccessRestricted {
    if (_otherProfileVisibility == _privacyNobody) return true;
    if (_otherProfileVisibility == _privacyFriends && !_isFriends) return true;
    return false;
  }

  static const List<String> _bannedWords = [
    'abuse',
    'hate',
    'insult',
    'threat',
  ];

  bool get _isAnyBlock => _isBlocked || _hasBlockedMe;
  bool get _isLoadingBlock => _loadingBlockState || _loadingOtherBlockState;

  bool get _isFriendshipEnforced {
    if (_currentUserId.isEmpty) return false;
    final other = _otherUserId;
    if (other == null || other.isEmpty) return false;
    return true;
  }

  bool get _canSendMessages {
    if (_isAnyBlock) return false;
    if (!_isFriendshipEnforced) return false;

    // ✅ Extra safety: if profile is restricted, don't allow chat send.
    // (In practice you won't reach here from friends tab now, but protects deep-links/old builds)
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

  String? get _typingIndicatorAvatarType {
    if (!_isOtherTyping && !_isOtherRecording) return null;
    return _otherUserAvatarType;
  }

  TypingAvatarGender get _typingIndicatorGender => _otherUserGender;

  ChatActivityIndicatorMode get _typingIndicatorMode {
    if (_isOtherRecording) return ChatActivityIndicatorMode.recording;
    return ChatActivityIndicatorMode.typing;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ✅ Create ChatMediaService with required constructor args
  // ────────────────────────────────────────────────────────────────────────────
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

    debugPrint('[ChatScreen] ChatMediaService initialized ✅ '
        '(roomId=${widget.roomId}, me=$_currentUserId, other=$other)');
  }

  void _toastSnack(String msg) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      final addFriendVis = _readOtherPrivacyValue(data, _fieldAddFriendVisibility);

      if (!mounted) return;
      setState(() {
        _otherUserGender = parsedGender;
        _otherUserAvatarType = parsedAvatar;
        _otherProfileVisibility = profileVis;
        _otherAddFriendVisibility = addFriendVis;
      });
    } catch (e, st) {
      debugPrint('[ChatScreen] _primeOtherUserMetaOnce error: $e\n$st');
    }
  }

  void _subscribeToMyMeta() {
    final me = _currentUserId;
    if (me.isEmpty) return;

    _myUserSub?.cancel();
    _myUserSub = FirebaseFirestore.instance
        .collection('users')
        .doc(me)
        .snapshots()
        .listen(
          (snap) {
        if (_disposed) return;
        final data = snap.data() ?? {};
        final parsed = _parseAvatarType(data['avatarType']);
        if (!mounted) return;

        if (parsed != _myAvatarType) {
          setState(() => _myAvatarType = parsed);
        } else {
          _myAvatarType = parsed;
        }
      },
      onError: (e, st) {
        debugPrint('[ChatScreen] _subscribeToMyMeta error: $e\n$st');
      },
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    final user = FirebaseAuth.instance.currentUser;
    _currentUserId = user?.uid ?? '';

    _voiceCtrl = vrc.VoiceRecorderController();

    PresenceService.instance.markOnline();

    // clear typing/recording on open
    unawaited(_updateMyTyping(false));
    unawaited(_updateMyRecording(false));

    // roomId format: "<uidA>_<uidB>"
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

      final derivedOther = _resolveOtherFromParticipants(data['participants']);
      if (derivedOther != null && derivedOther != _otherUserId) {
        debugPrint(
            '[ChatScreen] otherUserId corrected: $_otherUserId -> $derivedOther');
        _otherUserId = derivedOther;

        _didPrimeOtherOnce = false;

        _ensureMediaService(forceRecreate: true);

        unawaited(_primeOtherUserMetaOnce(force: true));
        _subscribeToOtherUserBlockState();
        _subscribeToFriendship();
        _subscribeToBlockState();
      }

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
    } catch (e, st) {
      debugPrint('[ChatScreen] _markRecentMessagesAsSeen error: $e\n$st');
    }
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
        .listen(
          (snap) {
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
      },
      onError: (e, st) {
        debugPrint('[ChatScreen] _subscribeToBlockState error: $e\n$st');
        if (!mounted || _disposed) return;
        setState(() {
          _isBlocked = false;
          _loadingBlockState = false;
        });
      },
    );
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
        .listen(
          (snap) {
        if (_disposed) return;

        final data = snap.data() ?? {};

        final raw = data['blockedUserIds'] as List<dynamic>?;
        final blockedIds =
        (raw ?? const <dynamic>[]).map((e) => e.toString()).toList();
        final hasBlockedMeNow = blockedIds.contains(_currentUserId);

        final parsedGender = _parseGender(data['gender']);
        final parsedAvatarType = _parseAvatarType(data['avatarType']);

        // ✅ privacy (new + legacy)
        final profileVis = _readOtherPrivacyValue(data, _fieldProfileVisibility);
        final addFriendVis = _readOtherPrivacyValue(data, _fieldAddFriendVisibility);

        final genderChanged = parsedGender != _otherUserGender;
        final blockChanged = hasBlockedMeNow != _hasBlockedMe;
        final avatarChanged = parsedAvatarType != _otherUserAvatarType;

        final privacyChanged =
            profileVis != _otherProfileVisibility || addFriendVis != _otherAddFriendVisibility;

        final shouldUpdate = blockChanged ||
            _loadingOtherBlockState ||
            genderChanged ||
            avatarChanged ||
            privacyChanged;

        if (!mounted) return;
        if (shouldUpdate) {
          setState(() {
            _hasBlockedMe = hasBlockedMeNow;
            _loadingOtherBlockState = false;
            _otherUserGender = parsedGender;
            _otherUserAvatarType = parsedAvatarType;
            _otherProfileVisibility = profileVis;
            _otherAddFriendVisibility = addFriendVis;
          });
        } else if (_loadingOtherBlockState) {
          setState(() => _loadingOtherBlockState = false);
        }
      },
      onError: (e, st) {
        debugPrint('[ChatScreen] _subscribeToOtherUserBlockState error: $e\n$st');
        if (!mounted || _disposed) return;
        setState(() {
          _hasBlockedMe = false;
          _loadingOtherBlockState = false;
          _otherUserGender = TypingAvatarGender.other;
          _otherUserAvatarType = 'bear';
          _otherProfileVisibility = _privacyEveryone;
          _otherAddFriendVisibility = _privacyEveryone;
        });
      },
    );
  }

  // ✅ FIX: Use the new friendshipStatusStream() (normalized statuses + correct subscription type)
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
        .listen(
          (status) {
        if (!mounted || _disposed) return;

        if (status == _friendStatus && _loadingFriendship == false) {
          _scheduleMarkSeen();
          return;
        }

        setState(() {
          _friendStatus = status; // requested/incoming/accepted/null
          _loadingFriendship = false;
        });

        _scheduleMarkSeen();
      },
      onError: (e, st) {
        debugPrint('[ChatScreen] friendship stream error: $e\n$st');
        if (!mounted || _disposed) return;
        setState(() {
          _friendStatus = null;
          _loadingFriendship = false;
        });
      },
    );
  }

  String? _resolveOtherFromParticipants(dynamic rawParticipants) {
    final me = _currentUserId;
    if (me.isEmpty) return null;

    final list = (rawParticipants as List?)
        ?.map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList() ??
        const <String>[];

    if (list.length < 2) return null;

    final other = list.firstWhere((id) => id != me, orElse: () => '');
    return other.isEmpty ? null : other;
  }

  Future<void> _sendFriendRequest() async {
    final other = _otherUserId;
    if (_currentUserId.isEmpty || other == null || other.isEmpty) return;

    // ✅ respect privacy
    if (!_canRequestFriendByPrivacy) {
      final l10n = AppLocalizations.of(context);
      _toastSnack(l10n?.friendRequestNotAllowed ??
          'This user is not accepting friend requests.');
      return;
    }

    await _friendshipService.sendRequest(me: _currentUserId, other: other);
  }

  Future<void> _acceptFriendRequest() async {
    final other = _otherUserId;
    if (_currentUserId.isEmpty || other == null || other.isEmpty) return;
    await _friendshipService.acceptRequest(me: _currentUserId, other: other);
  }

  Future<void> _declineFriendRequest() async {
    final other = _otherUserId;
    if (_currentUserId.isEmpty || other == null || other.isEmpty) return;
    await _friendshipService.declineRequest(me: _currentUserId, other: other);
  }

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
    if (_disposed) return;

    try {
      await FirebaseFirestore.instance
          .collection('privateChats')
          .doc(widget.roomId)
          .set({'typing_$_currentUserId': isTyping}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ChatScreen] _updateMyTyping failed: $e');
    }
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
    } catch (e) {
      debugPrint('[ChatScreen] _updateMyRecording failed: $e');
    }
  }

  void _onComposerChanged(String value) {
    // If we are restricted/blocked, never set typing flags.
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

  Future<void> _confirmAndClearChat() async {
    await ChatScreenDeletion.confirmAndClearChat(
      context: context,
      roomId: widget.roomId,
      currentUserId: _currentUserId,
      otherUserId: _otherUserId,
    );
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
          content: Text(l10n?.userBlockedInfo ?? 'You cannot message this user.'),
        ),
      );
      return false;
    }

    // ✅ Profile access restriction safety
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
        info = l10n?.friendshipInfoIncoming ??
            'Accept the friend request to chat.';
      } else {
        // If requests are disabled, show a more accurate message.
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
    } catch (e, st) {
      debugPrint('[ChatScreen] _sendMessage error: $e\n$st');
    } finally {
      if (mounted && !_disposed) setState(() => _sending = false);
    }
  }

  // ✅ VOICE NOTE SEND
  Future<void> _handleVoiceDraftSend(vrc.VoiceDraft draft) async {
    if (!_guardCanSendWithSnackbar()) return;
    if (_isUploading) return;

    _ensureMediaService();
    final media = _mediaService;
    if (media == null) {
      debugPrint(
          '[ChatScreen] _handleVoiceDraftSend: mediaService is null (otherUserId=$_otherUserId)');
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
        pf = PlatformFile(
          name: name,
          size: bytes.length,
          bytes: bytes,
          path: null,
        );
      } else if (!kIsWeb && path != null && path.trim().isNotEmpty) {
        pf = PlatformFile(name: name, size: 0, path: path.trim());
      } else {
        debugPrint('[ChatScreen] VoiceDraft has no bytes/path; cannot send');
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
    } catch (e, st) {
      debugPrint('[ChatScreen] _handleVoiceDraftSend error: $e\n$st');
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _uploadProgress = null);
    }

    if (task == null) {
      debugPrint('[ChatScreen] Voice send failed (no UploadTask returned).');
    }
  }

  Future<void> _handleAttachPressed() async {
    if (_isUploading) return;
    if (!_guardCanSendWithSnackbar()) return;

    _ensureMediaService();
    if (_mediaService == null) {
      _toastSnack('Unable to attach right now.');
      return;
    }

    FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted || _disposed) return;

    final l10n = AppLocalizations.of(context)!;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101018),
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
                    if (!isWeb) ...[
                      ListTile(
                        leading:
                        const Icon(Icons.camera_alt, color: Colors.white70),
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

    if (!_guardCanSendWithSnackbar()) return;
    if (_isUploading) return;

    _ensureMediaService();
    final media = _mediaService;
    if (media == null) {
      debugPrint('[ChatScreen] _sendPlatformFile: mediaService is null');
      _toastSnack('Unable to send file right now.');
      return;
    }

    if (!mounted || _disposed) return;
    setState(() => _uploadProgress = 0.0);

    try {
      await media.sendFileMessage(
        file,
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
  }

  Future<void> _pickImageFromGallery() async {
    _ensureMediaService();
    final media = _mediaService;
    if (media == null) return;

    final file = await media.pickImageFromGallery();
    await _sendPlatformFile(file);
  }

  Future<void> _pickVideoFromGallery() async {
    _ensureMediaService();
    final media = _mediaService;
    if (media == null) return;

    final file = await media.pickVideoFromGallery();
    await _sendPlatformFile(file);
  }

  Future<void> _captureImageWithCamera(
      {CameraDevice camera = CameraDevice.rear}) async {
    _ensureMediaService();
    final media = _mediaService;
    if (media == null) return;

    final file = await media.captureImageWithCamera(preferredCamera: camera);
    if (file == null) return;
    await _sendPlatformFile(file);
  }

  Future<void> _captureVideoWithCamera(
      {CameraDevice camera = CameraDevice.rear}) async {
    _ensureMediaService();
    final media = _mediaService;
    if (media == null) return;

    final file = await media.captureVideoWithCamera(preferredCamera: camera);
    if (file == null) return;
    await _sendPlatformFile(file);
  }

  Future<void> _pickAndSendFile() async {
    _ensureMediaService();
    final media = _mediaService;
    if (media == null) return;

    final file = await media.pickFileFromDevice();
    await _sendPlatformFile(file);
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
        } catch (e, st) {
          debugPrint('[ChatScreen] leaveRoom (postFrame) error: $e\n$st');
        }
      });
    } catch (_) {
      Future.microtask(() {
        try {
          CurrentChatTracker.instance.leaveRoom();
        } catch (e, st) {
          debugPrint('[ChatScreen] leaveRoom (microtask) error: $e\n$st');
        }
      });
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

    _msgController.dispose();
    _roomSub?.cancel();
    _blockSub?.cancel();
    _otherUserSub?.cancel();
    _myUserSub?.cancel();
    _messagesSub?.cancel();

    // ✅ cancel friendship stream subscription
    _friendSub?.cancel();
    _friendSub = null;

    // keep service dispose safe
    _friendshipService.dispose();

    try {
      _mediaService?.dispose();
    } catch (_) {}
    _mediaService = null;

    _voiceCtrl.disposeController();

    _safeLeaveRoom();

    super.dispose();
  }

  Widget _buildFriendshipBanner(AppLocalizations l10n) {
    if (_loadingFriendship || !_isFriendshipEnforced) {
      return const SizedBox.shrink();
    }

    // ✅ If other profile is private and we are not friends, show locked banner
    if (!_isAnyBlock && _isChatAccessRestricted && !_isFriends) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.profilePrivateChatRestricted ??
                    'This user’s profile is private. You must be friends to chat.',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          ],
        ),
      );
    }

    if (_friendStatus == null) {
      final bool canRequest = _canRequestFriendByPrivacy;

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
            Icon(
              canRequest ? Icons.person_add_alt_1_outlined : Icons.lock_outline,
              color: Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                canRequest
                    ? l10n.friendshipBannerNotFriends(widget.title)
                    : (l10n.friendRequestNotAllowed ??
                    'This user is not accepting friend requests.'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            if (canRequest)
              TextButton(
                onPressed: _sendFriendRequest,
                child: Text(l10n.friendshipBannerSendRequestButton),
              ),
          ],
        ),
      );
    }

    if (_hasIncomingFriendRequest) {
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
        Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 4),
      ],
    );

    String cannotSendText() {
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

    // ✅ The bottom inset (keyboard height). We will pin the composer above it.
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    // ✅ Reserve space so messages never get covered by the pinned bottom stack.
    const double composerReserve = 96;
    const double indicatorReserve = 54;
    final bool showIndicator =
        !_isAnyBlock && (_isOtherTyping || _isOtherRecording);

    final double listBottomPadding =
        composerReserve + (showIndicator ? indicatorReserve : 0) + safeBottom + 8;

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
      bottomArea = ChatInputBar(
        key: ValueKey('chat_input_${widget.roomId}'),
        controller: _msgController,
        sending: _sending || _isUploading,
        uploadProgress: _uploadProgress,
        onAttach: _handleAttachPressed,
        onSend: _sendMessage,
        onTextChanged: _onComposerChanged,
        voiceController: _voiceCtrl,
        onVoiceSend: _handleVoiceDraftSend,

        // ✅ while recording: force typing=false and recording=true
        onVoiceRecordStart: () {
          _typingDebounce?.cancel();
          _isMeTypingFlag = false;
          unawaited(_updateMyTyping(false));
          unawaited(_updateMyRecording(true));
        },
        onVoiceRecordStop: () {
          unawaited(_updateMyRecording(false));
        },
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

    final typingKey =
    ValueKey('typing:${widget.roomId}:${_otherUserId ?? 'unknown'}');

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
        child: Stack(
          children: [
            Column(
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
                    bottomInset: listBottomPadding,
                  ),
                ),
              ],
            ),

            // ✅ Pinned bottom stack (TypingIndicator + Composer)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: viewInsetsBottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isAnyBlock)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: Alignment.bottomCenter,
                        child: (showIndicator)
                            ? TypingIndicator(
                          key: typingKey,
                          isVisible: true,
                          text: _isOtherRecording
                              ? '${widget.title} is recording...'
                              : l10n.isTyping(widget.title),
                          gender: _typingIndicatorGender,
                          avatarType: _typingIndicatorAvatarType,
                          mode: _typingIndicatorMode,
                        )
                            : const SizedBox(height: 0),
                      ),
                    SafeArea(
                      top: false,
                      child: bottomArea,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
