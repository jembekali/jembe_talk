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
import 'package:jembe_talk/email_verification_screen.dart';
import 'package:jembe_talk/profile_setup_screen.dart';

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
      _phoneController.text = widget.initialPhone!.replaceAll(RegExp(r'\+\d{1,3}'), '');
    }
  }

  Future<void> _pickEmailWithGoogle(String c) async {
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser != null) {
        setState(() {
          _emailController.text = googleUser.email;
          _isEmailFromGoogle = true;
          if (_nameController.text.isEmpty) _nameController.text = googleUser.displayName ?? "";
        });
      }
    } catch (e) { _showSnackBar(AppTranslations.translate(c, 'error_google_pick'), Colors.orange); }
  }

  Future<void> _register(String c) async {
    if (!_formKey.currentState!.validate()) return;
    String phoneInput = _phoneController.text.trim();

    try {
      // FIXED: destinationCountry n'izina 'type:' mu buto ya isValid
      final phoneNumber = PhoneNumber.parse(
        phoneInput, 
        destinationCountry: IsoCode.values.byName(_selectedISOCode.toUpperCase())
      );
      if (!phoneNumber.isValid(type: PhoneNumberType.mobile)) { // <<<--- FIXED HANO
        _showSnackBar(AppTranslations.translate(c, 'val_phone_err'), Colors.orangeAccent);
        return;
      }
    } catch (e) {
      _showSnackBar(AppTranslations.translate(c, 'val_phone_err'), Colors.orangeAccent);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final String email = _emailController.text.trim();
      final String password = _passwordController.text.trim();
      final String fullPhone = "$_selectedCountryCode$phoneInput";

      final phoneCheck = await FirebaseFirestore.instance.collection('users').where('phoneNumber', isEqualTo: fullPhone).limit(1).get();
      if (phoneCheck.docs.isNotEmpty) {
        _showSnackBar(AppTranslations.translate(c, 'error_already_exists'), Colors.blueGrey);
        setState(() => _isLoading = false);
        return;
      }

      UserCredential userCredential;
      if (_isEmailFromGoogle) {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        final GoogleSignInAuthentication googleAuth = await googleUser!.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        await userCredential.user!.updatePassword(password);
      } else {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
        await userCredential.user!.sendEmailVerification();
      }

      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid, 'displayName': _nameController.text.trim(), 
        'phoneNumber': fullPhone, 'email': email, 'createdAt': FieldValue.serverTimestamp()
      });

      if (!mounted) return;
      if (_isEmailFromGoogle) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (ctx) => const ProfileSetupScreen()), (r) => false);
      } else {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (ctx) => EmailVerificationScreen(email: email)), (r) => false);
      }
    } catch (e) { _showSnackBar(AppTranslations.translate(c, 'error_generic'), Colors.red); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showSnackBar(String m, Color col) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: col));

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;
    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 25), child: Form(key: _formKey, child: Column(children: [
        const Icon(Icons.star_rounded, color: Colors.amber, size: 80),
        Text(AppTranslations.translate(c, 'register_title'), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 35),
        _buildField(_nameController, AppTranslations.translate(c, 'full_name_label'), Icons.person_outline, (v) => v!.length < 3 ? AppTranslations.translate(c, 'val_name') : null),
        _buildPhoneField(c),
        _buildEmailFieldWithGoogle(c),
        
        TextFormField(
          controller: _passwordController, obscureText: _obscurePassword,
          validator: (v) => v!.length < 6 ? AppTranslations.translate(c, 'val_pass') : null,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: AppTranslations.translate(c, 'password_hint'), filled: true, fillColor: Colors.white.withOpacity(0.05),
            prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38),
            suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white38), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          ),
        ),

        const SizedBox(height: 40),
        _isLoading ? const CircularProgressIndicator(color: Colors.teal) : ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E8449), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: () => _register(c), child: Text(AppTranslations.translate(c, 'register_submit_btn'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      ]))),
    );
  }

  Widget _buildEmailFieldWithGoogle(String c) {
    return Padding(padding: const EdgeInsets.only(bottom: 15), child: TextFormField(controller: _emailController, onChanged: (v) => setState(() => _isEmailFromGoogle = false), style: const TextStyle(color: Colors.white), validator: (v) => !v!.contains("@") ? AppTranslations.translate(c, 'val_email') : null, decoration: InputDecoration(labelText: AppTranslations.translate(c, 'email_label'), filled: true, fillColor: Colors.white.withOpacity(0.05), prefixIcon: Icon(Icons.email_outlined, color: _isEmailFromGoogle ? Colors.amber : Colors.white38), suffixIcon: TextButton(onPressed: () => _pickEmailWithGoogle(c), child: const Text("Google", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))));
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, String? Function(String?)? val) {
    return Padding(padding: const EdgeInsets.only(bottom: 15), child: TextFormField(controller: ctrl, validator: val, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: label, filled: true, fillColor: Colors.white.withOpacity(0.05), prefixIcon: Icon(icon, color: Colors.white38), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))));
  }

  Widget _buildPhoneField(String c) {
    return Container(margin: const EdgeInsets.only(bottom: 15), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)), child: Row(children: [
      CountryCodePicker(onChanged: (v) => setState(() { _selectedCountryCode = v.dialCode!; _selectedISOCode = v.code!; }), initialSelection: 'BI', textStyle: const TextStyle(color: Colors.white)),
      Expanded(child: TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: InputDecoration(border: InputBorder.none, hintText: AppTranslations.translate(c, 'login_phone_hint'), hintStyle: const TextStyle(color: Colors.white24))))
    ]));
  }
}