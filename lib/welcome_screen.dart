// welcome_screen.dart (YAKOSOWE)

import 'package:flutter/material.dart';
import 'package:jembe_talk/phone_auth_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E8449),
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Center(
                  child: Image.asset(
                    'assets/images/welcome_logo.png',
                    height: 250.0,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      "Imbere yuko winjira, banza wemere ko utazokoresha uru rubuga mubintu vyose vyigisha irwanko canke ibintu vyose bitandukanye n'umuco w'akarere k'ibiyaga binini. Utegerezwa kandi kuba wemeye ko utazokoresha uru rubuga mu bintu birenga ku mategeko y'Igihugu cawe.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.0,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 25.0),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const PhoneAuthScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1E8449),
                        minimumSize: const Size.fromHeight(55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        elevation: 5.0,
                      ),
                      // << HANO NIHO HAHINDUTSE >>
                      child: const Text(
                        'Injira Ukoresheje Telefone',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 15.0),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}