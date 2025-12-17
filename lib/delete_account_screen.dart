// Code ya: JEMBE TALK APP
// Dosiye: lib/delete_account_screen.dart (YAKOSOWE NEZA)

import 'package:cloud_firestore/cloud_firestore.dart'; // Ntiwibagire iyi
import 'package:firebase_auth/firebase_auth.dart';     // Ntiwibagire iyi
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/welcome_screen.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _isConfirmed = false;
  bool _isDeleting = false;

  void _showFinalConfirmationDialog() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).dialogBackgroundColor,
          title: Text(lang.t('delete_acc_dialog_title')), 
          content: Text(lang.t('delete_acc_dialog_msg')),
          actions: [
            TextButton(
              child: Text(lang.t('delete_acc_dialog_no'), style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(lang.t('delete_acc_dialog_yes'), style: const TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAccount(); // Tugiye guhamagara function yakosowe
              },
            ),
          ],
        );
      },
    );
  }

  // --- IYI NI YO MPINDUKA NYAMUKURU ---
  Future<void> _deleteAccount() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    setState(() => _isDeleting = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        // 1. Gusiba amakuru muri FIRESTORE (Database)
        // Ibi bigomba gukorwa IMBERE yo gusiba Auth, kuko iyo amaze gusibwa muri Auth
        // ashobora kutabona uburenganzira bwo gusiba muri database (Permission denied).
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();

        // 2. Gusiba umukoresha muri AUTHENTICATION (Login)
        await user.delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(lang.t('delete_acc_success')), backgroundColor: Colors.green),
          );
          
          // Gusubira kuri Welcome Screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (Route<dynamic> route) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage = "${lang.t('error_generic')} ${e.message}";
        
        // Firebase isaba ko iyo ugiye gusiba konti, ugomba kuba uheruka kwinjira vuba (Recent Login).
        if (e.code == 'requires-recent-login') {
          errorMessage = "Utegerezwa kubanza gusohoka hanyuma ukongera kwinjira kugira ufute konti.";
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${lang.t('error_generic')} $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }
  // --- IMPINDUKA IRARANGIRIYE HANO ---

  @override
  Widget build(BuildContext context) {
    // ... Code ya UI yose iguma uko yari imeze ...
    // Nta kintu na kimwe gihinduka muri build() uretse ko _deleteAccount ubu ikora bya nyabyo.
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text(lang.t('delete_acc_title'))),
      body: _isDeleting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(lang.t('delete_acc_deleting')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  lang.t('delete_acc_warning'), 
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(color: Colors.red),
                ),
                const SizedBox(height: 24),
                
                _buildConsequencePoint(context, lang.t('delete_acc_point1')),
                _buildConsequencePoint(context, lang.t('delete_acc_point2')),
                _buildConsequencePoint(context, lang.t('delete_acc_point3')),
                
                const SizedBox(height: 32),
                
                CheckboxListTile(
                  title: Text(lang.t('delete_acc_confirm_text')),
                  value: _isConfirmed,
                  onChanged: (bool? value) {
                    setState(() => _isConfirmed = value ?? false);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.red,
                ),
                
                const SizedBox(height: 32),
                
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConfirmed ? Colors.red : Colors.grey.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isConfirmed ? _showFinalConfirmationDialog : null,
                    child: Text(lang.t('delete_acc_btn'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildConsequencePoint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.close, color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}