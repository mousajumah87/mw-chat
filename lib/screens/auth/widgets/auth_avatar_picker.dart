// lib/screens/auth/widgets/auth_avatar_picker.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

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
      duration: const Duration(milliseconds: 250),
      lowerBound: 0.95,
      upperBound: 1.1,
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

    try {
      await _controller.forward();
      if (!mounted) return;
      await _controller.reverse();
      if (!mounted) return;

      await Future<void>.sync(widget.onPickImage);
    } catch (e, st) {
      debugPrint('[AuthAvatarPicker] onPickImage error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasImage = widget.imageBytes != null || widget.imageFile != null;

    final Widget avatarImage = ClipOval(
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
        Icons.person_rounded,
        size: 60,
        color: Colors.white.withOpacity(0.85),
      ),
    );

    return Tooltip(
      message: l10n.choosePicture,
      child: InkWell(
        onTap: _handleTap,
        customBorder: const CircleBorder(),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // === Dynamic glow halo ===
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kPrimaryBlue.withOpacity(0.45),
                    kSecondaryAmber.withOpacity(0.35),
                    Colors.transparent,
                  ],
                  stops: const [0.4, 0.8, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryBlue.withOpacity(0.25),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: kSecondaryAmber.withOpacity(0.25),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),

            // === Main avatar circle ===
            AnimatedScale(
              scale: widget.isSubmitting ? 1.0 : 1.02,
              duration: const Duration(milliseconds: 180),
              child: Container(
                width: 126,
                height: 126,
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    width: 2,
                    color: hasImage
                        ? Colors.white.withOpacity(0.35)
                        : Colors.white.withOpacity(0.25),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.1),
                      Colors.white.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white.withOpacity(0.08),
                  child: avatarImage,
                ),
              ),
            ),

            // === Overlay when no image ===
            if (!hasImage)
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),

            // === Neon camera icon ===
            Positioned(
              bottom: 8,
              right: 10,
              child: ScaleTransition(
                scale: _scale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [kPrimaryBlue, kSecondaryAmber],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimaryBlue.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: kSecondaryAmber.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // === Optional shimmer pulse ===
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: widget.isSubmitting ? 0.2 : 0.05,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          kPrimaryBlue.withOpacity(0.15),
                          kSecondaryAmber.withOpacity(0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
