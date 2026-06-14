// lib/user_blocked_screen.dart (VERSION 4.0 - REDIRECT TO HELP SETTINGS)

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/help_settings_screen.dart'; // <--- IYI NIYO IYOBORA UBUTUMWA

class UserBlockedScreen extends StatelessWidget {
  const UserBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Gura language provider kugira ngo indimi zikore
    final lang = Provider.of<LanguageProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Koresha ibara ry'umukara nk'irya Login niba ari Dark Mode
      backgroundColor: isDark ? const Color(0xFF1C2935) : Colors.white,
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- 1. ICON Y'UMUTUKU (Blocked Icon) ---
            const Icon(Icons.block_flipped, color: Colors.redAccent, size: 100),
            const SizedBox(height: 30),

            // --- 2. TITLE (Translated) ---
            Text(
              lang.t('blocked_title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // --- 3. DESCRIPTION (Translated) ---
            Text(
              lang.t('blocked_desc'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 15,
                  height: 1.5),
            ),
            const SizedBox(height: 50),

            // --- 4. 🔥 BUTO IYOBORA KURI HELP SETTINGS SCREEN ---
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Mujyane kuri HelpSettingsScreen imaze guhitamo 'ban_appeal'
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => const HelpSettingsScreen(
                        initialCategory: 'help_cat_ban_appeal',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.support_agent_rounded,
                    color: Colors.white),
                label: Text(lang.t('blocked_btn_contact'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade800,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15))),
              ),
            ),

            const SizedBox(height: 25),

            // --- 5. BUTO YO GUSOHOKA (LOGOUT) ---
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                // Garuka kuri WelcomeScreen (kuko authGate izahita ibimenya)
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              child: Text(lang.t('blocked_logout'),
                  style: const TextStyle(
                      color: Colors.white38,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }
}
