// lib/settings_screen.dart (VERSION 32.18 - RAM OPTIMIZED & NO FREEZE)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; 
import 'package:jembe_talk/language_provider.dart'; 
import 'package:jembe_talk/account_settings_screen.dart';
import 'package:jembe_talk/chat_settings_screen.dart';
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/edit_profile_screen.dart';
import 'package:jembe_talk/help_settings_screen.dart';
import 'package:jembe_talk/language_settings_screen.dart';
import 'package:jembe_talk/notifications_settings_screen.dart';
import 'package:jembe_talk/storage_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 🔥 ONGEZA IYI IMPORT
import 'package:cached_network_image/cached_network_image.dart';

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
    final lang = Provider.of<LanguageProvider>(context); 

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(lang.t('settings')), 
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
                    // 🔥 OPTIMIZED PROFILE IMAGE (ZERO FREEZE)
                    _buildOptimizedProfileImage(theme),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName ?? lang.t('default_user'), 
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _aboutText ?? lang.t('default_status'), 
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
            
            _buildSettingsItem(
              icon: Icons.key, 
              title: lang.t('settings_account'), 
              subtitle: lang.t('settings_account_sub'), 
              onTap: () => Navigator.push(context, SlideRightPageRoute(page: const AccountSettingsScreen()))
            ),
            _buildSettingsItem(
              icon: Icons.chat, 
              title: lang.t('settings_chats'), 
              subtitle: lang.t('settings_chats_sub'), 
              onTap: () => Navigator.push(context, SlideRightPageRoute(page: const ChatSettingsScreen()))
            ),
            _buildSettingsItem(
              icon: Icons.notifications, 
              title: lang.t('settings_notif'), 
              subtitle: lang.t('settings_notif_sub'), 
              onTap: () => Navigator.push(context, SlideRightPageRoute(page: const NotificationSettingsScreen()))
            ),
            _buildSettingsItem(
              icon: Icons.language, 
              title: lang.t('settings_lang'), 
              subtitle: lang.t('settings_lang_sub'), 
              onTap: () => Navigator.push(context, SlideRightPageRoute(page: const LanguageSettingsScreen()))
            ),
            _buildSettingsItem(
              icon: Icons.storage, 
              title: lang.t('settings_storage'), 
              subtitle: lang.t('settings_storage_sub'), 
              onTap: () => Navigator.push(context, SlideRightPageRoute(page: const StorageSettingsScreen()))
            ),
            _buildSettingsItem(
                icon: Icons.help_outline,
                title: lang.t('settings_help'), 
                subtitle: lang.t('settings_help_sub'),
                onTap: () => Navigator.push(context, SlideRightPageRoute(page: const HelpSettingsScreen()))
            ),
            
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

  // --- 🔥 OPTIMIZATION FUNCTION ---
  Widget _buildOptimizedProfileImage(ThemeData theme) {
    if (_photoUrl == null || _photoUrl!.isEmpty) {
      return CircleAvatar(
        radius: 35,
        backgroundColor: theme.colorScheme.surface,
        child: Icon(Icons.person, size: 35, color: theme.iconTheme.color),
      );
    }

    return CachedNetworkImage(
      imageUrl: _photoUrl!,
      memCacheWidth: 300, // 🔥 Important: Ifoto ntifate RAM nini
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: 35,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: 35,
        backgroundColor: theme.colorScheme.surface,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (context, url, error) => CircleAvatar(
        radius: 35,
        backgroundColor: theme.colorScheme.surface,
        child: const Icon(Icons.person, size: 35),
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