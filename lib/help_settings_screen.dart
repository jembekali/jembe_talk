import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider

class HelpSettingsScreen extends StatefulWidget {
  const HelpSettingsScreen({super.key});
  @override
  State<HelpSettingsScreen> createState() => _HelpSettingsScreenState();
}

class _HelpSettingsScreenState extends State<HelpSettingsScreen> {
  final _messageController = TextEditingController();
  // Dukoresha "keys" (English like keys) muri code, ariko tugaragaza translations
  String _selectedCategoryKey = "help_cat_support"; 
  bool _isLoading = false;

  final List<String> _categories = [
    'help_cat_support', 
    'help_cat_feedback', 
    'help_cat_bug', 
    'help_cat_other'
  ];

  Future<void> _sendFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    final lang = Provider.of<LanguageProvider>(context, listen: false); // Provider for messages
    
    if (user == null) return;

    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() { _isLoading = true; });

    try {
      await FirebaseFirestore.instance.collection('feedback').add({
        'uid': user.uid,
        'userEmail': user.email ?? 'Email ntizwi',
        'message': message,
        'category': lang.t(_selectedCategoryKey), // Tubika translation kugira admin yumve
        'categoryKey': _selectedCategoryKey, // Tubika na key niba bikenewe
        'language': lang.currentLanguage, // Tubika n'ururimi yakoresheje
        'createdAt': FieldValue.serverTimestamp(),
        'isResolved': false,
        'hasAdminReply': false,
        'hasUnreadReply': false,
      });

      if (mounted) {
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('help_sent_success')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${lang.t('help_send_error')} $e')));
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context); // Provider

    return Scaffold(
      appBar: AppBar(title: Text(lang.t('help_title'))), // "Ubufasha"
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lang.t('help_category_label')), // "Hitamwo ico..."
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedCategoryKey,
              items: _categories.map((key) => DropdownMenuItem(value: key, child: Text(lang.t(key)))).toList(),
              onChanged: (value) { if (value != null) { setState(() { _selectedCategoryKey = value; }); } },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            Text(lang.t('help_message_label')), // "Andika ubutumwa..."
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              decoration: InputDecoration(border: const OutlineInputBorder(), hintText: lang.t('help_hint')),
              maxLines: 8,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.send),
                label: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : Text(lang.t('help_btn_send')), // "RUNGIKA"
                onPressed: _isLoading ? null : _sendFeedback,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}