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

  Future<void> _handleLogin(String c) async {
    String phoneInput = _phoneController.text.trim();
    String password = _passwordController.text.trim();

    if (phoneInput.isEmpty || password.isEmpty) {
      _showSnackBar(AppTranslations.translate(c, 'error_fill_all'), Colors.orange);
      return;
    }

    try {
      final phoneNumber = PhoneNumber.parse(
        phoneInput, 
        destinationCountry: IsoCode.values.byName(_selectedISOCode.toUpperCase())
      );
      
      if (!phoneNumber.isValid(type: PhoneNumberType.mobile)) {
        _showSnackBar(AppTranslations.translate(c, 'val_phone_err'), Colors.orangeAccent);
        return;
      }
    } catch (e) {
      _showSnackBar(AppTranslations.translate(c, 'val_phone_err'), Colors.orangeAccent);
      return;
    }

    String fullPhone = "$_selectedCountryCode$phoneInput";
    setState(() => _isLoading = true);
    try {
      final query = await FirebaseFirestore.instance.collection('users').where('phoneNumber', isEqualTo: fullPhone).limit(1).get(); 
      if (query.docs.isEmpty) {
        _showSnackBar(AppTranslations.translate(c, 'error_no_account'), Colors.blueGrey);
        setState(() => _isLoading = false);
        return;
      }

      String hiddenEmail = query.docs.first.data()['email'];
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: hiddenEmail, 
        password: password
      );
      User? user = userCredential.user;

      if (user != null && !user.emailVerified) {
        if (!mounted) return;
        _showSnackBar(AppTranslations.translate(c, 'verify_title'), Colors.amber);
        Navigator.push(context, MaterialPageRoute(builder: (ctx) => EmailVerificationScreen(email: hiddenEmail)));
        setState(() => _isLoading = false);
        return;
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (ctx) => const HomeScreen()), (r) => false);
      
    } catch (e) {
      _showSnackBar(AppTranslations.translate(c, 'error_wrong_password'), Colors.redAccent);
    } finally { 
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  Future<void> _handlePasswordReset(String c) async {
    String email = _emailResetController.text.trim();
    String phoneInput = _phoneResetController.text.trim();
    if (email.isEmpty || phoneInput.isEmpty) { 
      _showSnackBar(AppTranslations.translate(c, 'error_fill_all'), Colors.orange); 
      return; 
    }
    String fullPhone = "$_selectedCountryCode$phoneInput";
    setState(() => _isLoading = true);
    try {
      final query = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).where('phoneNumber', isEqualTo: fullPhone).limit(1).get();
      if (query.docs.isEmpty) {
        _showSnackBar(AppTranslations.translate(c, 'error_match'), Colors.redAccent);
        setState(() => _isLoading = false);
        return;
      }
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        _showSuccessDialog(AppTranslations.translate(c, 'link_sent_title'), AppTranslations.translate(c, 'link_sent_body'), c);
        setState(() => _isResetMode = false);
      }
    } catch (e) { 
      _showSnackBar(AppTranslations.translate(c, 'error_generic'), Colors.orange); 
    } finally { 
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  Future<void> _pickEmailWithGoogle(TextEditingController ctrl) async {
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser != null) { setState(() => ctrl.text = googleUser.email); }
    } catch (e) { }
  }

  void _showSnackBar(String m, Color col) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: col, behavior: SnackBarBehavior.floating));

  void _showSuccessDialog(String title, String body, String c) {
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1E1E26), title: Text(title, style: const TextStyle(color: Colors.white)), content: Text(body, style: const TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppTranslations.translate(c, 'success_btn')))]));
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;
    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 30), child: Column(children: [
        const Icon(Icons.star_rounded, color: Colors.amber, size: 90),
        const Text("Jembe Talk", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 50),
        AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: _isResetMode ? _buildResetView(c) : _buildLoginView(c)),
      ])),
    );
  }

  Widget _buildLoginView(String c) {
    return Column(key: const ValueKey(1), children: [
      _buildPhoneInput(controller: _phoneController),
      const SizedBox(height: 20),
      TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38),
          hintText: AppTranslations.translate(c, 'password_label'),
          filled: true, fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          // ✅ NTIBIHINDURA LOGIC: Agakuru Bot izasoma
          semanticCounterText: "password_field", 
          suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white38), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
        ),
      ),
      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => _isResetMode = true), child: Text(AppTranslations.translate(c, 'forgot_password'), style: const TextStyle(color: Colors.white60)))),
      const SizedBox(height: 20),
      _isLoading ? const CircularProgressIndicator(color: Colors.teal) : ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E8449), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: () => _handleLogin(c), child: Text(AppTranslations.translate(c, 'login_btn'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      const SizedBox(height: 40),
      _buildRegisterPrompt(c),
    ]);
  }

  Widget _buildResetView(String c) {
    return Column(key: const ValueKey(2), children: [
      const Icon(Icons.security_rounded, size: 70, color: Colors.amber),
      const SizedBox(height: 15),
      Text(AppTranslations.translate(c, 'forgot_password'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      TextFormField(
        controller: _emailResetController, 
        style: const TextStyle(color: Colors.white), 
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.email_outlined, color: Colors.white38), 
          hintText: AppTranslations.translate(c, 'email_label'), 
          filled: true, fillColor: Colors.white.withOpacity(0.05), 
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          suffixIcon: TextButton(onPressed: () => _pickEmailWithGoogle(_emailResetController), child: const Text("Google", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)))
        )
      ),
      const SizedBox(height: 15),
      _buildPhoneInput(controller: _phoneResetController),
      const SizedBox(height: 30),
      _isLoading ? const CircularProgressIndicator(color: Colors.amber) : ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: () => _handlePasswordReset(c), child: Text(AppTranslations.translate(c, 'resend_link').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))),
      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => const AccountRecoveryScreen())), child: Text(AppTranslations.translate(c, 'forgot_everything'), style: const TextStyle(color: Colors.redAccent, decoration: TextDecoration.underline))),
      TextButton(onPressed: () => setState(() => _isResetMode = false), child: Text(AppTranslations.translate(c, 'back_btn'), style: const TextStyle(color: Colors.white38))),
    ]);
  }

  Widget _buildPhoneInput({required TextEditingController controller}) {
    return Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white12)), child: Row(children: [
      CountryCodePicker(
        onChanged: (v) => setState(() { _selectedCountryCode = v.dialCode!; _selectedISOCode = v.code!; }),
        initialSelection: 'BI', favorite: const ['BI', 'RW'], textStyle: const TextStyle(color: Colors.white)
      ),
      Expanded(child: TextField(
        controller: controller, 
        keyboardType: TextInputType.phone, 
        style: const TextStyle(color: Colors.white), 
        decoration: const InputDecoration(
          border: InputBorder.none, 
          contentPadding: EdgeInsets.symmetric(horizontal: 10),
          // ✅ NTIBIHINDURA LOGIC: Agakuru Bot izasoma
          semanticCounterText: "phone_field", 
        )
      ))
    ]));
  }

  Widget _buildRegisterPrompt(String c) {
    return InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => const RegistrationScreen())), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(AppTranslations.translate(c, 'new_here'), style: const TextStyle(color: Colors.white60)), Text(AppTranslations.translate(c, 'register_btn_text'), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]));
  }
}