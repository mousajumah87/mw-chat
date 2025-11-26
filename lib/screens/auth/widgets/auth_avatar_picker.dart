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
  late AnimationController _controller;
  late Animation<double> _scale;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      lowerBound: 0.94,
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

  void _onPressed() async {
    if (widget.isSubmitting) return;
    await _controller.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    await _controller.reverse();
    widget.onPickImage();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasImage = widget.imageBytes != null || widget.imageFile != null;

    Widget imageChild;
    if (widget.imageBytes != null) {
      imageChild = ClipOval(
        child: Image.memory(
          widget.imageBytes!,
          width: 112,
          height: 112,
          fit: BoxFit.cover,
        ),
      );
    } else if (widget.imageFile != null) {
      imageChild = ClipOval(
        child: Image.file(
          widget.imageFile!,
          width: 112,
          height: 112,
          fit: BoxFit.cover,
        ),
      );
    } else {
      imageChild = Icon(
        Icons.person,
        size: 60,
        color: Colors.white.withOpacity(0.85),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Tooltip(
        message: l10n.choosePicture,
        child: InkWell(
          onTap: _onPressed,
          customBorder: const CircleBorder(),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer gradient glow
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isHovering ? 136 : 130,
                height: _isHovering ? 136 : 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0x80256EFF),
                      Color(0x80FFB300),
                      Colors.transparent,
                    ],
                    stops: [0.3, 0.8, 1.0],
                  ),
                  boxShadow: _isHovering
                      ? [
                    BoxShadow(
                      color: const Color(0xFF0057FF).withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: const Color(0xFFFFB300).withOpacity(0.25),
                      blurRadius: 30,
                      spreadRadius: 6,
                    ),
                  ]
                      : [],
                ),
              ),

              // Avatar
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.22),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor:
                  Colors.white.withOpacity(hasImage ? 0.06 : 0.12),
                  child: imageChild,
                ),
              ),

              if (!hasImage)
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.black.withOpacity(0.1),
                ),

              // Camera icon
              Positioned(
                bottom: 6,
                right: 8,
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0057FF), Color(0xFFFFB300)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 10,
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
