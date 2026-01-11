// lib/screens/profile/widgets/profile_avatar_section.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/mw_avatar.dart';

class ProfileAvatarSection extends StatelessWidget {
  final Animation<double> scale;
  final Uint8List? imageBytes;
  final File? imageFile;

  /// Can be:
  /// - https download URL (Firebase Storage)
  /// - gs:// bucket URL (Firebase Storage)
  /// - empty/null
  final String? currentUrl;

  /// "bear" or "girl" (and any legacy aliases handled by MwAvatar)
  final String avatarType;

  final bool uploadingImage;
  final double uploadProgress;

  final bool saving;

  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;
  final VoidCallback onOpenFullScreen;

  const ProfileAvatarSection({
    super.key,
    required this.scale,
    required this.imageBytes,
    required this.imageFile,
    required this.currentUrl,
    required this.avatarType,
    required this.uploadingImage,
    required this.uploadProgress,
    required this.saving,
    required this.onPickImage,
    required this.onRemoveImage,
    required this.onOpenFullScreen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final ImageProvider? localProvider = kIsWeb
        ? (imageBytes != null ? MemoryImage(imageBytes!) : null)
        : (imageFile != null ? FileImage(imageFile!) : null);

    final bool hasNetwork = (currentUrl?.trim().isNotEmpty ?? false);

    // Stable hero tag for the same user photo across app.
    const heroTag = 'my_profile_photo';

    const double avatarRadius = 60;

    // Allow opening viewer when we have *any* image source.
    final bool canOpen = (localProvider != null) || hasNetwork;

    Widget avatarCore;
    if (localProvider != null) {
      avatarCore = Hero(
        tag: heroTag,
        child: ClipOval(
          child: SizedBox(
            width: avatarRadius * 2,
            height: avatarRadius * 2,
            child: Image(
              image: localProvider,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              // ✅ Never let a decode error break the UI.
              errorBuilder: (_, __, ___) {
                return MwAvatar(
                  heroTag: heroTag,
                  radius: avatarRadius,
                  avatarType: avatarType,
                  profileUrl: null,
                  hideRealAvatar: true,
                  showRing: true,
                  showOnlineDot: false,
                  showOnlineGlow: false,
                  cachePolicy: MwAvatarCachePolicy.normal,
                );
              },
            ),
          ),
        ),
      );
    } else {
      // ✅ MwAvatar handles:
      // - gs:// resolution
      // - https URL load
      // - 404/403 fallback (never blocks UI)
      avatarCore = MwAvatar(
        heroTag: heroTag,
        radius: avatarRadius,
        avatarType: avatarType,
        profileUrl: currentUrl,
        hideRealAvatar: false,
        showRing: true,
        showOnlineDot: false,
        showOnlineGlow: false,
        cachePolicy: MwAvatarCachePolicy.normal,
      );
    }

    return ScaleTransition(
      scale: scale,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (!canOpen || uploadingImage) ? null : onOpenFullScreen,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: avatarRadius * 2 + 8,
                  height: avatarRadius * 2 + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kSurfaceAltColor.withOpacity(0.9),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                  ),
                ),
                avatarCore,
                if (canOpen && !uploadingImage)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.60),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: const Icon(
                        Icons.zoom_in_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (uploadingImage) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: uploadProgress),
          ],

          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: saving ? null : onPickImage,
            icon: const Icon(Icons.photo_outlined),
            label: Text(l10n.choosePicture),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryGold,
              foregroundColor: Colors.black,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          if ((localProvider != null || hasNetwork) && !uploadingImage) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: saving ? null : onRemoveImage,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: Text(
                l10n.removePhoto,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
