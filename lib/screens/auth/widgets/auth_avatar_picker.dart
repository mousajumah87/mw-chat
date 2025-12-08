// lib/screens/auth/widgets/auth_avatar_picker.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; //
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class AuthAvatarPicker extends StatefulWidget {
  final Uint8List? imageBytes;
  final File? imageFile;
  final bool isSubmitting;
  final VoidCallback onPickImage;

  // OPTIONAL — backward compatible
  final bool isUploading;
  final double uploadProgress;
  final VoidCallback? onRemoveImage;

  const AuthAvatarPicker({
    super.key,
    required this.imageBytes,
    required this.imageFile,
    required this.isSubmitting,
    required this.onPickImage,

    // DEFAULTS KEEP OLD FLOW WORKING
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.onRemoveImage,
  });

  @override
  State<AuthAvatarPicker> createState() => _AuthAvatarPickerState();
}

class _AuthAvatarPickerState extends State<AuthAvatarPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  bool _isPicking = false; // PREVENTS TRANSIENT REBUILD GLITCH
  bool _showSuccessRing = false; // Success animation

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _scale = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

  }

  @override
  void didUpdateWidget(covariant AuthAvatarPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Trigger success ring when a new image arrives
    final hadOldImage =
        oldWidget.imageBytes != null || oldWidget.imageFile != null;
    final hasNewImage =
        widget.imageBytes != null || widget.imageFile != null;

    if (!hadOldImage && hasNewImage) {
      _showSuccessRing = true;
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _showSuccessRing = false);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.isSubmitting || _isPicking) return;

    // HAPTIC FEEDBACK
    HapticFeedback.mediumImpact();

    setState(() => _isPicking = true);

    try {
      await _controller.forward();
      if (!mounted) return;
      await _controller.reverse();
      if (!mounted) return;

      await Future<void>.sync(widget.onPickImage);
    } catch (e, st) {
      debugPrint('[AuthAvatarPicker] onPickImage error: $e\n$st');
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasImage = widget.imageBytes != null || widget.imageFile != null;

    // SAFE IMAGE PROVIDER (NO iOS / WEB GLITCH)
    final ImageProvider? provider = kIsWeb
        ? (widget.imageBytes != null ? MemoryImage(widget.imageBytes!) : null)
        : (widget.imageFile != null ? FileImage(widget.imageFile!) : null);

    final Widget avatarImage = ClipOval(
      child: provider != null
          ? Image(
        image: provider,
        width: 112,
        height: 112,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      )
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
            // Success ring
            if (_showSuccessRing)
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: kSecondaryAmber.withOpacity(0.9),
                    width: 3,
                  ),
                ),
              ),

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
                  color: Colors.black.withOpacity(0.35), // HARD SAFE BASE
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
                  backgroundColor: Colors.black.withOpacity(0.25), // NEVER RED
                  child: avatarImage,
                ),
              ),
            ),

            // === Upload progress overlay (optional) ===
            if (widget.isUploading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.55),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: widget.uploadProgress > 0
                          ? widget.uploadProgress
                          : null,
                      strokeWidth: 3,
                      color: kPrimaryBlue,
                    ),
                  ),
                ),
              ),

            // === Remove image button (optional) ===
            if (hasImage && widget.onRemoveImage != null && !widget.isUploading)
              Positioned(
                top: 6,
                right: 8,
                child: GestureDetector(
                  onTap: widget.onRemoveImage,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: kErrorColor,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
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

            // Freeze UI while picking (prevents red flash)
            if (_isPicking)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.35),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
