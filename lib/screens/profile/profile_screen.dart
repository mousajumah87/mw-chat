// lib/screens/profile/profile_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui'; // still OK even if BackdropFilter not used elsewhere

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // for PlatformException
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';
import '../legal/terms_of_use_screen.dart';

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
  bool _pickingImage = false; // <--- new flag to avoid double-taps

  String? _currentUrl;
  String _avatarType = 'bear';
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  DateTime? _birthday;

  // 'none' = user did not specify gender (optional)
  String _gender = 'none';

  late AnimationController _avatarController;
  late Animation<double> _scale;

  static const String _appVersion = 'v1.0';
  static const String _websiteUrl = 'https://www.mwchats.com';

  // NEW (safe additions)
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

  // NEW: REMOVE PROFILE IMAGE SAFELY
  Future<void> _removeImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 1. Delete from Firebase Storage
      if (_currentUrl != null && _currentUrl!.isNotEmpty) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(_currentUrl!);
          await ref.delete();
        } catch (e) {
          debugPrint('[ProfileScreen] Storage delete failed: $e');
        }
      }

      // 2. Remove from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'profileUrl': FieldValue.delete(),
      });

      // 3. Remove from Firebase Auth
      await user.updatePhotoURL(null);

      // 4. Clear locally
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


  Future<void> _openMwWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      debugPrint('Could not launch $_websiteUrl');
    }
  }

  Future<void> _loadCurrentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};

      if (!mounted) return;
      setState(() {
        _currentUrl = data['profileUrl'] ?? '';
        _avatarType = data['avatarType'] ?? 'bear';
        _firstNameCtrl.text = data['firstName'] ?? '';
        _lastNameCtrl.text = data['lastName'] ?? '';

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

          if (mounted) {
            setState(() => _uploadProgress = progress);
          }
        });

        await task;

        if (mounted) {
          setState(() => _uploadingImage = false);
        }

        url = await ref.getDownloadURL();
      }

      final Map<String, dynamic> data = {
        'profileUrl': url ?? '',
        'avatarType': _avatarType,
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
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
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profileUpdated)),
        );

        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e, st) {
      debugPrint('[ProfileScreen] _saveProfile error: $e\n$st');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
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
        SnackBar(
          content: Text(l10n.accountDeletedSuccessfully),
        ),
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
        SnackBar(
          content: Text(l10n.deleteAccountFailedRetry),
        ),
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

  Widget _buildAvatar() {
    final ImageProvider? imageProvider = kIsWeb
        ? (_imageBytes != null ? MemoryImage(_imageBytes!) : null)
        : (_imageFile != null ? FileImage(_imageFile!) : null);

    final ImageProvider? finalProvider =
        imageProvider ??
            (_currentUrl?.isNotEmpty ?? false
                ? NetworkImage(_currentUrl!)
                : null);

    return ScaleTransition(
      scale: _scale,
      child: Column(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: kSurfaceAltColor,
            backgroundImage: finalProvider,
            child: finalProvider == null
                ? Text(
              _avatarType == 'smurf' ? '🧜‍♀️' : '🐻',
              style: const TextStyle(fontSize: 40),
            )
                : null,
          ),

          if (_uploadingImage) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _uploadProgress),
          ],

          if (finalProvider != null && !_uploadingImage) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _saving ? null : _removeImage,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text(
                'Remove Photo',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _birthdayLabel(AppLocalizations l10n) {
    if (_birthday == null) return l10n.selectBirthday;
    return '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}';
  }

  Widget _buildFooter(
      BuildContext context,
      AppLocalizations l10n, {
        required bool isWide,
      }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      fontSize: 11,
    );
    final versionStyle = textStyle?.copyWith(
      color: Colors.white38,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 16 : 12,
        vertical: 8,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.appBrandingBeta,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
          Text(
            _appVersion,
            style: versionStyle,
            textAlign: TextAlign.center,
          ),
          InkWell(
            onTap: _openMwWebsite,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'mwchats.com',
                style: textStyle?.copyWith(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
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
          top: false, // AppBar already covers the top
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  const SizedBox(height: 12),

                  // ==== BODY: one main card, same feel as HomeScreen ====
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isWide ? 16 : 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints:
                            const BoxConstraints(maxWidth: 540),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildAvatar(),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _saving || _pickingImage
                                      ? null
                                      : _pickImage,
                                  icon: _pickingImage
                                      ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                    CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : const Icon(
                                    Icons.photo_outlined,
                                  ),
                                  label: Text(l10n.choosePicture),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryBlue,
                                    foregroundColor: Colors.white,
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _firstNameCtrl,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: l10n.firstName,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _lastNameCtrl,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: l10n.lastName,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // === Birthday label (optional) ===
                                Align(
                                  alignment: isRtl
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Text(
                                    '${l10n.birthday} ${l10n.optional}',
                                    textDirection: textDirection,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),

                                OutlinedButton(
                                  onPressed:
                                  _saving ? null : _pickBirthday,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color:
                                      Colors.white.withOpacity(0.3),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 14,
                                    ),
                                  ),
                                  child: Row(
                                    textDirection: textDirection,
                                    children: [
                                      const Icon(
                                        Icons.cake_outlined,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _birthdayLabel(l10n),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          textAlign: isRtl
                                              ? TextAlign.right
                                              : TextAlign.left,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 22),

                                // === Gender label (optional) ===
                                Align(
                                  alignment: isRtl
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Text(
                                    '${l10n.gender} ${l10n.optional}',
                                    textDirection: textDirection,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                Builder(
                                  builder: (_) {
                                    final maleChip = ChoiceChip(
                                      label: Text('${l10n.male} 🐻'),
                                      selected: _gender == 'male',
                                      selectedColor: kPrimaryBlue,
                                      backgroundColor: kSurfaceColor,
                                      labelStyle: TextStyle(
                                        color: _gender == 'male'
                                            ? Colors.white
                                            : Colors.white70,
                                      ),
                                      onSelected: (_) => setState(
                                              () => _gender = 'male'),
                                    );

                                    final femaleChip = ChoiceChip(
                                      label: Text('${l10n.female} 💃'),
                                      selected: _gender == 'female',
                                      selectedColor: kSecondaryAmber,
                                      backgroundColor: kSurfaceColor,
                                      labelStyle: TextStyle(
                                        color: _gender == 'female'
                                            ? Colors.black
                                            : Colors.white70,
                                      ),
                                      onSelected: (_) => setState(
                                              () => _gender = 'female'),
                                    );

                                    final preferNotChip = ChoiceChip(
                                      label: Text(l10n.preferNotToSay),
                                      selected: _gender == 'none',
                                      selectedColor: Colors.grey,
                                      backgroundColor: kSurfaceColor,
                                      labelStyle: TextStyle(
                                        color: _gender == 'none'
                                            ? Colors.black
                                            : Colors.white70,
                                      ),
                                      onSelected: (_) => setState(
                                              () => _gender = 'none'),
                                    );

                                    final chips = isRtl
                                        ? <Widget>[
                                      femaleChip,
                                      maleChip,
                                      preferNotChip
                                    ]
                                        : <Widget>[
                                      maleChip,
                                      femaleChip,
                                      preferNotChip
                                    ];

                                    return Wrap(
                                      spacing: 10,
                                      runSpacing: 8,
                                      textDirection: textDirection,
                                      children: chips,
                                    );
                                  },
                                ),

                                const SizedBox(height: 30),

                                // === Save profile ===
                                ElevatedButton.icon(
                                  onPressed:
                                  _saving ? null : _saveProfile,
                                  icon: _saving
                                      ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child:
                                    CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : const Icon(Icons.save),
                                  label: Text(
                                    _saving
                                        ? l10n.saving
                                        : l10n.save.toUpperCase(),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kSecondaryAmber,
                                    foregroundColor: Colors.black,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 24,
                                    ),
                                  ),
                                ),

                                // === Legal & Support section ===
                                const SizedBox(height: 32),
                                const Divider(height: 32),
                                Align(
                                  alignment: isRtl
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Text(
                                    l10n.legalTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                Container(
                                  decoration: BoxDecoration(
                                    color: kSurfaceColor,
                                    borderRadius:
                                    BorderRadius.circular(12),
                                    border: Border.all(
                                      color: kBorderColor,
                                    ),
                                  ),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.gavel_outlined,
                                      color: Colors.white70,
                                    ),
                                    title: Text(
                                      l10n.termsTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white54,
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                          const TermsOfUseScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                const SizedBox(height: 12),

                                Container(
                                  decoration: BoxDecoration(
                                    color: kSurfaceColor,
                                    borderRadius:
                                    BorderRadius.circular(12),
                                    border: Border.all(
                                      color: kBorderColor,
                                    ),
                                  ),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.mail_outline,
                                      color: Colors.white70,
                                    ),
                                    title: Text(
                                      l10n.contactSupport,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      l10n.contactSupportSubtitle,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 40),
                                const Divider(height: 32),
                                Align(
                                  alignment: isRtl
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Text(
                                    l10n.dangerZone,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: isRtl
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Text(
                                    l10n.deleteAccountDescription,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                      color: Colors.white60,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                        Icons.delete_forever),
                                    label: Text(
                                      _deletingAccount
                                          ? l10n.deletingAccount
                                          : l10n.deleteMyAccount,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(
                                        color: Colors.red,
                                      ),
                                      padding:
                                      const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 16,
                                      ),
                                    ),
                                    onPressed: _deletingAccount
                                        ? null
                                        : _confirmDeleteAccount,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // ==== FOOTER (same style as Home) ====
                  _buildFooter(context, l10n, isWide: isWide),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
