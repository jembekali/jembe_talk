// lib/privacy_settings_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/about_settings_screen.dart'; // Twongereyeho iyi dosiye nshya
import 'package:jembe_talk/last_seen_settings_screen.dart';
import 'package:jembe_talk/profile_photo_settings_screen.dart'; 
import 'package:jembe_talk/services/database_helper.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  
  bool _isLoading = true;
  String _lastSeenValue = "Iratunganywa...";
  String _profilePhotoValue = "Iratunganywa...";
  String _aboutValue = "Iratunganywa...";
  String _blockedCount = "0";

  @override
  void initState() {
    super.initState();
    _refreshAllSettings();
  }
  
  Future<void> _loadAndSyncSetting({
    required String localKey,
    required String firestoreKey,
    required Function(String) updateState,
    required String defaultValue,
  }) async {
    final localValue = await _dbHelper.getSetting(localKey);
    if (mounted) {
      setState(() {
        updateState(_translatePrivacyValue(localValue ?? defaultValue));
      });
    }

    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      String firestoreValue = defaultValue;
      if (doc.exists && doc.data()!.containsKey(firestoreKey)) {
        firestoreValue = doc.data()![firestoreKey];
      }
      
      if (firestoreValue != localValue) {
        await _dbHelper.saveSetting(localKey, firestoreValue);
        if (mounted) {
          setState(() {
            updateState(_translatePrivacyValue(firestoreValue));
          });
        }
      }
    } catch (e) {
      // aha twashiramwo ubutumwa bugaragara iyo bibaye ngombwa
    }
  }

  Future<void> _refreshAllSettings() async {
    if(mounted) setState(() => _isLoading = true);

    await _loadAndSyncSetting(
      localKey: 'privacy_lastSeen',
      firestoreKey: 'lastSeenPrivacy',
      updateState: (val) => _lastSeenValue = val,
      defaultValue: 'everyone',
    );
    await _loadAndSyncSetting(
      localKey: 'privacy_profilePhoto',
      firestoreKey: 'profilePhotoPrivacy',
      updateState: (val) => _profilePhotoValue = val,
      defaultValue: 'everyone',
    );
    await _loadAndSyncSetting(
      localKey: 'privacy_about',
      firestoreKey: 'aboutPrivacy',
      updateState: (val) => _aboutValue = val,
      defaultValue: 'everyone',
    );
    
    if(mounted) setState(() => _isLoading = false);
  }
  
  String _translatePrivacyValue(String key) {
    switch (key) {
      case 'everyone': return 'Bose';
      case 'my_contacts': return 'Abo mfise';
      case 'nobody': return 'Ntanumwe';
      default: return 'Bose';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101D25),
      appBar: AppBar(
        title: const Text("Ibibazo vy'Ibanga"),
        backgroundColor: const Color(0xFF202C33),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              onRefresh: _refreshAllSettings,
              color: Colors.white,
              backgroundColor: Colors.teal,
              child: ListView(
                children: [
                  _buildSectionHeader(context, "Ninde ashobora kubona amakuru yanje?"),
                  _buildPrivacyItem(
                    context,
                    title: "Igihe waherukiye kumurongo (Last Seen)",
                    value: _lastSeenValue,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LastSeenSettingsScreen()),
                      ).then((_) => _refreshAllSettings());
                    }
                  ),
                  _buildPrivacyItem(
                    context, 
                    title: "Ifoto ya Porofile", 
                    value: _profilePhotoValue, 
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ProfilePhotoSettingsScreen()),
                      ).then((_) => _refreshAllSettings());
                    }
                  ),
                  // ==========================================================
                  // >>>>>>>>> KWIBUKA IMPINDUKA NSHASHA NAKOZE HANO <<<<<<<<<<<
                  // ==========================================================
                  _buildPrivacyItem(
                    context, 
                    title: "Amajambo akuranga (About)", 
                    value: _aboutValue, 
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AboutSettingsScreen()),
                      ).then((_) => _refreshAllSettings()); // Twahujije ipaji nshya
                    }
                  ),
                  const Divider(color: Colors.white24, thickness: 0.5),
                  _buildPrivacyItem(context, title: "Abahagaritswe (Blocked)", value: _blockedCount, onTap: () {}),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 20.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(color: Colors.tealAccent.withOpacity(0.8), fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildPrivacyItem(BuildContext context, {required String title, required String value, required VoidCallback onTap}) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(value, style: const TextStyle(color: Colors.white70)),
      onTap: onTap,
    );
  }
}