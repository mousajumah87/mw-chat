// lib/screens/auth/widgets/auth_avatar_picker.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  bool _isPicking = false;
  bool _showSuccessRing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _scale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
  }

  @override
  void didUpdateWidget(covariant AuthAvatarPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final hadOldImage =
        oldWidget.imageBytes != null || oldWidget.imageFile != null;
    final hasNewImage = widget.imageBytes != null || widget.imageFile != null;

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
    if (widget.isSubmitting || widget.isUploading || _isPicking) return;

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
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasImage = widget.imageBytes != null || widget.imageFile != null;

    // ✅ SAFER: allow bytes OR file on ALL platforms
    ImageProvider? provider;
    if (widget.imageBytes != null) {
      provider = MemoryImage(widget.imageBytes!);
    } else if (!kIsWeb && widget.imageFile != null) {
      provider = FileImage(widget.imageFile!);
    }

    final avatarImage = ClipOval(
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
                    color: kGoldDeep.withOpacity(0.9),
                    width: 3,
                  ),
                ),
              ),

            // Glow halo
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kPrimaryGold.withOpacity(0.45),
                    kGoldDeep.withOpacity(0.35),
                    Colors.transparent,
                  ],
                  stops: const [0.4, 0.8, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryGold.withOpacity(0.25),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: kGoldDeep.withOpacity(0.22),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),

            // Main avatar circle
            AnimatedScale(
              scale: (widget.isSubmitting || widget.isUploading) ? 1.0 : 1.02,
              duration: const Duration(milliseconds: 180),
              child: Container(
                width: 126,
                height: 126,
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.35),
                  border: Border.all(
                    width: 2,
                    color: hasImage
                        ? Colors.white.withOpacity(0.35)
                        : Colors.white.withOpacity(0.25),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.10),
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
                  backgroundColor: Colors.black.withOpacity(0.25),
                  child: avatarImage,
                ),
              ),
            ),

            // Upload progress overlay
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
                      color: kPrimaryGold,
                    ),
                  ),
                ),
              ),

            // ✅ RTL-safe remove button
            if (hasImage && widget.onRemoveImage != null && !widget.isUploading)
              PositionedDirectional(
                top: 6,
                end: 8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onRemoveImage?.call();
                  },
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

            // ✅ RTL-safe camera icon
            PositionedDirectional(
              bottom: 8,
              end: 10,
              child: ScaleTransition(
                scale: _scale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [kPrimaryGold, kGoldDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimaryGold.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: kGoldDeep.withOpacity(0.3),
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

            // Optional shimmer pulse
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: (widget.isSubmitting || widget.isUploading) ? 0.2 : 0.05,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          kPrimaryGold.withOpacity(0.15),
                          kGoldDeep.withOpacity(0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Freeze UI while picking
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
