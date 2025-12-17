// Fayili: lib/font_settings_screen.dart
// IYI NI VERSION NSHASHA ITUNGANIJE NEZA (ARIRO UMUTI NYAKURI URI MURI THEME_MANAGER)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/theme_manager.dart';
import 'package:jembe_talk/language_provider.dart';

class FontSettingsScreen extends StatelessWidget {
  const FontSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context, listen: true);
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);

    double sliderValue = themeManager.fontSizeMultiplier.clamp(0.85, 1.2);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          lang.t('font_title'),
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20.0,
          ),
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        iconTheme: IconThemeData(color: theme.iconTheme.color),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          _buildSectionHeader(context, lang.t('font_size_header')),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      lang.t('font_size_small'),
                      style: TextStyle(
                        fontSize: 14.0,
                        color: theme.textTheme.bodyMedium?.color
                      ),
                    ),
                    Text(
                      lang.t('font_size_large'),
                      style: TextStyle(
                        fontSize: 24.0,
                        color: theme.textTheme.bodyMedium?.color
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                
                Slider(
                  value: sliderValue,
                  min: 0.85,
                  max: 1.2,
                  divisions: 4,
                  label: _getLabelForSize(sliderValue, lang),
                  onChanged: (double newValue) {
                      themeManager.setFontSize(newValue);
                  },
                  activeColor: theme.colorScheme.secondary,
                  inactiveColor: theme.colorScheme.secondary.withOpacity(0.3),
                ),
                const SizedBox(height: 5),
                
                Text(
                  _getLabelForSize(sliderValue, lang),
                  style: TextStyle(
                    fontSize: 14.0,
                    color: theme.textTheme.bodySmall?.color,
                    fontWeight: FontWeight.bold
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          Divider(color: theme.dividerColor.withOpacity(0.5)),
          
          _buildSectionHeader(context, lang.t('font_family_header')),
          
          _buildRadioTile(context, themeManager, lang.t('font_default'), 'SystemDefault', null),
          _buildRadioTile(context, themeManager, 'Roboto', 'Roboto', 'Roboto'),
          _buildRadioTile(context, themeManager, 'Lato', 'Lato', 'Lato'),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 20.0, bottom: 15.0),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
          fontSize: 16.0,
        ),
      ),
    );
  }

  Widget _buildRadioTile(BuildContext context, ThemeManager themeManager, String title, String value, String? fontFamily) {
    final theme = Theme.of(context);
    return RadioListTile<String>(
      title: Text(
        title,
        style: TextStyle(
          fontFamily: fontFamily,
          color: theme.textTheme.bodyLarge?.color,
          fontSize: 16.0,
        )
      ),
      value: value,
      groupValue: themeManager.fontFamily,
      onChanged: (val) {
        if (val != null) themeManager.setFontFamily(val);
      },
      activeColor: theme.colorScheme.secondary,
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  String _getLabelForSize(double value, LanguageProvider lang) {
    const double epsilon = 0.01;
    if ((value - 0.85).abs() < epsilon) return lang.t('font_size_xsmall');
    if ((value - 0.9375).abs() < epsilon) return lang.t('font_size_small');
    if ((value - 1.025).abs() < epsilon) return lang.t('font_size_medium');
    if ((value - 1.1125).abs() < epsilon) return lang.t('font_size_large');
    if ((value - 1.2).abs() < epsilon) return lang.t('font_size_xlarge');
    
    return lang.t('font_size_medium');
  }
}