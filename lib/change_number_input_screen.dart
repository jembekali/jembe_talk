import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:provider/provider.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:jembe_talk/email_verification_screen.dart'; // <<< Twahinduye hano
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/phone_auth_screen.dart'; 

class ChangeNumberInputScreen extends StatefulWidget {
  const ChangeNumberInputScreen({super.key});
  @override
  State<ChangeNumberInputScreen> createState() => _ChangeNumberInputScreenState();
}

class _ChangeNumberInputScreenState extends State<ChangeNumberInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldNumberController = TextEditingController();
  final _newNumberController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Imyirondoro ya Numero ya kera
  String _oldCountryCode = '+257';
  String _oldISOCode = "BI";

  // Imyirondoro ya Numero nshasha
  String _newCountryCode = '+257';
  String _newISOCode = "BI";

  @override
  void dispose() {
    _oldNumberController.dispose();
    _newNumberController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- LOGIC YO GUHINDURA NUMERO ---
  Future<void> _handleProcess(String c) async {
    // 1. Genzura niba Form yujuje (koresha ?. aho kuba !)
    if (_formKey.currentState?.validate() ?? false) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final String userEmail = user.email ?? "";
      String oldNumberFull = _oldCountryCode + _oldNumberController.text.trim();
      String newNumberFull = _newCountryCode + _newNumberController.text.trim();
      String password = _passwordController.text.trim();

      if (userEmail.isEmpty) {
        _showSnackBar("Email not found. Please log in again.", Colors.red);
        return;
      }

      if (oldNumberFull == newNumberFull) {
        _showSnackBar("Numero nshasha igomba kuba itandukanye n'iya kera.", Colors.orange);
        return;
      }

      setState(() => _isLoading = true);

      try {
        // 2. GENZURA NIBA NUMERO YA KERA YANDITSE ARI YO IRI MURI FIRESTORE
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        String currentPhoneInDb = userDoc.data()?['phoneNumber'] ?? "";

        if (oldNumberFull != currentPhoneInDb) {
          _showSnackBar("Numero ya kera wanditse siyo iri kuri iyi konte.", Colors.redAccent);
          setState(() => _isLoading = false);
          return;
        }

        // 3. GENZURA NIBA NUMERO NSHA ISANZWE IFITE UNDI UYIKORESHA
        final phoneCheck = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: newNumberFull)
            .limit(1).get();

        if (phoneCheck.docs.isNotEmpty) {
          _showSnackBar(AppTranslations.translate(c, 'error_already_exists'), Colors.redAccent);
          setState(() => _isLoading = false);
          return;
        }

        // 4. RE-AUTHENTICATION (Check Password)
        AuthCredential credential = EmailAuthProvider.credential(email: userEmail, password: password);
        await user.reauthenticateWithCredential(credential);

        // 5. RUNGIKA EMAIL VERIFICATION KURI EMAIL YE
        await user.sendEmailVerification();

        // 6. JYA KURI EMAIL VERIFICATION SCREEN
        if (mounted) {
          Navigator.push(context, SlideRightPageRoute(
            page: EmailVerificationScreen(
              email: userEmail, 
              newPhoneNumber: newNumberFull, // Twohereje numero nshasha
              isChangingNumber: true,        // Twerekanye ko ari uguhindura numero
            ),
          ));
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          _showSnackBar(AppTranslations.translate(c, 'error_wrong_password'), Colors.redAccent);
        } else {
          _showSnackBar("Error: ${e.message}", Colors.redAccent);
        }
      } catch (e) {
        _showSnackBar("Habaye ikosa ryo kugenzura.", Colors.redAccent);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String m, Color col) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: col));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;

    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(
        title: Text(AppTranslations.translate(c, 'chg_num_input_title')), 
        backgroundColor: Colors.transparent, 
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            const Icon(Icons.phonelink_setup_rounded, size: 60, color: Colors.tealAccent),
            const SizedBox(height: 20),

            // 1. NUMERO YA KERA
            _buildPhoneField(
              c: c, 
              label: AppTranslations.translate(c, 'chg_num_label_old'), 
              controller: _oldNumberController,
              onCountryChanged: (v) => setState(() { _oldCountryCode = v.dialCode ?? '+257'; _oldISOCode = v.code ?? 'BI'; })
            ),
            const SizedBox(height: 15),

            // 2. NUMERO NSHASHA
            _buildPhoneField(
              c: c, 
              label: AppTranslations.translate(c, 'chg_num_label_new'), 
              controller: _newNumberController,
              onCountryChanged: (v) => setState(() { _newCountryCode = v.dialCode ?? '+257'; _newISOCode = v.code ?? 'BI'; })
            ),
            const SizedBox(height: 15),

            // 3. PASSWORD
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: AppTranslations.translate(c, 'chg_num_pass_label'),
                labelStyle: const TextStyle(color: Colors.white60),
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.tealAccent),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                filled: true, 
                fillColor: Colors.white.withAlpha(15), 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
              validator: (v) => (v == null || v.isEmpty) ? AppTranslations.translate(c, 'error_fill_all') : null,
            ),

            // FORGOT PASSWORD -> JYA KURI PHONE AUTH (RESET MODE)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const PhoneAuthScreen(isResetModeInitially: true)));
                }, 
                child: Text(
                  AppTranslations.translate(c, 'forgot_password'), 
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)
                )
              ),
            ),

            const SizedBox(height: 30),
            _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary, 
                    minimumSize: const Size.fromHeight(55), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: () => _handleProcess(c),
                  child: Text(AppTranslations.translate(c, 'btn_confirm').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneField({required String c, required String label, required TextEditingController controller, required Function(CountryCode) onCountryChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 4),
          child: Text(label, style: const TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15), 
            borderRadius: BorderRadius.circular(15)
          ),
          child: Row(children: [
            CountryCodePicker(
              onChanged: (v) { if (v != null) onCountryChanged(v); },
              initialSelection: 'BI', 
              textStyle: const TextStyle(color: Colors.white),
              dialogBackgroundColor: const Color(0xFF1C2935),
              dialogTextStyle: const TextStyle(color: Colors.white),
              searchStyle: const TextStyle(color: Colors.white),
            ),
            Expanded(
              child: TextFormField(
                controller: controller, 
                keyboardType: TextInputType.phone, 
                style: const TextStyle(color: Colors.white), 
                decoration: const InputDecoration(
                  border: InputBorder.none, 
                  hintText: "7X XXX XXX", 
                  hintStyle: TextStyle(color: Colors.white24)
                ),
                validator: (v) => (v == null || v.isEmpty) ? AppTranslations.translate(c, 'error_fill_all') : null,
              )
            ),
          ]),
        ),
      ],
    );
  }
}