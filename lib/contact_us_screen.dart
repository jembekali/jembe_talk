// lib/contact_us_screen.dart (VERSION IVUGURUYE - WITH SUCCESS FEEDBACK)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  // --- FUNCTION YO KWEREKANA KO UBUTUMWA BWAGIYE (SUCCESS DIALOG) ---
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Bituma umuntu adahita akanda hanze ngo bivurunge
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 70),
              const SizedBox(height: 16),
              const Text(
                "Ubutumwa Bwarungitswe!",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Ubutumwa bwawe bwageze kuri Admin ya Jembe Talk. Tuzagusubiza vuba bishoboka binyuze kuri konte yawe.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
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
                    Navigator.of(context).pop(); // Funga Dialog
                    Navigator.of(context).pop(); // Suka inyuma kuri Blocked Screen
                  },
                  child: const Text("Sawa, Ndategereje"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final String message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Andika ubutumwa mbere yo kohereza.")),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final User? user = FirebaseAuth.instance.currentUser;
      
      // Kohereza muri Firestore
      await FirebaseFirestore.instance.collection('feedback').add({
        'uid': user?.uid ?? 'Anonymous',
        'userEmail': user?.email ?? 'Nta Email',
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isResolved': false,
        'type': 'contact_us_banned_user',
      });

      if (mounted) {
        _messageController.clear();
        _showSuccessDialog(); // Erekana ya Dialog y'icyizere
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ikosa ryabaye: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Twandikire Admin"),
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
                      "Sobanura neza ikibazo ufite cyangwa impamvu konte yawe ikwiriye gufungurwa.",
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              "Ubutumwa bwawe",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _messageController,
              maxLines: 8,
              enabled: !_isSending,
              decoration: InputDecoration(
                hintText: "Andika hano...",
                fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
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
                    elevation: 2,
                  ),
                  onPressed: _isSending ? null : _sendMessage,
                  child: _isSending 
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3) 
                    : const Text("Rungika Ubutumwa", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                "Tuzagusubiza mu masaha 24.",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}