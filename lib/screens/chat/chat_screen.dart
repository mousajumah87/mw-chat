// lib/screens/chat/chat_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' show UploadTask;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/chat_attachment_utils.dart';
import '../../utils/current_chat_tracker.dart';
import '../../utils/notification_badge_service.dart';
import '../../utils/presence_service.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/chat_media_preview_sheet.dart';
import '../../widgets/chat/message_reactions.dart';
import '../../widgets/chat/message_reply.dart';
import '../../widgets/chat/mw_emoji_panel.dart';
import '../../widgets/chat/typing_indicator.dart';
import '../../widgets/safety/report_message_dialog.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_feedback.dart';
import 'chat_app_bar.dart';
import 'chat_friendship_service.dart';
import 'chat_media_service.dart';
import 'chat_message_list.dart';
import 'chat_screen_deletion.dart';

import 'package:mw/utils/voice_recorder_controller.dart' as vrc;
import '../../widgets/chat/mw_reply_to.dart';

import 'dart:typed_data'; // ✅ Uint8List
import 'package:path/path.dart' as p; // ✅ p.extension, p.join
import 'package:path_provider/path_provider.dart'; // ✅ getTemporaryDirectory

// ✅ Web-safe: conditional import for io File helper (you already use this pattern in other files)
import '../../utils/io/io_file_stub.dart'
if (dart.library.io) '../../utils/io/io_file.dart';

import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../calls/call_screen.dart';

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


  // ✅ Key to control ChatMessageList scroll programmatically
  final GlobalKey<ChatMessageListState> _listKey = GlobalKey<ChatMessageListState>();

  final GlobalKey _composerAreaKey = GlobalKey();
  double _composerAreaHeight = 84; // fallback
  bool _measureScheduled = false;

  MwReplyTo? _replyingTo;

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

  // ------------------------------------------------------------
  // ✅ WhatsApp-like selection state
  // ------------------------------------------------------------
  final Set<String> _selectedMessageIds = <String>{};
  DocumentSnapshot<Map<String, dynamic>>? _selectedMessageDoc;
  bool _selectedIsMe = false;

  String? get _selectedMessageId {
    if (_selectedMessageIds.isEmpty) return null;
    return _selectedMessageIds.first;
  }

  bool _unreadSyncInFlight = false;
  DateTime? _lastUnreadSyncAt;

  bool get _hasSelection => _selectedMessageIds.isNotEmpty;

  bool get _isFriends => ChatFriendshipService.isFriends(_friendStatus);

  bool get _isAnyBlock => _isBlocked || _hasBlockedMe;
  bool get _isLoadingBlock => _loadingBlockState || _loadingOtherBlockState;

  bool get _isFriendshipEnforced {
    if (_currentUserId.isEmpty) return false;
    final other = _otherUserId;
    if (other == null || other.isEmpty) return false;
    return true;
  }

  bool get _hasIncomingFriendRequest => _friendStatus == ChatFriendshipService.statusIncoming;
  bool get _hasOutgoingFriendRequest => _friendStatus == ChatFriendshipService.statusRequested;

  bool get _canRequestFriendByPrivacy {
    if (_isAnyBlock) return false;

    if (_friendStatus == ChatFriendshipService.statusRequested ||
        _friendStatus == ChatFriendshipService.statusIncoming ||
        _friendStatus == ChatFriendshipService.statusAccepted) {
      return false;
    }

    if (_otherAddFriendVisibility == _privacyNobody) return false;
    if (_otherAddFriendVisibility == _privacyFriends) return false;

    return true;
  }

  // ✅ IMPORTANT:
  // profileVisibility must NOT block chat for existing friends.
  bool get _isChatAccessRestricted {
    if (_isFriends) return false;

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

  bool _isDeletedForEveryoneDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return data['deletedForEveryone'] == true;
  }

  // ------------------------------------------------------------
  // ✅ Typing indicator helpers
  // ------------------------------------------------------------
  TypingAvatarGender _parseGender(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s == 'female') return TypingAvatarGender.female;
    if (s == 'male') return TypingAvatarGender.male;
    return TypingAvatarGender.other;
  }

  String _parseAvatarType(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return 'bear';
    return s;
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

    final chosen = (rawNew != null && rawNew.trim().isNotEmpty) ? rawNew : rawLegacy;
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

  Future<void> _resetUnreadBadgeCountServerBestEffort() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable('resetMyUnreadBadgeCount')
          .call();
    } catch (e) {
      debugPrint('⚠️ resetMyUnreadBadgeCount failed in chat screen: $e');
    }
  }

  Future<int> _computeMyTotalUnreadAcrossRooms() async {
    if (_currentUserId.isEmpty) return 0;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('privateChats')
          .where('participants', arrayContains: _currentUserId)
          .get();

      int total = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final unreadMap =
            (data['unreadCounts'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};

        final raw = unreadMap[_currentUserId];
        if (raw is num) {
          total += raw.toInt();
        }
      }

      return total < 0 ? 0 : total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _syncBadgesAfterUnreadChange() async {
    if (_currentUserId.isEmpty) return;

    final totalUnread = await _computeMyTotalUnreadAcrossRooms();

    await NotificationBadgeService.instance.setBadgeCount(totalUnread);

    if (totalUnread <= 0) {
      await _resetUnreadBadgeCountServerBestEffort();
    }
  }

  Future<void> _markRoomReadAndSyncBadges() async {
    if (_currentUserId.isEmpty) return;

    final now = DateTime.now();
    if (_unreadSyncInFlight) return;
    if (_lastUnreadSyncAt != null &&
        now.difference(_lastUnreadSyncAt!).inMilliseconds < 700) {
      return;
    }

    _unreadSyncInFlight = true;
    _lastUnreadSyncAt = now;

    final roomRef =
    FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);

    try {
      await roomRef.set(
        {
          'unreadCounts': {_currentUserId: 0},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}

    try {
      await _syncBadgesAfterUnreadChange();
    } finally {
      _unreadSyncInFlight = false;
    }
  }

  // ------------------------------------------------------------
  // ✅ MW Feedback helpers
  // ------------------------------------------------------------
  void _toastInfo(String msg) {
    if (!mounted || _disposed) return;
    MwFeedback.show(context, message: msg, type: MwFeedbackType.info);
  }

  void _toastError(String msg) {
    if (!mounted || _disposed) return;
    MwFeedback.show(context, message: msg, type: MwFeedbackType.error);
  }

  Future<void> _hapticLight() async {
    if (kIsWeb) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  void _hideReactionOverlay() {
    try {
      MwReactionOverlay.hide();
    } catch (_) {}
  }

  void _clearSelection() {
    if (!mounted || _disposed) return;
    setState(() {
      _selectedMessageIds.clear();
      _selectedMessageDoc = null;
      _selectedIsMe = false;
    });
  }

  void _toggleSingleSelection(
      DocumentSnapshot<Map<String, dynamic>> doc,
      bool isMe,
      ) {
    if (!mounted || _disposed) return;

    if (_isDeletedForEveryoneDoc(doc)) return;

    final id = doc.id.trim();
    if (id.isEmpty) return;

    setState(() {
      if (_selectedMessageIds.contains(id)) {
        _selectedMessageIds.clear();
        _selectedMessageDoc = null;
        _selectedIsMe = false;
      } else {
        _selectedMessageIds
          ..clear()
          ..add(id);
        _selectedMessageDoc = doc;
        _selectedIsMe = isMe;
      }
    });
  }

  bool _isUsableLocalPath(String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return false;

    // iOS Photos asset identifiers can look like ph://... which is not a real file path
    if (p.startsWith('ph://')) return false;

    // Some pickers return file://... normalize later, still usable
    return true;
  }

  String _stripFileScheme(String path) {
    final p = path.trim();
    if (p.startsWith('file://')) return p.replaceFirst('file://', '');
    return p;
  }

  /// Ensures PlatformFile is uploadable by your media service:
  /// - If it already has a usable local path: keep it.
  /// - Else if it has bytes (non-web): write temp file and return a new PlatformFile with a real path.
  /// - Else return as-is (media service might still handle it, but likely will fail).
  Future<PlatformFile> _preparePlatformFileForUpload(PlatformFile pf, {required String forcedType}) async {
    if (kIsWeb) return pf;

    final rawPath = pf.path;
    if (_isUsableLocalPath(rawPath)) {
      final normalized = _stripFileScheme(rawPath!.trim());
      if (normalized == rawPath) return pf;

      return PlatformFile(
        name: pf.name,
        size: pf.size,
        bytes: pf.bytes, // keep if present
        path: normalized,
        readStream: pf.readStream,
      );
    }

    final bytes = pf.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      // ✅ Write to temp so ChatMediaService can upload by file path
      final tmp = await _writeTempPickedBytesToFile(
        bytes: bytes,
        originalName: pf.name,
        forcedType: forcedType,
      );

      if (tmp != null && tmp.trim().isNotEmpty) {
        return PlatformFile(
          name: pf.name,
          size: bytes.length,
          path: tmp,
          // important: don’t keep huge bytes around unless you really need them
          bytes: null,
        );
      }
    }

    return pf;
  }

  /// Writes picked bytes to a temp file (non-web).
  Future<String?> _writeTempPickedBytesToFile({
    required Uint8List bytes,
    required String originalName,
    required String forcedType,
  }) async {
    try {
      final dir = await getTemporaryDirectory();

      final ext = p.extension(originalName).toLowerCase();
      String safeExt = ext;

      if (safeExt.isEmpty) {
        // fallback based on type
        if (forcedType == 'video') safeExt = '.mp4';
        else if (forcedType == 'image') safeExt = '.jpg';
        else if (forcedType == 'audio') safeExt = '.m4a';
        else safeExt = '.bin';
      }

      final fileName = 'mw_pick_${forcedType}_${DateTime.now().millisecondsSinceEpoch}$safeExt';
      final fullPath = p.join(dir.path, fileName);

      final f = ioFile(fullPath);
      await f.writeAsBytes(bytes, flush: true);
      return fullPath;
    } catch (_) {
      return null;
    }
  }


  // ------------------------------------------------------------
  // ✅ Scroll helpers
  // ------------------------------------------------------------
  Future<void> _scrollToLatestAndFocus({
    bool animated = true,
    bool afterNextFrame = false,
  }) async {
    if (!mounted || _disposed) return;

    if (_panelVisible) {
      setState(() => _panelVisible = false);
    }

    if (afterNextFrame) {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    if (!mounted || _disposed) return;

    // If you want to re-enable:
    // await _listKey.currentState?.scrollToLatest(animated: animated);

    if (!mounted || _disposed) return;
    _composerFocusNode.requestFocus();
  }

  // ------------------------------------------------------------
  // ✅ Reply helpers
  // ------------------------------------------------------------
  Map<String, dynamic>? _replyToPayloadOrNull(MwReplyTo? r) {
    if (r == null) return null;

    Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(r.toMap());
    } catch (_) {
      return null;
    }

    final rawPreview = (map['previewText'] ?? map['text'] ?? map['message'] ?? '').toString().trim();
    final rawMessageId = (map['messageId'] ?? map['id'] ?? '').toString().trim();
    final rawSenderId = (map['senderId'] ?? map['fromId'] ?? '').toString().trim();

    var type = (map['type'] ?? map['messageType'] ?? '').toString().trim();
    if (type.isEmpty) type = 'text';

    final fileName = (map['fileName'] ?? '').toString().trim();
    final createdAt = map['createdAt'];

    final payload = <String, dynamic>{
      if (rawMessageId.isNotEmpty) 'messageId': rawMessageId,
      if (rawSenderId.isNotEmpty) 'senderId': rawSenderId,
      'type': type,
      'previewText': rawPreview.isEmpty ? '…' : rawPreview,
      if (fileName.isNotEmpty) 'fileName': fileName,
      if (createdAt is Timestamp) 'createdAt': createdAt,
    };

    if ((payload['messageId'] as String?)?.trim().isEmpty ?? true) return null;
    if ((payload['senderId'] as String?)?.trim().isEmpty ?? true) return null;

    return payload;
  }

  void _setReplyTo(MwReplyTo r) {
    if (!mounted || _disposed) return;
    if (_isAnyBlock || !_canSendMessages) return;

    setState(() => _replyingTo = r);

    _closeEmojiPanelIfOpen();
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      _composerFocusNode.requestFocus();
    });
  }

  void _clearReplyTo() {
    if (!mounted || _disposed) return;
    setState(() => _replyingTo = null);
  }

