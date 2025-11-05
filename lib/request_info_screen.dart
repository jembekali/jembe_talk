// Code ya: JEMBE TALK APP
// Dosiye: lib/request_info_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/report_display_screen.dart';

class RequestInfoScreen extends StatefulWidget {
  const RequestInfoScreen({super.key});

  @override
  State<RequestInfoScreen> createState() => _RequestInfoScreenState();
}

class _RequestInfoScreenState extends State<RequestInfoScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> _requestAndShowReport() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nta mukoresha ari muri konti.")));
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        Navigator.push(context, SlideRightPageRoute(page: ReportDisplayScreen(reportData: data)));
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Amakuru yawe ntiyabonetse."), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Habaye ikibazo: $e"), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Gusaba Amakuru ya Konte")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.description_outlined, size: 80, color: Colors.tealAccent),
            const SizedBox(height: 24),
            Text("Saba raporo y'amakuru ya konte yawe.", textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text(
              "Iyi raporo izoba irimwo amakuru ya porofili yawe (izina, ifoto, nimero), ariko ntizoba irimwo ibiganiro canke ama posts yawe kubera bifudika.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            _isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.secondary,
                        foregroundColor: theme.colorScheme.onSecondary,
                      ),
                      icon: const Icon(Icons.download_for_offline_outlined),
                      label: const Text("SABA RAPORO", style: TextStyle(fontSize: 16)),
                      onPressed: _requestAndShowReport,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}