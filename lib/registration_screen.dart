// lib/registration_screen.dart (VERSION 57.0 - ULTIMATE GHOST PROTECTION & RESCUE LOGIC)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:jembe_talk/email_verification_screen.dart';
import 'package:jembe_talk/profile_setup_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart' as sp;

class RegistrationScreen extends StatefulWidget {
  final String? initialPhone;
  const RegistrationScreen({super.key, this.initialPhone});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  bool _isLoading = false;
  bool _isEmailFromGoogle = false;
  bool _obscurePassword = true;
  String _selectedCountryCode = "+257";
  String _selectedISOCode = "BI";

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null) {
      _phoneController.text =
          widget.initialPhone!.replaceAll(RegExp(r'\+\d{1,3}'), '');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- 1. COMPACT LOGO ---
  Widget _buildAppLogo() {
    return Container(
      width: 65,
      height: 65,
      decoration: const BoxDecoration(
        color: Color(0xFF005A5A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
          bottomRight: Radius.circular(15),
          bottomLeft: Radius.circular(5),
        ),
      ),
      child: const Center(
          child: Icon(Icons.star_rounded, color: Colors.amber, size: 45)),
    );
  }

  Future<void> _pickEmailWithGoogle(String c) async {
    if (_isLoading) return;
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser != null && mounted) {
        setState(() {
          _emailController.text = googleUser.email;
          _isEmailFromGoogle = true;
          if (_nameController.text.isEmpty)
            _nameController.text = googleUser.displayName ?? "";
        });
      }
    } catch (e) {
      if (mounted)
        _showSnackBar(
            AppTranslations.translate(c, 'error_google_pick'), Colors.orange);
    }
  }

  // --- 2. REGISTRATION LOGIC (WITH RESCUE & GHOST PROTECTION) ---
  Future<void> _register(String c) async {
    if (!_formKey.currentState!.validate() || _isLoading) return;

    String phoneInput = _phoneController.text.trim();
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();
    String fullPhone = "$_selectedCountryCode$phoneInput";

    setState(() => _isLoading = true);

    try {
      // A. Reba niba numero isanzwe ifite konti (Kwirinda numero imwe kuri konti ebyiri)
      final phoneCheck = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: fullPhone)
          .limit(1)
          .get();
      if (!mounted) return;
      if (phoneCheck.docs.isNotEmpty) {
        _showSnackBar(AppTranslations.translate(c, 'error_phone_exists_login'),
            Colors.orange);
        setState(() => _isLoading = false);
        return;
      }

      UserCredential? userCredential;

      // B. KORA KONTI MURI AUTH (TRY-CATCH RESCUE)
      try {
        if (_isEmailFromGoogle) {
          final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
          if (googleUser == null) {
            setState(() => _isLoading = false);
            return;
          }
          final GoogleSignInAuthentication googleAuth =
              await googleUser.authentication;
          final AuthCredential credential = GoogleAuthProvider.credential(
              accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
          userCredential =
              await FirebaseAuth.instance.signInWithCredential(credential);
        } else {
          userCredential = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: email, password: password);
        }
      } on FirebaseAuthException catch (authError) {
        // 🔥 🔥 🔥 IKIBAZO CYA "EMAIL ALREADY IN USE" 🔥 🔥 🔥
        // Niba Email ihari ariko konti ikaba yari yaramagaye muri Firestore (Ghost), mwinjize (Login)
        if (authError.code == 'email-already-in-use') {
          userCredential = await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: email, password: password);
        } else {
          rethrow; // Niba ari indi error, yandike hasi muri catch rusange
        }
      }

      if (userCredential == null || userCredential.user == null)
        throw Exception("Auth failed");

      // C. 🔥 🔥 🔥 GHOST PROTECTION: Hita wandika muri Firestore ako kanya 🔥 🔥 🔥
      // Ibi bituma ubutaha nagaruka adashobora kuba "Ghost" kuko amakuru yagezemo.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'uid': userCredential.user!.uid,
        'displayName': _nameController.text.trim(),
        'phoneNumber': fullPhone,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'isProfileComplete': false, // Izuzuzwa muri ProfileSetupScreen
        'isDisabled': false,
      }, SetOptions(merge: true));

      // D. ZERO-HISTORY CLEANUP (Hanagura ubutumwa bwa kera bwa SQL)
      await DatabaseHelper.instance.clearAllData();

      if (!mounted) return;

      // E. REDIRECTION (Umutekano wa Email Verification)
      if (_isEmailFromGoogle || userCredential.user!.emailVerified) {
        // Niba ari Google cyanzi yemeje Email, jya kuri Setup
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (ctx) => const ProfileSetupScreen()),
            (r) => false);
      } else {
        // Niba ari Email isanzwe, banza ukore verification link
        await userCredential.user!.sendEmailVerification();
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (ctx) => EmailVerificationScreen(
                    email: email, newPhoneNumber: fullPhone)),
            (r) => false);
      }
    } catch (e) {
      debugPrint("Registration Error: $e");
      if (mounted)
        _showSnackBar(
            AppTranslations.translate(c, 'error_generic'), Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String m, Color col) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: col));

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;

    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Form(
              key: _formKey,
              child: Column(children: [
                _buildAppLogo(),
                const SizedBox(height: 10),
                Text(AppTranslations.translate(c, 'register_title'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _buildField(
                    _nameController,
                    AppTranslations.translate(c, 'full_name_label'),
                    Icons.person_outline,
                    (v) => v!.length < 3
                        ? AppTranslations.translate(c, 'val_name')
                        : null),
                _buildPhoneField(c),
                _buildEmailSelectionSection(c),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  validator: (v) => v!.length < 6
                      ? AppTranslations.translate(c, 'val_pass')
                      : null,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    labelText: AppTranslations.translate(c, 'password_hint'),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: Colors.white38, size: 20),
                    suffixIcon: IconButton(
                        icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white38,
                            size: 20),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 25),
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.teal)
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E8449),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(55),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _register(c),
                        child: Text(
                            AppTranslations.translate(c, 'register_submit_btn'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16))),
                const SizedBox(height: 20),
              ]))),
    );
  }

  Widget _buildEmailSelectionSection(String c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _isEmailFromGoogle ? Colors.amber : Colors.white10)),
      child: Column(children: [
        InkWell(
          onTap: () => _pickEmailWithGoogle(c),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [
                Color(0xFF4285F4),
                Color(0xFFEA4335),
                Color(0xFFFBBC05),
                Color(0xFF34A853)
              ], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.mail_lock_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(AppTranslations.translate(c, 'google_pick_email'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ]),
          ),
        ),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              const Expanded(child: Divider(color: Colors.white10)),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(AppTranslations.translate(c, 'divider_or'),
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 11))),
              const Expanded(child: Divider(color: Colors.white10)),
            ])),
        TextFormField(
            controller: _emailController,
            onChanged: (v) => setState(() => _isEmailFromGoogle = false),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            validator: (v) => !v!.contains("@")
                ? AppTranslations.translate(c, 'val_email')
                : null,
            decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: AppTranslations.translate(c, 'email_label'),
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.black26,
                prefixIcon: Icon(Icons.email_outlined,
                    color: _isEmailFromGoogle ? Colors.amber : Colors.white38,
                    size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none))),
      ]),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon,
      String? Function(String?)? val) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
            controller: ctrl,
            validator: val,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                labelText: label,
                labelStyle:
                    const TextStyle(color: Colors.white60, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                prefixIcon: Icon(icon, color: Colors.white38, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none))));
  }

  Widget _buildPhoneField(String c) {
    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          CountryCodePicker(
              onChanged: (v) => setState(() {
                    _selectedCountryCode = v.dialCode!;
                    _selectedISOCode = v.code!;
                  }),
              initialSelection: 'BI',
              favorite: const ['BI', 'RW'],
              textStyle: const TextStyle(color: Colors.white, fontSize: 14)),
          Expanded(
              child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText:
                          AppTranslations.translate(c, 'login_phone_hint'),
                      hintStyle: const TextStyle(
                          color: Colors.white24, fontSize: 14))))
        ]));
  }
}
