// lib/delete_account_screen.dart (ULTIMATE R2 CLEANUP - 100% COMPLETE)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/welcome_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/presence_service.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:jembe_talk/phone_auth_screen.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _isConfirmed = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  final PresenceService _presenceService = PresenceService();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // 1. LOGIC YO GUSIBA AMAFAYIRI YOSE KURI R2 (PRO CLEANUP)
  // ===========================================================================
  Future<void> _cleanupAllR2Media(String uid) async {
    final r2 = R2Service();

    // A. PROFILE & THUMBNAILS (Folder: profiles/)
    try {
      await r2.deleteFile("profiles/$uid.jpg");
      await r2.deleteFile("thumbnails/profiles/$uid.jpg");
    } catch (e) { debugPrint("R2 Cleanup: No profile found."); }

    // B. POSTS MEDIA & THUMBNAILS (Folder: posts/[UID]/...)
    try {
      final postsQuery = await FirebaseFirestore.instance
          .collection('posts')
          .where('authorId', isEqualTo: uid)
          .get();

      for (var doc in postsQuery.docs) {
        // Niba ubibika nka: posts/$uid/${doc.id}.jpg
        String postPath = "posts/$uid/${doc.id}.jpg";
        // Niba hari field yitwa 'remotePath' muri Firestore, koresha iyo
        String finalPath = doc.data()['remotePath'] ?? postPath;

        await r2.deleteFile(finalPath);
        await r2.deleteFile("thumbnails/$finalPath");
        await doc.reference.delete(); // Siba na Post muri Firestore
      }
    } catch (e) { debugPrint("R2 Cleanup: Posts error: $e"); }

    // C. CHAT MEDIA & THUMBNAILS (Folder: chat/[UID]/...)
    try {
      final messages = await FirebaseFirestore.instance
          .collectionGroup('messages')
          .where('senderID', isEqualTo: uid)
          .get();

      for (var msg in messages.docs) {
        String? mediaPath = msg.data()['mediaPath']; // inzira nka chat/uid/file.jpg
        if (mediaPath != null) {
          await r2.deleteFile(mediaPath);
          await r2.deleteFile("thumbnails/$mediaPath");
        }
      }
    } catch (e) { debugPrint("R2 Cleanup: Chat media error: $e"); }
  }

  // ===========================================================================
  // 2. ACTION NYAMUKURU (GUSIBA BYOSE)
  // ===========================================================================
  Future<void> _handleDeleteAccount(String langCode) async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isConfirmed) {
      _showSnackBar(AppTranslations.translate(langCode, 'val_required'), Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      String uid = user.uid;
      String email = user.email ?? "";
      String password = _passwordController.text.trim();

      // I. RE-AUTHENTICATION (Umutekano imbere yo gusiba)
      AuthCredential credential = EmailAuthProvider.credential(email: email, password: password);
      await user.reauthenticateWithCredential(credential);

      // II. ISUKU RYA REALTIME DB (Banza ibi kugira ngo bitaza gutanga Permission Denied)
      try {
        _presenceService.forceOffline();
        await FirebaseDatabase.instance.ref('status/$uid').remove();
        await FirebaseDatabase.instance.ref('activity/$uid').remove();
      } catch (e) { debugPrint("DB Error (Ignored): $e"); }

      // III. ISUKU RYA R2 (GUSIBA AMAFOTO & VIDEO NTAMANANIZA)
      await _cleanupAllR2Media(uid);

      // IV. ISUKU RYA FIRESTORE (User Doc)
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // V. GUSIBA AUTH (Login burundu - Adasigara ari Ghost)
      await user.delete();

      // VI. LOCAL DATA WIPE (SQLITE & PREFS)
      await DatabaseHelper.instance.wipeAllData();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const WelcomeScreen()), (r) => false);
        _showSnackBar(AppTranslations.translate(langCode, 'delete_acc_success'), Colors.green);
      }

    } on FirebaseAuthException catch (e) {
      String msg;
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = AppTranslations.translate(langCode, 'error_wrong_password');
      } else if (e.code == 'requires-recent-login') {
        msg = langCode == 'ki' ? "Banza usohoke winjire bundi bushya maze usibe konte." : "Please re-login to delete account.";
      } else {
        msg = AppTranslations.translate(langCode, 'error_generic');
      }
      _showSnackBar(msg, Colors.redAccent);
    } catch (e) {
      _showSnackBar(AppTranslations.translate(langCode, 'error_generic'), Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String m, Color col) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: col));
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;

    return Scaffold(
      backgroundColor: const Color(0xFF101D25),
      appBar: AppBar(
        title: Text(AppTranslations.translate(c, 'delete_acc_title')),
        backgroundColor: const Color(0xFF202C33),
      ),
      body: _isLoading 
        ? Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.redAccent),
              const SizedBox(height: 20),
              Text(AppTranslations.translate(c, 'delete_acc_deleting'), style: const TextStyle(color: Colors.white70)),
            ],
          ))
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                const Icon(Icons.delete_forever, color: Colors.redAccent, size: 80),
                const SizedBox(height: 16),
                Text(
                  AppTranslations.translate(c, 'delete_acc_warning'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 30),
                _buildPoint(AppTranslations.translate(c, 'delete_acc_point1')),
                _buildPoint(AppTranslations.translate(c, 'delete_acc_point2')),
                _buildPoint(AppTranslations.translate(c, 'delete_acc_point3')),
                const SizedBox(height: 40),

                // PASSWORD
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppTranslations.translate(c, 'chg_num_pass_label'),
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.redAccent),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true, fillColor: Colors.white.withAlpha(15),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? AppTranslations.translate(c, 'error_fill_all') : null,
                ),

                // FORGOT PASSWORD
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const PhoneAuthScreen(isResetModeInitially: true))),
                    child: Text(AppTranslations.translate(c, 'forgot_password'), style: const TextStyle(color: Colors.amber)),
                  ),
                ),

                const SizedBox(height: 15),

                // CONFIRMATION
                CheckboxListTile(
                  title: Text(AppTranslations.translate(c, 'delete_acc_confirm_text'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  value: _isConfirmed,
                  onChanged: (v) => setState(() => _isConfirmed = v ?? false),
                  activeColor: Colors.redAccent,
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                const SizedBox(height: 40),
                SizedBox(
                  height: 58,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _isConfirmed ? Colors.redAccent : Colors.grey.shade800, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    onPressed: _isConfirmed ? () => _handleDeleteAccount(c) : null,
                    child: Text(AppTranslations.translate(c, 'delete_acc_btn').toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(children: [
        const Icon(Icons.cancel, color: Colors.redAccent, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14))),
      ]),
    );
  }
}