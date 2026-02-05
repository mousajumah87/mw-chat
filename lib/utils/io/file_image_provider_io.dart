import 'dart:io';
import 'package:flutter/painting.dart';

ImageProvider? fileImageProvider(String path) {
  final p = path.trim();
  if (p.isEmpty) return null;
  return FileImage(File(p));
}
