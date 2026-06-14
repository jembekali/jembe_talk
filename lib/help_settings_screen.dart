// lib/help_settings_screen.dart (VERSION 5.0 - PREMIUM MODERN DESIGN)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';

class HelpSettingsScreen extends StatefulWidget {
  final String? initialCategory;
  const HelpSettingsScreen({super.key, this.initialCategory});

  @override
  State<HelpSettingsScreen> createState() => _HelpSettingsScreenState();
}

class _HelpSettingsScreenState extends State<HelpSettingsScreen> {
  final _messageController = TextEditingController();
  late String _selectedCategoryKey; 
  bool _isLoading = false;

  final List<String> _categories = [
    'help_cat_support', 
    'help_cat_feedback', 
    'help_cat_bug', 
    'help_cat_ban_appeal',
    'help_cat_other'
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategoryKey = widget.initialCategory ?? "help_cat_support";
  }

  Future<void> _sendFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.t('contact_empty_error')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('feedback').add({
        'uid': user?.uid ?? 'anonymous',
        'userEmail': user?.email ?? 'Nta Email',
        'message': message,
        'category': lang.t(_selectedCategoryKey), 
        'categoryKey': _selectedCategoryKey, 
        'language': lang.currentLanguage, 
        'type': _selectedCategoryKey == 'help_cat_ban_appeal' ? 'ban_appeal' : 'general_support',
        'createdAt': FieldValue.serverTimestamp(),
        'isResolved': false,
        'hasAdminReply': false,
        'hasUnreadReply': false,
      });

      if (mounted) {
        _messageController.clear();
        _showSuccessDialog(lang);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${lang.t('error_generic')} $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(LanguageProvider lang) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            Text(
              lang.t('help_sent_success'), 
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
                child: Text(lang.t('btn_ok'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131C21) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(lang.t('help_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- HEADER SECTION ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.support_agent_rounded, size: 60, color: Colors.amber),
                  const SizedBox(height: 15),
                  Text(
                    lang.t('contact_admin_title'),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    lang.t('contact_info_text'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- CATEGORY SELECTION ---
                  _buildLabel(lang.t('help_category_label'), isDark),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategoryKey,
                        dropdownColor: isDark ? const Color(0xFF1C2935) : Colors.white,
                        items: _categories.map((key) => DropdownMenuItem(
                          value: key, 
                          child: Text(lang.t(key), style: TextStyle(color: isDark ? Colors.white : Colors.black87))
                        )).toList(),
                        onChanged: (value) { if (value != null) setState(() => _selectedCategoryKey = value); },
                        decoration: const InputDecoration(border: InputBorder.none),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // --- MESSAGE AREA ---
                  _buildLabel(lang.t('help_message_label'), isDark),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                      ],
                    ),
                    child: TextField(
                      controller: _messageController,
                      maxLines: 6,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: lang.t('help_hint'),
                        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                        contentPadding: const EdgeInsets.all(20),
                        border: InputBorder.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- SEND BUTTON ---
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      icon: _isLoading 
                          ? const SizedBox.shrink() 
                          : const Icon(Icons.send_rounded, color: Colors.white),
                      label: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3) 
                          : Text(
                              lang.t('help_btn_send').toUpperCase(), 
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                            ),
                      onPressed: _isLoading ? null : _sendFeedback,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8449),
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: Colors.green.withOpacity(0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      lang.t('contact_footer_text'),
                      style: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.amber.shade200 : Colors.black54,
        ),
      ),
    );
  }
}