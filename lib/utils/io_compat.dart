// lib/utils/io_compat.dart
//
// Web-safe wrapper around file operations.
// On Web: functions do nothing.
// On Mobile/Desktop: uses dart:io.

import 'io_compat_stub.dart'
if (dart.library.io) 'io_compat_io.dart' as impl;

Future<void> writeFileBytes(String path, List<int> bytes) =>
    impl.writeFileBytes(path, bytes);

Future<void> deleteFileIfExists(String path) => impl.deleteFileIfExists(path);
