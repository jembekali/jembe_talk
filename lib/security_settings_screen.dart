// Code ya: JEMBE TALK APP
// Dosiye: lib/security_settings_screen.dart

import 'package:flutter/material.dart';
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

  // Turasoma muri SharedPreferences kugira ngo tumenye ihitamwo ry'umukiriya wacu.
  Future<void> _loadSecuritySetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // Niba ataco turabika, dufata 'true' nk'ihitamwo ry'intango.
        _showSecurityNotifications = prefs.getBool('security_notifications_enabled') ?? true;
        _isLoading = false;
      });
    }
  }

  // Iyo umukoresha ahinduye, duca tubika ihitamwo ryiwe
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Umutekano"),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              children: [
                // Agace ko gusobanura akamaro k'iki gice
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.security_outlined, size: 40, color: theme.colorScheme.secondary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          "Jembe Talk iritwararika umutekano wawe. Twokumenyesha kugira ngo ubashe gukingira konte yawe neza.",
                          style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: theme.dividerColor.withAlpha(80), thickness: 0.8),
                
                // Akabuto ko guhindura
                SwitchListTile(
                  title: Text(
                    "Erekana notification y'umutekano",
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    "Rungika ubutumwa iyo umuntu agerageje kwinjira muri konti yawe ari kuyindi telefone canke iyo habaye impinduka zihambaye.",
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