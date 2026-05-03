// lib/tangaza_star/profile_setup_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as img; 
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:jembe_talk/full_photo_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _aboutController = TextEditingController();
  File? _imageFile;
  bool _isLoading = false;

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (pickedFile != null) setState(() => _imageFile = File(pickedFile.path));
  }

  Future<File> _compressImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return file;

      if (image.width > 500) {
        image = img.copyResize(image, width: 500);
      }

      final compressedBytes = img.encodeJpg(image, quality: 60); 
      final tempDir = await getTemporaryDirectory();
      final compressedFile = File('${tempDir.path}/prof_comp_${DateTime.now().millisecondsSinceEpoch}.jpg');
      return await compressedFile.writeAsBytes(compressedBytes);
    } catch (e) {
      return file;
    }
  }

  Future<void> _saveProfile() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    
    // 1. Genzura gusa 'Display Name' kuko 'About' ubu ni optional
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? photoUrl;
      if (_imageFile != null) {
        File compressedFile = await _compressImage(_imageFile!);
        photoUrl = await R2Service().uploadFile(compressedFile, "profiles/${user.uid}.jpg", 'image/jpeg');
        if (compressedFile.path.contains('prof_comp_')) await compressedFile.delete();
      }

      // <<<--- NYAMURURU: DEFAULT ABOUT LOGIC --->>>
      String finalAbout = _aboutController.text.trim();
      if (finalAbout.isEmpty) {
        finalAbout = "Hi there! I am using Jembe Talk";
      }

      final userData = {
        'displayName': _displayNameController.text.trim(),
        'about': finalAbout, // Koresha rya jambo rishya niba ahasigaye ubusa
        'photoUrl': photoUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));

      final localData = Map<String, dynamic>.from(userData);
      localData['id'] = user.uid;
      localData['phoneNumber'] = user.phoneNumber;
      await DatabaseHelper.instance.saveJembeContact(localData);

      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const HomeScreen()), (r) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(
        title: Text(lang.t('profile_setup_title')),
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30.0),
        child: Form(
          key: _formKey,
          child: Column(children: [
            const SizedBox(height: 20),
            Center(
              child: Stack(children: [
                GestureDetector(
                  onTap: () {
                    if (_imageFile != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => FullPhotoScreen(imageUrl: _imageFile!.path, heroTag: 'setup-pic', isLocalFile: true)));
                    }
                  },
                  child: Hero(tag: 'setup-pic', child: CircleAvatar(radius: 75, backgroundColor: Colors.white10, backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null, child: _imageFile == null ? const Icon(Icons.person, size: 80, color: Colors.white24) : null)),
                ),
                Positioned(bottom: 5, right: 5, child: GestureDetector(onTap: _pickImage, child: Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.tealAccent, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Color(0xFF1C2935), size: 24)))),
              ]),
            ),
            const SizedBox(height: 15),
            Text(lang.t('profile_tap_photo'), style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 50),
            
            // Izina rigomba kuzuuzwa (Mandatory)
            _buildField(_displayNameController, lang.t('profile_name_label'), Icons.person_outline, isOptional: false, maxLength: 13), 
            
            const SizedBox(height: 20),
            
            // About ubu ni optional
            _buildField(_aboutController, lang.t('profile_about_label'), Icons.info_outline, isOptional: true, maxLines: 2), 
            
            const SizedBox(height: 50),
            _isLoading 
              ? const CircularProgressIndicator(color: Colors.tealAccent) 
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E8449), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
                  onPressed: _saveProfile, 
                  child: Text(lang.t('btn_save_continue').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))
                ),
          ]),
        ),
      ),
    );
  }

  // Nafashe ya method nshyiramo parameter ya 'isOptional'
  Widget _buildField(TextEditingController ctrl, String label, IconData icon, {int maxLines = 1, int? maxLength, bool isOptional = false}) {
    return TextFormField(
      controller: ctrl, 
      maxLines: maxLines, 
      maxLength: maxLength,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(color: Colors.white), 
      decoration: InputDecoration(
        labelText: label, 
        labelStyle: const TextStyle(color: Colors.white60), 
        prefixIcon: Icon(icon, color: Colors.tealAccent), 
        filled: true, 
        fillColor: Colors.white.withOpacity(0.05), 
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        counterStyle: const TextStyle(color: Colors.white24, fontSize: 10),
      ), 
      // Niba isOptional ari true, ntibizabaza ko 'v.isEmpty'
      validator: (v) {
        if (isOptional) return null;
        return (v == null || v.isEmpty) ? "Andika hano" : null;
      }
    );
  }
}