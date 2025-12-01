import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_language_button.dart';
import 'widgets/auth_header.dart';
import 'widgets/auth_register_section.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

// 'none' means user did not specify gender (gender is optional)
  static const String _genderNone = 'none';
  static const String _genderMale = 'male';
  static const String _genderFemale = 'female';

  final ValueNotifier<String> _genderNotifier = ValueNotifier(_genderNone);

  DateTime? _birthday;
  File? _imageFile;
  Uint8List? _imageBytes;

  bool _isLogin = true;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _genderNotifier.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_submitting) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 75,
    );
    if (picked == null) return;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imageFile = null;
      });
    } else {
      final compressed = await compute(_compressImage, picked.path);
      setState(() {
        _imageFile = File(compressed);
        _imageBytes = null;
      });
    }
  }

  static String _compressImage(String path) {
    // For lightweight compression, just return same path here.
    // Optionally integrate image library (e.g. flutter_image_compress)
    return path;
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Future<String?> _uploadProfileImage(String uid) async {
    if (_imageFile == null && _imageBytes == null) return null;
    try {
      final ref = FirebaseStorage.instance.ref().child('profile_pics/$uid');
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      if (kIsWeb && _imageBytes != null) {
        await ref.putData(_imageBytes!, metadata);
      } else if (_imageFile != null) {
        await ref.putFile(_imageFile!, metadata);
      }
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
        return;
      }

      if (_birthday == null) {
        setState(() => _errorText = l10n.selectBirthday);
        return;
      }

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      final user = cred.user;
      if (user == null) {
        setState(() => _errorText = l10n.failedToCreateUser);
        return;
      }

      final profileUrl = await _uploadProfileImage(user.uid);

      final gender = _genderNotifier.value;
      final hasGender =
          gender == _genderMale || gender == _genderFemale;

      // Decide avatarType:
      // - if user chose female → smurf
      // - if user chose male  → bear
      // - if user did not choose → default bear
      final avatarType = hasGender && gender == _genderFemale
          ? 'smurf'
          : 'bear';

      final userData = <String, dynamic>{
        'email': user.email,
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'birthday': Timestamp.fromDate(_birthday!),
        'profileUrl': profileUrl ?? '',
        'avatarType': avatarType,
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
        'isActive': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Only store gender if the user actually chose male/female
      if (hasGender) {
        userData['gender'] = gender;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(userData);


      if (profileUrl != null) await user.updatePhotoURL(profileUrl);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorText = e.message ?? l10n.authError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _birthdayLabel(AppLocalizations l10n) {
    if (_birthday == null) return l10n.selectBirthday;
    return '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRegister = !_isLogin;
    final isWide = MediaQuery.of(context).size.width > 900;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      body: MwBackground(
        child: Stack(
          children: [
            Positioned(
              top: 32,
              right: isRTL ? null : 32,
              left: isRTL ? 32 : null,
              child: const MwLanguageButton(),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 20,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 34, 28, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AuthHeader(isRegister: isRegister),
                          const SizedBox(height: 28),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                if (isRegister)
                                  ValueListenableBuilder<String>(
                                    valueListenable: _genderNotifier,
                                    builder: (_, gender, __) => AuthRegisterSection(
                                      firstNameCtrl: _firstNameCtrl,
                                      lastNameCtrl: _lastNameCtrl,
                                      birthdayLabel: _birthdayLabel(l10n),
                                      gender: gender,
                                      isSubmitting: _submitting,
                                      imageBytes: _imageBytes,
                                      imageFile: _imageFile,
                                      onPickImage: _pickImage,
                                      onPickBirthday: _pickBirthday,
                                      onGenderChanged: (value) =>
                                      _genderNotifier.value = value,
                                    ),
                                  ),
                                _buildTextField(
                                  controller: _emailCtrl,
                                  icon: Icons.email_outlined,
                                  label: l10n.email,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return l10n.requiredField;
                                    }
                                    if (!v.contains('@')) {
                                      return l10n.invalidEmail;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                _buildTextField(
                                  controller: _passwordCtrl,
                                  icon: Icons.lock_outline,
                                  label: l10n.password,
                                  obscure: true,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return l10n.requiredField;
                                    }
                                    if (v.length < 6) {
                                      return l10n.minPassword;
                                    }
                                    return null;
                                  },
                                ),
                                if (_errorText != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _errorText!,
                                    style: const TextStyle(color: Colors.redAccent),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                const SizedBox(height: 22),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _submitting ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: _submitting
                                        ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                        : Text(isRegister
                                        ? l10n.register
                                        : l10n.login),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Divider(color: Colors.white10),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: _submitting
                                      ? null
                                      : () {
                                    setState(() {
                                      _isLogin = !_isLogin;
                                      _errorText = null;
                                    });
                                  },
                                  child: Text(
                                    isRegister
                                        ? l10n.alreadyHaveAccount
                                        : l10n.createNewAccount,
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (isWide)
              Positioned(
                left: 24,
                bottom: 20,
                child: Text(
                  l10n.appBrandingBeta,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white38),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFFFFB300), width: 1.3),
        ),
      ),
      validator: validator,
    );
  }
}
