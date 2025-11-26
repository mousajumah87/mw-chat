// lib/utils/chat_utils.dart

/// Build consistent roomId between two users.
/// Ensures same roomId regardless of order.
String buildRoomId(String uid1, String uid2) {
  final ids = [uid1, uid2]..sort(); // sort alphabetically
  return ids.join('_');
}

/// Returns field name for unread counter in room doc
String unreadFieldForUser(String uid) => 'unreadCounts.$uid';

/// Returns typing flag key name
String typingFieldForUser(String uid) => 'typing_$uid';
