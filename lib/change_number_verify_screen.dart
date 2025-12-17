// Fayili: lib/change_number_verify_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
// Ntiwibagire provider niba ushaka gukoresha indimi (optional hano, ariko byaba byiza)
// import 'package:jembe_talk/language_provider.dart'; 
// import 'package:provider/provider.dart';

class ChangeNumberVerifyScreen extends StatefulWidget {
  final String phoneNumber; // Iyi ni ya nimero nshasha ivuye muri input screen
  const ChangeNumberVerifyScreen({super.key, required this.phoneNumber});

  @override
  State<ChangeNumberVerifyScreen> createState() => _ChangeNumberVerifyScreenState();
}

class _ChangeNumberVerifyScreenState extends State<ChangeNumberVerifyScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isVerifying = false;
  int _resendTimer = 60;
  Timer? _timer;
  
  String? _verificationId; // Hano tuzabika ID ya verification itanzwe na Firebase

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _verifyPhoneNumber(); // Duhita dusaba OTP tukinjira
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        if (mounted) setState(() => _resendTimer--);
      } else {
        _timer?.cancel();
      }
    });
  }

  // --- IYI NI YO MOTERI YA FIREBASE (Gusaba OTP) ---
  Future<void> _verifyPhoneNumber() async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        
        // 1. Iyo Android yisomye code yonyine (Auto-fill)
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _updateUserPhoneNumber(credential);
        },
        
        // 2. Iyo habaye ikosa (urugero: nimero mbi, nta internet)
        verificationFailed: (FirebaseAuthException e) {
          if(!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Ikosa: ${e.message}"), backgroundColor: Colors.red),
          );
        },
        
        // 3. Iyo code yohererejwe (SMS yagiye)
        codeSent: (String verificationId, int? resendToken) {
          if(mounted) {
            setState(() {
              _verificationId = verificationId;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Code yohererejwe. Yandike hasi.")),
            );
          }
        },
        
        // 4. Iyo igihe kirenganye (Timeout)
        codeAutoRetrievalTimeout: (String verificationId) {
          if(mounted) {
            setState(() {
              _verificationId = verificationId;
            });
          }
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      debugPrint("Ikosa ryo gutangiza verification: $e");
    }
  }

  Future<void> _resendOTP() async {
    if (_resendTimer == 0) {
      if (mounted) setState(() => _resendTimer = 60);
      _startResendTimer();
      await _verifyPhoneNumber();
    }
  }

  // --- IYI NI YO MOTERI YO KWEMEZA NO KUVUGURURA (Update) ---
  Future<void> _manualVerify() async {
    if (_pinController.text.length != 6 || _verificationId == null) return;
    
    // Kurema credential dukoresheje code umuntu yanditse
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: _pinController.text,
    );

    await _updateUserPhoneNumber(credential);
  }

  Future<void> _updateUserPhoneNumber(PhoneAuthCredential credential) async {
    if (mounted) setState(() => _isVerifying = true);

    try {
      final user = _auth.currentUser;
      if (user != null) {
        // 1. Kuvugurura muri AUTH SYSTEM (Kugira ngo ubutaha azinjirire kuri iyi nimero)
        await user.updatePhoneNumber(credential);

        // 2. Kuvugurura muri FIRESTORE (Kugira ngo muri profile bigaragara)
        await _firestore.collection('users').doc(user.uid).update({
          'phoneNumber': widget.phoneNumber,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Nimero yahinduwe neza!"), backgroundColor: Colors.green)
        );
        
        // Gusubira inyuma rwose
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = "Habaye ikosa.";
      if (e.code == 'invalid-verification-code') {
        message = "Code wanditse si yo.";
      } else if (e.code == 'credential-already-in-use') {
        message = "Iyo nimero isanzwe ikoreshwa n'uwundi.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent)
      );
    } catch (e) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ikosa: $e"), backgroundColor: Colors.redAccent)
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Design ya PIN
    final defaultPinTheme = PinTheme(
      width: 56, 
      height: 60, 
      textStyle: const TextStyle(fontSize: 22, color: Colors.white), 
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: Colors.transparent)
      )
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Emeza nimero"), backgroundColor: theme.appBarTheme.backgroundColor),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Twakurunikiye code y'ibiharuro 6 kuri nimero:",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: theme.textTheme.bodyMedium?.color),
              ),
              const SizedBox(height: 8),
              Text(
                widget.phoneNumber, 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white) // Canke theme color
              ),
              const SizedBox(height: 32),
              
              Pinput(
                length: 6, 
                controller: _pinController, 
                defaultPinTheme: defaultPinTheme, 
                focusedPinTheme: defaultPinTheme.copyWith(
                  decoration: defaultPinTheme.decoration!.copyWith(border: Border.all(color: theme.colorScheme.secondary))
                ), 
                // Iyo yujuje imibare 6, duhita dukora verification
                onCompleted: (pin) => _manualVerify() 
              ),
              
              const SizedBox(height: 32),
              
              _isVerifying 
                ? const CircularProgressIndicator() 
                : SizedBox(
                    width: double.infinity, 
                    height: 50, 
                    child: ElevatedButton(
                      onPressed: _manualVerify, // Guhamagara function nyayo
                      child: const Text("EMEZA")
                    )
                  ),
              
              const SizedBox(height: 24),
              TextButton(
                onPressed: _resendOTP, 
                child: Text(
                  _resendTimer > 0 
                    ? "Subira urungike code mu ($_resendTimer)" 
                    : "Subira urungike code", 
                  style: TextStyle(color: _resendTimer > 0 ? Colors.grey : theme.colorScheme.secondary)
                )
              ),
            ],
          ),
        ),
      ),
    );
  }
}