// lib/screens/auth/auth_screen.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/mw_background.dart';
import '../../widgets/ui/mw_language_button.dart';
import '../legal/terms_of_use_screen.dart';
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
  bool _showPassword = false;
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  final ValueNotifier<String> _genderNotifier = ValueNotifier('none');

  DateTime? _birthday;
  File? _imageFile;
  Uint8List? _imageBytes;

  // ✅ NEW: Upload state
  bool _uploadingImage = false;
  double _uploadProgress = 0.0;

  bool _isLogin = true;
  bool _submitting = false;
  bool _pickingImage = false;
  bool _agreedToTerms = false;
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

  // -------------------------
  // ✅ IMAGE PICKING (UNCHANGED)
  // -------------------------
  Future<void> _pickImage() async {
    if (_submitting || _pickingImage || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() => _pickingImage = true);

    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
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
    } on PlatformException catch (e, st) {
      debugPrint('[AuthScreen] _pickImage PlatformException: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
    } catch (e, st) {
      debugPrint('[AuthScreen] _pickImage error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pickingImage = false);
      }
    }
  }

  // ✅ REMOVE PROFILE IMAGE
  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _imageFile = null;
    });
  }

  static String _compressImage(String path) => path;

  // -------------------------
  // BIRTHDAY
  // -------------------------
  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday ?? DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked != null) {
      setState(() => _birthday = picked);
    }
  }

  // -------------------------
  // TERMS OF USE
  // -------------------------
  Future<void> _openTerms() async {
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TermsOfUseScreen()),
    );

    if (accepted == true) {
      setState(() {
        _agreedToTerms = true;
        _errorText = null;
      });
    }
  }

  // -------------------------
  // ✅ SUBMIT (WITH UPLOAD PROGRESS)
  // -------------------------
  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;

    if (!_isLogin && !_agreedToTerms) {
      setState(() => _errorText = l10n.mustAcceptTerms);
      return;
    }

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

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      final user = cred.user;
      if (user == null) {
        setState(() => _errorText = l10n.authError);
        return;
      }

      String? profileUrl;

      // ✅ UPLOAD WITH PROGRESS
      if (_imageBytes != null || _imageFile != null) {
        final ref =
        FirebaseStorage.instance.ref().child('profile_pics/${user.uid}');
        final metadata = SettableMetadata(contentType: 'image/jpeg');

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
              ? (event.bytesTransferred / event.totalBytes).toDouble()
              : 0.0;

          if (mounted) {
            setState(() => _uploadProgress = progress);
          }
        });

        await task;

        if (mounted) {
          setState(() => _uploadingImage = false);
        }

        profileUrl = await ref.getDownloadURL();
      }

      final gender = _genderNotifier.value;
      final avatarType = gender == 'female' ? 'smurf' : 'bear';

      final userData = <String, dynamic>{
        'email': user.email,
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'profileUrl': profileUrl ?? '',
        'avatarType': avatarType,
        'isOnline': false,
        'isActive': false,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'blockedUserIds': <String>[],
        'hasAcceptedTerms': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      };

      if (_birthday != null) {
        userData['birthday'] = Timestamp.fromDate(_birthday!);
      }
      if (gender != 'none') {
        userData['gender'] = gender;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(userData);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorText = e.message ?? l10n.authError);
    } catch (e, st) {
      debugPrint('[AuthScreen] _submit error: $e\n$st');
      setState(() => _errorText = l10n.authError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _birthdayLabel(AppLocalizations l10n) {
    if (_birthday == null) return l10n.selectBirthday;
    return "${_birthday!.year}-"
        "${_birthday!.month.toString().padLeft(2, '0')}-"
        "${_birthday!.day.toString().padLeft(2, '0')}";
  }

  // -------------------------
  // UI BUILD
  // -------------------------
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRegister = !_isLogin;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      backgroundColor: Colors.black,
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: kSurfaceAltColor.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: kBorderColor.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kSecondaryAmber.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          AuthHeader(isRegister: isRegister),
                          const SizedBox(height: 28),

                          if (isRegister)
                            ValueListenableBuilder<String>(
                              valueListenable: _genderNotifier,
                              builder: (_, g, __) => AuthRegisterSection(
                                firstNameCtrl: _firstNameCtrl,
                                lastNameCtrl: _lastNameCtrl,
                                birthdayLabel: _birthdayLabel(l10n),
                                gender: g,
                                isSubmitting: _submitting,
                                imageBytes: _imageBytes,
                                imageFile: _imageFile,
                                onPickImage: _pickImage,

                                // ✅ NEW WIRING
                                isUploading: _uploadingImage,
                                uploadProgress: _uploadProgress,
                                onRemoveImage: _removeImage,

                                onPickBirthday: _pickBirthday,
                                onGenderChanged: (v) =>
                                _genderNotifier.value = v,
                                agreedToTerms: _agreedToTerms,
                                onAgreeChanged: (bool v) {
                                  setState(() {
                                    _agreedToTerms = v;
                                    if (v) _errorText = null;
                                  });
                                },
                                onViewTerms: _openTerms,
                              ),
                            ),

                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _emailCtrl,
                            decoration: InputDecoration(
                              labelText: l10n.email,
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l10n.requiredField;
                              }
                              if (!v.contains('@')) {
                                return l10n.invalidEmail;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: !_showPassword,
                            decoration: InputDecoration(
                              labelText: l10n.password,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: kTextSecondary,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showPassword = !_showPassword;
                                  });
                                },
                              ),
                            ),
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
                              style: const TextStyle(color: kErrorColor),
                            ),
                          ],

                          const SizedBox(height: 24),

                          ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryBlue,
                              foregroundColor: Colors.white,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 40,
                              ),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _submitting
                                  ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                                  : Text(
                                isRegister
                                    ? l10n.register
                                    : l10n.login,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isLogin = !_isLogin;
                                _errorText = null;
                              });
                            },
                            child: Text(
                              isRegister
                                  ? l10n.alreadyHaveAccount
                                  : l10n.createNewAccount,
                              style: const TextStyle(
                                color: kTextSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
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
