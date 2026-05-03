import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image/image.dart' as img; 
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:jembe_talk/services/r2_service.dart';

class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _newEmailController = TextEditingController();
  final _reasonController = TextEditingController(); 
  
  File? _selectedImage;
  bool _isLoading = false;
  bool _isEmailFromGoogle = false;
  String _selectedCountryCode = "+257";
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _newEmailController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  // GUHITAMO IFOTO
  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (pickedFile != null) setState(() => _selectedImage = File(pickedFile.path));
  }

  // KUGABANYA UBUHUNGIRO BW'IFOTO (COMPRESSION) - 100% LOGIC
  Future<File> _compressImage(File file) async {
    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return file;
    final compressedBytes = img.encodeJpg(image, quality: 70);
    final tempDir = await getTemporaryDirectory();
    final compressedFile = File('${tempDir.path}/comp_${DateTime.now().millisecondsSinceEpoch}.jpg');
    return await compressedFile.writeAsBytes(compressedBytes);
  }

  Future<void> _pickEmailWithGoogle(String c) async {
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser != null) {
        setState(() {
          _newEmailController.text = googleUser.email;
          _isEmailFromGoogle = true;
        });
      }
    } catch (e) { _showSnackBar(AppTranslations.translate(c, 'error_google_pick'), Colors.orange); }
  }

  // --- LOGIC YO KOHEREZA UBUSABE (100% NK'UKO VYARI IRI) ---
  Future<void> _submitRequest(String c) async {
    if (!_formKey.currentState!.validate() || _selectedImage == null) {
      _showSnackBar(
        _selectedImage == null 
          ? AppTranslations.translate(c, 'error_id_photo') 
          : AppTranslations.translate(c, 'error_fill_all'), 
        Colors.orangeAccent
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Compression
      File compressedFile = await _compressImage(_selectedImage!);
      
      // 2. Upload kuri R2 Service
      String fileName = "recovery_ids/${DateTime.now().millisecondsSinceEpoch}.jpg";
      String imageUrl = await R2Service().uploadFile(compressedFile, fileName, 'image/jpeg');

      // 3. Kubika muri Firestore
      await FirebaseFirestore.instance.collection('recovery_requests').add({
        'full_name': _nameController.text.trim(),
        'phone_number': "$_selectedCountryCode${_phoneController.text.trim()}",
        'new_email': _newEmailController.text.trim(),
        'reason': _reasonController.text.trim(),
        'id_document_url': imageUrl,
        'created_at': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      if (mounted) _showSuccessDialog(c);
    } on FirebaseException catch (e) {
      _showSnackBar(AppTranslations.translate(c, 'error_generic'), Colors.redAccent);
    } catch (e) { 
      _showSnackBar(AppTranslations.translate(c, 'error_generic'), Colors.redAccent); 
    } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showSnackBar(String m, Color col) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: col, behavior: SnackBarBehavior.floating)
  );

  void _showSuccessDialog(String c) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Icon(Icons.check_circle_rounded, color: Colors.teal, size: 60),
      content: Text(AppTranslations.translate(c, 'success_recovery_body'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      actions: [Center(child: ElevatedButton(onPressed: () => Navigator.popUntil(ctx, (route) => route.isFirst), child: Text(AppTranslations.translate(c, 'success_btn'))))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;

    return Scaffold(
      backgroundColor: const Color(0xFF1C2935),
      appBar: AppBar(
        title: Text(AppTranslations.translate(c, 'recovery_title')), 
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(AppTranslations.translate(c, 'recovery_desc'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 25),

            _buildField(_nameController, AppTranslations.translate(c, 'full_name_label'), Icons.person_outline, (v) => v!.length < 3 ? AppTranslations.translate(c, 'val_name') : null),
            _buildPhoneField(c),
            _buildEmailFieldWithGoogle(c),

            _buildField(
              _reasonController, 
              AppTranslations.translate(c, 'reason_label'), 
              Icons.help_outline, 
              (v) => v!.length < 10 ? AppTranslations.translate(c, 'val_reason') : null,
              maxLines: 3,
            ),

            const SizedBox(height: 15),
            Text(AppTranslations.translate(c, 'id_photo_title'), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 10),
            _buildImagePicker(c),

            const SizedBox(height: 40),

            _isLoading 
              ? Center(child: Column(children: [const CircularProgressIndicator(color: Colors.teal), const SizedBox(height: 10), Text(AppTranslations.translate(c, 'loading_msg'), style: const TextStyle(color: Colors.white54))]))
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  onPressed: () => _submitRequest(c), // HANO NIHO HARI HAKOSOYE
                  child: Text(AppTranslations.translate(c, 'recovery_submit_btn'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
            const SizedBox(height: 50),
          ]),
        ),
      ),
    );
  }

  Widget _buildEmailFieldWithGoogle(String c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: _newEmailController,
        onChanged: (v) => setState(() => _isEmailFromGoogle = false),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: "  Email nshasha", labelStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(Icons.email_outlined, color: _isEmailFromGoogle ? Colors.amber : Colors.white38),
          suffixIcon: TextButton(onPressed: () => _pickEmailWithGoogle(c), child: const Text("Google", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),
          filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, String? Function(String?)? val, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: ctrl, validator: val, maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(icon, color: Colors.white38),
          filled: true, fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildPhoneField(String c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        CountryCodePicker(onChanged: (v) => _selectedCountryCode = v.dialCode!, initialSelection: 'BI', textStyle: const TextStyle(color: Colors.white)),
        Expanded(child: TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: InputDecoration(border: InputBorder.none, hintText: AppTranslations.translate(c, 'login_phone_hint'), hintStyle: const TextStyle(color: Colors.white24)))),
      ]),
    );
  }

  Widget _buildImagePicker(String c) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 180, width: double.infinity,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white12)),
        child: _selectedImage != null 
          ? ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_selectedImage!, fit: BoxFit.cover))
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_a_photo_outlined, color: Colors.white54, size: 40), const SizedBox(height: 10), Text(AppTranslations.translate(c, 'id_photo_tap'), style: const TextStyle(color: Colors.white38))]),
      ),
    );
  }
}