// lib/phone_auth_screen.dart (VERSION 57.2 - ENHANCED FEEDBACK)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart'; 
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/registration_screen.dart';
import 'package:jembe_talk/account_recovery_screen.dart';
import 'package:jembe_talk/email_verification_screen.dart';

class PhoneAuthScreen extends StatefulWidget {
  final bool isResetModeInitially; 
  const PhoneAuthScreen({super.key, this.isResetModeInitially = false});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailResetController = TextEditingController();
  final _phoneResetController = TextEditingController(); 
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  bool _isLoading = false;
  late bool _isResetMode; 
  bool _obscurePassword = true;
  String _selectedCountryCode = "+257";
  String _selectedISOCode = "BI";

  @override
  void initState() {
    super.initState();
    _isResetMode = widget.isResetModeInitially; 
  }

  @override
  void dispose() {
    _phoneController.dispose(); _passwordController.dispose();
    _emailResetController.dispose(); _phoneResetController.dispose();
    super.dispose();
  }

  Widget _buildAppLogo() {
    return Container(
      width: 70, height: 70,
      decoration: const BoxDecoration(
        color: Color(0xFF005A5A), 
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18), topRight: Radius.circular(18),
          bottomRight: Radius.circular(18), bottomLeft: Radius.circular(6),
        ),
      ),
      child: const Center(child: Icon(Icons.star_rounded, color: Colors.amber, size: 50)),
    );
  }

  // --- 1. LOGIN LOGIC ---
  Future<void> _handleLogin(String c) async {
    if (_isLoading) return;
    String phoneInput = _phoneController.text.trim();
    String password = _passwordController.text.trim();

    if (phoneInput.isEmpty || password.isEmpty) {
      _showSnackBar(AppTranslations.translate(c, 'error_fill_all'), Colors.orange);
      return;
    }

    try {
      final phoneNumber = PhoneNumber.parse(phoneInput, destinationCountry: IsoCode.values.byName(_selectedISOCode.toUpperCase()));
      if (!phoneNumber.isValid(type: PhoneNumberType.mobile)) {
        _showSnackBar(AppTranslations.translate(c, 'val_phone_err'), Colors.orangeAccent);
        return;
      }
    } catch (e) { _showSnackBar(AppTranslations.translate(c, 'val_phone_err'), Colors.orangeAccent); return; }

    String fullPhone = "$_selectedCountryCode$phoneInput";
    setState(() => _isLoading = true);

    try {
      final query = await FirebaseFirestore.instance.collection('users').where('phoneNumber', isEqualTo: fullPhone).limit(1).get(); 
      if (!mounted) return;

      if (query.docs.isEmpty) {
        _showSnackBar(AppTranslations.translate(c, 'error_no_account'), Colors.blueGrey);
        setState(() => _isLoading = false); return;
      }

      final userData = query.docs.first.data();
      if (userData['isDisabled'] == true) {
        _showSnackBar(AppTranslations.translate(c, 'error_account_disabled'), Colors.red);
        setState(() => _isLoading = false); return; 
      }

      String hiddenEmail = query.docs.first.data()['email'];
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: hiddenEmail, password: password);
      
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && !user.emailVerified) {
        Navigator.push(context, MaterialPageRoute(builder: (ctx) => EmailVerificationScreen(email: hiddenEmail, newPhoneNumber: fullPhone)));
        setState(() => _isLoading = false); return;
      }

      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (ctx) => const HomeScreen()), (r) => false);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(AppTranslations.translate(c, 'error_wrong_password'), Colors.redAccent);
    } finally { if (mounted) setState(() => _isLoading = false); }
  }

  // --- 2. PASSWORD RESET LOGIC WITH DIALOG SIGNAL ---
  Future<void> _handlePasswordReset(String c) async {
    if (_isLoading) return;
    String phoneInput = _phoneResetController.text.trim();

    if (phoneInput.isEmpty) {
      _showSnackBar(AppTranslations.translate(c, 'val_phone_err'), Colors.orange);
      return;
    }

    String fullPhone = "$_selectedCountryCode$phoneInput";
    setState(() => _isLoading = true);

    try {
      final query = await FirebaseFirestore.instance.collection('users').where('phoneNumber', isEqualTo: fullPhone).limit(1).get();

      if (query.docs.isEmpty) {
        if (!mounted) return;
        _showSnackBar(AppTranslations.translate(c, 'error_no_account'), Colors.blueGrey);
        setState(() => _isLoading = false);
        return;
      }

      String email = query.docs.first.data()['email'];
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      setState(() => _isLoading = false);
      
      // Koresha Dialog nko muri Verification Screen kugira ngo umukoresha abone ubutumwa bwuzuye
      _showResetSuccessDialog(c, email);

    } catch (e) {
      if (mounted) {
        _showSnackBar(AppTranslations.translate(c, 'error_generic'), Colors.redAccent);
        setState(() => _isLoading = false);
      }
    }
  }

  // --- 3. SUCCESS DIALOG (Signal kugaragarira umukoresha) ---
  void _showResetSuccessDialog(String c, String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2935),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Icon(Icons.mark_email_read_rounded, color: Colors.amber, size: 60),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppTranslations.translate(c, 'link_sent_title') ?? "Email Yarungitswe!", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 15),
            Text("${AppTranslations.translate(c, 'verify_msg')}\n\n$email", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _isResetMode = false); // Garuka kuri Login ubu noneho
              },
              child: Text(AppTranslations.translate(c, 'success_btn') ?? "OK", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  void _showSnackBar(String m, Color col) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: col, behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;
    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30), 
        child: Column(children: [
          _buildAppLogo(),
          const SizedBox(height: 10),
          const Text("Jembe Talk", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30), 
          AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: _isResetMode ? _buildResetView(c) : _buildLoginView(c)),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _buildLoginView(String c) {
    return Column(key: const ValueKey(1), children: [
      _buildPhoneInput(controller: _phoneController),
      const SizedBox(height: 15), 
      TextField(
        controller: _passwordController, obscureText: _obscurePassword, style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38, size: 20),
          hintText: AppTranslations.translate(c, 'password_label'),
          filled: true, fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
        ),
      ),
      Align(alignment: Alignment.centerRight, child: InkWell(onTap: () => setState(() => _isResetMode = true), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(AppTranslations.translate(c, 'forgot_password'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: Colors.amber))))),
      const SizedBox(height: 15),
      _isLoading 
        ? const CircularProgressIndicator(color: Colors.teal) 
        : ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E8449), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => _handleLogin(c), child: Text(AppTranslations.translate(c, 'login_btn'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      const SizedBox(height: 30), 
      _buildRegisterPrompt(c),
    ]);
  }

  Widget _buildResetView(String c) {
    return Column(key: const ValueKey(2), children: [
      const Icon(Icons.security_rounded, size: 60, color: Colors.amber),
      const SizedBox(height: 10),
      Text(AppTranslations.translate(c, 'forgot_password'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      _buildPhoneInput(controller: _phoneResetController),
      const SizedBox(height: 25),
      _isLoading 
          ? const CircularProgressIndicator(color: Colors.amber) 
          : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
              onPressed: () => _handlePasswordReset(c), 
              child: Text(AppTranslations.translate(c, 'resend_link').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))),
      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => const AccountRecoveryScreen())), child: Text(AppTranslations.translate(c, 'forgot_everything'), style: const TextStyle(color: Colors.redAccent, decoration: TextDecoration.underline, fontSize: 12))),
      TextButton(onPressed: () => setState(() => _isResetMode = false), child: Text(AppTranslations.translate(c, 'back_btn'), style: const TextStyle(color: Colors.white38, fontSize: 12))),
    ]);
  }

  Widget _buildPhoneInput({required TextEditingController controller}) {
    return Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: Row(children: [
      CountryCodePicker(onChanged: (v) => setState(() { _selectedCountryCode = v.dialCode!; _selectedISOCode = v.code!; }), initialSelection: 'BI', favorite: const ['BI', 'RW'], textStyle: const TextStyle(color: Colors.white, fontSize: 14)),
      Expanded(child: TextField(controller: controller, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white, fontSize: 15), decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 10), semanticCounterText: "phone_field")))
    ]));
  }

  Widget _buildRegisterPrompt(String c) {
    return Container(
      padding: const EdgeInsets.all(15), 
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
      child: Column(children: [
        Text(AppTranslations.translate(c, 'new_here'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton(style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amber, width: 1.2), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => const RegistrationScreen())), child: Text(AppTranslations.translate(c, 'register_btn_text').toUpperCase(), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0)))),
      ]),
    );
  }
}