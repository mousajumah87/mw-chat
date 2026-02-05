import 'dart:typed_data';
import 'package:flutter/material.dart';

class WebVideoPreviewDialog extends StatelessWidget {
  final Uint8List bytes;
  const WebVideoPreviewDialog({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Web video preview is not supported on this platform.'),
      ),
    );
  }
}
