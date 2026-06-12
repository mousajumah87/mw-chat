// lib/features/group/screens/group_chat_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../widgets/chat/message_bubble.dart';
import '../../../widgets/chat/message_reactions.dart';
import '../../../widgets/chat/message_reply.dart';
import '../../../widgets/chat/mw_emoji_panel.dart';
import '../../../widgets/chat/mw_reply_to.dart';
import '../../../widgets/chat/typing_indicator.dart';
import '../models/chat_message_model.dart';
import '../models/chat_room_model.dart';
import '../services/group_chat_service.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.roomId,
  });

  final String roomId;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUpdatingGroupPhoto = false;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _roomStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;

  int _lastVisibleMessageCount = 0;
  bool _pendingAutoScroll = false;
  bool _didInitialScroll = false;

  bool _isSending = false;
  bool _isLeaving = false;
  bool _panelVisible = false;

  MwReplyTo? _replyingTo;

  String? _selectedMessageId;
  ChatMessageModel? _selectedMessage;
  DocumentSnapshot<Map<String, dynamic>>? _selectedMessageDoc;
  bool _selectedIsMe = false;

  static const double _panelHeight = 300.0;

  bool get _hasSelection => _selectedMessageId != null;

  final Map<String, String> _typingNames = <String, String>{};

  bool _isSomeoneTyping = false;
  String _typingText = '';

  final Map<String, String> _memberAvatarTypes = <String, String>{};

  bool _isMeTyping = false;
  static const Duration _typingDebounceDuration = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _roomStream = _groupChatService.watchRoom(widget.roomId);
    _messagesStream = _groupChatService.watchMessages(widget.roomId);

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _messageController.text.trim().isEmpty) {
        _stopMyTypingNow();
      }
    });
  }


  @override
  void dispose() {
    _stopMyTypingNow();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _loadCurrentUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    return userSnap.data();
  }

  String _normalizeAvatarType(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return 'bear';
    return value;
  }

  Future<void> _setMyTyping(bool isTyping) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.roomId)
          .set(
        {
          'typingMembers.${currentUser.uid}': isTyping,
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  void _onComposerChanged(String value) {
    if (_isSending) return;

    final hasText = value.trim().isNotEmpty;

    if (hasText && !_isMeTyping) {
      _isMeTyping = true;
      _setMyTyping(true);
    }

    _scheduleTypingStop();
  }

  void _scheduleTypingStop() {
    Future<void>.delayed(_typingDebounceDuration, () async {
      if (!mounted) return;

      final textStillTyping = _messageController.text.trim().isNotEmpty;
      if (textStillTyping && _focusNode.hasFocus) {
        return;
      }

      if (_isMeTyping) {
        _isMeTyping = false;
        await _setMyTyping(false);
      }
    });
  }

  Future<void> _stopMyTypingNow() async {
    if (!_isMeTyping) return;
    _isMeTyping = false;
    await _setMyTyping(false);
  }

  Future<Map<String, dynamic>?> _loadUserBrief(String userId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      return snap.data();
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshTypingState(Map<String, dynamic> roomData) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final typingRaw = roomData['typingMembers'];
    final typingMap = typingRaw is Map
        ? Map<String, dynamic>.from(typingRaw as Map)
        : <String, dynamic>{};

    final activeOtherIds = typingMap.entries
        .where((e) =>
    e.key != currentUser.uid &&
        e.value == true)
        .map((e) => e.key)
        .toList();

    if (activeOtherIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isSomeoneTyping = false;
        _typingText = '';
      });
      return;
    }

    for (final uid in activeOtherIds) {
      if (!_typingNames.containsKey(uid)) {
        final data = await _loadUserBrief(uid);
        final firstName = (data?['firstName'] ?? '').toString().trim();
        final lastName = (data?['lastName'] ?? '').toString().trim();
        final email = (data?['email'] ?? '').toString().trim();
        final avatarType = _normalizeAvatarType(data?['avatarType']);

        final fullName = [firstName, lastName]
            .where((e) => e.isNotEmpty)
            .join(' ')
            .trim();

        _typingNames[uid] = fullName.isNotEmpty
            ? fullName
            : (email.isNotEmpty ? email : 'Someone');

        _memberAvatarTypes[uid] = avatarType;
      }
    }

    final names = activeOtherIds
        .map((id) => _typingNames[id] ?? 'Someone')
        .toList();

    String text;
    if (names.length == 1) {
      text = '${names.first} is typing...';
    } else if (names.length == 2) {
      text = '${names[0]} and ${names[1]} are typing...';
    } else {
      text = '${names[0]}, ${names[1]} and others are typing...';
    }

    if (!mounted) return;
    setState(() {
      _isSomeoneTyping = true;
      _typingText = text;
    });
  }

  String? _typingAvatarTypeFromCurrentState() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return 'bear';

    for (final entry in _typingNames.entries) {
      if (entry.key == currentUser.uid) continue;
      return _memberAvatarTypes[entry.key] ?? 'bear';
    }

    return 'bear';
  }

  Future<List<_GroupUserInfo>> _loadUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    final futures = userIds.map((id) async {
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(id).get();
      final data = snap.data();

      final firstName = (data?['firstName'] ?? '').toString().trim();
      final lastName = (data?['lastName'] ?? '').toString().trim();
      final email = (data?['email'] ?? '').toString().trim();
      final profileUrl = (data?['profileUrl'] ?? '').toString().trim();

      final fullName = [firstName, lastName]
          .where((e) => e.isNotEmpty)
          .join(' ')
          .trim();

      return _GroupUserInfo(
        id: id,
        name: fullName.isNotEmpty
            ? fullName
            : (email.isNotEmpty ? email : 'Unknown User'),
        email: email,
        profileUrl: profileUrl.isEmpty ? null : profileUrl,
      );
    });

    return Future.wait(futures);
  }

  String _buildDisplayName(Map<String, dynamic>? data, User currentUser) {
    if (data == null) {
      return currentUser.email ?? 'Unknown User';
    }

    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();

    final fullName = [firstName, lastName]
        .where((e) => e.isNotEmpty)
        .join(' ')
        .trim();

    if (fullName.isNotEmpty) return fullName;
    if (email.isNotEmpty) return email;
    return currentUser.email ?? 'Unknown User';
  }

  Future<void> _changeGroupPhoto(ChatRoomModel room) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    if (!room.memberIds.contains(currentUser.uid)) return;
    if (_isUpdatingGroupPhoto) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1400,
      );

      if (picked == null) return;

      if (!mounted) return;
      setState(() {
        _isUpdatingGroupPhoto = true;
      });

      final userData = await _loadCurrentUserData();
      final displayName = _buildDisplayName(userData, currentUser);
      final imageName = picked.name.trim().isNotEmpty
          ? picked.name.trim()
          : picked.path.split('/').last;

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();

        await _groupChatService.updateGroupPhoto(
          roomId: room.id,
          userId: currentUser.uid,
          userName: displayName,
          imageBytes: bytes,
          imageFileName: imageName,
        );
      } else {
        final file = File(picked.path);

        await _groupChatService.updateGroupPhoto(
          roomId: room.id,
          userId: currentUser.uid,
          userName: displayName,
          imageFile: file,
          imageFileName: imageName,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update group photo: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isUpdatingGroupPhoto = false;
      });
    }
  }

  Widget _buildGroupAvatar(
      ChatRoomModel room, {
        double radius = 22,
        bool showEditBadge = false,
      }) {
    final photoUrl = (room.photoUrl ?? '').trim();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty
              ? Text(
            _initials(
              room.name?.trim().isNotEmpty == true ? room.name! : 'Group',
            ),
          )
              : null,
        ),
        if (showEditBadge)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: radius * 0.7,
              height: radius * 0.7,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                size: radius * 0.32,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGroupHeaderAvatar(
      ChatRoomModel room, {
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: _buildGroupAvatar(
          room,
          radius: 42,
          showEditBadge: true,
        ),
      ),
    );
  }

  Map<String, dynamic>? _replyToPayloadOrNull(MwReplyTo? r) {
    if (r == null) return null;

    Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(r.toMap());
    } catch (_) {
      return null;
    }

    final rawPreview =
    (map['previewText'] ?? map['text'] ?? map['message'] ?? '')
        .toString()
        .trim();
    final rawMessageId = (map['messageId'] ?? map['id'] ?? '')
        .toString()
        .trim();
    final rawSenderId = (map['senderId'] ?? map['fromId'] ?? '')
        .toString()
        .trim();

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

  void _setReplyToFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final type = (data['type'] ?? 'text').toString().trim();

    final reply = MwReplyTo.fromMessageDoc(
      doc: doc,
      fallbackType: type.isEmpty ? 'text' : type,
    );

    if (reply == null) return;

    setState(() {
      _replyingTo = reply;
      _clearSelectionInternal();
      _panelVisible = false;
    });

    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  void _clearReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  Future<void> _sendMessage() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    _pendingAutoScroll = true;

    try {
      await _stopMyTypingNow();

      final userData = await _loadCurrentUserData();
      final senderName = _buildDisplayName(userData, currentUser);
      final senderPhotoUrl =
      (userData?['profileUrl'] ?? '').toString().trim().isNotEmpty
          ? (userData!['profileUrl'] as String).trim()
          : null;

      await _groupChatService.sendTextMessage(
        roomId: widget.roomId,
        senderId: currentUser.uid,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        text: text,
        replyTo: _replyToPayloadOrNull(_replyingTo),
      );

      _messageController.clear();

      if (!mounted) return;

      setState(() {
        _replyingTo = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
      });
    } catch (e) {
      _pendingAutoScroll = false;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _onReactionTapAsync(String messageId, String emoji) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final mid = messageId.trim();
    final e = emoji.trim();
    if (mid.isEmpty || e.isEmpty) return;

    final msgRef = FirebaseFirestore.instance
        .collection('groupChats')
        .doc(widget.roomId)
        .collection('messages')
        .doc(mid);

    try {
      await MwReactions.setSingleReaction(
        messageRef: msgRef,
        userId: currentUser.uid,
        emoji: e,
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to react: $err')),
      );
    }
  }

  void _scheduleScrollIfNeeded(
      List<ChatMessageModel> messages,
      User currentUser,
      ) {
    final visibleCount = messages.length;

    if (!_didInitialScroll) {
      _didInitialScroll = true;
      _lastVisibleMessageCount = visibleCount;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
      return;
    }

    if (visibleCount == _lastVisibleMessageCount) return;

    final addedNewMessage = visibleCount > _lastVisibleMessageCount;
    _lastVisibleMessageCount = visibleCount;

    if (!addedNewMessage) return;

    final shouldScroll = _pendingAutoScroll ||
        (messages.isNotEmpty && messages.last.senderId == currentUser.uid);

    if (!shouldScroll) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom(animated: true);
    });

    _pendingAutoScroll = false;
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;

    final target = _scrollController.position.maxScrollExtent;

    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _dismissKeyboardAndSelection() {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_panelVisible) {
      setState(() {
        _panelVisible = false;
      });
    }

    if (_selectedMessage != null) {
      _clearSelection();
    }
  }

  void _selectMessage(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ChatMessageModel message,
      bool isMe,
      ) {
    final data = doc.data() ?? const <String, dynamic>{};
    if (data['deletedForEveryone'] == true) return;

    setState(() {
      _selectedMessageId = message.id;
      _selectedMessage = message;
      _selectedMessageDoc = doc;
      _selectedIsMe = isMe;
      _replyingTo = null;
    });
  }

  void _clearSelectionInternal() {
    _selectedMessageId = null;
    _selectedMessage = null;
    _selectedMessageDoc = null;
    _selectedIsMe = false;
  }

  void _clearSelection() {
    setState(_clearSelectionInternal);
  }

  Widget _buildCustomPanel(BuildContext context) {
    return MwEmojiPanel(
      onInsert: (insert) {
        final controller = _messageController;
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

  Future<void> _copySelectedMessage() async {
    final text = (_selectedMessage?.text ?? '').trim();
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied')),
    );

    _clearSelection();
  }

  Future<void> _deleteSelectedMessage() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final selected = _selectedMessage;

    if (currentUser == null || selected == null) return;

    final canDeleteForEveryone = _selectedIsMe;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete message'),
          content: const Text('Choose how you want to delete this message.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('me'),
              child: const Text('Delete for me'),
            ),
            if (canDeleteForEveryone)
              TextButton(
                onPressed: () => Navigator.of(context).pop('everyone'),
                child: const Text(
                  'Delete for everyone',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        );
      },
    );

    if (choice == null) return;

    try {
      if (choice == 'me') {
        await _groupChatService.deleteMessageForMe(
          roomId: widget.roomId,
          messageId: selected.id,
          userId: currentUser.uid,
        );
      } else if (choice == 'everyone') {
        await _groupChatService.deleteMessageForEveryone(
          roomId: widget.roomId,
          messageId: selected.id,
          deletedBy: currentUser.uid,
        );
      }

      if (!mounted) return;
      _clearSelection();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete message: $e')),
      );
    }
  }

  Future<void> _confirmLeaveGroup(
      ChatRoomModel room,
      String currentUserId,
      ) async {
    if (_isLeaving) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Leave group'),
          content: Text(
            'Are you sure you want to leave "${room.name ?? 'this group'}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Leave',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    setState(() {
      _isLeaving = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final userData = await _loadCurrentUserData();
      final displayName = currentUser == null
          ? 'A member'
          : _buildDisplayName(userData, currentUser);

      await _groupChatService.leaveGroup(
        roomId: widget.roomId,
        userId: currentUserId,
        userName: displayName,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to leave group: $e')),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isLeaving = false;
      });
    }
  }

  Future<void> _openGroupInfo(ChatRoomModel room) async {
    final adminIds = room.adminIds.isNotEmpty
        ? room.adminIds
        : (room.createdBy != null ? [room.createdBy!] : <String>[]);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            Future<void> handleChangePhoto() async {
              if (_isUpdatingGroupPhoto) return;

              sheetSetState(() {});
              await _changeGroupPhoto(room);
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            }

            return FutureBuilder<List<_GroupUserInfo>>(
              future: _loadUsersByIds(room.memberIds),
              builder: (context, snapshot) {
                final members = snapshot.data ?? [];
                final admins = members
                    .where((m) => adminIds.contains(m.id))
                    .toList(growable: false);

                _GroupUserInfo? createdByUser;
                if (room.createdBy != null) {
                  for (final member in members) {
                    if (member.id == room.createdBy) {
                      createdByUser = member;
                      break;
                    }
                  }
                }

                return FractionallySizedBox(
                  heightFactor: 0.90,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withAlpha(102),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                room.name?.trim().isNotEmpty == true
                                    ? room.name!
                                    : 'Group Info',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            Center(
                              child: Column(
                                children: [
                                  _buildGroupHeaderAvatar(
                                    room,
                                    onTap: handleChangePhoto,
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed:
                                    _isUpdatingGroupPhoto ? null : handleChangePhoto,
                                    icon: _isUpdatingGroupPhoto
                                        ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                        : const Icon(Icons.camera_alt_rounded),
                                    label: const Text('Change group photo'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _InfoTile(
                              icon: Icons.group_rounded,
                              title: 'Members',
                              subtitle: '${room.memberIds.length} members',
                            ),
                            if (room.createdAt != null)
                              _InfoTile(
                                icon: Icons.calendar_today_rounded,
                                title: 'Created',
                                subtitle: _formatFullDate(room.createdAt),
                              ),
                            if (createdByUser != null)
                              _InfoTile(
                                icon: Icons.person_add_alt_1_rounded,
                                title: 'Created by',
                                subtitle: createdByUser.name,
                              ),
                            if (admins.isNotEmpty)
                              _InfoTile(
                                icon: Icons.shield_rounded,
                                title: 'Admins',
                                subtitle: admins.map((e) => e.name).join(', '),
                              ),
                            const SizedBox(height: 18),
                            Text(
                              'Members',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            if (snapshot.connectionState == ConnectionState.waiting)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (members.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text('No members found.'),
                              )
                            else
                              ...members.map(
                                    (member) => _MemberTile(
                                  member: member,
                                  isAdmin: adminIds.contains(member.id),
                                  isCreator: room.createdBy == member.id,
                                ),
                              ),
                            const SizedBox(height: 24),
                            OutlinedButton.icon(
                              onPressed: _isLeaving
                                  ? null
                                  : () {
                                Navigator.of(context).pop();
                                final currentUser =
                                    FirebaseAuth.instance.currentUser;
                                if (currentUser != null) {
                                  _confirmLeaveGroup(room, currentUser.uid);
                                }
                              },
                              icon: const Icon(
                                Icons.exit_to_app_rounded,
                                color: Colors.red,
                              ),
                              label: const Text(
                                'Leave group',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar({
    required ChatRoomModel room,
    required String currentUserId,
  }) {
    final isSelectionMode = _selectedMessage != null;

    if (isSelectionMode) {
      return AppBar(
        title: const Text('1 selected'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _clearSelection,
        ),
        actions: [
          if ((_selectedMessage?.text ?? '').trim().isNotEmpty)
            IconButton(
              tooltip: 'Copy',
              onPressed: _copySelectedMessage,
              icon: const Icon(Icons.copy_rounded),
            ),
          IconButton(
            tooltip: 'Reply',
            onPressed: () {
              final doc = _selectedMessageDoc;
              if (doc == null) return;
              _setReplyToFromDoc(doc);
            },
            icon: const Icon(Icons.reply_rounded),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _deleteSelectedMessage,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      );
    }

    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openGroupInfo(room),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              _buildGroupAvatar(room, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name?.trim().isNotEmpty == true
                          ? room.name!
                          : 'Group Chat',
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${room.memberIds.length} members',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Group info',
          onPressed: () => _openGroupInfo(room),
          icon: const Icon(Icons.info_outline_rounded),
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'info') {
              _openGroupInfo(room);
            } else if (value == 'photo') {
              _changeGroupPhoto(room);
            } else if (value == 'leave') {
              _confirmLeaveGroup(room, currentUserId);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem<String>(
              value: 'info',
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded),
                  SizedBox(width: 10),
                  Text('Group info'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'photo',
              child: Row(
                children: [
                  Icon(Icons.camera_alt_rounded),
                  SizedBox(width: 10),
                  Text('Change group photo'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'leave',
              child: Row(
                children: [
                  Icon(Icons.exit_to_app_rounded, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Leave group'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComposer(bool hasLeftGroup) {
    if (hasLeftGroup) {
      return const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Text(
            'You left this group.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: MessageReply(
                replyTo: _replyingTo!,
                onCancel: _clearReply,
              ),
            ),
          if (_panelVisible && MediaQuery.of(context).viewInsets.bottom <= 0)
            SizedBox(
              height: _panelHeight,
              child: _buildCustomPanel(context),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attachments',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Group attachments are not wired yet in this screen.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  IconButton(
                    tooltip: 'Emoji',
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() {
                        _panelVisible = !_panelVisible;
                      });
                    },
                    icon: Icon(
                      _panelVisible
                          ? Icons.keyboard_rounded
                          : Icons.emoji_emotions_outlined,
                    ),
                  ),
                  Expanded(
                    child: Focus(
                      autofocus: false,
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }

                        final isEnter =
                            event.logicalKey == LogicalKeyboardKey.enter;
                        final isShiftPressed =
                            HardwareKeyboard.instance.isShiftPressed;

                        if (isEnter && !isShiftPressed) {
                          if (_messageController.text.trim().isNotEmpty &&
                              !_isSending) {
                            _sendMessage();
                            return KeyEventResult.handled;
                          }
                        }

                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        enabled: !_isSending,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        minLines: 1,
                        maxLines: 5,
                        onChanged: _onComposerChanged,
                        onTap: () {
                          if (_selectedMessage != null) {
                            _clearSelection();
                          }
                          if (_panelVisible) {
                            setState(() {
                              _panelVisible = false;
                            });
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: 'Type a message',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 44,
                    width: 44,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: _isSending
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                        CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSenderHeader(ChatMessageModel message) {
    final senderPhotoUrl = (message.senderPhotoUrl ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundImage:
            senderPhotoUrl.isNotEmpty ? NetworkImage(senderPhotoUrl) : null,
            child: senderPhotoUrl.isEmpty
                ? Text(
              _initials(message.senderName),
              style: const TextStyle(fontSize: 11),
            )
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.senderName,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTile(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ChatMessageModel message,
      User currentUser,
      ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final isMe = message.senderId == currentUser.uid;
    final isSelected = _selectedMessageId == message.id;
    final isSystem = message.type.trim() == 'system';

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withAlpha(153),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              message.text ?? '',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final reactions = data[MwReactions.fieldReactions] is Map
        ? Map<String, dynamic>.from(data[MwReactions.fieldReactions] as Map)
        : (data['reactions'] is Map
        ? Map<String, dynamic>.from(data['reactions'] as Map)
        : null);

    final bubble = MessageBubble(
      key: ValueKey('group_${message.id}'),
      messageId: message.id,
      text: message.text ?? '',
      timeLabel: _formatTime(message.createdAt),
      isMe: isMe,
      isSeen: false,
      fileUrl: (data['fileUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (data['fileUrl'] as String),
      fileName: (data['fileName'] ?? '').toString().trim().isEmpty
          ? null
          : (data['fileName'] as String),
      fileType: (data['fileType'] ?? '').toString().trim().isEmpty
          ? null
          : (data['fileType'] as String),
      thumbUrl: (data['thumbUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (data['thumbUrl'] as String),
      thumbnailUrl: (data['thumbnailUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (data['thumbnailUrl'] as String),
      videoThumbUrl: (data['videoThumbUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (data['videoThumbUrl'] as String),
      callInfo: data['callInfo'] is Map
          ? Map<String, dynamic>.from(data['callInfo'] as Map)
          : null,
      replyTo: data['replyTo'] ?? message.replyTo,
      currentUserId: currentUser.uid,
      reactions: reactions,
      onReactionTapAsync: (emoji) => _onReactionTapAsync(message.id, emoji),
      onReactionCommitted: _clearSelection,
      onReplyPreviewTap: null,
      isSelected: isSelected,
      onBubbleLongPress: () => _selectMessage(doc, message, isMe),
      onBubbleTap: () {
        if (_hasSelection) {
          _clearSelection();
        } else {
          _dismissKeyboardAndSelection();
        }
      },
      onSwipeReply: () => _setReplyToFromDoc(doc),
      disableSwipeReply: _hasSelection,
      isDeleted: data['deletedForEveryone'] == true,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment:
        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe) _buildSenderHeader(message),
          bubble,
        ],
      ),
    );
  }

  Widget _buildMessagesArea(
      List<DocumentSnapshot<Map<String, dynamic>>> docs,
      List<ChatMessageModel> messages,
      User currentUser,
      ) {
    if (messages.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissKeyboardAndSelection,
        child: const Center(
          child: Text('No messages yet. Start the conversation.'),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissKeyboardAndSelection,
      child: ListView.builder(
        key: const PageStorageKey<String>('group_chat_messages'),
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          return _buildMessageTile(docs[index], messages[index], currentUser);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('No signed-in user found.'),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _roomStream,
      builder: (context, roomSnapshot) {
        if (roomSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (roomSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Group Chat')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load group: ${roomSnapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (!roomSnapshot.hasData || !roomSnapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Group Chat')),
            body: const Center(
              child: Text('Group not found.'),
            ),
          );
        }

        final roomData = roomSnapshot.data!.data() ?? {};
        final room = ChatRoomModel.fromMap(roomSnapshot.data!.id, roomData);
        final hasLeftGroup = !room.memberIds.contains(currentUser.uid);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _refreshTypingState(roomData);
        });

        return Scaffold(
          appBar: _buildAppBar(
            room: room,
            currentUserId: currentUser.uid,
          ),
          resizeToAvoidBottomInset: true,
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, messageSnapshot) {
                    if (messageSnapshot.connectionState ==
                        ConnectionState.waiting &&
                        !(messageSnapshot.hasData &&
                            messageSnapshot.data!.docs.isNotEmpty)) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (messageSnapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Failed to load messages: ${messageSnapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final docs = messageSnapshot.data?.docs ?? [];

                    final visibleDocs =
                    docs.where((doc) {
                      final data = doc.data();
                      final hiddenFor =
                          (data['hiddenFor'] as List?)?.cast<String>() ??
                              const <String>[];
                      return !hiddenFor.contains(currentUser.uid);
                    }).toList();

                    final messages = visibleDocs
                        .map((doc) =>
                        ChatMessageModel.fromMap(doc.id, doc.data()))
                        .toList();

                    _scheduleScrollIfNeeded(messages, currentUser);

                    return _buildMessagesArea(
                      visibleDocs,
                      messages,
                      currentUser,
                    );
                  },
                ),
              ),
              if (!hasLeftGroup)
                TypingIndicator(
                  isVisible: _isSomeoneTyping,
                  text: _typingText,
                  avatarType: _typingAvatarTypeFromCurrentState(),
                  mode: ChatActivityIndicatorMode.typing,
                  height: 34,
                  showTopDivider: false,
                ),
              _buildComposer(hasLeftGroup),
            ],
          ),
        );
      },
    );
  }

  static String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';

    final hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $suffix';
  }

  static String _formatFullDate(DateTime? value) {
    if (value == null) return 'Unknown';

    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final month = monthNames[value.month - 1];
    final day = value.day;
    final year = value.year;
    final hour = value.hour > 12
        ? value.hour - 12
        : (value.hour == 0 ? 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';

    return '$month $day, $year • $hour:$minute $suffix';
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isAdmin,
    required this.isCreator,
  });

  final _GroupUserInfo member;
  final bool isAdmin;
  final bool isCreator;

  @override
  Widget build(BuildContext context) {
    final badges = <String>[
      if (isCreator) 'creator',
      if (isAdmin) 'admin',
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundImage:
        member.profileUrl != null ? NetworkImage(member.profileUrl!) : null,
        child: member.profileUrl == null ? Text(_initials(member.name)) : null,
      ),
      title: Text(member.name),
      subtitle: member.email.isNotEmpty ? Text(member.email) : null,
      trailing: badges.isEmpty
          ? null
          : Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          badges.join(' • '),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _GroupUserInfo {
  const _GroupUserInfo({
    required this.id,
    required this.name,
    required this.email,
    required this.profileUrl,
  });

  final String id;
  final String name;
  final String email;
  final String? profileUrl;
}