// lib/phone_auth_screen.dart (YAKOSOWE NEZA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/profile_setup_screen.dart'; // <<< TWONGEYEMWO URUPAPURO RUSHASHA
import 'package:pinput/pinput.dart';
import 'package:country_code_picker/country_code_picker.dart';

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
    String phoneNumber = "$_selectedCountryCode${_phoneController.text.trim()}";
    
    setState(() { _isLoading = true; });
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async { await _signInWithCredential(credential); },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() { _isLoading = false; });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Habaye ikosa: ${e.message}")));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Habaye ikosa ritazwi: $e')));
      }
    }
  }

  Future<void> _signInWithOtp() async {
    if (_verificationId == null) return;
    setState(() { _isLoading = true; });
    try {
      final credential = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _otpController.text.trim());
      await _signInWithCredential(credential);
    } catch (e) { if (mounted) { setState(() { _isLoading = false; }); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code wanditse si yo.'))); } }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();

        // ==========================================================
        // ===== IKI GICE COSE CARAHINDUTSE CANE =====
        // ==========================================================
        if (doc.exists) {
          // Umukoresha asanzwe ahari, aca yinjira
          if (mounted) { 
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false); 
          }
        } else {
          // Ni umukoresha mushasha, aja kwuzuza amakuru
          if (mounted) { 
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const ProfileSetupScreen()), (route) => false); 
          }
        }
        // ==========================================================
      }
    } on FirebaseAuthException catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ikosa ryo kwinjira: ${e.message}"))); }
    } finally { if (mounted) { setState(() { _isLoading = false; }); } }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emeza Nimero yawe")),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20.0), child: _isOtpSent ? _buildOtpScreen() : _buildPhoneInputScreen()),
    );
  }

  // ... (Code isigaye ya _buildPhoneInputScreen na _buildOtpScreen ntihinduka)
  Widget _buildPhoneInputScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 50),
        const Text("Shiramwo nimero yawe ya telefone", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text("Turarungika code yo kwemeza biciye muri SMS.", style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
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
                  decoration: const InputDecoration(
                    hintText: 'Nimero ya Telefone',
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
                child: const Text('Rungika Code', style: TextStyle(fontSize: 18)),
              ),
      ],
    );
  }
  
  Widget _buildOtpScreen() {
    String fullPhoneNumber = "$_selectedCountryCode${_phoneController.text.trim()}";
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 50),
        const Text("Emeza Code wakiriye", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text("Andika code y'ibiharuro 6 twarungitse kuri $fullPhoneNumber", style: const TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
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
                child: const Text('Emeza', style: TextStyle(fontSize: 18)),
              ),
        TextButton(
          onPressed: () { setState(() { _isOtpSent = false; _isLoading = false; }); },
          child: const Text("Hindura nimero ya telefone"),
        )
      ],
    );
  }
}