// lib/screens/auth/auth_screen.dart
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
  Uint8List? _imageBytes;

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

  // ---------------------------
  // Forgot password
  // ---------------------------
  Future<void> _showForgotPasswordDialog() async {
    if (_submitting || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        String? inlineError;
        bool sending = false;

        Future<void> submit(StateSetter setLocalState) async {
          final email = emailCtrl.text.trim();

          // ✅ client-side validation (instant)
          if (email.isEmpty) {
            setLocalState(() => inlineError = l10n.requiredField);
            return;
          }

          final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
          if (!emailOk) {
            setLocalState(() => inlineError = l10n.invalidEmail);
            return;
          }

          setLocalState(() {
            inlineError = null;
            sending = true;
          });

          try {
            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

            if (!mounted) return;
            Navigator.of(ctx).pop();

            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.resetEmailSent)));
          } on FirebaseAuthException catch (e) {
            final msg = _mapResetError(e, l10n);
            setLocalState(() {
              inlineError = msg; // ✅ show Firebase errors inline too
              sending = false;
            });
          } catch (_) {
            setLocalState(() {
              inlineError = l10n.authError;
              sending = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(l10n.resetPasswordTitle),

              // ✅ keyboard + small screens safe (iPhone mini, etc.)
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.send,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: l10n.email,
                          hintText: 'name@example.com',
                          errorText: inlineError, // ✅ inline error under field
                        ),
                        onChanged: (_) {
                          if (inlineError != null) {
                            setLocalState(() => inlineError = null);
                          }
                        },
                        onSubmitted: (_) =>
                            sending ? null : submit(setLocalState),
                      ),
                      if (sending) ...[
                        const SizedBox(height: 14),
                        const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: sending ? null : () => submit(setLocalState),
                  child: Text(l10n.send),
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();
  }

  String _mapResetError(FirebaseAuthException e, AppLocalizations l10n) {
    switch (e.code) {
      case 'invalid-email':
        return l10n.invalidEmail;
      case 'user-not-found':
        // privacy-friendly:
        return l10n.resetEmailIfExists; // ✅ add key
      case 'missing-email':
        return l10n.requiredField;
      case 'too-many-requests':
        return l10n.tooManyRequests; // ✅ add key
      default:
        return e.message ?? l10n.authError;
    }
  }

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
        });
      } else {
        final bytes = await picked.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
      }
    } on PlatformException catch (e, st) {
      debugPrint('[AuthScreen] _pickImage PlatformException: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.authError)));
      }
    } catch (e, st) {
      debugPrint('[AuthScreen] _pickImage error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.authError)));
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
    });
  }

  static String _compressImage(String path) => path;

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

  Future<void> _openTerms() async {
    final accepted = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const TermsOfUseScreen()));

    if (accepted == true) {
      setState(() {
        _agreedToTerms = true;
        _errorText = null;
      });
    }
  }

  Future<void> _warmUserDocFromServer(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
    } catch (_) {
      // Safe no-op
    }
  }

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
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );

        final uid = cred.user?.uid;
        if (uid != null) {
          await _warmUserDocFromServer(uid);
        }
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

      if (_imageBytes != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'profile_pics/${user.uid}',
        );
        final metadata = SettableMetadata(contentType: 'image/jpeg');

        setState(() {
          _uploadingImage = true;
          _uploadProgress = 0.0;
        });

        final bytes = _imageBytes;
        if (bytes == null) {
          throw StateError('Missing image bytes');
        }
        final UploadTask task = ref.putData(bytes, metadata);

        task.snapshotEvents.listen((event) {
          final double progress = event.totalBytes > 0
              ? (event.bytesTransferred / event.totalBytes).toDouble()
              : 0.0;

          if (mounted) setState(() => _uploadProgress = progress);
        });

        await task;

        if (mounted) setState(() => _uploadingImage = false);

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

  void _resetRegisterState() {
    _agreedToTerms = false;
    _genderNotifier.value = 'none';
    _birthday = null;
    _imageBytes = null;
    _uploadingImage = false;
    _uploadProgress = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRegister = !_isLogin;

    return Scaffold(
      backgroundColor: Colors.black,
      body: MwBackground(
        child: Stack(
          children: [
            Positioned(
              top: 32,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: const MwLanguageButton(),
              ),
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
                    border: Border.all(color: kBorderColor.withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: kGoldDeep.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 34,
                    ),
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
                                imageFile: null,
                                onPickImage: _pickImage,
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
                              if (v == null || v.isEmpty)
                                return l10n.requiredField;
                              if (!v.contains('@')) return l10n.invalidEmail;
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
                                onPressed: () => setState(() {
                                  _showPassword = !_showPassword;
                                }),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty)
                                return l10n.requiredField;
                              if (v.length < 6) return l10n.minPassword;
                              return null;
                            },
                          ),

                          // ✅ Forgot password only for login
                          if (!isRegister) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: _submitting
                                    ? null
                                    : _showForgotPasswordDialog,
                                child: Text(
                                  l10n.forgotPassword, // ✅ add key
                                  style: const TextStyle(
                                    color: kTextSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],

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
                              backgroundColor: kPrimaryGold,
                              foregroundColor: Colors.black,
                              elevation: 3,
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
                                        color: Colors.black,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      isRegister ? l10n.register : l10n.login,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black,
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

                                if (!_isLogin) {
                                  _resetRegisterState();
                                }
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
