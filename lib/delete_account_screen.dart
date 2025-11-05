// Code ya: JEMBE TALK APP
// Dosiye: lib/delete_account_screen.dart

import 'package:flutter/material.dart';
// NAKUYEHO 'package:firebase_auth/firebase_auth.dart' UBU NDABONAKO NTAKIYIKENEYE
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).dialogBackgroundColor,
          title: const Text("Uremera vy'ukuri?"),
          content: const Text("Iki gikorwa ntigisubirwako. Amakuru yawe yose azofutwa burundu."),
          actions: [
            TextButton(
              child: Text("OYA", style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("EGO, FUTA", style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAccount();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount() async {
    setState(() => _isDeleting = true);

    try {
      await Future.delayed(const Duration(seconds: 3));

      // Hano ni ho code yo gufuta umukoresha muri Firebase yoshirwa
      // await FirebaseAuth.instance.currentUser?.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          (Route<dynamic> route) => false,
        );
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Konti yawe yafuswe neza."), backgroundColor: Colors.green),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Habaye ikibazo mu gufuta konte: ${e.toString()}"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Gufuta Konti Yanje")),
      body: _isDeleting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text("Turiko turafuta amakuru yawe..."),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  "Gufuta konti yawe ni igikorwa ca burundu",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(color: Colors.red),
                ),
                const SizedBox(height: 24),
                
                _buildConsequencePoint(context, "Konti yawe izofutwa muri Jembe Talk."),
                _buildConsequencePoint(context, "Ibiganiro vyose warimwo bizofutika."),
                _buildConsequencePoint(context, "Ntibizoshoboka ko wongera kugarura amakuru yawe."),
                
                const SizedBox(height: 32),
                
                CheckboxListTile(
                  title: const Text("Ndemera ko ndabitahuye neza kandi nshaka gufuta konte yanje burundu."),
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
                    child: const Text("FUTA KONTE YANJE", style: TextStyle(fontWeight: FontWeight.bold)),
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