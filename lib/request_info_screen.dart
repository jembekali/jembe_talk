import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // <<< PROVIDER
import 'package:jembe_talk/language_provider.dart'; // <<< LANGUAGE PROVIDER
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
    // Kugira tubone ubutumwa bw'ikosa mu rurimi rukwiye (listen: false mu ma async functions)
    final lang = Provider.of<LanguageProvider>(context, listen: false); 
    
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('req_error_no_user'))));
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        Navigator.push(context, SlideRightPageRoute(page: ReportDisplayScreen(reportData: data)));
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('req_error_not_found')), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('error_generic')} $e"), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context); // PROVIDER

    return Scaffold(
      appBar: AppBar(title: Text(lang.t('req_info_title'))), // "Gusaba Amakuru..."
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.description_outlined, size: 80, color: Colors.tealAccent),
            const SizedBox(height: 24),
            Text(lang.t('req_info_subtitle'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text(
              lang.t('req_info_desc'), // "Iyi raporo izoba irimwo..."
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
                      label: Text(lang.t('req_info_btn'), style: const TextStyle(fontSize: 16)), // "SABA RAPORO"
                      onPressed: _requestAndShowReport,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}