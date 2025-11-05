// Code ya: JEMBE TALK APP
// Dosiye: lib/help_settings_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HelpSettingsScreen extends StatefulWidget {
  const HelpSettingsScreen({super.key});
  @override
  State<HelpSettingsScreen> createState() => _HelpSettingsScreenState();
}

class _HelpSettingsScreenState extends State<HelpSettingsScreen> {
  final _messageController = TextEditingController();
  String _selectedCategory = "Gusaba ubufasha";
  bool _isLoading = false;

  Future<void> _sendFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() { _isLoading = true; });

    try {
      await FirebaseFirestore.instance.collection('feedback').add({
        'uid': user.uid, // UYU MURONGO NI WO UHAMBAYE CANE
        'userEmail': user.email ?? 'Email ntizwi',
        'message': message,
        'category': _selectedCategory,
        'createdAt': FieldValue.serverTimestamp(),
        'isResolved': false,
        'hasAdminReply': false,
        'hasUnreadReply': false,
      });

      if (mounted) {
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ubutumwa bwarungitswe.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kurungika vyanse: $e')));
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ubufasha')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Hitamwo ico ubutumwa bwawe bwerekeye:"),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              items: ["Gusaba ubufasha", "Intererano", "Ikibazo c'ubuhinga", "Ibindi"].map((label) => DropdownMenuItem(value: label, child: Text(label))).toList(),
              onChanged: (value) { if (value != null) { setState(() { _selectedCategory = value; }); } },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            const Text("Andika ubutumwa bwawe hano:"),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Andika...'),
              maxLines: 8,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.send),
                label: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('RUNGIKA'),
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