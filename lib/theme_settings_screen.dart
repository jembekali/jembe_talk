// Fayili: lib/theme_settings_screen.dart
// IYI NI VERSION NSHASHA YAKOSOWE IKIBABO C'UMUTUKU (FONTSIZE NULL ERROR)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/theme_manager.dart';
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final lang = Provider.of<LanguageProvider>(context);
    
    // Amabara rusange
    const Color backgroundColor = Color(0xFF101D25);
    const Color appBarColor = Color(0xFF202C33);
    const Color textColor = Colors.white;
    const Color activeColor = Colors.tealAccent;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(lang.t('theme_title')), // "Amabara"
        backgroundColor: appBarColor,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              lang.t('theme_header'), // "Hitamo uko..."
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          RadioListTile<ThemeMode>(
            // << IMPINDUKA HANO: Twongeyemwo 'fontSize' >>
            title: Text(lang.t('theme_light'), style: const TextStyle(color: textColor, fontSize: 16.0)),
            value: ThemeMode.light,
            groupValue: themeManager.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) themeManager.setThemeMode(value);
            },
            activeColor: activeColor,
          ),
          RadioListTile<ThemeMode>(
            // << IMPINDUKA HANO: Twongeyemwo 'fontSize' >>
            title: Text(lang.t('theme_dark'), style: const TextStyle(color: textColor, fontSize: 16.0)),
            value: ThemeMode.dark,
            groupValue: themeManager.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) themeManager.setThemeMode(value);
            },
            activeColor: activeColor,
          ),
          RadioListTile<ThemeMode>(
            // << IMPINDUKA HANO: Twongeyemwo 'fontSize' >>
            title: Text(lang.t('theme_system'), style: const TextStyle(color: textColor, fontSize: 16.0)),
            subtitle: Text(lang.t('theme_system_sub'), style: const TextStyle(color: Colors.white70)),
            value: ThemeMode.system,
            groupValue: themeManager.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) themeManager.setThemeMode(value);
            },
            activeColor: activeColor,
          ),
        ],
      ),
    );
  }
}