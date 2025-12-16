// lib/utils/io_compat_stub.dart
// Used on Web (no dart:io)

Future<void> writeFileBytes(String path, List<int> bytes) async {
  // no-op on web
}

Future<void> deleteFileIfExists(String path) async {
  // no-op on web
}
