// lib/contact_us_screen.dart (VERSION 4.0 - MULTI-LANGUAGE SUPPORT)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart'; // <--- Ingenzi

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  void _showSuccessDialog(LanguageProvider lang) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 70),
              const SizedBox(height: 16),
              Text(
                lang.t('contact_success_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                lang.t('contact_success_body'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(); 
                    Navigator.of(context).pop(); 
                  },
                  child: Text(lang.t('contact_success_btn')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage(LanguageProvider lang) async {
    final String message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.t('contact_empty_error'))),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final User? user = FirebaseAuth.instance.currentUser;
      
      await FirebaseFirestore.instance.collection('feedback').add({
        'uid': user?.uid ?? 'Anonymous',
        'userEmail': user?.email ?? 'Nta Email',
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isResolved': false,
        'type': 'ban_appeal', // Kumenyesha Admin ko ari ubusabe bwo gufungurwa
      });

      if (mounted) {
        _messageController.clear();
        _showSuccessDialog(lang); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${lang.t('error_generic')} $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.t('contact_admin_title')),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lang.t('contact_info_text'),
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            Text(
              lang.t('contact_your_msg_label'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _messageController,
              maxLines: 8,
              enabled: !_isSending,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: lang.t('contact_hint'),
                fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E8449), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Center(
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8449),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSending ? null : () => _sendMessage(lang),
                  child: _isSending 
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3) 
                    : Text(lang.t('contact_btn_send'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                lang.t('contact_footer_text'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}