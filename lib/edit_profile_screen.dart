
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

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('user_displayName') ?? '';
      _aboutController.text = prefs.getString('user_about') ?? '';
      _currentPhotoUrl = prefs.getString('user_photoUrl');
    });

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists && mounted) {
      final data = doc.data()!;
      setState(() { 
        _nameController.text = data['displayName'] ?? ''; 
        _aboutController.text = data['about'] ?? ''; 
        _currentPhotoUrl = data['photoUrl']; 
        _phoneNumber = data['phoneNumber'] ?? ""; 
      });
    }
  }

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

      if (editedImage != null && editedImage is Uint8List) {
        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg').create();
        await file.writeAsBytes(editedImage);
        setState(() { _selectedImage = file; });
      }
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (pickedFile != null) {
      setState(() { _selectedImage = File(pickedFile.path); });
    }
  }

  Future<void> _handleDeletePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);
    try {
      await R2Service().deleteFile("profiles/${user.uid}.jpg");
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'photoUrl': null});
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_photoUrl');
      setState(() { _currentPhotoUrl = null; _selectedImage = null; });
    } catch (e) {
      debugPrint("Delete Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    // 1. Genzura validator (Ubu izina gusa ni ryo rya ngombwa)
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      String? photoUrl = _currentPhotoUrl;

      if (_selectedImage != null) {
        final bytes = await _selectedImage!.readAsBytes();
        img.Image? image = img.decodeImage(bytes);
        if (image != null) {
          final compressedBytes = img.encodeJpg(image, quality: 70);
          final tempDir = await getTemporaryDirectory();
          final compressedFile = await File('${tempDir.path}/upd_${user.uid}.jpg').writeAsBytes(compressedBytes);
          String rawUrl = await R2Service().uploadFile(compressedFile, "profiles/${user.uid}.jpg", 'image/jpeg');
          photoUrl = "$rawUrl&t=${DateTime.now().millisecondsSinceEpoch}";
        }
      }

      // <<<--- LOGIC YA DEFAULT ABOUT --->>>
      String finalAbout = _aboutController.text.trim();
      if (finalAbout.isEmpty) {
        finalAbout = "Hi there! I am using Jembe Talk";
      }
      
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'displayName': _nameController.text.trim(), 
        'about': finalAbout, // Koresha jambo rya default niba ari ubusa
        'photoUrl': photoUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_displayName', _nameController.text.trim());
      await prefs.setString('user_about', finalAbout);
      if (photoUrl != null) await prefs.setString('user_photoUrl', photoUrl);
      
      if (mounted) { 
        HapticFeedback.mediumImpact();
        Navigator.pop(context); 
      }
    } catch (e) {
      debugPrint("$e");
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
        title: Text(lang.t('profile_setup_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      ),
      body: Container(
        height: double.infinity, width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F171E), Color(0xFF1A252F)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          )
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildAvatarSection(),
              const SizedBox(height: 10),
              Text(_phoneNumber, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
              const SizedBox(height: 30),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildCustomTextField(
                      controller: _nameController,
                      label: lang.t('profile_name_label'), 
                      icon: Icons.person_outline_rounded,
                      maxLength: 15,
                      isOptional: false, // Izina rirakenewe
                    ),
                    const SizedBox(height: 15),
                    _buildCustomTextField(
                      controller: _aboutController,
                      label: lang.t('profile_about_label'), 
                      icon: Icons.info_outline_rounded,
                      maxLines: 2,
                      isOptional: true, // "About" ishobora gusimbukwa
                    ),
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
    if (_selectedImage != null) {
      bgImage = FileImage(_selectedImage!);
    } else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      bgImage = CachedNetworkImageProvider(_currentPhotoUrl!);
    }

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: () {
              if (bgImage != null) {
                String path = _selectedImage?.path ?? _currentPhotoUrl!;
                Navigator.push(context, MaterialPageRoute(builder: (c) => FullPhotoScreen(imageUrl: path, heroTag: 'profile-pic-edit', isLocalFile: _selectedImage != null)));
              }
            },
            child: Hero(
              tag: 'profile-pic-edit',
              child: Opacity(
                opacity: _isLoading ? 0.5 : 1.0, 
                child: CircleAvatar(
                  radius: 65,
                  backgroundColor: const Color(0xFF1C2935),
                  backgroundImage: bgImage,
                  child: (bgImage == null) ? const Icon(Icons.person_rounded, size: 65, color: Colors.white24) : null,
                ),
              ),
            ),
          ),
          if (_isLoading)
            const SizedBox(
              height: 65, width: 65,
              child: CircularProgressIndicator(color: Colors.tealAccent, strokeWidth: 3),
            ),
          if (!_isLoading)
            Positioned(
              bottom: 0, right: 0,
              child: GestureDetector(
                onTap: () { HapticFeedback.lightImpact(); _showImageOptions(); },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Colors.tealAccent, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF0F171E), size: 20),
                ),
              ),
            ),
          if (!_isLoading && (bgImage != null))
            Positioned(
              top: 0, right: 0,
              child: GestureDetector(
                onTap: () { HapticFeedback.lightImpact(); _openImageEditor(); },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded, color: Color(0xFF0F171E), size: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomTextField({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    int maxLines = 1, 
    int? maxLength,
    bool isOptional = false, // Parameter nshya
  }) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.tealAccent, size: 22),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
        counterStyle: const TextStyle(color: Colors.white24),
      ),
      validator: (v) {
        if (isOptional) return null; // Niba ari optional, ntacyo ubaza
        return (v == null || v.isEmpty) ? lang.t('val_required') : null;
      },
    );
  }

  Widget _buildSaveButton(LanguageProvider lang) {
    return SizedBox(
      width: double.infinity, height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _updateProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.tealAccent,
          foregroundColor: const Color(0xFF0F171E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: _isLoading
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F171E)))
          : Text(lang.t('btn_save_continue').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
    );
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A252F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            InkWell(
              onTap: () { Navigator.pop(context); _pickImage(); },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_rounded, color: Colors.tealAccent, size: 45),
                  SizedBox(height: 8),
                  Text("Gallery", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            if (_currentPhotoUrl != null || _selectedImage != null)
              InkWell(
                onTap: () { Navigator.pop(context); _handleDeletePhoto(); },
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 45),
                    SizedBox(height: 8),
                    Text("Delete", style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}