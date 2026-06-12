import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/group_chat_service.dart';

class CreateGroupController extends ChangeNotifier {
  CreateGroupController({
    required GroupChatService groupChatService,
    required String currentUserId,
  })  : _groupChatService = groupChatService,
        _currentUserId = currentUserId;

  final GroupChatService _groupChatService;
  final String _currentUserId;

  final List<GroupSelectableUser> _selectedUsers = <GroupSelectableUser>[];

  File? _pickedImage;
  Uint8List? _pickedImageBytes;
  String? _pickedImageFileName;
  bool _isCreating = false;
  String _groupName = '';

  List<GroupSelectableUser> get selectedUsers =>
      List<GroupSelectableUser>.unmodifiable(_selectedUsers);

  File? get pickedImage => _pickedImage;
  Uint8List? get pickedImageBytes => _pickedImageBytes;
  String? get pickedImageFileName => _pickedImageFileName;
  bool get isCreating => _isCreating;
  String get groupName => _groupName;

  bool get canContinueFromMembers => _selectedUsers.length >= 2;

  bool get canCreateGroup {
    return _groupName.trim().isNotEmpty &&
        _selectedUsers.length >= 2 &&
        !_isCreating;
  }

  void setGroupName(String value) {
    final next = value.trimLeft();
    if (_groupName == next) return;
    _groupName = next;
    notifyListeners();
  }

  void toggleUser(GroupSelectableUser user) {
    final index = _selectedUsers.indexWhere((e) => e.id == user.id);

    if (index >= 0) {
      _selectedUsers.removeAt(index);
    } else {
      _selectedUsers.add(user);
    }

    notifyListeners();
  }

  bool isSelected(String userId) {
    return _selectedUsers.any((e) => e.id == userId);
  }

  void removeSelectedUser(String userId) {
    final oldLength = _selectedUsers.length;
    _selectedUsers.removeWhere((e) => e.id == userId);

    if (_selectedUsers.length != oldLength) {
      notifyListeners();
    }
  }

  void setPickedImage({
    File? file,
    Uint8List? bytes,
    String? fileName,
  }) {
    final samePath = _pickedImage?.path == file?.path;
    final sameFileName = _pickedImageFileName == fileName;
    final sameBytes = identical(_pickedImageBytes, bytes);

    if (samePath && sameFileName && sameBytes) return;

    _pickedImage = file;
    _pickedImageBytes = bytes;
    _pickedImageFileName = fileName;
    notifyListeners();
  }

  void clearPickedImage() {
    _pickedImage = null;
    _pickedImageBytes = null;
    _pickedImageFileName = null;
    notifyListeners();
  }

  void reset() {
    _selectedUsers.clear();
    _pickedImage = null;
    _pickedImageBytes = null;
    _pickedImageFileName = null;
    _isCreating = false;
    _groupName = '';
    notifyListeners();
  }

  Future<String> createGroup() async {
    if (!canCreateGroup) {
      throw Exception('Group name and at least 2 members are required.');
    }

    if (_currentUserId.trim().isEmpty) {
      throw Exception('Current user is missing.');
    }

    _isCreating = true;
    notifyListeners();

    try {
      final memberIds = <String>{
        _currentUserId,
        ..._selectedUsers.map((e) => e.id.trim()).where((e) => e.isNotEmpty),
      }.toList();

      final roomId = await _groupChatService.createGroup(
        currentUserId: _currentUserId,
        name: _groupName.trim(),
        memberIds: memberIds,
        imageFile: _pickedImage,
        imageBytes: _pickedImageBytes,
        imageFileName: _pickedImageFileName,
      );

      return roomId;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }
}

class GroupSelectableUser {
  final String id;
  final String displayName;
  final String? photoUrl;

  const GroupSelectableUser({
    required this.id,
    required this.displayName,
    this.photoUrl,
  });

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}