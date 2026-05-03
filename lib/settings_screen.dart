import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // <<< PROVIDER
import 'package:jembe_talk/language_provider.dart'; // <<< LANGUAGE PROVIDER
import 'package:jembe_talk/account_settings_screen.dart';
import 'package:jembe_talk/chat_settings_screen.dart';
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/edit_profile_screen.dart';
import 'package:jembe_talk/help_settings_screen.dart';
import 'package:jembe_talk/language_settings_screen.dart';
import 'package:jembe_talk/notifications_settings_screen.dart';
import 'package:jembe_talk/storage_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String? _displayName;
  String? _aboutText;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserData();
  }

  Future<void> _loadCurrentUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _displayName = prefs.getString('user_displayName');
        _aboutText = prefs.getString('user_about');
        _photoUrl = prefs.getString('user_photoUrl');
      });
    }

    final user = _auth.currentUser;
    if (user == null) return;
    
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final newDisplayName = data['displayName'];
        final newAbout = data['about'];
        final newPhotoUrl = data['photoUrl'];

        if (mounted && (_displayName != newDisplayName || _aboutText != newAbout || _photoUrl != newPhotoUrl)) {
          setState(() { 
            _displayName = newDisplayName;
            _aboutText = newAbout;
            _photoUrl = newPhotoUrl;
          });
          await prefs.setString('user_displayName', newDisplayName);
          await prefs.setString('user_about', newAbout ?? '');
          if (newPhotoUrl != null) {
            await prefs.setString('user_photoUrl', newPhotoUrl);
          } else {
            await prefs.remove('user_photoUrl');
          }
        }
      }
    } catch (e) {
      debugPrint("Ikosa ryo kuvugurura amakuru y'umukoresha: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor;
    final lang = Provider.of<LanguageProvider>(context); // GUKORESHA PROVIDER

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(lang.t('settings')), // "Igenekereza"
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: RefreshIndicator(
              onRefresh: _loadCurrentUserData,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: InkWell(
                      onTap: () => Navigator.push(context, SlideRightPageRoute(page: const EditProfileScreen())).then((_) => _loadCurrentUserData()),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 35,
                            backgroundColor: theme.colorScheme.surface,
                            backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                            child: _photoUrl == null 
                                ? Icon(Icons.person, size: 35, color: theme.iconTheme.color) 
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _displayName ?? lang.t('default_user'), // Uwukoresha Jembe Talk
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _aboutText ?? lang.t('default_status'), // Status...
                                  style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)), 
                                  overflow: TextOverflow.ellipsis
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.qr_code, color: theme.colorScheme.secondary),
                        ],
                      ),
                    ),
                  ),
                  Divider(thickness: 0.5, color: dividerColor),
                  
                  // IBI BICE BYOSE UBU BIRI MU RURIMI
                  _buildSettingsItem(
                    icon: Icons.key, 
                    title: lang.t('settings_account'), // Konte
                    subtitle: lang.t('settings_account_sub'), 
                    onTap: () => Navigator.push(context, SlideRightPageRoute(page: const AccountSettingsScreen()))
                  ),
                  _buildSettingsItem(
                    icon: Icons.chat, 
                    title: lang.t('settings_chats'), // Ibiganiro
                    subtitle: lang.t('settings_chats_sub'), 
                    onTap: () => Navigator.push(context, SlideRightPageRoute(page: const ChatSettingsScreen()))
                  ),
                  _buildSettingsItem(
                    icon: Icons.notifications, 
                    title: lang.t('settings_notif'), // Udusonere
                    subtitle: lang.t('settings_notif_sub'), 
                    onTap: () => Navigator.push(context, SlideRightPageRoute(page: const NotificationSettingsScreen()))
                  ),
                  _buildSettingsItem(
                    icon: Icons.language, 
                    title: lang.t('settings_lang'), // Ururimi
                    subtitle: lang.t('settings_lang_sub'), 
                    onTap: () => Navigator.push(context, SlideRightPageRoute(page: const LanguageSettingsScreen()))
                  ),
                  _buildSettingsItem(
                    icon: Icons.storage, 
                    title: lang.t('settings_storage'), // Ububiko bw'Amakuru
                    subtitle: lang.t('settings_storage_sub'), 
                    onTap: () => Navigator.push(context, SlideRightPageRoute(page: const StorageSettingsScreen()))
                  ),
                  _buildSettingsItem(
                      icon: Icons.help_outline,
                      title: lang.t('settings_help'), // Ubufasha
                      subtitle: lang.t('settings_help_sub'),
                      onTap: () {
                        Navigator.push(context, SlideRightPageRoute(page: const HelpSettingsScreen()));
                      }),
                  
                  const SizedBox(height: 30),
                  Center(
                    child: Column(
                      children: [
                        Text("from", style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
                        Text("JK SYSTEM.", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingsItem({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)),
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
      onTap: onTap,
    );
  }
}