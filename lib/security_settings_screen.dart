// lib/security_settings_screen.dart (VERSION IVUGURUYE)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _showSecurityNotifications = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSecuritySetting();
  }

  Future<void> _loadSecuritySetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showSecurityNotifications = prefs.getBool('security_notifications_enabled') ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSecurityNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showSecurityNotifications = value;
    });
    await prefs.setBool('security_notifications_enabled', value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(lang.t('security_title')),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.security_outlined, size: 40, color: theme.colorScheme.secondary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          lang.t('security_intro'),
                          style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: theme.dividerColor.withAlpha(80), thickness: 0.8),
                
                SwitchListTile(
                  title: Text(
                    lang.t('security_switch_title'),
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    lang.t('security_switch_sub'),
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  value: _showSecurityNotifications,
                  onChanged: _toggleSecurityNotifications,
                  activeColor: theme.colorScheme.secondary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                ),
              ],
            ),
    );
  }
}