// ------------------------------------------------------------
// ✅ Composer height measure (for listBottomInset)
// ------------------------------------------------------------
  static const double _composerMinHeight = 74.0;

  void _measureComposerHeight() {
    if (_measureScheduled) return;
    _measureScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted || _disposed) return;

      final ctx = _composerAreaKey.currentContext;
      if (ctx == null) return;

      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) return;

      final raw = ro.size.height;
      final h = raw.isFinite ? raw : 0.0;

      // ✅ always keep a sane minimum to avoid under-reserving space
      final next = math.max(_composerMinHeight, h);

      if ((next - _composerAreaHeight).abs() > 1.0) {
        if (!mounted || _disposed) return;
        setState(() => _composerAreaHeight = next);
      }
    });
  }

  // ------------------------------------------------------------
  // ✅ Media service
  // ------------------------------------------------------------
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

  // ------------------------------------------------------------
  // ✅ Seen logic
  // ------------------------------------------------------------
  bool _snapshotHasUnseenIncoming(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_disposed) return false;

    final me = _currentUserId;
    final other = _otherUserId;
    if (me.isEmpty || other == null || other.isEmpty) return false;
    if (_isAnyBlock) return false;
    if (!_isFriends) return false;

    for (final doc in snap.docs) {
      final data = doc.data();

      final senderId = (data['senderId'] ?? '').toString();
      if (senderId.isEmpty || senderId == me) continue;

      final hiddenFor = (data['hiddenFor'] as List?)?.cast<String>() ?? const [];
      if (hiddenFor.contains(me)) continue;

      if (data['deletedForEveryone'] == true) continue;

      final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? const [];
      if (!seenBy.contains(me)) return true;
    }
    return false;
  }

  void _maybeScheduleMarkSeenFromSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted || _disposed) return;
    if (_snapshotHasUnseenIncoming(snap)) {
      _scheduleMarkSeen();
    }
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
    if (!_isFriends) return;

    final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);

    try {
      final snap = await roomRef.collection('messages').orderBy('createdAt', descending: true).limit(40).get();

      if (_disposed) return;

      final batch = FirebaseFirestore.instance.batch();
      int updates = 0;

      for (final doc in snap.docs) {
        final data = doc.data();

        final senderId = (data['senderId'] as String?) ?? '';
        if (senderId.isEmpty || senderId == me) continue;

        final hiddenFor = (data['hiddenFor'] as List?)?.cast<String>() ?? [];
        if (hiddenFor.contains(me)) continue;

        if (data['deletedForEveryone'] == true) continue;

        final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? const [];
        if (seenBy.contains(me)) continue;

        batch.update(doc.reference, {'seenBy': FieldValue.arrayUnion([me])});
        updates++;
        if (updates >= 20) break;
      }

      if (updates > 0) {
        await batch.commit();
      }
      await _resetMyUnread();
    } catch (_) {}
  }

  // ------------------------------------------------------------
  // ✅ Firestore meta
  // ------------------------------------------------------------
  Future<void> _resetMyUnread() async {
    await _markRoomReadAndSyncBadges();
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
          .set({'recording_$_currentUserId': isRecording}, SetOptions(merge: true));
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
        return l10n?.messageContainsRestrictedContent ?? 'Message contains restricted content.';
      }
    }
    return null;
  }

  bool _guardCanSendWithSnackbar() {
    final l10n = AppLocalizations.of(context);

    if (_isAnyBlock) {
      _toastInfo(l10n?.userBlockedInfo ?? 'You cannot message this user.');
      return false;
    }

    if (_isChatAccessRestricted) {
      _toastInfo(
        l10n?.profilePrivateChatRestricted ?? 'This user’s profile is private. You must be friends to chat.',
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
          info = l10n?.friendRequestNotAllowed ?? 'This user is not accepting friend requests.';
        } else {
          info = l10n?.friendshipInfoNotFriends ?? 'You must be friends to chat.';
        }
      }
      _toastInfo(info);
      return false;
    }

    return true;
  }

  // ------------------------------------------------------------
  // ✅ Reactions
  // ------------------------------------------------------------
  Future<void> _onReactionTapAsync(String messageId, String emoji) async {
    if (_disposed) return;
    if (_currentUserId.isEmpty) return;
    if (_isAnyBlock) return;

    final mid = messageId.trim();
    final e = emoji.trim();
    if (mid.isEmpty || e.isEmpty) return;

    _hideReactionOverlay();

    final msgRef = FirebaseFirestore.instance
        .collection('privateChats')
        .doc(widget.roomId)
        .collection('messages')
        .doc(mid);

    try {
      await MwReactions.setSingleReaction(
        messageRef: msgRef,
        userId: _currentUserId,
        emoji: e,
      );
    } catch (_) {
      if (mounted) {
        MwFeedback.show(
          context,
          message: AppLocalizations.of(context)?.generalErrorMessage ?? 'Something went wrong',
          type: MwFeedbackType.error,
        );
      }
    }
  }

  // ------------------------------------------------------------
  // ✅ Header actions
  // ------------------------------------------------------------
  bool get _canCopySelected {
    final data = _selectedMessageDoc?.data();
    if (data == null) return false;
    if (data['deletedForEveryone'] == true) return false;
    final type = (data['type'] ?? '').toString();
    if (type != 'text') return false;
    final txt = (data['text'] ?? '').toString().trim();
    return txt.isNotEmpty;
  }

  bool get _canDeleteSelected {
    final doc = _selectedMessageDoc;
    if (doc == null) return false;
    if (_isAnyBlock) return false;
    if (_isDeletedForEveryoneDoc(doc)) return false;
    return true;
  }

  bool get _canReportSelected {
    final doc = _selectedMessageDoc;
    if (doc == null) return false;
    if (_isAnyBlock) return false;
    if (_isDeletedForEveryoneDoc(doc)) return false;
    return true;
  }

  Future<void> _copySelectedMessage() async {
    final l10n = AppLocalizations.of(context);
    final data = _selectedMessageDoc?.data();
    if (data == null) return;

    final txt = (data['text'] ?? '').toString();
    if (txt.trim().isEmpty) return;

    try {
      await Clipboard.setData(ClipboardData(text: txt));
      _toastInfo(l10n?.copied ?? 'Copied');
    } catch (_) {
      _toastError(l10n?.generalErrorMessage ?? 'Something went wrong');
    } finally {
      _clearSelection();
    }
  }

  Future<void> _onHeaderCopyPressed() async {
    _hideReactionOverlay();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    unawaited(_copySelectedMessage());
  }

  Future<void> _onHeaderDeletePressed() async {
    _hideReactionOverlay();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _deleteSelectedMessageFlow();
  }

  Future<void> _onHeaderReportPressed() async {
    _hideReactionOverlay();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _reportSelectedMessageFlow();
  }

  DocumentReference<Map<String, dynamic>>? _selectedMessageRefOrNull() {
    final doc = _selectedMessageDoc;
    if (doc == null) return null;

    return FirebaseFirestore.instance
        .collection('privateChats')
        .doc(widget.roomId)
        .collection('messages')
        .doc(doc.id);
  }

  Future<void> _deleteSelectedMessageFlow() async {
    if (!mounted || _disposed) return;

    final l10n = AppLocalizations.of(context)!;
    final doc = _selectedMessageDoc;
    if (doc == null) return;

    final me = _currentUserId;
    if (me.isEmpty) return;

    final msgRef = _selectedMessageRefOrNull();
    if (msgRef == null) return;

    final data = doc.data() ?? const <String, dynamic>{};
    final alreadyDeletedForEveryone = data['deletedForEveryone'] == true;

    Future<void> deleteForMe() async {
      try {
        await msgRef.set(
          {
            'hiddenFor': FieldValue.arrayUnion([me]),
            'hiddenAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        _toastInfo(l10n.messageDeletedForMeSuccess ?? 'Deleted for you');
      } catch (_) {
        _toastError(l10n.generalErrorMessage ?? 'Something went wrong');
      } finally {
        _clearSelection();
      }
    }

    Future<void> deleteForEveryone() async {
      if (!_selectedIsMe) {
        await deleteForMe();
        return;
      }

      try {
        await msgRef.set(
          {
            'deletedForEveryone': true,
            'deletedAt': FieldValue.serverTimestamp(),
            'deletedBy': me,
            'text': '',
            'type': (data['type'] ?? 'text'),
            'fileUrl': FieldValue.delete(),
            'fileName': FieldValue.delete(),
            'fileType': FieldValue.delete(),
            'replyTo': FieldValue.delete(),
            MwReactions.fieldReactions: <String, dynamic>{},
          },
          SetOptions(merge: true),
        );

        _toastInfo(l10n.messageDeletedForEveryoneSuccess ?? 'Deleted for everyone');
      } catch (_) {
        _toastError(l10n.generalErrorMessage ?? 'Something went wrong');
      } finally {
        _clearSelection();
      }
    }

    final bool canEveryone = _selectedIsMe && !alreadyDeletedForEveryone;

    final bool? choice = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteMessageTitle ?? 'Delete message'),
        content: Text(
          canEveryone
              ? (l10n.deleteMessageDescriptionEveryone ?? 'Choose how you want to delete this message.')
              : (l10n.deleteMessageDescriptionMe ?? 'This will delete the message for you only.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l10n.cancel ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.deleteForMe ?? 'Delete for me'),
          ),
          if (canEveryone)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.deleteForEveryone ?? 'Delete for everyone',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
        ],
      ),
    );

    if (!mounted || _disposed) return;

    if (choice == null) return;
    if (choice == true) {
      await deleteForEveryone();
    } else {
      await deleteForMe();
    }
  }

  Future<void> _reportSelectedMessageFlow() async {
    final l10n = AppLocalizations.of(context)!;
    final doc = _selectedMessageDoc;
    final otherId = _otherUserId;
    if (doc == null || otherId == null || otherId.trim().isEmpty) return;

    try {
      await ReportMessageDialog.open(
        context,
        roomId: widget.roomId,
        messageId: doc.id,
        reportedUserId: otherId,
        messageData: doc.data() ?? const <String, dynamic>{},
      );
    } catch (_) {
      _toastError(l10n.generalErrorMessage ?? 'Something went wrong');
    } finally {
      _clearSelection();
    }
  }

  // ------------------------------------------------------------
  // ✅ Friend actions (unchanged)
  // ------------------------------------------------------------
  Future<void> _sendFriendRequestToOther() async {
    final otherId = _otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    if (_currentUserId.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;

    final status = _friendStatus;
    if (ChatFriendshipService.isFriends(status) ||
        ChatFriendshipService.isRequested(status) ||
        ChatFriendshipService.isIncoming(status)) {
      return;
    }

    if (!_canRequestFriendByPrivacy) {
      _toastInfo(l10n.friendRequestNotAllowed ?? 'This user is not accepting friend requests.');
      return;
    }

    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('friends')
        .doc(otherId);

    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(otherId)
        .collection('friends')
        .doc(_currentUserId);

    final now = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch();

    batch.set(
      myRef,
      {
        'status': ChatFriendshipService.statusRequested,
        'createdAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    batch.set(
      theirRef,
      {
        'status': ChatFriendshipService.statusIncoming,
        'createdAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    try {
      await batch.commit();
      if (!mounted || _disposed) return;
      _toastInfo(l10n.friendRequestSent ?? 'Friend request sent');
    } catch (_) {
      if (!mounted || _disposed) return;
      _toastError(l10n.friendRequestSendFailed ?? 'Failed to send request');
    }
  }

  Future<void> _acceptIncomingRequest() async {
    final otherId = _otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    if (_currentUserId.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;

    if (!ChatFriendshipService.isIncoming(_friendStatus)) return;

    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('friends')
        .doc(otherId);

    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(otherId)
        .collection('friends')
        .doc(_currentUserId);

    final batch = FirebaseFirestore.instance.batch();
    final now = FieldValue.serverTimestamp();
    final payload = {
      'status': ChatFriendshipService.statusAccepted,
      'updatedAt': now,
    };

    batch.set(myRef, payload, SetOptions(merge: true));
    batch.set(theirRef, payload, SetOptions(merge: true));

    try {
      await batch.commit();
      if (!mounted || _disposed) return;
      _toastInfo(l10n.friendRequestAccepted ?? 'Friend request accepted');
      _scheduleMarkSeen();
    } catch (_) {
      if (!mounted || _disposed) return;
      _toastError(l10n.friendRequestSendFailed ?? 'Something went wrong');
    }
  }

  Future<void> _declineOrCancelRequest() async {
    final otherId = _otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    if (_currentUserId.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;

    final status = _friendStatus;
    final bool isIncoming = ChatFriendshipService.isIncoming(status);
    final bool isRequested = ChatFriendshipService.isRequested(status);
    if (!isIncoming && !isRequested) return;

    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('friends')
        .doc(otherId);

    final theirRef = FirebaseFirestore.instance
        .collection('users')
        .doc(otherId)
        .collection('friends')
        .doc(_currentUserId);

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(myRef);
    batch.delete(theirRef);

    try {
      await batch.commit();
      if (!mounted || _disposed) return;
      _toastInfo(isIncoming ? (l10n.friendRequestDeclined ?? 'Declined') : (l10n.cancel ?? 'Cancelled'));
    } catch (_) {
      if (!mounted || _disposed) return;
      _toastError(l10n.friendRequestDeclined ?? 'Failed');
    }
  }

  // ------------------------------------------------------------
  // ✅ Messaging / Media
  // ------------------------------------------------------------
  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_guardCanSendWithSnackbar()) return;

    _closeEmojiPanelIfOpen();

    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final error = _validateMessageContent(text);
    if (error != null) {
      _toastInfo(error);
      return;
    }

    final MwReplyTo? replySnapshot = _replyingTo;
    final Map<String, dynamic>? replyPayload = _replyToPayloadOrNull(replySnapshot);

    _msgController.clear();

    if (mounted && !_disposed && _replyingTo != null) {
      setState(() => _replyingTo = null);
    }

    if (!mounted || _disposed) return;
    setState(() => _sending = true);

    try {
      await _updateMyTyping(false);
      await _updateMyRecording(false);
      _isMeTypingFlag = false;
      _typingDebounce?.cancel();

      final otherId = _otherUserId;
      if (otherId == null || otherId.trim().isEmpty) return;

      final meta = await _getSenderMeta(user);
      final profileUrl = meta['profileUrl'];
      final avatarType = meta['avatarType'];

      final batch = FirebaseFirestore.instance.batch();

      final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);
      final msgRef = roomRef.collection('messages').doc();

      final msgData = <String, dynamic>{
        'type': 'text',
        'text': text,
        'senderId': user.uid,
        'senderEmail': user.email,
        'profileUrl': profileUrl,
        'avatarType': avatarType,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
        'seenBy': <String>[],
        if (replyPayload != null) 'replyTo': replyPayload,
      };

      batch.set(msgRef, msgData);

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
      unawaited(_resetMyUnread());

      if (mounted && !_disposed) {
        await _hapticLight();
        unawaited(_scrollToLatestAndFocus(animated: true, afterNextFrame: true));
      }

      _scheduleMarkSeen();
    } catch (_) {
      // optional toast
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
      _toastInfo('Unable to send voice note right now.');
      return;
    }

    // ✅ Snapshot reply ONCE
    final replySnapshot = _replyingTo;
    final replyPayload = _replyToPayloadOrNull(replySnapshot);

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

      // ✅ Ensure uploadable on non-web (real path if needed)
      final prepared = await _preparePlatformFileForUpload(pf, forcedType: 'audio');

      task = await media.sendFileMessage(
        prepared,
        forcedType: 'audio',
        forcedContentType: mime,
        extraMessageFields: replyPayload != null ? {'replyTo': replyPayload} : null,
        onProgress: (p) {
          if (!mounted || _disposed) return;
          setState(() => _uploadProgress = p.clamp(0.0, 1.0));
        },
      );

      // ✅ Clear reply only after success
      if (mounted && !_disposed && _replyingTo != null) {
        setState(() => _replyingTo = null);
      }

      // ✅ Clear selection (WhatsApp-like)
      if (_hasSelection) _clearSelection();

      if (mounted && !_disposed) {
        await _hapticLight();
        unawaited(_scrollToLatestAndFocus(animated: true, afterNextFrame: true));
      }

      _scheduleMarkSeen();
    } catch (_) {
      _toastError('Failed to send voice note.');
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
      _toastInfo('Unable to attach right now.');
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

        Future<void> closeThen(Future<void> Function() action) async {
          Navigator.of(ctx, rootNavigator: true).pop();
          await Future<void>.delayed(const Duration(milliseconds: 150));
          if (!mounted || _disposed) return;
          await action();
        }

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
                      onTap: () => closeThen(() async {
                        final items = await _pickImagesMultiFromGallery();
                        if (!mounted || _disposed) return;
                        if (items.isEmpty) return;

                        await ChatMediaPreviewSheet.open(
                          context,
                          items: items,
                          onSend: (picked, caption) => _sendBatchWithProgress(picked, caption: caption),
                        );
                      }),
                    ),
                    ListTile(
                      leading: const Icon(Icons.videocam, color: Colors.white70),
                      title: Text(l10n.attachVideoFromGallery),
                      onTap: () => closeThen(_pickVideoFromGallery),
                    ),
                    if (!isWeb) ...[
                      ListTile(
                        leading: const Icon(Icons.camera_alt, color: Colors.white70),
                        title: Text(l10n.attachTakePhoto),
                        onTap: () => closeThen(() => _captureImageWithCamera(camera: CameraDevice.rear)),
                      ),
                      ListTile(
                        leading: const Icon(Icons.videocam_outlined, color: Colors.white70),
                        title: Text(l10n.attachRecordVideo),
                        onTap: () => closeThen(() => _captureVideoWithCamera(camera: CameraDevice.rear)),
                      ),
                    ],
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file, color: Colors.white70),
                      title: Text(l10n.attachFileFromDevice),
                      onTap: () => closeThen(() async {
                        final items = await _pickFilesMulti();
                        if (!mounted || _disposed) return;
                        if (items.isEmpty) return;

                        await ChatMediaPreviewSheet.open(
                          context,
                          items: items,
                          onSend: (picked, caption) => _sendBatchWithProgress(picked, caption: caption),
                        );
                      }),
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

  // previeow media
  Future<void> _sendTextMessageDirect(
      String text, {
        Map<String, dynamic>? replyPayload,
      }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_guardCanSendWithSnackbar()) return;

    final clean = text.trim();
    if (clean.isEmpty) return;

    final error = _validateMessageContent(clean);
    if (error != null) {
      _toastInfo(error);
      return;
    }

    final otherId = _otherUserId;
    if (otherId == null || otherId.trim().isEmpty) return;

    final meta = await _getSenderMeta(user);
    final profileUrl = meta['profileUrl'];
    final avatarType = meta['avatarType'];

    final batch = FirebaseFirestore.instance.batch();
    final roomRef = FirebaseFirestore.instance.collection('privateChats').doc(widget.roomId);
    final msgRef = roomRef.collection('messages').doc();

    batch.set(msgRef, {
      'type': 'text',
      'text': clean,
      'senderId': user.uid,
      'senderEmail': user.email,
      'profileUrl': profileUrl,
      'avatarType': avatarType,
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.now(),
      'seenBy': <String>[],
      if (replyPayload != null) 'replyTo': replyPayload,
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
    unawaited(_resetMyUnread());
  }


  Future<List<PendingAttachment>> _pickImagesMultiFromGallery() async {
    try {
      // image_picker supports multi-image
      final xs = await _picker.pickMultiImage(imageQuality: 88);
      if (xs.isEmpty) return const [];

      final capped = xs.take(ChatAttachmentUtils.defaultMaxSelection).toList();

      final out = <PendingAttachment>[];
      for (final x in capped) {
        if (kIsWeb) {
          final bytes = await x.readAsBytes();
          out.add(PendingAttachment(
            type: 'image',
            file: PlatformFile(name: x.name, size: bytes.length, bytes: bytes, path: null),
          ));
        } else {
          out.add(PendingAttachment(
            type: 'image',
            file: PlatformFile(name: x.name, size: 0, path: x.path),
          ));
        }
      }
      return out;
    } catch (_) {
      _toastError('Unable to pick photos.');
      return const [];
    }
  }

  Future<List<PendingAttachment>> _pickFilesMulti() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb, // ✅ web needs bytes for video thumb + upload
      );

      final files = res?.files ?? const <PlatformFile>[];
      if (files.isEmpty) return const [];

      final capped = files.take(ChatAttachmentUtils.defaultMaxSelection).toList();

      return capped.map((pf) {
        final type = _detectAttachmentType(pf);
        return PendingAttachment(type: type, file: pf);
      }).toList();
    } catch (_) {
      _toastError('Unable to pick files.');
      return const [];
    }
  }


  String _detectAttachmentType(PlatformFile pf) {
    final name = pf.name.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';

    const img = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};
    const vid = {'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'};
    const aud = {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'};

    if (img.contains(ext)) return 'image';
    if (vid.contains(ext)) return 'video';
    if (aud.contains(ext)) return 'audio';
    return 'file';
  }

  Future<void> _sendBatchWithProgress(
      List<PendingAttachment> items, {
        required String caption,
      }) async {
    if (items.isEmpty) return;
    if (!_guardCanSendWithSnackbar()) return;

    _ensureMediaService();
    final media = _mediaService;
    if (media == null) {
      _toastInfo('Unable to attach right now.');
      return;
    }

    // ✅ Snapshot reply ONCE, and decide who receives it (caption or first attachment)
    final replySnapshot = _replyingTo;
    final replyPayload = _replyToPayloadOrNull(replySnapshot);

    final cleanCaption = caption.trim();
    final hasCaption = cleanCaption.isNotEmpty;

    if (!mounted || _disposed) return;
    setState(() => _uploadProgress = 0.0);

    try {
      // ✅ Send caption first (as independent message).
      // WhatsApp-like: if caption exists, it receives the replyTo, attachments do NOT.
      if (hasCaption) {
        await _sendTextMessageDirect(
          cleanCaption,
          replyPayload: replyPayload,
        );
      }

      final total = items.length;

      for (int i = 0; i < total; i++) {
        final it = items[i];

        // ✅ If NO caption, first attachment carries replyTo
        final attachReply = (!hasCaption && i == 0) ? replyPayload : null;

        // ✅ Ensure PlatformFile is uploadable on non-web (real path if needed)
        final prepared = await _preparePlatformFileForUpload(
          it.file,
          forcedType: it.type,
        );

        await media.sendFileMessage(
          prepared,
          forcedType: it.type,
          forcedContentType: it.type == 'image'
              ? 'image/*'
              : it.type == 'video'
              ? 'video/*'
              : it.type == 'audio'
              ? 'audio/*'
              : null,

          // ✅ Only include replyTo if your ChatMediaService supports extra fields.
          extraMessageFields: attachReply != null ? {'replyTo': attachReply} : null,

          onProgress: (p) {
            if (!mounted || _disposed) return;
            final overall = (i + (p.clamp(0.0, 1.0))) / total;
            setState(() => _uploadProgress = overall);
          },
        );
      }

      // ✅ clear reply only after everything succeeds
      if (mounted && !_disposed && _replyingTo != null) {
        setState(() => _replyingTo = null);
      }

      if (mounted && !_disposed) {
        await _hapticLight();
        unawaited(_scrollToLatestAndFocus(animated: true, afterNextFrame: true));
      }

      _scheduleMarkSeen();
    } catch (_) {
      _toastError('Failed to send attachments.');
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _uploadProgress = null);
    }
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
      _toastInfo('Unable to attach right now.');
      return;
    }

    // ✅ Snapshot reply ONCE
    final replySnapshot = _replyingTo;
    final replyPayload = _replyToPayloadOrNull(replySnapshot);

    if (!mounted || _disposed) return;
    setState(() => _uploadProgress = 0.0);

    try {
      final ft = (forcedType ?? _detectAttachmentType(file)).trim();
      final prepared = await _preparePlatformFileForUpload(file, forcedType: ft);

      await media.sendFileMessage(
        prepared,
        forcedType: forcedType,
        forcedContentType: forcedContentType,
        extraMessageFields: replyPayload != null ? {'replyTo': replyPayload} : null,
        onProgress: (p) {
          if (!mounted || _disposed) return;
          setState(() => _uploadProgress = p.clamp(0.0, 1.0));
        },
      );

      // ✅ Clear reply only after success
      if (mounted && !_disposed && _replyingTo != null) {
        setState(() => _replyingTo = null);
      }

      // ✅ Clear selection (WhatsApp-like)
      if (_hasSelection) _clearSelection();

      if (mounted && !_disposed) {
        await _hapticLight();
        unawaited(_scrollToLatestAndFocus(animated: true, afterNextFrame: true));
      }

      _scheduleMarkSeen();
    } catch (_) {
      _toastError('Failed to attach file.');
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _uploadProgress = null);
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      // ✅ WEB: keep FilePicker (works)
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          withData: true,
          type: FileType.custom,
          allowedExtensions: const ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'],
        );

        final files = res?.files ?? const <PlatformFile>[];
        if (files.isEmpty) return;

        final capped = files.take(ChatAttachmentUtils.defaultMaxSelection).toList();
        final items = capped.map((pf) => PendingAttachment(type: 'video', file: pf)).toList();

        if (!mounted || _disposed) return;

        await ChatMediaPreviewSheet.open(
          context,
          items: items,
          onSend: (picked, caption) => _sendBatchWithProgress(picked, caption: caption),
        );
        return;
      }

      // ✅ iOS/Android: real gallery multi-select for videos
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          requestType: RequestType.video,
          maxAssets: ChatAttachmentUtils.defaultMaxSelection,
          // Optional: keeps UI snappy
          sortPathDelegate: SortPathDelegate.common,
        ),
      );

      if (assets == null || assets.isEmpty) return;

      final items = <PendingAttachment>[];

      for (final a in assets) {
        final file = await a.file; // ✅ returns a real local file (path)
        if (file == null) continue;

        final path = file.path;
        if (path.trim().isEmpty) continue;

        items.add(
          PendingAttachment(
            type: 'video',
            file: PlatformFile(
              name: path.split('/').last,
              size: await file.length(),
              path: path,
            ),
          ),
        );
      }

      if (items.isEmpty) return;
      if (!mounted || _disposed) return;

      await ChatMediaPreviewSheet.open(
        context,
        items: items,
        onSend: (picked, caption) => _sendBatchWithProgress(picked, caption: caption),
      );
    } catch (_) {
      _toastError('Unable to pick video.');
    }
  }

  Future<void> _captureImageWithCamera({CameraDevice camera = CameraDevice.rear}) async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: camera,
        imageQuality: 88,
      );
      if (x == null) return;

      final pf = PlatformFile(name: x.name, size: 0, path: x.path);
      await _sendPlatformFile(pf, forcedType: 'image', forcedContentType: 'image/*');
    } catch (_) {
      _toastError('Unable to take photo.');
    }
  }

  Future<void> _captureVideoWithCamera({CameraDevice camera = CameraDevice.rear}) async {
    try {
      final x = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: camera,
      );
      if (x == null) return;

      final path = x.path.trim();
      if (path.isEmpty) return;

      final items = <PendingAttachment>[
        PendingAttachment(
          type: 'video',
          file: PlatformFile(name: x.name, size: 0, path: path),
        ),
      ];

      if (!mounted || _disposed) return;

      await ChatMediaPreviewSheet.open(
        context,
        items: items,
        onSend: (picked, caption) => _sendBatchWithProgress(picked, caption: caption),
      );
    } catch (_) {
      _toastError('Unable to record video.');
    }
  }

  Future<Map<String, dynamic>> _getSenderMeta(User user) async {
    final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = snap.data() ?? {};
    return {
      'profileUrl': data['profileUrl'] as String?,
      'avatarType': data['avatarType'] as String?,
    };
  }

  // ------------------------------------------------------------
  // ✅ Friendship banner (same as yours)
  // ------------------------------------------------------------
  Widget _buildFriendshipBanner(AppLocalizations l10n) {
    if (_isAnyBlock) return const SizedBox.shrink();
    if (_loadingFriendship) return const SizedBox.shrink();

    if (ChatFriendshipService.isFriends(_friendStatus)) {
      return const SizedBox.shrink();
    }

    final bool canRequest = _canRequestFriendByPrivacy;
    final bool isRestricted = _isChatAccessRestricted;

    String title;
    String subtitle;
    IconData icon;
    Color badgeColor;

    if (_hasIncomingFriendRequest) {
      title = l10n.friendshipInfoIncoming ?? 'Friend request received';
      subtitle = l10n.friendshipCannotSendIncoming ?? 'Accept to start chatting.';
      icon = Icons.person_add_alt_1_rounded;
      badgeColor = Colors.amber;
    } else if (_hasOutgoingFriendRequest) {
      title = l10n.friendshipInfoOutgoing ?? 'Friend request sent';
      subtitle = l10n.friendshipCannotSendOutgoing ?? 'Waiting for acceptance.';
      icon = Icons.hourglass_top_rounded;
      badgeColor = Colors.white24;
    } else if (!canRequest) {
      title = l10n.friendRequestNotAllowed ?? 'Friend requests are off';
      subtitle = isRestricted
          ? (l10n.profilePrivateChatRestricted ??
          'This user’s profile is private. You must be friends to chat.')
          : (l10n.friendshipCannotSendNotFriends ?? 'You must be friends to chat.');
      icon = Icons.lock_rounded;
      badgeColor = Colors.white24;
    } else {
      title = l10n.friendshipInfoNotFriends ?? 'Not friends yet';
      subtitle = isRestricted
          ? (l10n.profilePrivateChatRestricted ??
          'This user’s profile is private. You must be friends to chat.')
          : (l10n.friendshipCannotSendNotFriends ?? 'Send a friend request to chat.');
      icon = Icons.person_add_alt_1_rounded;
      badgeColor = Colors.white24;
    }

    Widget actions() {
      if (_hasIncomingFriendRequest) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: _acceptIncomingRequest,
              icon: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
              label: Text(
                l10n.friendAcceptTooltip ?? 'Accept',
                style: const TextStyle(color: Colors.greenAccent),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: l10n.friendDeclineTooltip ?? 'Decline',
              onPressed: _declineOrCancelRequest,
              icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
            ),
          ],
        );
      }

      if (_hasOutgoingFriendRequest) {
        return TextButton(
          onPressed: _declineOrCancelRequest,
          child: Text(
            l10n.cancel ?? 'Cancel',
            style: const TextStyle(color: Colors.white70),
          ),
        );
      }

      if (!canRequest) return const SizedBox.shrink();

      return TextButton.icon(
        onPressed: _sendFriendRequestToOther,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: Text(
          l10n.addFriendTooltip ?? 'Add',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            actions(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomPanel(BuildContext context) {
    return MwEmojiPanel(
      onInsert: (insert) {
        final controller = _msgController;
        final text = controller.text;
        final sel = controller.selection;

        int start = sel.start >= 0 ? sel.start : text.length;
        int end = sel.end >= 0 ? sel.end : text.length;

        if (start > text.length) start = text.length;
        if (end > text.length) end = text.length;
        if (end < start) end = start;

        String prefix = '';
        String suffix = '';

        if (start > 0 && text[start - 1].trim().isNotEmpty) {
          prefix = ' ';
        }
        if (start < text.length && text[start].trim().isNotEmpty) {
          suffix = ' ';
        }

        final token = '$prefix$insert$suffix';
        final newText = text.replaceRange(start, end, token);

        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start + token.length),
        );

        _onComposerChanged(newText);
      },
    );
  }

  // ------------------------------------------------------------
  // ✅ Lifecycle
  // ------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    CurrentChatTracker.instance.enterRoom(widget.roomId);
    WidgetsBinding.instance.addObserver(this);

    final user = FirebaseAuth.instance.currentUser;
    _currentUserId = user?.uid ?? '';

    _voiceCtrl = vrc.VoiceRecorderController();

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      _scheduleMarkSeen();
      _measureComposerHeight();
    });

    unawaited(_resetMyUnread());

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
        unawaited(_resetMyUnread());
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

    CurrentChatTracker.instance.leaveRoom(widget.roomId);
    _hideReactionOverlay();

    WidgetsBinding.instance.removeObserver(this);

    _seenDebounce?.cancel();
    _typingDebounce?.cancel();

    unawaited(_updateMyTyping(false));
    unawaited(_updateMyRecording(false));

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
    _selectedMessageIds.clear();
    _selectedMessageDoc = null;
    _selectedIsMe = false;

    super.dispose();
  }

  // ------------------------------------------------------------
  // ✅ Subscriptions (same behavior as yours)
  // ------------------------------------------------------------
  Future<void> _primeOtherUserMetaOnce({bool force = false}) async {
    final otherId = _otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    if (_disposed) return;

    if (!force && _didPrimeOtherOnce) return;
    _didPrimeOtherOnce = true;

    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(otherId).get();
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
    } catch (_) {}
  }

  void _subscribeToMyMeta() {
    final me = _currentUserId;
    if (me.isEmpty) return;

    _myUserSub?.cancel();
    _myUserSub = FirebaseFirestore.instance.collection('users').doc(me).snapshots().listen((snap) {
      if (_disposed) return;
      final data = snap.data() ?? {};
      final parsed = _parseAvatarType(data['avatarType']);
      if (!mounted) return;

      if (parsed != _myAvatarType) {
        setState(() => _myAvatarType = parsed);
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

      _maybeScheduleMarkSeenFromSnapshot(snap);

      if (_hasSelection && _selectedMessageDoc != null) {
        final selectedId = _selectedMessageId;
        if (selectedId != null) {
          final idx = snap.docs.indexWhere((d) => d.id == selectedId);
          if (idx >= 0) {
            final freshDoc = snap.docs[idx];
            if (_isDeletedForEveryoneDoc(freshDoc)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _disposed) return;
                _clearSelection();
              });
            } else {
              _selectedMessageDoc = freshDoc;
            }
          }
        }
      }

      final visible = snap.docs.any((doc) {
        final data = doc.data();
        final hiddenFor = (data['hiddenFor'] as List?)?.cast<String>() ?? [];
        return !hiddenFor.contains(_currentUserId);
      });

      if (visible != _hasAnyMessages) {
        setState(() => _hasAnyMessages = visible);
      }
    });
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
    _blockSub = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().listen((snap) {
      if (_disposed) return;
      final data = snap.data() ?? {};
      final blockedListDynamic = (data['blockedUserIds'] as List<dynamic>?) ?? const [];
      final blockedList = blockedListDynamic.map((e) => e.toString()).toList();
      final isBlockedNow = blockedList.contains(_otherUserId);

      if (!mounted) return;
      setState(() {
        _isBlocked = isBlockedNow;
        _loadingBlockState = false;

        if (_isAnyBlock) _replyingTo = null;
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
    _otherUserSub = FirebaseFirestore.instance.collection('users').doc(otherId).snapshots().listen((snap) {
      if (_disposed) return;

      final data = snap.data() ?? {};
      final raw = data['blockedUserIds'] as List<dynamic>?;
      final blockedIds = (raw ?? const <dynamic>[]).map((e) => e.toString()).toList();
      final hasBlockedMeNow = blockedIds.contains(_currentUserId);

      final parsedGender = _parseGender(data['gender']);
      final parsedAvatarType = _parseAvatarType(data['avatarType']);

      final profileVis = _readOtherPrivacyValue(data, _fieldProfileVisibility);
      final addFriendVis = _readOtherPrivacyValue(data, _fieldAddFriendVisibility);

      if (!mounted) return;
      setState(() {
        _hasBlockedMe = hasBlockedMeNow;
        _loadingOtherBlockState = false;
        _otherUserGender = parsedGender;
        _otherUserAvatarType = parsedAvatarType;
        _otherProfileVisibility = profileVis;
        _otherAddFriendVisibility = addFriendVis;

        if (_isAnyBlock) _replyingTo = null;
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

    _friendSub = _friendshipService.friendshipStatusStream(me: me, other: other).listen(
          (status) {
        if (!mounted || _disposed) return;

        setState(() {
          _friendStatus = status;
          _loadingFriendship = false;

          if (!_canSendMessages) _replyingTo = null;
        });

        _scheduleMarkSeen();
      },
      onError: (_, __) {
        if (!mounted || _disposed) return;
        setState(() {
          _friendStatus = null;
          _loadingFriendship = false;
        });
      },
    );
  }

  // ------------------------------------------------------------
  // ✅ Build
  // ------------------------------------------------------------
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
        return l10n.friendRequestNotAllowed ?? 'This user is not accepting friend requests.';
      }

      return l10n.friendshipCannotSendNotFriends;
    }

    final bool canShowReplyUi = !_isAnyBlock && _canSendMessages;

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
      composerWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canShowReplyUi && _replyingTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: MessageReply(replyTo: _replyingTo!, onCancel: _clearReplyTo),
            ),
          ChatInputBar(
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

              if (!newVisible) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  await Future.delayed(const Duration(milliseconds: 50));
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

              if (_panelVisible && mounted && !_disposed) {
                setState(() => _panelVisible = false);
              }
              FocusManager.instance.primaryFocus?.unfocus();
            },
            onVoiceRecordStop: () {
              unawaited(_updateMyRecording(false));
            },
          ),
        ],
      );
    } else {
      if (_replyingTo != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _disposed) return;
          if (_replyingTo != null) setState(() => _replyingTo = null);
        });
      }

      composerWidget = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          cannotSendText(),
          textAlign: TextAlign.center,
          style: overlayInfoTextStyle,
        ),
      );
    }

    // ✅ keep list inset correct
    _measureComposerHeight();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: ChatAppBar(
        title: widget.title,
        currentUserId: _currentUserId,
        otherUserId: otherUserId,
        selectionMode: _hasSelection,
        selectedCount: _selectedMessageIds.length,
        onClearSelection: () {
          _hideReactionOverlay();
          _clearSelection();
        },
        onAudioCall: (!_isAnyBlock && _canSendMessages && otherUserId != null && otherUserId.isNotEmpty)
            ? () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CallScreen.outgoing(
                roomId: widget.roomId,
                callerId: _currentUserId,
                calleeId: otherUserId,
                video: false,
              ),
            ),
          );
        } : null,
        onCopySelected: _canCopySelected ? _onHeaderCopyPressed : null,
        onDeleteSelected: _canDeleteSelected ? _onHeaderDeletePressed : null,
        onReportSelected: _canReportSelected ? _onHeaderReportPressed : null,
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // ✅ FIX: always dismiss keyboard + emoji panel when tapping outside
          _dismissKeyboardAndPanel();
          _hideReactionOverlay();
          if (_hasSelection) _clearSelection();
        },
        child: MwBackground(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mq = MediaQuery.of(context);
              final keyboardInset = mq.viewInsets.bottom;
              final keyboardOpen = keyboardInset > 0;

              final showIndicator = !_isAnyBlock && (_isOtherTyping || _isOtherRecording);
              final showPanel = _panelVisible && !keyboardOpen;

              // Safe bottom ONLY when keyboard is closed.
              // When keyboard is open, it already defines the occluded area.
              final safeBottom = mq.padding.bottom;
              final effectiveSafeBottom = keyboardOpen ? 0.0 : safeBottom;

              // ✅ IMPORTANT: in manual mode we MUST include keyboardInset in listBottomInset,
              // otherwise messages will sit behind the keyboard + input bar.
              const double typingSlotHeight = 40.0;
              final double listBottomInset =
                  _composerAreaHeight +
                      (showPanel ? _panelHeight : 0.0) +
                      (!_isAnyBlock ? typingSlotHeight : 0.0) +
                      keyboardInset +
                      effectiveSafeBottom +
                      8.0;

              final bottomOverlay = Material(
                color: Colors.transparent,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  // ✅ lift the whole overlay above the keyboard
                  padding: EdgeInsets.only(bottom: keyboardInset),
                  child: Padding(
                    // ✅ apply safe bottom only when keyboard is closed
                    padding: EdgeInsets.only(bottom: keyboardOpen ? 0.0 : safeBottom),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isAnyBlock)
                          SizedBox(
                            height: 40,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: TypingIndicator(
                                key: ValueKey(
                                  'typing:${widget.roomId}:${_otherUserId ?? 'unknown'}:${_typingIndicatorMode.name}',
                                ),
                                isVisible: showIndicator,
                                text: _isOtherRecording
                                    ? '${widget.title} is recording...'
                                    : '${widget.title} is typing...',
                                gender: _typingIndicatorGender,
                                avatarType: _typingIndicatorAvatarType,
                                mode: _typingIndicatorMode,
                                height: 34,
                                showTopDivider: false,
                              ),
                            ),
                          ),

                        if (showPanel)
                          SizedBox(
                            height: _panelHeight,
                            child: _buildCustomPanel(context),
                          ),

                        KeyedSubtree(
                          key: _composerAreaKey,
                          child: composerWidget,
                        ),
                      ],
                    ),
                  ),
                ),
              );

              return Stack(
                children: [
                  Column(
                    children: [
                      _buildFriendshipBanner(l10n),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n is ScrollStartNotification || n is UserScrollNotification) {
                              if (MediaQuery.of(context).viewInsets.bottom > 0 || _panelVisible) {
                                _dismissKeyboardAndPanel();
                              }
                              _hideReactionOverlay();
                              if (_hasSelection) _clearSelection();
                            }
                            return false;
                          },
                          child: _isLoadingBlock
                              ? const Center(child: CircularProgressIndicator())
                              : ChatMessageList(
                            key: _listKey,
                            roomId: widget.roomId,
                            currentUserId: _currentUserId,
                            otherUserId: otherUserId,
                            isBlocked: _isAnyBlock,
                            bottomInset: listBottomInset, // ✅ includes keyboardInset
                            onReply: _setReplyTo,
                            onReactionTapAsync: _onReactionTapAsync,
                            selectedMessageId: _selectedMessageId,
                            selectedMessageIds: _selectedMessageIds,
                            onMessageTap: () {
                              _dismissKeyboardAndPanel();
                              _hideReactionOverlay();
                              if (_hasSelection) _clearSelection();
                            },
                            onMessageLongPress: (doc, isMe) async {
                              if (!mounted || _disposed) return;
                              await _hapticLight();
                              _toggleSingleSelection(doc, isMe);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(left: 0, right: 0, bottom: 0, child: bottomOverlay),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ✅ Helpers
  // ------------------------------------------------------------
  void _dismissKeyboardAndPanel() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_panelVisible) {
      if (!mounted || _disposed) return;
      setState(() => _panelVisible = false);
    }
  }

  void _closeEmojiPanelIfOpen() {
    if (_panelVisible) {
      if (!mounted || _disposed) return;
      setState(() => _panelVisible = false);
    }
  }
}

extension _FirstOrNullExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
