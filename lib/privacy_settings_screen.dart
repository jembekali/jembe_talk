import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:jembe_talk/about_settings_screen.dart'; 
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
  String _lastSeenValue = "loading"; // default keys
  String _profilePhotoValue = "loading";
  String _aboutValue = "loading";
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
    // Hano tubika "Key" (nka 'everyone') aho kubika ijambo (nka 'Bose')
    if (mounted) {
      setState(() {
        updateState(localValue ?? defaultValue); 
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
            updateState(firestoreValue);
          });
        }
      }
    } catch (e) {
      // ignore error
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
  
  // Iyi function ihindura key ikayijyana mu rurimi rukwiye
  String _translatePrivacyValue(String key, LanguageProvider lang) {
    if (key == 'loading') return lang.t('privacy_loading');
    if (key == 'everyone') return lang.t('privacy_everyone'); // Bose
    if (key == 'my_contacts') return lang.t('privacy_contacts'); // Abo mfise
    if (key == 'nobody') return lang.t('privacy_nobody'); // Ntanumwe
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context); // Provider

    return Scaffold(
      backgroundColor: const Color(0xFF101D25),
      appBar: AppBar(
        title: Text(lang.t('privacy_title')), // "Ibibazo vy'Ibanga"
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
                  _buildSectionHeader(context, lang.t('privacy_header')), // "NINDE ASHOBORA..."
                  _buildPrivacyItem(
                    context,
                    title: lang.t('privacy_last_seen'), // "Igihe waherukiye..."
                    value: _translatePrivacyValue(_lastSeenValue, lang),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LastSeenSettingsScreen()),
                      ).then((_) => _refreshAllSettings());
                    }
                  ),
                  _buildPrivacyItem(
                    context, 
                    title: lang.t('privacy_profile_photo'), // "Ifoto ya Porofile"
                    value: _translatePrivacyValue(_profilePhotoValue, lang),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ProfilePhotoSettingsScreen()),
                      ).then((_) => _refreshAllSettings());
                    }
                  ),
                  _buildPrivacyItem(
                    context, 
                    title: lang.t('privacy_about'), // "Amajambo akuranga"
                    value: _translatePrivacyValue(_aboutValue, lang),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AboutSettingsScreen()),
                      ).then((_) => _refreshAllSettings()); 
                    }
                  ),
                  const Divider(color: Colors.white24, thickness: 0.5),
                  _buildPrivacyItem(
                    context, 
                    title: lang.t('privacy_blocked'), // "Abahagaritswe"
                    value: _blockedCount, 
                    onTap: () {}
                  ),
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