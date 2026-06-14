// lib/profile_setup_screen.dart (VERSION 59.0 - GHOST PROTECTION & CACHE SYNC)

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:jembe_talk/full_photo_screen.dart';
import 'package:jembe_talk/home_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _phoneController = TextEditingController(); // Controller nshya niba numero ibuze

  File? _selectedImage;
  String? _currentPhotoUrl;
  String _phoneNumber = ""; 
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aboutController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // --- 1. LOAD DATA (Fata Numero muri Firestore cyangwa muri Auth) ---
  Future<void> _loadInitialData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Banza urebe muri Firestore
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    
    if (mounted) {
      setState(() {
        if (doc.exists) {
          final data = doc.data()!;
          _nameController.text = data['displayName'] ?? ''; 
          _aboutController.text = data['about'] ?? ''; 
          _currentPhotoUrl = data['photoUrl']; 
          _phoneNumber = data['phoneNumber'] ?? user.phoneNumber ?? "";
        } else {
          // Niba nta doc ihari (Ghost), koresha amakuru ari muri Firebase Auth
          _phoneNumber = user.phoneNumber ?? "";
          _nameController.text = user.displayName ?? "";
        }
        _phoneController.text = _phoneNumber;
      });
    }
  }

  // --- 2. VECTOR LOGO COMPACT ---
  Widget _buildAppLogo() {
    return Container(
      width: 60, height: 60,
      decoration: const BoxDecoration(
        color: Color(0xFF005A5A), 
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15), topRight: Radius.circular(15),
          bottomRight: Radius.circular(15), bottomLeft: Radius.circular(5),
        ),
      ),
      child: const Center(child: Icon(Icons.star_rounded, color: Colors.amber, size: 40)),
    );
  }

  // --- 3. IMAGE EDITOR LOGIC ---
  Future<void> _openImageEditor() async {
    Uint8List? imageBytes;
    if (_selectedImage != null) {
      imageBytes = await _selectedImage!.readAsBytes();
    } else if (_currentPhotoUrl != null) {
      try {
        final ByteData data = await NetworkAssetBundle(Uri.parse(_currentPhotoUrl!)).load("");
        imageBytes = data.buffer.asUint8List();
      } catch (e) { return; }
    }

    if (imageBytes != null && mounted) {
      final editedImage = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ImageEditor(image: imageBytes!)),
      );

      if (editedImage != null && editedImage is Uint8List && mounted) {
        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/setup_${DateTime.now().millisecondsSinceEpoch}.jpg').create();
        await file.writeAsBytes(editedImage);
        setState(() { _selectedImage = file; });
      }
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (pickedFile != null && mounted) {
      setState(() { _selectedImage = File(pickedFile.path); });
      _openImageEditor(); 
    }
  }

  // --- 4. SAVE PROFILE (GHOST PROTECTION + CACHE) ---
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;
    
    setState(() => _isLoading = true);
    final String c = Provider.of<LanguageProvider>(context, listen: false).currentLanguage;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      String? photoUrl = _currentPhotoUrl;

      // Upload image if changed
      if (_selectedImage != null) {
        final bytes = await _selectedImage!.readAsBytes();
        img.Image? image = img.decodeImage(bytes);
        if (image != null) {
          final compressedBytes = img.encodeJpg(image, quality: 70);
          final tempDir = await getTemporaryDirectory();
          final compressedFile = await File('${tempDir.path}/setup_final_${user.uid}.jpg').writeAsBytes(compressedBytes);
          String rawUrl = await R2Service().uploadFile(compressedFile, "profiles/${user.uid}.jpg", 'image/jpeg');
          photoUrl = "$rawUrl&t=${DateTime.now().millisecondsSinceEpoch}";
        }
      }

      String finalAbout = _aboutController.text.trim();
      if (finalAbout.isEmpty) finalAbout = AppTranslations.translate(c, 'default_status');
      
      // 🔥 SELF-HEALING: Emeza ko amakuru y'ingenzi yose yagiye muri Firestore
      final userData = {
        'uid': user.uid,
        'displayName': _nameController.text.trim(), 
        'about': finalAbout,
        'photoUrl': photoUrl,
        'email': user.email, // <--- SYNC EMAIL
        'phoneNumber': _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : _phoneNumber, // <--- SYNC PHONE
        'lastUpdated': FieldValue.serverTimestamp(),
        'isProfileComplete': true, // Flag y'uko konti yuzuye
      };

      // 1. Bika muri Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));
      
      // 2. 🔥 ACTIVATE CACHE: Bika muri SharedPreferences ngo ubutaha main.dart izahite ifunguka
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_profile_complete', true);
      await prefs.setString('user_displayName', _nameController.text.trim());
      await prefs.setString('user_about', finalAbout);
      if (photoUrl != null) await prefs.setString('user_photoUrl', photoUrl);
      
      if (mounted) { 
        HapticFeedback.mediumImpact();
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (ctx) => const HomeScreen()), (r) => false); 
      }
    } catch (e) {
      if (mounted) _showSnackBar(AppTranslations.translate(c, 'error_generic'), Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String m, Color col) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: col));

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;

    return Scaffold(
      backgroundColor: const Color(0xFF0F171E),
      appBar: AppBar(
        title: Text(AppTranslations.translate(c, 'profile_setup_title')),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        height: double.infinity, width: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0F171E), Color(0xFF1A252F)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(children: [
            const SizedBox(height: 10),
            _buildAppLogo(),
            const SizedBox(height: 25),
            _buildAvatarSection(c),
            
            // 🔥 🔥 🔥 SMART PHONE SECTION 🔥 🔥 🔥
            const SizedBox(height: 15),
            if (_phoneNumber.isNotEmpty)
              _buildPhoneDisplay(_phoneNumber) // Numero ihari, yerekane gusa
            else
              _buildPhoneInputField(c), // Ghost Account: Numero ntabwo ihari, yandike!

            const SizedBox(height: 35),
            Form(
              key: _formKey,
              child: Column(children: [
                _buildCustomTextField(
                  controller: _nameController,
                  label: AppTranslations.translate(c, 'full_name_label'), 
                  icon: Icons.person_outline_rounded,
                  maxLength: 20,
                  isOptional: false,
                ),
                const SizedBox(height: 15),
                _buildCustomTextField(
                  controller: _aboutController,
                  label: AppTranslations.translate(c, 'profile_about_label'), 
                  icon: Icons.info_outline_rounded,
                  maxLines: 2,
                  isOptional: true,
                ),
                const SizedBox(height: 40),
                _isLoading 
                  ? const CircularProgressIndicator(color: Colors.tealAccent) 
                  : SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _saveProfile, style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: const Color(0xFF0F171E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(AppTranslations.translate(c, 'btn_save_continue').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)))),
                const SizedBox(height: 30),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPhoneDisplay(String phone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.phone_android_rounded, color: Colors.tealAccent, size: 16),
        const SizedBox(width: 8),
        Text(phone, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
      ]),
    );
  }

  Widget _buildPhoneInputField(String c) {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: AppTranslations.translate(c, 'login_phone_hint'),
        prefixIcon: const Icon(Icons.phone_android, color: Colors.tealAccent, size: 20),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
      ),
      validator: (v) => (v == null || v.isEmpty) ? AppTranslations.translate(c, 'val_required') : null,
    );
  }

  Widget _buildAvatarSection(String c) {
    ImageProvider? bgImage;
    if (_selectedImage != null) bgImage = FileImage(_selectedImage!);
    else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) bgImage = CachedNetworkImageProvider(_currentPhotoUrl!);

    return Center(
      child: Stack(alignment: Alignment.center, children: [
        GestureDetector(
          onTap: () {
            if (bgImage != null) Navigator.push(context, MaterialPageRoute(builder: (c) => FullPhotoScreen(imageUrl: _selectedImage?.path ?? _currentPhotoUrl!, heroTag: 'setup-pic', isLocalFile: _selectedImage != null)));
          },
          child: Hero(tag: 'setup-pic', child: Opacity(opacity: _isLoading ? 0.5 : 1.0, child: CircleAvatar(radius: 70, backgroundColor: const Color(0xFF1C2935), backgroundImage: bgImage, child: (bgImage == null) ? const Icon(Icons.person_rounded, size: 70, color: Colors.white24) : null))),
        ),
        if (!_isLoading) Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _pickImage, child: Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.tealAccent, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF0F171E), size: 24)))),
        if (!_isLoading && bgImage != null) Positioned(top: 0, right: 0, child: GestureDetector(onTap: _openImageEditor, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle), child: const Icon(Icons.edit_rounded, color: Color(0xFF0F171E), size: 18)))),
      ]),
    );
  }

  Widget _buildCustomTextField({required TextEditingController controller, required String label, required IconData icon, int maxLines = 1, int? maxLength, bool isOptional = false}) {
    final langCode = Provider.of<LanguageProvider>(context, listen: false).currentLanguage;
    return TextFormField(
      controller: controller, maxLines: maxLines, maxLength: maxLength, textCapitalization: TextCapitalization.words,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.tealAccent, size: 22),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
        counterStyle: const TextStyle(color: Colors.white24),
      ),
      validator: (v) => (!isOptional && (v == null || v.isEmpty)) ? AppTranslations.translate(langCode, 'val_required') : null,
    );
  }
}