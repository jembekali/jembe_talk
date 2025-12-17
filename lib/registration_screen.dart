import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Ntiwibagire iyi import
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/language_provider.dart'; // Import ya provider wacu

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController displayNameController = TextEditingController(); 

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> _registerUser() async {
    final isMounted = mounted;
    final lang = Provider.of<LanguageProvider>(context, listen: false); // Turahamagara provider kugira dukoreshe t()
    
    if(displayNameController.text.trim().isEmpty) {
      if(isMounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('enter_name_error'))));
      return;
    }

    setState(() { _isLoading = true; });

    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (userCredential.user != null) {
        
        // Dufata izina umukoresha yanditse
        String displayName = displayNameController.text.trim();

        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'uid': userCredential.user!.uid,
          'email': userCredential.user!.email,
          'displayName': displayName,
          'displayName_lowercase': displayName.toLowerCase(),
          'photoUrl': null, 
          'createdAt': Timestamp.now(),
        });
      }

      if (isMounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }

    } on FirebaseAuthException catch (e) {
      if (isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${lang.t('registration_error')} ${e.message}"))
        );
      }
    } finally {
      if (isMounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hamagara provider hano kugira UI ihinduke iyo ururimi ruhindutse
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text(lang.t('register_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 50),
            
            TextField(
              controller: displayNameController,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                  labelText: lang.t('full_name_label'),
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0))),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: lang.t('email_label'),
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0))),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: lang.t('password_label'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0))),
            ),
            const SizedBox(height: 40),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _registerUser,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    child: Text(
                      lang.t('confirm_registration_btn'),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}