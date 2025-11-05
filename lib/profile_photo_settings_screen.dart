// lib/profile_photo_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/services/database_helper.dart';

class ProfilePhotoSettingsScreen extends StatefulWidget {
  const ProfilePhotoSettingsScreen({super.key});

  @override
  State<ProfilePhotoSettingsScreen> createState() => _ProfilePhotoSettingsScreenState();
}

class _ProfilePhotoSettingsScreenState extends State<ProfilePhotoSettingsScreen> {
  // Dutanguza ibikoresho vyacu
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  String? _currentSelection; // ('everyone', 'my_contacts', 'nobody')
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSetting();
  }

  /// Soma agaciro kari muri database ya telefone
  Future<void> _loadCurrentSetting() async {
    // Ubu dusoma 'privacy_profilePhoto'
    final value = await _dbHelper.getSetting('privacy_profilePhoto');
    if (mounted) {
      setState(() {
        _currentSelection = value ?? 'everyone';
      });
    }
  }

  /// Bika ihitamwo rishasha muri telefone no kuri internet
  Future<void> _updateSetting(String newValue) async {
    if (_auth.currentUser == null) return;
    if (mounted) setState(() => _isSaving = true);

    setState(() => _currentSelection = newValue);
    // Ubu tubika muri 'privacy_profilePhoto'
    await _dbHelper.saveSetting('privacy_profilePhoto', newValue);

    try {
      await _firestore.collection('users').doc(_auth.currentUser!.uid).set(
        // Ubu duhindura 'profilePhotoPrivacy' kuri Firestore
        { 'profilePhotoPrivacy': newValue },
        SetOptions(merge: true),
      );
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Ivyahinduwe vyabitswe neza."),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
       if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Habayeho ikibazo mu kubika, ongera ugerageze: $e"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101D25),
      appBar: AppBar(
        // Twahinduye umutwe w'ipaji
        title: const Text("Ifoto ya Porofile"),
        backgroundColor: const Color(0xFF202C33),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 20.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white,))),
            ),
        ],
      ),
      body: _currentSelection == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Twahinduye umutwe w'igice
                _buildSectionHeader(context, "Ninde ashobora kubona ifoto yanje ya porofile?"),
                _buildRadioOption(
                  context,
                  title: 'Bose',
                  value: 'everyone',
                ),
                _buildRadioOption(
                  context,
                  title: 'Abo mfise gusa',
                  value: 'my_contacts',
                ),
                _buildRadioOption(
                  context,
                  title: 'Ntanumwe',
                  value: 'nobody',
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 20.0, bottom: 8.0, right: 16.0),
      child: Text(
        title,
        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
      ),
    );
  }

  Widget _buildRadioOption(BuildContext context, {required String title, required String value}) {
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      value: value,
      groupValue: _currentSelection,
      onChanged: (selectedValue) {
        if (selectedValue != null && !_isSaving) {
          _updateSetting(selectedValue);
        }
      },
      activeColor: Colors.tealAccent,
      tileColor: Colors.white.withOpacity(0.05),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}