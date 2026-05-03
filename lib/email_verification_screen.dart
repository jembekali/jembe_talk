import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:jembe_talk/profile_setup_screen.dart';
import 'package:jembe_talk/home_screen.dart'; // <<< Import HomeScreen

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String? newPhoneNumber; // Numero nshasha (niba ihari)
  final bool isChangingNumber; // Twereka niba ari uguhindura numero canke kwiyandikisha
  
  const EmailVerificationScreen({
    super.key, 
    required this.email, 
    this.newPhoneNumber, 
    this.isChangingNumber = false
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isEmailVerified = false;
  bool _canResendEmail = false;
  Timer? _checkTimer;   
  Timer? _countdownTimer; 
  int _secondsRemaining = 120; 

  @override
  void initState() {
    super.initState();
    _checkTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkEmailVerified());
    _startCountdown();
  }

  void _startCountdown() {
    setState(() { _canResendEmail = false; _secondsRemaining = 120; });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        setState(() => _canResendEmail = true);
        timer.cancel();
      }
    });
  }

  Future<void> _checkEmailVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await user.reload();
    if (user.emailVerified) {
      setState(() => _isEmailVerified = true);
      _checkTimer?.cancel();
      _countdownTimer?.cancel();
      
      // --- LOGIC YA CHANGE NUMBER ---
      if (widget.isChangingNumber && widget.newPhoneNumber != null) {
        try {
          // 1. Vugurura Firestore
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'phoneNumber': widget.newPhoneNumber
          });
          
          if (mounted) {
            _showSuccessDialog();
          }
        } catch (e) {
          debugPrint("Firestore Update Error: $e");
        }
      } else {
        // --- LOGIC YA REGISTRATION ---
        if (mounted) {
          Future.delayed(const Duration(seconds: 1), () {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const ProfileSetupScreen()), (r) => false);
          });
        }
      }
    }
  }

  void _showSuccessDialog() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2935),
        title: const Icon(Icons.check_circle, color: Colors.tealAccent, size: 50),
        content: Text(
          AppTranslations.translate(lang.currentLanguage, 'privacy_saved'), // "Amakuru yabitswe neza"
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const HomeScreen()), (r) => false),
            child: Text(AppTranslations.translate(lang.currentLanguage, 'success_btn'), style: const TextStyle(color: Colors.tealAccent)),
          )
        ],
      ),
    );
  }

  Future<void> _resendEmail(String c) async {
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppTranslations.translate(c, 'link_sent_title'))));
      _startCountdown();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Try again later.")));
    }
  }

  @override
  void dispose() { _checkTimer?.cancel(); _countdownTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;

    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))),
      body: Container(width: double.infinity, padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_isEmailVerified ? Icons.check_circle : Icons.mark_email_unread_rounded, size: 100, color: _isEmailVerified ? Colors.tealAccent : Colors.amber),
        const SizedBox(height: 30),
        Text(AppTranslations.translate(c, _isEmailVerified ? 'verify_success' : 'verify_title'), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        Text("${AppTranslations.translate(c, 'verify_msg')}\n${widget.email}", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 40),
        if (!_isEmailVerified) ...[
          const CircularProgressIndicator(color: Colors.teal),
          const SizedBox(height: 40),
          TextButton(
            onPressed: _canResendEmail ? () => _resendEmail(c) : null, 
            child: Text(_canResendEmail ? AppTranslations.translate(c, 'resend_link') : "${AppTranslations.translate(c, 'resend_wait')} ($_secondsRemaining)", style: TextStyle(color: _canResendEmail ? Colors.tealAccent : Colors.white38, fontWeight: FontWeight.bold)),
          ),
        ] else Text(AppTranslations.translate(c, 'verifying_msg'), style: const TextStyle(color: Colors.tealAccent)),
      ])),
    );
  }
}