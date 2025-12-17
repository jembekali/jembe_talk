// lib/language_settings_screen.dart (VERSION IVUGURUYE)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  
  // Impinduka: Ubu turakoresha 'keys' aho gukoresha amazina yanditse
  final List<Map<String, String>> _languages = [
    {'key': 'lang_name_ki', 'native_name': 'Ikirundi (Burundi)', 'code': 'ki'},
    {'key': 'lang_name_sw', 'native_name': 'Igiswahili (Afrika y\'Ubuseruko)', 'code': 'sw'},
    {'key': 'lang_name_en', 'native_name': 'English (United Kingdom)', 'code': 'en'},
    {'key': 'lang_name_fr', 'native_name': 'Français (France)', 'code': 'fr'},
  ];

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    const Color backgroundColor = Color(0xFF101D25);
    const Color appBarColor = Color(0xFF202C33);
    const Color textColor = Colors.white;
    const Color activeColor = Color(0xFF00A884); // Green accent

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          lang.t('language_settings_title'), 
          style: const TextStyle(color: textColor),
        ),
        backgroundColor: appBarColor,
        iconTheme: const IconThemeData(color: textColor),
      ),
      body: ListView(
        children: _languages.map((language) {
          return RadioListTile<String>(
            // Impinduka: Turakoresha lang.t() kugira duhindure izina
            title: Text(
              lang.t(language['key']!), 
              style: const TextStyle(color: textColor, fontSize: 16)
            ),
            value: language['code']!,
            groupValue: lang.currentLanguage, 
            onChanged: (String? value) {
              if (value != null) {
                lang.changeLanguage(value);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    // Impinduka: Ubutumwa bwa SnackBar bukoresha izina ry'umwimerere ry'ururimi
                    content: Text("${lang.t('language_selected_msg')}${language['native_name']}"),
                    duration: const Duration(milliseconds: 1000),
                    backgroundColor: activeColor,
                  )
                );
              }
            },
            activeColor: activeColor,
            controlAffinity: ListTileControlAffinity.trailing,
          );
        }).toList(),
      ),
    );
  } 
}