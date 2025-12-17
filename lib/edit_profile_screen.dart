// lib/edit_profile_screen.dart (YAKOSOWE: Theme Adaptive)

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart'; 
import 'package:jembe_talk/language_provider.dart'; 
import 'package:jembe_talk/full_photo_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _aboutController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(); 
  
  String? _photoUrl;
  bool _isLoading = true;
  bool _isSaving = false;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _nameController.text = data['displayName'] ?? data['email'] ?? '';
        _aboutController.text = data['about'] ?? '';
        
        // Gushira numero muri controller
        String phoneNumber = data['phoneNumber'] ?? user.phoneNumber ?? '';
        _phoneController.text = phoneNumber;

        if (mounted) {
          setState(() {
            _photoUrl = data['photoUrl'];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('profile_error_load')} $e")));
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    try {
      final pickedFile = await ImagePicker().pickImage(source: source, imageQuality: 80);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('error_generic')} $e")));
    }
  }

  void _showImagePickerOptions() {
    if(!mounted) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(lang.t('profile_pick_gallery')), 
              onTap: () {
                _pickImage(ImageSource.gallery);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(lang.t('profile_pick_camera')), 
              onTap: () {
                _pickImage(ImageSource.camera);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (user == null) return;
    
    setState(() => _isSaving = true);
    
    try {
      String? newPhotoUrl = _photoUrl;
      
      if (_imageFile != null) {
        final ref = _storage.ref().child('profile_pictures').child('${user.uid}.jpg');
        await ref.putFile(_imageFile!);
        newPhotoUrl = await ref.getDownloadURL();
      }
      
      await _firestore.collection('users').doc(user.uid).update({
        'displayName': _nameController.text.trim(),
        'about': _aboutController.text.trim(),
        'photoUrl': newPhotoUrl,
      });

      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('profile_updated'))));
      Navigator.of(context).pop();

    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('profile_error_save')} $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = 'edit-profile-pic';
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    
    // <<< HANO: Turagenzura niba ari Dark Mode canke Light Mode
    final isDarkMode = theme.brightness == Brightness.dark;
    
    // Amabara duhitamo gukoresha
    final readOnlyFillColor = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade100;
    final helperTextColor = isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.t('profile_edit_title')),
        backgroundColor: Colors.teal,
        actions: [
          _isSaving 
            ? const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)))
            : IconButton(icon: const Icon(Icons.save), onPressed: _saveProfile)
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: () {
                            final imageToShow = _imageFile?.path ?? _photoUrl;
                            if (imageToShow != null && mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullPhotoScreen(
                                    imageUrl: imageToShow,
                                    heroTag: heroTag,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Hero(
                            tag: heroTag,
                            child: CircleAvatar(
                              radius: 70,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: _imageFile != null 
                                  ? FileImage(_imageFile!) 
                                  : (_photoUrl != null ? NetworkImage(_photoUrl!) : null) as ImageProvider?,
                              child: _imageFile == null && _photoUrl == null
                                  ? const Icon(Icons.person, size: 70, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: Colors.teal,
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt, color: Colors.white),
                              onPressed: _showImagePickerOptions,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Izina
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: lang.t('profile_name_label'), 
                      icon: const Icon(Icons.person),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Ibikuranga
                  TextField(
                    controller: _aboutController,
                    maxLength: 139,
                    decoration: InputDecoration(
                      labelText: lang.t('profile_about_label'),
                      icon: const Icon(Icons.info_outline),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  
                  const SizedBox(height: 10),

                  // <<< NUMERO YA TELEFONE (Irakurikiza Theme)
                  TextField(
                    controller: _phoneController,
                    readOnly: true, 
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color), // Ibara ry'inyandiko
                    decoration: InputDecoration(
                      labelText: "Numero ya Telefone", 
                      icon: Icon(Icons.phone, color: theme.iconTheme.color),
                      labelStyle: TextStyle(color: theme.textTheme.bodyMedium?.color),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: readOnlyFillColor, // Ibara ry'inyuma rihinduka
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Agasobanuro gato
                  Text(
                    "Numero yawe ntiushobora kuyihindurira hano.",
                    style: TextStyle(color: helperTextColor, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}