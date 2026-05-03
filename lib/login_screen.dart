// lib/login_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/registration_screen.dart';
import 'package:jembe_talk/account_recovery_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    String phoneInput = _phoneController.text.trim();
    String passwordInput = _passwordController.text.trim();

    if (phoneInput.isEmpty || passwordInput.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // 1. Shakisha email ihuye na ya numero muri Firestore
      final query = await _firestore.collection('users')
          .where('phoneNumber', isEqualTo: phoneInput).limit(1).get();

      if (!mounted) return; // Fix ya "BuildContext across async gaps"

      if (query.docs.isEmpty) {
        _showSnackBar("Iyi numero nta konte ifise!");
        // FIX: Hano tugomba guha RegistrationScreen numero twanditse
        Navigator.push(context, MaterialPageRoute(
          builder: (c) => RegistrationScreen(initialPhone: phoneInput)
        ));
        return;
      }

      String email = query.docs.first.data()['email'];
      
      // 2. Login muri Firebase Auth
      await _auth.signInWithEmailAndPassword(email: email, password: passwordInput);
      
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const HomeScreen()));

    } on FirebaseAuthException catch (_) { // Fix ya unused 'e'
      _showSnackBar("Password si yo!");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    String phone = _phoneController.text.trim();
    if (phone.isEmpty) { _showSnackBar("Banza wandike numero yawe!"); return; }
    try {
      final query = await _firestore.collection('users').where('phoneNumber', isEqualTo: phone).limit(1).get();
      if (query.docs.isNotEmpty) {
        await _auth.sendPasswordResetEmail(email: query.docs.first.data()['email']);
        _showSnackBar("Link yarungitswe muri email yawe.");
      }
    } catch (_) {}
  }

  void _showSnackBar(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      body: SingleChildScrollView(padding: const EdgeInsets.all(25), child: Column(children: [
        const SizedBox(height: 80),
        const Icon(Icons.lock_person, size: 80, color: Colors.white24),
        const SizedBox(height: 40),
        TextField(controller: _phoneController, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Numero ya Telefone", labelStyle: TextStyle(color: Colors.white60), prefixIcon: Icon(Icons.phone, color: Colors.white60))),
        const SizedBox(height: 15),
        TextField(controller: _passwordController, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Password", labelStyle: TextStyle(color: Colors.white60), prefixIcon: Icon(Icons.lock, color: Colors.white60))),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgotPassword, child: const Text("Wibagiye Password?", style: TextStyle(color: Colors.white70)))),
        const SizedBox(height: 30),
        _isLoading ? const CircularProgressIndicator() : ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(55)),
          onPressed: _handleLogin, 
          child: const Text("KWINJIRA", style: TextStyle(color: Color(0xFF1C2935), fontWeight: FontWeight.bold))
        ),
        TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AccountRecoveryScreen())), 
          child: const Text("Wibagiye vyose? fyonda hano.", style: TextStyle(color: Colors.redAccent))),
      ])),
    );
  }
}