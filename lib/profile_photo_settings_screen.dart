import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:jembe_talk/services/database_helper.dart';

class ProfilePhotoSettingsScreen extends StatefulWidget {
  const ProfilePhotoSettingsScreen({super.key});

  @override
  State<ProfilePhotoSettingsScreen> createState() => _ProfilePhotoSettingsScreenState();
}

class _ProfilePhotoSettingsScreenState extends State<ProfilePhotoSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  String? _currentSelection; 
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSetting();
  }

  Future<void> _loadCurrentSetting() async {
    final value = await _dbHelper.getSetting('privacy_profilePhoto');
    if (mounted) {
      setState(() {
        _currentSelection = value ?? 'everyone';
      });
    }
  }

  Future<void> _updateSetting(String newValue) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_auth.currentUser == null) return;
    if (mounted) setState(() => _isSaving = true);

    setState(() => _currentSelection = newValue);
    await _dbHelper.saveSetting('privacy_profilePhoto', newValue);

    try {
      await _firestore.collection('users').doc(_auth.currentUser!.uid).set(
        { 'profilePhotoPrivacy': newValue },
        SetOptions(merge: true),
      );
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang.t('privacy_saved')), 
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
       if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${lang.t('privacy_save_error')} $e"),
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
    final lang = Provider.of<LanguageProvider>(context); // Provider

    return Scaffold(
      backgroundColor: const Color(0xFF101D25),
      appBar: AppBar(
        title: Text(lang.t('photo_privacy_title')), // "Ifoto ya Porofile"
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
                _buildSectionHeader(context, lang.t('photo_privacy_header')), // "Ninde ashobora..."
                _buildRadioOption(
                  context,
                  title: lang.t('privacy_everyone'), // "Bose"
                  value: 'everyone',
                ),
                _buildRadioOption(
                  context,
                  title: lang.t('privacy_contacts'), // "Abo mfite gusa"
                  value: 'my_contacts',
                ),
                _buildRadioOption(
                  context,
                  title: lang.t('privacy_nobody'), // "Ntawe"
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