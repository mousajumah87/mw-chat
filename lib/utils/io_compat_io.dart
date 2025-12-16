// lib/utils/io_compat_io.dart
// Used on platforms that support dart:io (Android/iOS/macOS/Windows/Linux)

import 'dart:io';

Future<void> writeFileBytes(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<void> deleteFileIfExists(String path) async {
  final f = File(path);
  if (await f.exists()) {
    await f.delete();
  }
}
