import 'dart:async';
import 'package:flutter/foundation.dart';

/// Tracks which chat room is currently open in the UI.
/// If `activeRoomId` is null, user is not inside any specific chat screen.
class CurrentChatTracker extends ChangeNotifier {
  CurrentChatTracker._internal();
  static final CurrentChatTracker instance = CurrentChatTracker._internal();

  String? _activeRoomId;

  String? get activeRoomId => _activeRoomId;

  bool get isInChat => (_activeRoomId ?? '').isNotEmpty;

  void enterRoom(String roomId) {
    final id = roomId.trim();
    if (id.isEmpty) return;

    if (_activeRoomId == id) return;

    _activeRoomId = id;
    _dbg('➡️ enterRoom: $id');
    _safeNotify();
  }

  /// Leave ONLY if the caller is leaving the currently active room.
  /// This prevents clearing when switching quickly between chats.
  void leaveRoom(String roomId) {
    final id = roomId.trim();
    if (id.isEmpty) return;

    if (_activeRoomId != id) {
      _dbg('⚠️ leaveRoom ignored (active=$_activeRoomId, leaving=$id)');
      return;
    }

    _activeRoomId = null;
    _dbg('⬅️ leaveRoom: $id');
    _safeNotify();
  }

  /// Force-clear (rare). Use only on logout / global reset.
  void clear() {
    if (_activeRoomId == null) return;
    _dbg('🧹 clear: $_activeRoomId');
    _activeRoomId = null;
    _safeNotify();
  }

  void _safeNotify() {
    Future.microtask(() {
      if (hasListeners) notifyListeners();
    });
  }

  void _dbg(String msg) {
    if (kDebugMode) debugPrint('CurrentChatTracker $msg');
  }
}
