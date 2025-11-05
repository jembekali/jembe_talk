// Code ya: JEMBE TALK APP
// Dosiye: lib/chat_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/font_settings_screen.dart';
import 'package:jembe_talk/theme_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});
  @override State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _wallpaperPath;
  bool _isLoading = true;
  bool _enterIsSend = false;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _wallpaperPath = prefs.getString('wallpaperPath');
        _enterIsSend = prefs.getBool('enterIsSend') ?? false;
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePickWallpaper() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('wallpaperPath', pickedFile.path);
        if (mounted) {
          setState(() => _wallpaperPath = pickedFile.path);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ifoto y'inyuma yahinduwe neza."), backgroundColor: Colors.green));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Habaye ikibazo mu gutoranya ifoto."), backgroundColor: Colors.redAccent));
      }
    }
  }
  
  Future<void> _handleRemoveWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallpaperPath');
    if (mounted) {
      setState(() => _wallpaperPath = null);
    }
  }
  
  Future<void> _toggleEnterIsSend(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _enterIsSend = value);
    await prefs.setBool('enterIsSend', value);
  }

  void _showWallpaperOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Ifoto y'Inyuma"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Hindura ifoto'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _handlePickWallpaper();
                  }),
              if (_wallpaperPath != null && _wallpaperPath!.isNotEmpty)
                ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: const Text('Futa ifoto', style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _handleRemoveWallpaper();
                    }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("REKA"),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Ibiganiro"),
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView(
        children: [
          _buildSectionHeader(context, "Ingene bigaragara"),
          _buildSettingsItem(context, icon: Icons.color_lens_outlined, title: "Amabara (Theme)", subtitle: "Hindura umwijima n'umuco", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const ThemeSettingsScreen()))),
          _buildSettingsItem(context, icon: Icons.wallpaper_outlined, title: "Ifoto y'inyuma", subtitle: "Hindura ifoto igaragara inyuma y'ibiganiro", onTap: () => _showWallpaperOptions(context)),
          
          const Divider(thickness: 0.5),
          _buildSectionHeader(context, "Intunganyo y'ibiganiro"),
          
          SwitchListTile(
            title: Text("Enter ni yo yo kurungika", style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
            subtitle: Text("Iyo bifashwe, akabuto ka Enter karungika ubutumwa", style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            value: _enterIsSend,
            onChanged: _toggleEnterIsSend,
            secondary: Icon(Icons.keyboard_return, color: theme.textTheme.bodyMedium?.color),
            activeColor: theme.colorScheme.secondary,
          ),
          
          _buildSettingsItem(
            context,
            icon: Icons.font_download_outlined,
            title: "Uko indome zingana", 
            subtitle: "Ingano n'ubwoko vy'indome",
            onTap: () => Navigator.push(context, SlideRightPageRoute(page: const FontSettingsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 20.0, bottom: 8.0),
      child: Text(title.toUpperCase(), style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
  
  Widget _buildSettingsItem(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.textTheme.bodyMedium?.color),
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
      onTap: onTap,
    );
  }
}