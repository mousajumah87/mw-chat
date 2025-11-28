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
  String? _currentUrl;
  String _avatarType = 'bear';
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  DateTime? _birthday;
  String _gender = 'male';

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
      _gender = data['gender'] ?? 'male';
      final birthdayField = data['birthday'];
      if (birthdayField is Timestamp) _birthday = birthdayField.toDate();
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
      final ref = FirebaseStorage.instance.ref().child('profile_pics/${user.uid}');
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
        'gender': _gender,
      };
      if (_birthday != null) {
        data['birthday'] = Timestamp.fromDate(_birthday!);
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      if (url != null && url.isNotEmpty) await user.updatePhotoURL(url);

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profileUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.authError)));
      }
    }
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
                      horizontal: 24, vertical: 28),
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
                              borderRadius: BorderRadius.circular(12)),
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.birthday,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickBirthday,
                        icon: const Icon(Icons.cake_outlined,
                            color: Colors.white70),
                        label: Text(
                          _birthdayLabel(l10n),
                          style: const TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side:
                          BorderSide(color: Colors.white.withOpacity(0.3)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.gender,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        children: [
                          ChoiceChip(
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
                          ),
                          ChoiceChip(
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _saveProfile,
                        icon: _saving
                            ? const SizedBox(
                            height: 16,
                            width: 16,
                            child:
                            CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save),
                        label: Text(
                            _saving ? l10n.saving : l10n.save.toUpperCase()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSecondaryAmber,
                          foregroundColor: Colors.black,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 24),
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
