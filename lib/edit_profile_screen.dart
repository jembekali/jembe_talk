// lib/edit_profile_screen.dart (VERSION IKOSOYE)

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jembe_talk/full_photo_screen.dart'; // Ongeramo iyi import

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
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _nameController.text = data['displayName'] ?? data['email'] ?? '';
        _aboutController.text = data['about'] ?? '';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ikosa mu gupakira amakuru: $e")));
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await ImagePicker().pickImage(source: source, imageQuality: 80);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Guhitamo ifoto byanze: $e")));
    }
  }

  void _showImagePickerOptions() {
    if(!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Hitamo ifoto muri Gallery'),
              onTap: () {
                _pickImage(ImageSource.gallery);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Fata ifoto na Camera'),
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
    if (user == null) return;
    
    setState(() => _isSaving = true);
    
    try {
      String? newPhotoUrl = _photoUrl;
      
      if (_imageFile != null) {
        final ref = _storage.ref().child('profile_photos').child('${user.uid}.jpg');
        await ref.putFile(_imageFile!);
        newPhotoUrl = await ref.getDownloadURL();
      }
      
      await _firestore.collection('users').doc(user.uid).update({
        'displayName': _nameController.text.trim(),
        'about': _aboutController.text.trim(),
        'photoUrl': newPhotoUrl,
      });

      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Porofayili yavuguruwe neza!")));
      Navigator.of(context).pop();

    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Kubika byanze: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = 'edit-profile-pic';
    return Scaffold(
      appBar: AppBar(
        title: const Text("Guhindura Porofayili"),
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
                        // <<< IMPINDUKA ZATANGIRIYE HANO >>>
                        GestureDetector(
                          onTap: () {
                            final imageToShow = _imageFile?.path ?? _photoUrl;
                            if (imageToShow != null && mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullPhotoScreen(
                                    imageUrl: imageToShow, // Ubu dukoresheje 'imageUrl'
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
                        // <<< IMPINDUKA ZIRANGIRIYE HANO >>>
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
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: "Izina",
                      icon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _aboutController,
                    maxLength: 139,
                    decoration: const InputDecoration(
                      labelText: "Amagambo akuranga (About)",
                      icon: Icon(Icons.info_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}