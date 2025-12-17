import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';

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

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception(lang.t('req_error_no_user'));
      }

      String? photoUrl;
      if (_imageFile != null) {
        final ref = _storage.ref().child('profile_pictures').child('${user.uid}.jpg');
        await ref.putFile(_imageFile!);
        photoUrl = await ref.getDownloadURL();
      }

      final userData = {
        'uid': user.uid,
        'phoneNumber': user.phoneNumber,
        'displayName': _displayNameController.text.trim(),
        'about': _aboutController.text.trim(),
        'photoUrl': photoUrl,
        'createdAt': Timestamp.now(),
      };

      await _firestore.collection('users').doc(user.uid).set(userData);

      final localUserData = Map<String, dynamic>.from(userData);
      localUserData['id'] = user.uid; 
      await _dbHelper.saveJembeContact(localUserData);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${lang.t('profile_error_save')} $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context); // Provider

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.t('profile_setup_title')), // "Tunganya Umwirondoro Wawe"
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                  child: _imageFile == null
                      ? const Icon(Icons.camera_alt, size: 50, color: Colors.grey)
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(lang.t('profile_tap_photo'), style: const TextStyle(color: Colors.grey)), // "fyonda kw'ifoto..."
              const SizedBox(height: 40),
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: lang.t('profile_name_label'), // "Izina ryawe..."
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return lang.t('profile_name_error'); // "Shiramwo izina ryawe"
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _aboutController,
                decoration: InputDecoration(
                  labelText: lang.t('profile_about_label'), // "Ibikuranga..."
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.info_outline),
                ),
                maxLength: 70,
              ),
              const SizedBox(height: 40),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _saveProfile,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(55),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                      ),
                      child: Text(lang.t('btn_save_continue'), style: const TextStyle(fontSize: 18)), // "Bika hanyuma ubandanye"
                    ),
            ],
          ),
        ),
      ),
    );
  }
}