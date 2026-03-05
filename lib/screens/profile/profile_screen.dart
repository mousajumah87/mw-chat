// lib/screens/profile/profile_screen.dart
//
// MW Chat – Account (Profile) Screen
// Updated to align with new main menu:
// - Menu now has: Account (Profile), Font & Display, Privacy Settings, Invite Friends, About, Logout
// - This screen focuses on ACCOUNT fields + Save + Sensitive actions
// - Privacy + Font & Display + Legal are now accessed from the main menu (avoids duplication)
// - Responsive + RTL safe + iOS/Android/Web safe (small screens + large text scale)
//
// Notes:
// - Keeps your existing avatar/name/birthday/gender/email/save/delete flows intact
// - Keeps the subtle MW watermark section header style (6–8% opacity)
// - Layout: always scrollable, safe paddings, no overflow

import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:mw/screens/profile/widgets/profile_change_password_section.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/app_info.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_full_screen_image_viewer.dart';

import 'widgets/profile_avatar_section.dart';
import 'widgets/profile_birthday_section.dart';
import 'widgets/profile_danger_zone_section.dart';
import 'widgets/profile_footer.dart';
import 'widgets/profile_gender_section.dart';
import 'widgets/profile_name_section.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  File? _imageFile;
  Uint8List? _imageBytes;

  bool _saving = false;
  bool _deletingAccount = false;
  bool _pickingImage = false;

  String? _currentUrl;
  String _avatarType = 'bear';
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  DateTime? _birthday;

  String _gender = 'none';

  String? _email;

  late AnimationController _avatarController;
  late Animation<double> _scale;

  static const String _websiteUrl = AppInfo.websiteUrl;

  bool _uploadingImage = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();

    _avatarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _scale = _avatarController.drive(
      Tween<double>(begin: 0.95, end: 1.05),
    );

    _loadCurrentProfile();
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _openMwWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $_websiteUrl');
    }
  }

  Future<void> _loadCurrentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? {};

      final authEmail = (user.email ?? '').trim();
      final dbEmail = ((data['email'] ?? '') as String).trim();
      final effectiveEmail =
      authEmail.isNotEmpty ? authEmail : (dbEmail.isNotEmpty ? dbEmail : null);

      // persist auth email once
      if (authEmail.isNotEmpty && dbEmail.isEmpty) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'email': authEmail}, SetOptions(merge: true))
            .catchError((e) {
          debugPrint('[ProfileScreen] failed to persist email: $e');
        });
      }

      if (!mounted) return;
      setState(() {
        _email = effectiveEmail;

        _currentUrl = (data['profileUrl'] ?? '').toString();
        _avatarType = (data['avatarType'] ?? 'bear').toString();
        _firstNameCtrl.text = (data['firstName'] ?? '').toString();
        _lastNameCtrl.text = (data['lastName'] ?? '').toString();

        final rawGender = data['gender'];
        if (rawGender == 'male' || rawGender == 'female') {
          _gender = rawGender;
        } else {
          _gender = 'none';
        }

        final birthdayField = data['birthday'];
        if (birthdayField is Timestamp) {
          _birthday = birthdayField.toDate();
        } else {
          _birthday = null;
        }
      });
    } catch (e, st) {
      debugPrint('[ProfileScreen] _loadCurrentProfile error: $e\n$st');
    }
  }

  Future<void> _pickImage() async {
    if (_saving || _deletingAccount || _pickingImage) return;
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() => _pickingImage = true);

    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked == null) return;

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        setState(() {
          _imageBytes = bytes;
          _imageFile = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _imageFile = File(picked.path);
          _imageBytes = null;
        });
      }

      if (mounted) {
        await _avatarController.forward();
        if (!mounted) return;
        await _avatarController.reverse();
      }
    } on PlatformException catch (e, st) {
      debugPrint('[ProfileScreen] _pickImage PlatformException: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
    } catch (e, st) {
      debugPrint('[ProfileScreen] _pickImage error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pickingImage = false);
      } else {
        _pickingImage = false;
      }
    }
  }

  Future<void> _removeImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (_currentUrl != null && _currentUrl!.isNotEmpty) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(_currentUrl!);
          await ref.delete();
        } catch (e) {
          debugPrint('[ProfileScreen] Storage delete failed: $e');
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'profileUrl': FieldValue.delete(),
      });

      await user.updatePhotoURL(null);

      if (mounted) {
        setState(() {
          _imageFile = null;
          _imageBytes = null;
          _currentUrl = '';
        });
      }
    } catch (e, st) {
      debugPrint('[ProfileScreen] _removeImage error: $e\n$st');
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _birthday = picked);
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() => _saving = true);

    try {
      String? url = _currentUrl;
      final ref = FirebaseStorage.instance.ref().child('profile_pics/${user.uid}');
      final metadata = SettableMetadata(contentType: 'image/jpeg');

      if (_imageFile != null || _imageBytes != null) {
        setState(() {
          _uploadingImage = true;
          _uploadProgress = 0.0;
        });

        UploadTask task;
        if (kIsWeb && _imageBytes != null) {
          task = ref.putData(_imageBytes!, metadata);
        } else {
          task = ref.putFile(_imageFile!, metadata);
        }

        task.snapshotEvents.listen((event) {
          final double progress = event.totalBytes > 0
              ? (event.bytesTransferred / event.totalBytes)
              .clamp(0.0, 1.0)
              .toDouble()
              : 0.0;
          if (mounted) setState(() => _uploadProgress = progress);
        });

        await task;

        if (mounted) setState(() => _uploadingImage = false);
        url = await ref.getDownloadURL();
      }

      final authEmail = (user.email ?? '').trim();

      final Map<String, dynamic> data = {
        'profileUrl': url ?? '',
        'avatarType': _avatarType,
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        if (authEmail.isNotEmpty) 'email': authEmail,
      };

      if (_birthday != null) {
        data['birthday'] = Timestamp.fromDate(_birthday!);
      } else {
        data['birthday'] = FieldValue.delete();
      }

      if (_gender == 'male' || _gender == 'female') {
        data['gender'] = _gender;
      } else {
        data['gender'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      if (url != null && url.isNotEmpty) {
        await user.updatePhotoURL(url);
      }

      if (mounted) {
        setState(() {
          _email = authEmail.isNotEmpty ? authEmail : _email;
        });
      }

      if (!mounted) return;

      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileUpdated)),
      );

      // Account screen is opened from menu; popping back feels right after Save.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      debugPrint('[ProfileScreen] _saveProfile error: $e\n$st');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authError)),
      );
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteMyAccount),
        content: Text(l10n.deleteAccountWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _deletingAccount = true);

    try {
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      await _deleteUserData(db, uid);

      if (_currentUrl != null && _currentUrl!.isNotEmpty) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(_currentUrl!);
          await ref.delete();
        } catch (_) {}
      }

      await user.delete();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountDeletedSuccessfully)),
      );

      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'requires-recent-login'
                ? l10n.deleteAccountFailedRetry
                : (e.message ?? l10n.deleteAccountFailed),
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[ProfileScreen] _deleteAccount error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deleteAccountFailedRetry)),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingAccount = false);
      } else {
        _deletingAccount = false;
      }
    }
  }

  Future<void> _deleteUserData(FirebaseFirestore db, String uid) async {
    await db.collection('users').doc(uid).delete();

    final chatsSnap = await db
        .collection('privateChats')
        .where('participants', arrayContains: uid)
        .get();

    for (final chatDoc in chatsSnap.docs) {
      final messagesRef = chatDoc.reference.collection('messages');

      const batchSize = 50;
      while (true) {
        final msgSnap =
        await messagesRef.where('senderId', isEqualTo: uid).limit(batchSize).get();

        if (msgSnap.docs.isEmpty) break;

        final batch = db.batch();
        for (final m in msgSnap.docs) {
          batch.delete(m.reference);
        }
        await batch.commit();
      }

      await chatDoc.reference.update({
        'participants': FieldValue.arrayRemove([uid]),
      });
    }
  }

  void _openAvatarFullScreen(ImageProvider provider, String heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => MwFullScreenImageViewer(
          provider: provider,
          heroTag: heroTag,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // ===================== UI helpers (Modern MW) =====================

  /// Tiny MW watermark painted on the header line (super subtle).
  Widget _mwWatermark() {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.07, // 6–8%
        child: Text(
          'MW',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: kPrimaryGold,
          ),
        ),
      ),
    );
  }

  Widget _buildFancySectionHeader(
      ThemeData theme,
      String text, {
        required IconData icon,
      }) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kPrimaryGold.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kPrimaryGold.withOpacity(0.30)),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryGold.withOpacity(0.10),
                    blurRadius: 14,
                    spreadRadius: 0.0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: kPrimaryGold.withOpacity(0.95)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: kPrimaryGold.withOpacity(0.95),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      colors: [
                        kPrimaryGold.withOpacity(0.75),
                        kPrimaryGold.withOpacity(0.20),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 10,
                  child: _mwWatermark(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerHeader(
      ThemeData theme,
      String text, {
        required IconData icon,
      }) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.red.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: Colors.red.withOpacity(0.90)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.red.withOpacity(0.90),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.withOpacity(0.65),
                        Colors.red.withOpacity(0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 10,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.06,
                      child: Text(
                        'MW',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailTile(AppLocalizations l10n, ThemeData theme) {
    final email = (_email ?? '').trim();
    final hasEmail = email.isNotEmpty;

    final title = (l10n.email.isNotEmpty) ? l10n.email : 'Email';
    final noEmailText = (l10n.noEmailOnAccount.isNotEmpty)
        ? l10n.noEmailOnAccount
        : 'No email on this account';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.email_outlined, color: kTextPrimary.withOpacity(0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: kTextSecondary.withOpacity(0.95),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasEmail ? email : noEmailText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary.withOpacity(0.95),
                  ),
                ),
              ],
            ),
          ),
          if (hasEmail)
            IconButton(
              tooltip: (l10n.copy.isNotEmpty) ? l10n.copy : 'Copy',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: email));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text((l10n.copied.isNotEmpty) ? l10n.copied : 'Copied'),
                  ),
                );
              },
              icon: Icon(
                Icons.copy_rounded,
                color: kPrimaryGold.withOpacity(0.95),
              ),
            ),
        ],
      ),
    );
  }

  // ===================== build =====================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final textDirection = Directionality.of(context);
    final isRtl = textDirection == TextDirection.rtl;

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isWide = width >= 900;

    // ✅ smaller padding on tiny phones, larger on tablets/web
    final double pagePad = width < 360 ? 16 : 24;

    final ImageProvider? localProvider = kIsWeb
        ? (_imageBytes != null ? MemoryImage(_imageBytes!) : null)
        : (_imageFile != null ? FileImage(_imageFile!) : null);

    final bool hasNetwork = (_currentUrl?.trim().isNotEmpty ?? false);
    const heroTag = 'my_profile_photo';

    final ImageProvider? tapProvider =
        localProvider ?? (hasNetwork ? CachedNetworkImageProvider(_currentUrl!) : null);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        elevation: 0,
        centerTitle: true,
        title: Text(
          // Menu label is "Account", but screen can still show "Profile" in-app.
          // If you want it identical, create l10n.accountTitle and use it here.
          (l10n.profileTitle.isNotEmpty) ? l10n.profileTitle : 'Account',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        )
            : null,
      ),
      body: MwBackground(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isWide ? 16 : 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.62),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.all(pagePad),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Avatar
                                ProfileAvatarSection(
                                  scale: _scale,
                                  imageBytes: _imageBytes,
                                  imageFile: _imageFile,
                                  currentUrl: _currentUrl,
                                  avatarType: _avatarType,
                                  uploadingImage: _uploadingImage,
                                  uploadProgress: _uploadProgress,
                                  saving: _saving || _pickingImage,
                                  onPickImage: _pickImage,
                                  onRemoveImage: _removeImage,
                                  onOpenFullScreen: tapProvider == null
                                      ? () {}
                                      : () => _openAvatarFullScreen(tapProvider, heroTag),
                                ),

                                // ACCOUNT
                                _buildFancySectionHeader(
                                  theme,
                                  // menu says Account; keep it consistent
                                  (l10n.account.isNotEmpty) ? l10n.account : 'Account',
                                  icon: Icons.manage_accounts_rounded,
                                ),

                                ProfileNameSection(
                                  firstNameCtrl: _firstNameCtrl,
                                  lastNameCtrl: _lastNameCtrl,
                                ),
                                const SizedBox(height: 14),

                                _buildEmailTile(l10n, theme),
                                const SizedBox(height: 12),

                                const ProfileChangePasswordSection(),
                                const SizedBox(height: 18),

                                ProfileBirthdaySection(
                                  birthday: _birthday,
                                  saving: _saving,
                                  isRtl: isRtl,
                                  textDirection: textDirection,
                                  onPickBirthday: _pickBirthday,
                                ),
                                const SizedBox(height: 22),

                                ProfileGenderSection(
                                  gender: _gender,
                                  isRtl: isRtl,
                                  textDirection: textDirection,
                                  onGenderChanged: (v) => setState(() => _gender = v),
                                ),

                                const SizedBox(height: 18),

                                // SAVE
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _saving ? null : _saveProfile,
                                    icon: _saving
                                        ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                        : const Icon(Icons.save),
                                    label: Text(
                                      _saving
                                          ? l10n.saving
                                          : ((l10n.save.isNotEmpty) ? l10n.save : 'Save')
                                          .toUpperCase(),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kGoldDeep,
                                      foregroundColor: Colors.black,
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 24,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // DANGER / Sensitive actions (keep on Account screen)
                                _buildDangerHeader(
                                  theme,
                                  (l10n.sensitiveActions.isNotEmpty)
                                      ? l10n.sensitiveActions
                                      : ((l10n.dangerZone.isNotEmpty)
                                      ? l10n.dangerZone
                                      : 'Sensitive actions'),
                                  icon: Icons.warning_amber_rounded,
                                ),
                                ProfileDangerZoneSection(
                                  isRtl: isRtl,
                                  deletingAccount: _deletingAccount,
                                  onDeletePressed: _confirmDeleteAccount,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ProfileFooter(
                    l10n: l10n,
                    isWide: isWide,
                    appVersion: AppInfo.version,
                    onOpenWebsite: _openMwWebsite,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
