// lib/screens/update_guard_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jembe_talk/language_provider.dart';

class UpdateGuardScreen extends StatelessWidget {
  final int daysLeft;
  final bool forceUpdate;
  final VoidCallback? onSkip;

  const UpdateGuardScreen({
    super.key,
    required this.daysLeft,
    this.forceUpdate = false,
    this.onSkip,
  });

  // Function yo gufungura Play Store
  Future<void> _openPlayStore() async {
    const String playStoreUrl = "https://play.google.com/store/apps/details?id=com.jembetalk.app";
    final Uri url = Uri.parse(playStoreUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        debugPrint("Could not launch Play Store");
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  // 🔥 FUNCTION YO KUBIKA KO UMUKORESHA AKANZE "LATER" (NGO BIZONGERE EJO)
  Future<void> _handleSkipAction() async {
    final prefs = await SharedPreferences.getInstance();
    // Bika igihe cy'ubu (milliseconds)
    await prefs.setInt('last_update_prompt_time', DateTime.now().millisecondsSinceEpoch);
    
    // Hamagara onSkip iri muri main.dart
    if (onSkip != null) onSkip!();
  }

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LanguageProvider>(context);

    String title = forceUpdate 
        ? lp.t('update_required_title') 
        : lp.t('update_available_title');

    String description;
    if (forceUpdate) {
      description = lp.t('update_msg_force');
    } else {
      description = "${lp.t('update_msg_warn_prefix')} $daysLeft ${lp.t('update_msg_warn_suffix')}";
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.system_update_rounded, color: Colors.amber, size: 80),
            ),
            
            const SizedBox(height: 40),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
            ),

            const SizedBox(height: 60),

            // 1. BUTO YA "MAYBE LATER" (YASHIZWE HEJURU)
            if (!forceUpdate)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: TextButton(
                  onPressed: _handleSkipAction,
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  child: Text(
                    lp.t('btn_remind_me'),
                    style: const TextStyle(fontSize: 15, decoration: TextDecoration.underline),
                  ),
                ),
              ),

            // 2. BUTO YA "UPDATE NOW" (YASHIZWE HASI)
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _openPlayStore,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  lp.t('update_btn_now'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 30),
            Text(
              "Package: com.jembetalk.app",
              style: TextStyle(color: Colors.white.withOpacity(0.1), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}