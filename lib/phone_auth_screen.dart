import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/welcome_screen.dart'; // Import WelcomeScreen kugira dusubireyo
import 'package:jembe_talk/profile_setup_screen.dart';
import 'package:pinput/pinput.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:page_transition/page_transition.dart'; // <<<--- IMPORT Y'INGENZI

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  String _selectedCountryCode = "+257"; 
  
  String? _verificationId;
  bool _isOtpSent = false;
  bool _isLoading = false;

  Future<void> _verifyPhoneNumber() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    String phoneNumber = "$_selectedCountryCode${_phoneController.text.trim()}";
    
    setState(() { _isLoading = true; });
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async { await _signInWithCredential(credential); },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() { _isLoading = false; });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('error_generic')} ${e.message}")));
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() { _verificationId = verificationId; _isOtpSent = true; _isLoading = false; });
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${lang.t('error_unknown')} $e')));
      }
    }
  }

  Future<void> _signInWithOtp() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_verificationId == null) return;
    setState(() { _isLoading = true; });
    try {
      final credential = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _otpController.text.trim());
      await _signInWithCredential(credential);
    } catch (e) { if (mounted) { setState(() { _isLoading = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('error_invalid_code')))); } }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    try {
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();

        if (doc.exists) {
          if (mounted) { 
            // <<<--- ANIMATION: KUJA KURI HOME SCREEN (Right to Left) --->>>
            Navigator.pushAndRemoveUntil(
              context, 
              PageTransition(
                type: PageTransitionType.rightToLeftWithFade,
                child: const HomeScreen(),
                duration: const Duration(milliseconds: 1000), // Buke buke (1 sec)
                curve: Curves.easeInOut,
              ),
              (route) => false
            ); 
          }
        } else {
          if (mounted) { 
            // <<<--- ANIMATION: KUJA KURI PROFILE SETUP (Right to Left) --->>>
            Navigator.pushAndRemoveUntil(
              context, 
              PageTransition(
                type: PageTransitionType.rightToLeftWithFade,
                child: const ProfileSetupScreen(),
                duration: const Duration(milliseconds: 1000), // Buke buke (1 sec)
                curve: Curves.easeInOut,
              ), 
              (route) => false
            ); 
          }
        }
      }
    } on FirebaseAuthException catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('error_signin')} ${e.message}"))); }
    } finally { if (mounted) { setState(() { _isLoading = false; }); } }
  }

  // Iyi function idufasha gusubira inyuma muri WelcomeScreen n'animation nziza
  void _goBackToWelcome() {
    Navigator.pushReplacement(
      context,
      PageTransition(
        type: PageTransitionType.leftToRightWithFade, // Gusubira inyuma (Ibumoso)
        child: const WelcomeScreen(),
        duration: const Duration(milliseconds: 1000), // Buke buke
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    // Dukuraho uburyo busanzwe bwo gusubira inyuma (WillPopScope/PopScope)
    // Kugira ngo dukoreshe animation yacu bwite.
    return PopScope(
      canPop: false, // Tubuza back button isanzwe gukora ako kanya
      onPopInvoked: (didPop) {
        if (didPop) return;
        _goBackToWelcome(); // Dukoresha animation yacu
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(lang.t('verify_phone_title')),
          // Twahinduye buto yo gusubira inyuma iri hejuru
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBackToWelcome,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0), 
          child: _isOtpSent ? _buildOtpScreen(lang) : _buildPhoneInputScreen(lang)
        ),
      ),
    );
  }

  Widget _buildPhoneInputScreen(LanguageProvider lang) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 50),
        Text(lang.t('enter_phone_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(lang.t('sms_notice'), style: const TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
        const SizedBox(height: 30),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Row(
            children: [
              CountryCodePicker(
                onChanged: (countryCode) {
                  setState(() {
                    _selectedCountryCode = countryCode.dialCode!;
                  });
                },
                initialSelection: 'BI',
                favorite: const ['BI', 'RW', 'UG', 'TZ', 'KE', 'CD'],
                showCountryOnly: false,
                showOnlyCountryWhenClosed: false,
                alignLeft: false,
              ),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: lang.t('phone_hint'),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        _isLoading ? const CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _verifyPhoneNumber,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                ),
                child: Text(lang.t('send_code_btn'), style: const TextStyle(fontSize: 18)),
              ),
      ],
    );
  }
  
  Widget _buildOtpScreen(LanguageProvider lang) {
    String fullPhoneNumber = "$_selectedCountryCode${_phoneController.text.trim()}";
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 50),
        Text(lang.t('verify_otp_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text("${lang.t('enter_otp_subtitle')} $fullPhoneNumber", style: const TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
        const SizedBox(height: 30),
        Pinput(length: 6, controller: _otpController, autofocus: true, onCompleted: (pin) => _signInWithOtp()),
        const SizedBox(height: 40),
        _isLoading ? const CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _signInWithOtp,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                ),
                child: Text(lang.t('verify_btn'), style: const TextStyle(fontSize: 18)),
              ),
        TextButton(
          onPressed: () { setState(() { _isOtpSent = false; _isLoading = false; }); },
          child: Text(lang.t('change_phone_btn')),
        )
      ],
    );
  }
}