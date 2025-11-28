import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

class AuthAvatarPicker extends StatefulWidget {
  final Uint8List? imageBytes;
  final File? imageFile;
  final bool isSubmitting;
  final VoidCallback onPickImage;

  const AuthAvatarPicker({
    super.key,
    required this.imageBytes,
    required this.imageFile,
    required this.isSubmitting,
    required this.onPickImage,
  });

  @override
  State<AuthAvatarPicker> createState() => _AuthAvatarPickerState();
}

class _AuthAvatarPickerState extends State<AuthAvatarPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0.95,
      upperBound: 1.08,
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.isSubmitting) return;
    await _controller.forward();
    await _controller.reverse();
    widget.onPickImage();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasImage = widget.imageBytes != null || widget.imageFile != null;

    final Widget avatarImage = RepaintBoundary(
      child: ClipOval(
        child: hasImage
            ? (widget.imageBytes != null
            ? Image.memory(
          widget.imageBytes!,
          width: 112,
          height: 112,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        )
            : Image.file(
          widget.imageFile!,
          width: 112,
          height: 112,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ))
            : Icon(
          Icons.person,
          size: 60,
          color: Colors.white.withOpacity(0.85),
        ),
      ),
    );

    return Tooltip(
      message: l10n.choosePicture,
      child: InkWell(
        onTap: _handleTap,
        customBorder: const CircleBorder(),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: RepaintBoundary(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background subtle glow
              AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: widget.isSubmitting ? 1.0 : 1.02,
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0x4D0057FF), // subtle blue glow
                        Color(0x33FFB300), // subtle amber
                        Colors.transparent,
                      ],
                      stops: [0.5, 0.85, 1.0],
                    ),
                  ),
                ),
              ),

              // Main avatar circle
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.25),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor:
                  Colors.white.withOpacity(hasImage ? 0.08 : 0.14),
                  child: avatarImage,
                ),
              ),

              // Overlay if no image
              if (!hasImage)
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                ),

              // Camera icon — animated scale
              Positioned(
                bottom: 6,
                right: 8,
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0057FF),
                          Color(0xFFFFB300),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
