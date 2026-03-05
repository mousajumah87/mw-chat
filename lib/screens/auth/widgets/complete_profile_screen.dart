// lib/screens/auth/widgets/complete_profile_screen.dart
//
// ✅ Purpose:
// - After login, allow user to finish optional profile details (photo, birthday, gender).
// - Names are required ONLY if missing in Firestore (avoid duplication since names are now collected on registration).
//
// ✅ Behavior:
// - If first/last already exist: user can Skip (saves optional fields only).
// - If missing: first/last fields appear and are required.
//
// Notes:
// - Keeps upload progress tracking.
// - Uses safe setState guards to avoid setState after dispose.
// - Avoids relying on non-existent l10n keys by providing fallbacks.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class CompleteProfileScreen extends StatefulWidget {
  final String uid;
  const CompleteProfileScreen({super.key, required this.uid});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();

  String _gender = 'none';
  DateTime? _birthday;

  Uint8List? _imageBytes;

  bool _saving = false;
  bool _loading = true;

  bool _uploading = false;
  double _progress = 0.0;
  StreamSubscription<TaskSnapshot>? _uploadSub;

  bool _disposed = false;
  bool get _alive => mounted && !_disposed;

  bool _needsName = false; // ✅ only require names if missing in Firestore

  void _safeSetState(VoidCallback fn) {
    if (!_alive) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _disposed = true;
    _uploadSub?.cancel();
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  // ---------------------------
  // Load current user profile
  // ---------------------------
  Future<void> _loadExisting() async {
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(widget.uid);

      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref.get(const GetOptions(source: Source.server));
      } catch (_) {
        snap = await ref.get();
      }

      final data = snap.data() ?? <String, dynamic>{};

      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();

      _needsName = first.isEmpty || last.isEmpty;

      _firstCtrl.text = first;
      _lastCtrl.text = last;

      final g = (data['gender'] ?? '').toString().trim();
      if (g == 'male' || g == 'female') {
        _gender = g;
      } else {
        _gender = 'none';
      }

      final b = data['birthday'];
      if (b is Timestamp) _birthday = b.toDate();
    } catch (e, st) {
      debugPrint('[CompleteProfileScreen] load error: $e\n$st');
    } finally {
      _safeSetState(() => _loading = false);
    }
  }

  // ---------------------------
  // Pickers
  // ---------------------------
  Future<void> _pickBirthday() async {
    if (!_alive || _saving) return;

    final now = DateTime.now();
    final initial = _birthday ?? DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (!_alive) return;
    if (picked != null) _safeSetState(() => _birthday = picked);
  }

  String _birthdayLabel(AppLocalizations l10n) {
    if (_birthday == null) {
      try {
        return l10n.selectBirthday;
      } catch (_) {
        return 'Select birthday';
      }
    }

    return "${_birthday!.year}-"
        "${_birthday!.month.toString().padLeft(2, '0')}-"
        "${_birthday!.day.toString().padLeft(2, '0')}";
  }

  Future<void> _pickImage() async {
    if (!_alive || _saving) return;

    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
      );

      if (!_alive || picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!_alive) return;

      _safeSetState(() => _imageBytes = bytes);
    } catch (e, st) {
      debugPrint('[CompleteProfileScreen] pick image error: $e\n$st');
    }
  }

  void _removeImage() {
    if (!_alive) return;
    _safeSetState(() => _imageBytes = null);
  }

  // ---------------------------
  // Avatar type logic
  // ---------------------------
  String _avatarTypeFromGender(String g) => (g == 'female') ? 'smurf' : 'bear';

  bool get _genderIsAllowedByRules => _gender == 'male' || _gender == 'female';

  // ---------------------------
  // Upload (optional)
  // ---------------------------
  Future<String?> _uploadProfilePicIfAny() async {
    final bytes = _imageBytes;
    if (bytes == null) return null;

    final ref = FirebaseStorage.instance.ref().child('profile_pics/${widget.uid}');
    final metadata = SettableMetadata(contentType: 'image/jpeg');

    _safeSetState(() {
      _uploading = true;
      _progress = 0.0;
    });

    final task = ref.putData(bytes, metadata);

    await _uploadSub?.cancel();
    _uploadSub = task.snapshotEvents.listen((event) {
      final p = event.totalBytes > 0
          ? (event.bytesTransferred / event.totalBytes).toDouble()
          : 0.0;
      if (_alive) _safeSetState(() => _progress = p);
    });

    await task;
    await _uploadSub?.cancel();
    _uploadSub = null;

    _safeSetState(() => _uploading = false);
    return await ref.getDownloadURL();
  }

  // ---------------------------
  // Save
  // ---------------------------
  Future<void> _save({required bool allowSkipNames}) async {
    if (!_alive || _saving) return;
    final l10n = AppLocalizations.of(context)!;

    if (_needsName && !allowSkipNames) {
      final ok = _formKey.currentState?.validate() ?? false;
      if (!ok) return;
    }

    _safeSetState(() => _saving = true);

    try {
      final profileUrl = await _uploadProfilePicIfAny();

      final first = _firstCtrl.text.trim();
      final last = _lastCtrl.text.trim();

      final patch = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'profileCompletedAt': FieldValue.serverTimestamp(), // optional but recommended
      };

      // ✅ Only write gender if it matches rules (male/female).
      // If user picked "Prefer not to say", we simply omit the field.
      if (_genderIsAllowedByRules) {
        patch['gender'] = _gender;
        patch['avatarType'] = _avatarTypeFromGender(_gender);
      } else {
        // Optional: still allow avatarType default if you want
        // (rules allow avatarType as string)
        patch['avatarType'] = _avatarTypeFromGender('male'); // -> 'bear'
      }

      // ✅ Only write names if needed OR user typed them (and not skipping)
      if (_needsName && !allowSkipNames) {
        patch['firstName'] = first;
        patch['lastName'] = last;
      }

      if (_birthday != null) {
        patch['birthday'] = Timestamp.fromDate(_birthday!);
      }

      if (profileUrl != null && profileUrl.trim().isNotEmpty) {
        patch['profileUrl'] = profileUrl.trim();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .set(patch, SetOptions(merge: true));

      if (!_alive) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l10nOr(l10n, 'profileUpdated', fallback: 'Profile updated'),
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[CompleteProfileScreen] save error: $e\n$st');
      if (_alive) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
    } finally {
      _safeSetState(() => _saving = false);
    }
  }

  String _l10nOr(AppLocalizations l10n, String key, {required String fallback}) {
    try {
      switch (key) {
        case 'completeYourProfile':
          return l10n.completeYourProfile;
        case 'profileUpdated':
          return l10n.profileUpdated;
        case 'remove':
          return l10n.remove;
        case 'save':
          return l10n.save;
        default:
          return fallback;
      }
    } catch (_) {
      return fallback;
    }
  }

  // ---------------------------
  // UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _l10nOr(l10n, 'completeYourProfile', fallback: 'Complete your profile'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        automaticallyImplyLeading: false,
        actions: [
          if (!_needsName)
            TextButton(
              onPressed: _saving ? null : () => _save(allowSkipNames: true),
              child: Text(
                l10n.skipForNow,
                style: const TextStyle(
                  color: kTextSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: kSurfaceAltColor.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kBorderColor.withOpacity(0.25)),
                ),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _needsName ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: Colors.white.withOpacity(0.08),
                              backgroundImage: _imageBytes != null ? MemoryImage(_imageBytes!) : null,
                              child: _imageBytes == null
                                  ? Icon(
                                Icons.person,
                                size: 44,
                                color: Colors.white.withOpacity(0.5),
                              )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: InkWell(
                                onTap: _saving ? null : _pickImage,
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: kPrimaryGold,
                                  ),
                                  child: const Icon(
                                    Icons.photo,
                                    size: 18,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_imageBytes != null)
                        TextButton(
                          onPressed: _saving ? null : _removeImage,
                          child: Text(
                            _l10nOr(l10n, 'remove', fallback: 'Remove'),
                            style: const TextStyle(color: kTextSecondary),
                          ),
                        ),
                      if (_uploading) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: _progress),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 10),

                      if (_needsName) ...[
                        TextFormField(
                          controller: _firstCtrl,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: l10n.firstName,
                            prefixIcon: const Icon(Icons.badge_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _lastCtrl,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: l10n.lastName,
                            prefixIcon: const Icon(Icons.badge_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextButton.icon(
                        onPressed: _saving ? null : _pickBirthday,
                        icon: const Icon(Icons.cake_outlined),
                        label: Text(_birthdayLabel(l10n)),
                        style: TextButton.styleFrom(foregroundColor: kTextSecondary),
                      ),

                      const SizedBox(height: 10),

                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(l10n.male),
                            selected: _gender == 'male',
                            onSelected: _saving ? null : (_) => _safeSetState(() => _gender = 'male'),
                          ),
                          ChoiceChip(
                            label: Text(l10n.female),
                            selected: _gender == 'female',
                            onSelected: _saving ? null : (_) => _safeSetState(() => _gender = 'female'),
                          ),
                          ChoiceChip(
                            label: Text(l10n.preferNotToSay),
                            selected: _gender == 'none',
                            onSelected: _saving ? null : (_) => _safeSetState(() => _gender = 'none'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      ElevatedButton(
                        onPressed: _saving ? null : () => _save(allowSkipNames: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryGold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _saving
                              ? const SizedBox(
                            key: ValueKey('saving'),
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : Text(
                            _l10nOr(l10n, 'save', fallback: 'Save'),
                            key: const ValueKey('save'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),

                      if (kIsWeb) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Web note: this screen appears only if names are missing.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 12,
                          ),
                        ),
                      ],
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