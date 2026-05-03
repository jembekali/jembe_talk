import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/app_translations.dart';

class ChangeNumberVerifyScreen extends StatefulWidget {
  final String phoneNumber; 
  const ChangeNumberVerifyScreen({super.key, required this.phoneNumber});
  @override
  State<ChangeNumberVerifyScreen> createState() => _ChangeNumberVerifyScreenState();
}

class _ChangeNumberVerifyScreenState extends State<ChangeNumberVerifyScreen> {
  final _pinController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isVerifying = false;
  int _resendTimer = 60;
  Timer? _timer;
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _verifyPhoneNumber(); 
  }

  void _startResendTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendTimer > 0) { if (mounted) setState(() => _resendTimer--); } 
      else { t.cancel(); }
    });
  }

  Future<void> _verifyPhoneNumber() async {
    await _auth.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      verificationCompleted: (PhoneAuthCredential cred) async => await _updateUserPhone(cred),
      verificationFailed: (e) => _showSnackBar("Error: ${e.message}"),
      codeSent: (id, resend) => setState(() => _verificationId = id),
      codeAutoRetrievalTimeout: (id) => setState(() => _verificationId = id),
    );
  }

  Future<void> _updateUserPhone(PhoneAuthCredential credential) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final String c = lang.currentLanguage;
    setState(() => _isVerifying = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.updatePhoneNumber(credential);
        String sid = DateTime.now().millisecondsSinceEpoch.toString();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('sessionId', sid);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'phoneNumber': widget.phoneNumber, 'currentSessionId': sid});
        if (mounted) {
          _showSnackBar("Nimero yahinduwe neza!");
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
      }
    } catch (e) {
      _showSnackBar(AppTranslations.translate(c, 'error_generic'));
    } finally { if (mounted) setState(() => _isVerifying = false); }
  }

  void _showSnackBar(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;
    final defaultPinTheme = PinTheme(width: 56, height: 60, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)));

    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(title: Text(AppTranslations.translate(c, 'verify_title')), backgroundColor: Colors.transparent),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
        Text(AppTranslations.translate(c, 'verify_msg'), style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 10),
        Text(widget.phoneNumber, style: const TextStyle(color: Colors.tealAccent, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        Pinput(length: 6, controller: _pinController, defaultPinTheme: defaultPinTheme, onCompleted: (v) async {
          if (_verificationId != null) {
            final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: v);
            await _updateUserPhone(cred);
          }
        }),
        const SizedBox(height: 40),
        _isVerifying ? const CircularProgressIndicator() : const SizedBox(),
      ]))),
    );
  }
}