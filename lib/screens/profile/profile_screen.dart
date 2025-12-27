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
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_full_screen_image_viewer.dart';
import '../legal/terms_of_use_screen.dart';
import 'presence_privacy_screen.dart';

import 'widgets/profile_avatar_section.dart';
import 'widgets/profile_birthday_section.dart';
import 'widgets/profile_danger_zone_section.dart';
import 'widgets/profile_footer.dart';
import 'widgets/profile_gender_section.dart';
import 'widgets/profile_legal_section.dart';
import 'widgets/profile_name_section.dart';
import 'widgets/profile_privacy_tile.dart';

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

  // 'none' = user did not specify gender (optional)
  String _gender = 'none';

  // ✅ Email display (read-only)
  String? _email;

  late AnimationController _avatarController;
  late Animation<double> _scale;

  static const String _appVersion = 'v1.0';
  static const String _websiteUrl = 'https://www.mwchats.com';

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

      // ✅ Prefer auth email, fallback to Firestore
      final authEmail = (user.email ?? '').trim();
      final dbEmail = ((data['email'] ?? '') as String).trim();
      final effectiveEmail = authEmail.isNotEmpty ? authEmail : (dbEmail.isNotEmpty ? dbEmail : null);

      // ✅ If auth has email and DB doesn't, store it (merge)
      if (authEmail.isNotEmpty && dbEmail.isEmpty) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'email': authEmail},
          SetOptions(merge: true),
        ).catchError((e) {
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
      final ref =
      FirebaseStorage.instance.ref().child('profile_pics/${user.uid}');
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

        // ✅ Keep email in DB if available (read-only UI)
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

      // ✅ Refresh local email after save (in case provider updated)
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
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
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
        final msgSnap = await messagesRef
            .where('senderId', isEqualTo: uid)
            .limit(batchSize)
            .get();

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

  // ✅ Read-only email tile (modern, copy button)
  Widget _buildEmailTile(AppLocalizations l10n) {
    final email = (_email ?? '').trim();

    final providers = FirebaseAuth.instance.currentUser?.providerData
        .map((p) => p.providerId)
        .toList() ??
        const <String>[];

    final hasEmail = email.isNotEmpty;

    final subtitle = hasEmail
        ? email
        : (providers.contains('phone')
        ? l10n.authError // replace with a proper l10n string if you have one
        : l10n.authError);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceAltColor.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
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
                  // If you have l10n.emailLabel use it; otherwise keep "Email"
                  'Email',
                  style: TextStyle(
                    color: kTextSecondary.withOpacity(0.95),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasEmail ? subtitle : 'No email on this account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: kTextPrimary.withOpacity(0.95),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          if (hasEmail)
            IconButton(
              tooltip: 'Copy',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: email));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
              icon: Icon(Icons.copy_rounded,
                  color: kPrimaryGold.withOpacity(0.95)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textDirection = Directionality.of(context);
    final isRtl = textDirection == TextDirection.rtl;

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isWide = width >= 900;

    // Provider used for fullscreen
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
          l10n.profileTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
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
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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

                                const SizedBox(height: 28),

                                ProfileNameSection(
                                  firstNameCtrl: _firstNameCtrl,
                                  lastNameCtrl: _lastNameCtrl,
                                ),

                                // ✅ Email shown here (read-only)
                                const SizedBox(height: 14),
                                _buildEmailTile(l10n),

                                const SizedBox(height: 20),

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

                                const SizedBox(height: 30),

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
                                    label: Text(_saving ? l10n.saving : l10n.save.toUpperCase()),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kGoldDeep,
                                      foregroundColor: Colors.black,
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                                    ),
                                  ),
                                ),

                                ProfilePrivacyTile(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const PresencePrivacyScreen()),
                                    );
                                  },
                                ),

                                ProfileLegalSection(
                                  isRtl: isRtl,
                                  onOpenTerms: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const TermsOfUseScreen()),
                                    );
                                  },
                                ),

                                const SizedBox(height: 40),

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
                    appVersion: _appVersion,
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
