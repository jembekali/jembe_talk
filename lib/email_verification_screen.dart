// lib/email_verification_screen.dart (VERSION 54.0 - WITH PHONE VERIFICATION DISPLAY)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:jembe_talk/profile_setup_screen.dart';
import 'package:jembe_talk/registration_screen.dart';
import 'package:jembe_talk/home_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String? newPhoneNumber;
  final bool isChangingNumber;

  const EmailVerificationScreen(
      {super.key,
      required this.email,
      this.newPhoneNumber,
      this.isChangingNumber = false});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isEmailVerified = false;
  bool _canResendEmail = false;
  bool _isCleaningUp = false;
  Timer? _checkTimer;
  Timer? _countdownTimer;
  int _secondsRemaining = 120;

  @override
  void initState() {
    super.initState();
    _checkTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => _checkEmailVerified());
    _startCountdown();
  }

  Widget _buildAppLogo() {
    return Container(
      width: 85,
      height: 85,
      decoration: const BoxDecoration(
        color: Color(0xFF005A5A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(6),
        ),
      ),
      child: const Center(
          child: Icon(Icons.star_rounded, color: Colors.amber, size: 65)),
    );
  }

  void _startCountdown() {
    if (!mounted) return;
    setState(() {
      _canResendEmail = false;
      _secondsRemaining = 120;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
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
    if (user == null || _isCleaningUp) return;

    try {
      await user.reload();
      if (!mounted) return;

      if (user.emailVerified) {
        _isEmailVerified = true;
        _checkTimer?.cancel();
        _countdownTimer?.cancel();

        if (widget.isChangingNumber && widget.newPhoneNumber != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'phoneNumber': widget.newPhoneNumber});
          if (mounted) _showSuccessDialog();
        } else {
          if (mounted) {
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (c) => const ProfileSetupScreen()),
                    (r) => false);
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Verification Check Error: $e");
    }
  }

  Future<void> _abortAndGoBack(String c) async {
    if (_isCleaningUp) return;

    setState(() => _isCleaningUp = true);
    _checkTimer?.cancel();
    _countdownTimer?.cancel();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        String uid = user.uid;
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
        await user.delete();
      }
    } catch (e) {
      debugPrint("Cleanup Error: $e");
      await FirebaseAuth.instance.signOut();
    } finally {
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (ctx) =>
                    RegistrationScreen(initialPhone: widget.newPhoneNumber)),
            (r) => false);
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
        title:
            const Icon(Icons.check_circle, color: Colors.tealAccent, size: 50),
        content: Text(
            AppTranslations.translate(lang.currentLanguage, 'privacy_saved'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (c) => const HomeScreen()),
                  (r) => false);
            },
            child: Text(
                AppTranslations.translate(lang.currentLanguage, 'success_btn'),
                style: const TextStyle(color: Colors.tealAccent)),
          )
        ],
      ),
    );
  }

  Future<void> _resendEmail(String c) async {
    if (_isCleaningUp) return;
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppTranslations.translate(c, 'link_sent_title')),
            backgroundColor: Colors.teal));
        _startCountdown();
      }
    } catch (e) {
      if (mounted)
        _showSnackBar(
            AppTranslations.translate(c, 'error_generic'), Colors.orange);
    }
  }

  void _showSnackBar(String m, Color col) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: col));

  @override
  void dispose() {
    _checkTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;

    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isCleaningUp) ...[
              const CircularProgressIndicator(color: Colors.amber),
              const SizedBox(height: 20),
              Text(AppTranslations.translate(c, 'cleaning_data'),
                  style: const TextStyle(color: Colors.white70)),
            ] else ...[
              _buildAppLogo(),
              const SizedBox(height: 30),
              Text(
                  AppTranslations.translate(
                      c, _isEmailVerified ? 'verify_success' : 'verify_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // --- 🔥 🔥 🔥 INFO CONTAINER (EMAIL & PHONE) 🔥 🔥 🔥 ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white10)),
                child: Column(
                  children: [
                    // Email Display
                    Text(widget.email,
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(AppTranslations.translate(c, 'email_label') ?? "Email",
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),

                    // --- 🔥 🔥 DISPLAY PHONE NUMBER 🔥 🔥 ---
                    if (widget.newPhoneNumber != null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(color: Colors.white10, thickness: 1),
                      ),
                      Text(widget.newPhoneNumber!,
                          style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text(
                          AppTranslations.translate(c, 'login_phone_hint') ??
                              "Phone Number",
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(AppTranslations.translate(c, 'verify_msg'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 30),

              // --- 🔥 BUTTON TO GO BACK AND EDIT (WRONG INFO) 🔥 ---
              OutlinedButton.icon(
                onPressed: () => _abortAndGoBack(c),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.edit_note_rounded,
                    color: Colors.redAccent),
                label: Text(
                    AppTranslations.translate(c, 'wrong_email_prompt') ??
                        "Wrong info? Edit",
                    style: const TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),

              const SizedBox(height: 40),

              if (!_isEmailVerified) ...[
                const CircularProgressIndicator(color: Colors.teal),
                const SizedBox(height: 40),
                TextButton(
                  onPressed: _canResendEmail ? () => _resendEmail(c) : null,
                  child: Text(
                      _canResendEmail
                          ? AppTranslations.translate(c, 'resend_link')
                          : "${AppTranslations.translate(c, 'resend_wait')} ($_secondsRemaining)",
                      style: TextStyle(
                          color: _canResendEmail
                              ? Colors.tealAccent
                              : Colors.white38,
                          fontWeight: FontWeight.bold)),
                ),
              ] else
                Text(AppTranslations.translate(c, 'verifying_msg'),
                    style: const TextStyle(color: Colors.tealAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
