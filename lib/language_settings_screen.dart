// lib/language_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  String? _selectedLanguageCode = 'ki';

  final List<Map<String, String>> _languages = [
    {'name': 'Ikirundi (Burundi)', 'code': 'ki'},
    {'name': 'Igiswahili (afrika y"ubuseruko)', 'code': 'sw'},
    {'name': 'Icongereza (Ubwongereza)', 'code': 'en'},
    {'name': 'Igifarasa (Ubufarasa)', 'code': 'fr'},
  ];

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguageCode = prefs.getString('languageCode') ?? 'ki';
    });
  }

  Future<void> _saveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101D25),
      appBar: AppBar(
        title: const Text("Hitamwo ururimi ushaka"),
        backgroundColor: const Color(0xFF202C33),
      ),
      body: ListView(
        children: _languages.map((language) {
          return RadioListTile<String>(
            title: Text(language['name']!, style: const TextStyle(color: Colors.white)),
            value: language['code']!,
            groupValue: _selectedLanguageCode,
            onChanged: (String? value) {
              if (value != null) {
                setState(() {
                  _selectedLanguageCode = value;
                });
                _saveLanguage(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("${language['name']} Gwahiswemwo."))
                );
              }
            },
            activeColor: Colors.tealAccent,
            controlAffinity: ListTileControlAffinity.trailing,
          );
        }).toList(),
      ),
    );
  }
}