import 'package:cloud_firestore/cloud_firestore.dart'; // <<< ONGERAMO UYU MURONGO
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/home_screen.dart'; 
import 'package:jembe_talk/registration_screen.dart'; // Twongeyeho inzira yerekeza kuri RegistrationScreen

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // <<< ONGERAMWO N'UYU MURONGO
  bool _isLoading = false;

  // <<<<<<< FUNCTION YOSE YA _loginUser YARASUBIWEMO >>>>>>>>>
  Future<void> _loginUser() async {
    // Hindura uko 'mounted' ikoreshwa kugira code ibe nziza
    final isMounted = mounted;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // Intambwe ya 1: Injiza umukoresha muri Authentication
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      // <<<<<<< IKI NI CO GICE GISHASHA KANDI C'INGENZI CANE >>>>>>>>>
      // Intambwe ya 2: Genzura niba document y'uyu mukoresha iriho muri Firestore
      if (userCredential.user != null) {
        final uid = userCredential.user!.uid;
        final docRef = _firestore.collection('users').doc(uid);
        final docSnap = await docRef.get();

        // Niba document itariho, hita uyikora ubunyene
        if (!docSnap.exists) {
          await docRef.set({
            'uid': uid,
            'email': userCredential.user!.email,
            'photoUrl': null,
            'displayName': userCredential.user!.email?.split('@').first ?? 'User', // Izina ry'agateganyo
            'createdAt': FieldValue.serverTimestamp(),
            'blockedUsers': [],
          });
          print("SUCCESS: Document yakorewe umukoresha mushasha yinjiye: $uid");
        }
      }
      // <<<<<<<<<<<<<<<<<<<< IHEREZO RY'IGICE GISHYA >>>>>>>>>>>>>>>>>

      // Intambwe ya 3: Iyo vyose birangiye, mujane muri HomeScreen
      if (isMounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }

    } on FirebaseAuthException catch (e) {
      if (isMounted) {
        String errorMessage = "Habaye ikosa. Ongera ugerageze.";
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') { errorMessage = 'Email cyangwa ijambo ry\'ibanga si vyo.'; } 
        else if (e.code == 'wrong-password') { errorMessage = 'Ijambo ry\'ibanga si ryo.'; } 
        else if (e.code == 'invalid-email') { errorMessage = 'Uburyo wanditse email si bwo.'; }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } finally {
      if (isMounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Injira")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 50),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0))),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: 'Ijambo ry\'ibanga',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0))),
            ),
            const SizedBox(height: 40),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _loginUser,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    child: const Text(
                      'Emeza Kwinjira',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
            const SizedBox(height: 20),
            // aha nongeyeho buto yo kuja kwiyandikisha
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                );
              },
              child: const Text("Nta konte ufite? Iyandikishe hano"),
            ),
          ],
        ),
      ),
    );
  }
}