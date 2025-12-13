import 'package:flutter/foundation.dart';

/// Tracks which chat room is currently open in the UI.
/// If `activeRoomId` is null, user is not inside any specific chat screen.
class CurrentChatTracker extends ChangeNotifier {
  CurrentChatTracker._internal();
  static final CurrentChatTracker instance = CurrentChatTracker._internal();

  String? _activeRoomId;

  String? get activeRoomId => _activeRoomId;

  bool get isInChat => _activeRoomId != null;

  /// Call this when user enters a chat room (opens chat screen)
  void enterRoom(String roomId) {
    if (_activeRoomId == roomId) return;
    _activeRoomId = roomId;
    notifyListeners();
  }

  /// Call this when user leaves a chat room (pops the chat screen)
  void leaveRoom() {
    if (_activeRoomId == null) return;
    _activeRoomId = null;
    notifyListeners();
  }
}
