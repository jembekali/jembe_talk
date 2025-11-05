// lib/font_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/theme_manager.dart';

class FontSettingsScreen extends StatelessWidget {
  const FontSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context, listen: true);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Uko Indome zimeze"),
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: ListView(
        children: [
          _buildSectionHeader(context, "Uko Indome zingana"),
          _buildFontSizeSlider(context, themeManager),
          
          const SizedBox(height: 20),
          Divider(color: theme.dividerColor),
          
          _buildSectionHeader(context, "Ubwoko bw'Indome"),
          RadioListTile<String>(
            title: Text("Ibisanzwe (System Default)", style: TextStyle(fontFamily: 'SystemDefault', color: theme.textTheme.bodyLarge?.color)),
            value: 'SystemDefault',
            groupValue: themeManager.fontFamily,
            onChanged: (value) => themeManager.setFontFamily(value!),
            activeColor: theme.colorScheme.secondary,
          ),
          RadioListTile<String>(
            title: Text("Roboto", style: TextStyle(fontFamily: 'Roboto', color: theme.textTheme.bodyLarge?.color)),
            value: 'Roboto',
            groupValue: themeManager.fontFamily,
            onChanged: (value) => themeManager.setFontFamily(value!),
            activeColor: theme.colorScheme.secondary,
          ),
          RadioListTile<String>(
            title: Text("Lato", style: TextStyle(fontFamily: 'Lato', color: theme.textTheme.bodyLarge?.color)),
            value: 'Lato',
            groupValue: themeManager.fontFamily,
            onChanged: (value) => themeManager.setFontFamily(value!),
            activeColor: theme.colorScheme.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 20.0, bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildFontSizeSlider(BuildContext context, ThemeManager themeManager) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Ntoya", style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color)),
              Text("Nini", style: TextStyle(fontSize: 20, color: Theme.of(context).textTheme.bodyMedium?.color)),
            ],
          ),
          Slider(
            value: themeManager.fontSizeMultiplier,
            min: 0.85, // Ntoya
            max: 1.2,  // Nini
            divisions: 4, // Tuzogira ingano 5
            label: themeManager.fontSizeLabel,
            onChanged: (value) {
              themeManager.setFontSize(value);
            },
            activeColor: Theme.of(context).colorScheme.secondary,
          ),
        ],
      ),
    );
  }
}