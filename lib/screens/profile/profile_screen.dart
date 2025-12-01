import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';

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

  String? _currentUrl;
  String _avatarType = 'bear';
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  DateTime? _birthday;

  // 'none' = user did not specify gender (optional)
  String _gender = 'none';

  late AnimationController _avatarController;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _avatarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      lowerBound: 0.95,
      upperBound: 1.05,
    );
    _scale = CurvedAnimation(parent: _avatarController, curve: Curves.easeOut);
    _loadCurrentProfile();
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data() ?? {};

    if (!mounted) return;
    setState(() {
      _currentUrl = data['profileUrl'] ?? '';
      _avatarType = data['avatarType'] ?? 'bear';
      _firstNameCtrl.text = data['firstName'] ?? '';
      _lastNameCtrl.text = data['lastName'] ?? '';

      // gender is optional; only accept known values
      final rawGender = data['gender'];
      if (rawGender == 'male' || rawGender == 'female') {
        _gender = rawGender;
      } else {
        _gender = 'none';
      }

      final birthdayField = data['birthday'];
      if (birthdayField is Timestamp) {
        _birthday = birthdayField.toDate();
      }
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imageFile = null;
      });
    } else {
      setState(() {
        _imageFile = File(picked.path);
        _imageBytes = null;
      });
    }

    _avatarController.forward().then((_) => _avatarController.reverse());
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthday = picked);
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
        if (kIsWeb && _imageBytes != null) {
          await ref.putData(_imageBytes!, metadata);
        } else if (_imageFile != null) {
          await ref.putFile(_imageFile!, metadata);
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
      }

      // Gender is optional:
      // - if male/female → store
      // - otherwise → remove the field from Firestore
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

        // If this screen was pushed from somewhere (e.g. settings),
        // go back after successful save.
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        // If shown from AuthGate as the initial screen, there's nothing to pop;
        // AuthGate will switch to HomeScreen once profile is complete.
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
    }
  }

  // === Account deletion ===

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
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  /// Deletes:
  /// - Firestore user document
  /// - All messages authored by this user under privateChats/*/messages
  /// - Removes the user from any chat `participants` array
  /// - Profile picture from Storage
  /// - Auth account itself
  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _deletingAccount = true);

    try {
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      // 1) Delete Firestore user data (profile + messages, etc.)
      await _deleteUserData(db, uid);

      // 2) Delete profile picture from Storage, if present
      if (_currentUrl != null && _currentUrl!.isNotEmpty) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(_currentUrl!);
          await ref.delete();
        } catch (_) {
          // Ignore if already deleted or URL invalid
        }
      }

      // 3) Delete auth account
      await user.delete();

      // 4) Sign out so AuthGate shows AuthScreen again
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Show info before navigating away
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.accountDeletedSuccessfully),
        ),
      );

      // 5) Go back to the first route (AuthGate -> login)
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.deleteAccountFailedRetry),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingAccount = false);
      }
    }
  }

  /// Best-effort client-side cleanup of the user’s data.
  /// For very large datasets, consider moving this to a Cloud Function.
  Future<void> _deleteUserData(FirebaseFirestore db, String uid) async {
    // Delete the user profile document
    await db.collection('users').doc(uid).delete();

    // Delete messages authored by this user from private chats
    final chatsSnap = await db
        .collection('privateChats')
        .where('participants', arrayContains: uid)
        .get();

    for (final chatDoc in chatsSnap.docs) {
      final messagesRef = chatDoc.reference.collection('messages');

      // Delete in small batches to avoid huge writes.
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

      // Remove the user from participants array.
      await chatDoc.reference.update({
        'participants': FieldValue.arrayRemove([uid]),
      });
    }

    // If you have other collections like "friendships", "blocks", etc.,
    // you can extend this method to clean those as well.
  }

  Widget _buildAvatar() {
    final imageProvider = _imageBytes != null
        ? MemoryImage(_imageBytes!)
        : _imageFile != null
        ? FileImage(_imageFile!) as ImageProvider
        : (_currentUrl?.isNotEmpty ?? false)
        ? NetworkImage(_currentUrl!)
        : null;

    return ScaleTransition(
      scale: _scale,
      child: CircleAvatar(
        radius: 60,
        backgroundColor: kSurfaceAltColor,
        backgroundImage: imageProvider,
        child: imageProvider == null
            ? Text(
          _avatarType == 'smurf' ? '🧜‍♀️' : '🐻',
          style: const TextStyle(fontSize: 40),
        )
            : null,
      ),
    );
  }

  String _birthdayLabel(AppLocalizations l10n) {
    if (_birthday == null) return l10n.selectBirthday;
    return '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textDirection = Directionality.of(context);
    final isRtl = textDirection == TextDirection.rtl;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        centerTitle: true,
        backgroundColor: kSurfaceColor,
        elevation: 0,
      ),
      body: MwBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                decoration: BoxDecoration(
                  color: kSurfaceAltColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kBorderColor),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kSurfaceColor,
                      kSurfaceAltColor.withOpacity(0.95),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: Column(
                    children: [
                      _buildAvatar(),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _pickImage,
                        icon: const Icon(Icons.photo_outlined),
                        label: Text(l10n.choosePicture),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _firstNameCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: l10n.firstName,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _lastNameCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: l10n.lastName,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // === Birthday label ===
                      Align(
                        alignment: isRtl
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Text(
                          l10n.birthday,
                          textDirection: textDirection,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // === Birthday button (LTR + RTL aware) ===
                      OutlinedButton(
                        onPressed: _saving ? null : _pickBirthday,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
                                style: const TextStyle(color: Colors.white),
                                textAlign:
                                isRtl ? TextAlign.right : TextAlign.left,
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
                          '${l10n.gender} (optional)',
                          textDirection: textDirection,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // === Gender chips (male / female / prefer not to say) ===
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
                            onSelected: (_) =>
                                setState(() => _gender = 'male'),
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
                            onSelected: (_) =>
                                setState(() => _gender = 'female'),
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
                            onSelected: (_) =>
                                setState(() => _gender = 'none'),
                          );

                          final chips = isRtl
                              ? <Widget>[femaleChip, maleChip, preferNotChip]
                              : <Widget>[maleChip, femaleChip, preferNotChip];

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
                        onPressed: _saving ? null : _saveProfile,
                        icon: _saving
                            ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.save),
                        label: Text(
                          _saving ? l10n.saving : l10n.save.toUpperCase(),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSecondaryAmber,
                          foregroundColor: Colors.black,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 24,
                          ),
                        ),
                      ),

                      // === Danger zone / Delete account ===
                      const SizedBox(height: 40),
                      const Divider(height: 32),
                      Align(
                        alignment: isRtl
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Text(
                          l10n.dangerZone,
                          style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                          style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.delete_forever),
                          label: Text(
                            _deletingAccount
                                ? l10n.deletingAccount
                                : l10n.deleteMyAccount,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(
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
      ),
    );
  }
}
