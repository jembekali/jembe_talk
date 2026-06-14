// lib/edit_profile_screen.dart (VERSION 32.23 - GHOST & DELETE PROTECTION)

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:jembe_talk/full_photo_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();

  File? _selectedImage;
  String? _currentPhotoUrl;
  String _phoneNumber = "";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // 🔥 1. LOAD DATA + SECURITY CHECK 🔥
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // A. Banza usome Cache (Umuvuduko)
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameController.text = prefs.getString('user_displayName') ?? '';
        _aboutController.text = prefs.getString('user_about') ?? '';
        _currentPhotoUrl = prefs.getString('user_photoUrl');
      });
    }

    // B. 🔥 GENZURA NIBA KONTI IKIRIHO MURI FIRESTORE 🔥
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      // IKI NICYO GIKEMURA IKIBAZO: Niba yasibwe, musohore ako kanya
      _forceLogout();
      return;
    }

    if (mounted) {
      final data = doc.data()!;
      setState(() {
        _nameController.text = data['displayName'] ?? '';
        _aboutController.text = data['about'] ?? '';
        _currentPhotoUrl = data['photoUrl'];
        _phoneNumber = data['phoneNumber'] ?? "";
      });
    }
  }

  // 🔥 METHOD YO GUSOHORA UMUNTU WASIBWE 🔥
  void _forceLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_profile_complete');
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      // Musubize kuri WelcomeScreen (Kugaruka inyuma burundu)
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // --- IMAGE PICKER & EDITOR ---
  Future<void> _openImageEditor() async {
    Uint8List? imageBytes;
    if (_selectedImage != null) {
      imageBytes = await _selectedImage!.readAsBytes();
    } else if (_currentPhotoUrl != null) {
      try {
        final ByteData data =
            await NetworkAssetBundle(Uri.parse(_currentPhotoUrl!)).load("");
        imageBytes = data.buffer.asUint8List();
      } catch (e) {
        return;
      }
    }

    if (imageBytes != null && mounted) {
      final editedImage = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => ImageEditor(image: imageBytes!)),
      );

      if (editedImage != null && editedImage is Uint8List) {
        final tempDir = await getTemporaryDirectory();
        final file = await File(
                '${tempDir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg')
            .create();
        await file.writeAsBytes(editedImage);
        setState(() {
          _selectedImage = file;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (pickedFile != null)
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
  }

  // --- UPDATE PROFILE (WITH GHOST PREVENTION) ---
  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 🔥 GENZURA NANONE MBERE YO KUBIKA (Inshuro ya nyuma)
      final checkDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!checkDoc.exists) {
        _forceLogout();
        return;
      }

      String? photoUrl = _currentPhotoUrl;
      if (_selectedImage != null) {
        String rawUrl = await R2Service().uploadFile(
            _selectedImage!, "profiles/${user.uid}.jpg", 'image/jpeg');
        photoUrl = "$rawUrl&t=${DateTime.now().millisecondsSinceEpoch}";
      }

      String finalAbout = _aboutController.text.trim();
      if (finalAbout.isEmpty) finalAbout = "Hi there! I am using Jembe Talk";

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'displayName': _nameController.text.trim(),
        'about': finalAbout,
        'photoUrl': photoUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update Cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_displayName', _nameController.text.trim());
      await prefs.setString('user_about', finalAbout);
      if (photoUrl != null) await prefs.setString('user_photoUrl', photoUrl);

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Update error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F171E),
      appBar: AppBar(
        title: Text(lang.t('profile_setup_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF0F171E), Color(0xFF1A252F)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter)),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.tealAccent))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildAvatarSection(),
                    const SizedBox(height: 10),
                    Text(_phoneNumber,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 14)),
                    const SizedBox(height: 30),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildCustomTextField(
                              controller: _nameController,
                              label: lang.t('profile_name_label'),
                              icon: Icons.person_outline_rounded,
                              maxLength: 20),
                          const SizedBox(height: 15),
                          _buildCustomTextField(
                              controller: _aboutController,
                              label: lang.t('profile_about_label'),
                              icon: Icons.info_outline_rounded,
                              maxLines: 2,
                              isOptional: true),
                          const SizedBox(height: 40),
                          _buildSaveButton(lang),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    ImageProvider? bgImage;
    if (_selectedImage != null)
      bgImage = FileImage(_selectedImage!);
    else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty)
      bgImage = CachedNetworkImageProvider(_currentPhotoUrl!);

    return Center(
      child: Stack(alignment: Alignment.center, children: [
        GestureDetector(
          onTap: () {
            if (bgImage != null)
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (c) => FullPhotoScreen(
                          imageUrl: _selectedImage?.path ?? _currentPhotoUrl!,
                          heroTag: 'profile-pic-edit',
                          isLocalFile: _selectedImage != null)));
          },
          child: Hero(
              tag: 'profile-pic-edit',
              child: CircleAvatar(
                  radius: 65,
                  backgroundColor: const Color(0xFF1C2935),
                  backgroundImage: bgImage,
                  child: (bgImage == null)
                      ? const Icon(Icons.person_rounded,
                          size: 65, color: Colors.white24)
                      : null)),
        ),
        Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
                onTap: _pickImage,
                child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                        color: Colors.tealAccent, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Color(0xFF0F171E), size: 20)))),
      ]),
    );
  }

  Widget _buildCustomTextField(
      {required TextEditingController controller,
      required String label,
      required IconData icon,
      int maxLines = 1,
      int? maxLength,
      bool isOptional = false}) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.tealAccent),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white10)),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.tealAccent))),
      validator: (v) => (!isOptional && (v == null || v.isEmpty))
          ? lang.t('val_required')
          : null,
    );
  }

  Widget _buildSaveButton(LanguageProvider lang) {
    return SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
            onPressed: _updateProfile,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                foregroundColor: const Color(0xFF0F171E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15))),
            child: Text(lang.t('btn_save_continue').toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold))));
  }
}
