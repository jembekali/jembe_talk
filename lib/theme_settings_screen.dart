// lib/theme_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/theme_manager.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF101D25),
      appBar: AppBar(
        title: const Text("Amabara"),
        backgroundColor: const Color(0xFF202C33),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Hitamo uko porogaramu igaragara",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          RadioListTile<ThemeMode>(
            title: const Text("Umuco (Light)", style: TextStyle(color: Colors.white)),
            value: ThemeMode.light,
            groupValue: themeManager.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) themeManager.setThemeMode(value);
            },
            activeColor: Colors.tealAccent,
          ),
          RadioListTile<ThemeMode>(
            title: const Text("Umwijima (Dark)", style: TextStyle(color: Colors.white)),
            value: ThemeMode.dark,
            groupValue: themeManager.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) themeManager.setThemeMode(value);
            },
            activeColor: Colors.tealAccent,
          ),
          RadioListTile<ThemeMode>(
            title: const Text("Uko Telefone Iteye (System default)", style: TextStyle(color: Colors.white)),
            subtitle: Text("Porogaramu izoza irahinduka uko telefone yawe ihindutse", style: TextStyle(color: Colors.white70)),
            value: ThemeMode.system,
            groupValue: themeManager.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) themeManager.setThemeMode(value);
            },
            activeColor: Colors.tealAccent,
          ),
        ],
      ),
    );
  }
}