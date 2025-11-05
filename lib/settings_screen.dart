import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/account_settings_screen.dart';
import 'package:jembe_talk/chat_settings_screen.dart';
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/edit_profile_screen.dart';
import 'package:jembe_talk/help_settings_screen.dart';
import 'package:jembe_talk/language_settings_screen.dart';
import 'package:jembe_talk/notifications_settings_screen.dart';
import 'package:jembe_talk/storage_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅✅ NONGERAHO IYI MIRONGO ✅✅

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // ✅✅ IMPINDUKA: Dukoresha variables zihariye aho gukoresha Map ✅✅
  String? _displayName;
  String? _aboutText;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserData();
  }

  // ✅✅ IMPINDUKA NTEGEREZWA KWIBUKA: Iyi function yose ndayihinduye ngo ibanze isome mu bubiko bwa telefone ✅✅
  Future<void> _loadCurrentUserData() async {
    // 1. Banza usome amakuru mu bubiko bwa telefone (cache) ako kanya
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _displayName = prefs.getString('user_displayName');
        _aboutText = prefs.getString('user_about');
        _photoUrl = prefs.getString('user_photoUrl');
      });
    }

    // 2. Hanyuma, genda urondere amakuru mashasha kuri Firebase mwibanga
    final user = _auth.currentUser;
    if (user == null) return;
    
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        // 3. Gereranya amakuru mashasha n'ayari mu bubiko
        final newDisplayName = data['displayName'];
        final newAbout = data['about'];
        final newPhotoUrl = data['photoUrl'];

        // Niba hari impinduka, vugurura UI unabike amakuru mashasha
        if (mounted && (_displayName != newDisplayName || _aboutText != newAbout || _photoUrl != newPhotoUrl)) {
          setState(() { 
            _displayName = newDisplayName;
            _aboutText = newAbout;
            _photoUrl = newPhotoUrl;
          });
          // Bika amakuru mashasha muri SharedPreferences
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      // Nta 'isLoading' igikenewe kuko UI ihita yiyerekana
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
                                  _displayName ?? "Uwukoresha Jembe Talk", 
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _aboutText ?? "Status...", 
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
                  _buildSettingsItem(icon: Icons.key, title: "Konte", subtitle: "Ibibazo vy'ibanga, umutekano...", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const AccountSettingsScreen()))),
                  _buildSettingsItem(icon: Icons.chat, title: "Ibiganiro", subtitle: "Amabara, amafoto y'inyuma", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const ChatSettingsScreen()))),
                  _buildSettingsItem(icon: Icons.notifications, title: "Udusonere", subtitle: "Amajwi y'ubutumwa", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const NotificationSettingsScreen()))),
                  _buildSettingsItem(icon: Icons.language, title: "Ururimi", subtitle: "Kirundi (Ururimi gw'igihugu)", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const LanguageSettingsScreen()))),
                  _buildSettingsItem(icon: Icons.storage, title: "Ububiko bw'Amakuru", subtitle: "Ikoreshwa rya enterineti...", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const StorageSettingsScreen()))),
                  _buildSettingsItem(
                      icon: Icons.help_outline,
                      title: "Ubufasha",
                      subtitle: "Ikigo c'ubufasha, kutwandikira",
                      onTap: () {
                        Navigator.push(context, SlideRightPageRoute(page: const HelpSettingsScreen()));
                      }),
                  const SizedBox(height: 30),
                  Center(
                    child: Column(
                      children: [
                        Text("from", style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
                        Text("JEMBE KALI.", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, letterSpacing: 2)),
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