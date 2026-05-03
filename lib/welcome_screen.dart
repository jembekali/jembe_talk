import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/phone_auth_screen.dart';
import 'package:page_transition/page_transition.dart';
import 'package:jembe_talk/app_translations.dart';
import 'package:url_launcher/url_launcher.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLanguageMenuOpen = false;

  void _toggleLanguageMenu() {
    setState(() {
      _isLanguageMenuOpen = !_isLanguageMenuOpen;
    });
  }

  Future<void> _launchURL() async {
    final Uri url = Uri.parse('https://sites.google.com/view/jembe-talk-policy/home');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'ki': return 'Ikirundi';
      case 'sw': return 'Kiswahili';
      case 'en': return 'English';
      case 'fr': return 'Français';
      default: return 'Ikirundi';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String c = lang.currentLanguage;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 28, 41, 53),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 50), 
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Image.asset('assets/images/welcome_logo.png', height: 250.0),
                    ),
                  ),
                  Expanded(
                    flex: 4, 
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.25), 
                            borderRadius: BorderRadius.circular(15.0),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    AppTranslations.translate(c, 'terms_title'),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppTranslations.translate(c, 'welcome_terms'), 
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 13.0, height: 1.4),
                              ),
                              TextButton(
                                onPressed: _launchURL,
                                child: Text(
                                  AppTranslations.translate(c, 'read_more'),
                                  style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25.0),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              PageTransition(
                                type: PageTransitionType.rightToLeftWithFade,
                                child: const PhoneAuthScreen(),
                                duration: const Duration(milliseconds: 1000),
                                curve: Curves.easeInOut,
                                isIos: true,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color.fromARGB(255, 21, 29, 65),
                            minimumSize: const Size.fromHeight(55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
                            elevation: 5.0,
                          ),
                          child: Text(
                            AppTranslations.translate(c, 'login_phone_btn'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 15.0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            Positioned(
              top: 10, right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _toggleLanguageMenu,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.language, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(_getLanguageName(lang.currentLanguage), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _isLanguageMenuOpen ? 0.5 : 0, 
                            duration: const Duration(milliseconds: 300),
                            child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.fastOutSlowIn,
                    height: _isLanguageMenuOpen ? 180 : 0, 
                    width: 150,
                    decoration: BoxDecoration(color: const Color.fromARGB(255, 20, 24, 75), borderRadius: BorderRadius.circular(15)),
                    clipBehavior: Clip.hardEdge, 
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          // IKIRUNDI NI CYO KIZA MBERE
                          _buildLangItem(context, lang, 'ki', 'Ikirundi'),
                          _buildLangItem(context, lang, 'sw', 'Kiswahili'),
                          _buildLangItem(context, lang, 'en', 'English'),
                          _buildLangItem(context, lang, 'fr', 'Français'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLangItem(BuildContext context, LanguageProvider lang, String code, String name) {
    final bool isSelected = lang.currentLanguage == code;
    return InkWell(
      onTap: () {
        lang.changeLanguage(code);
        setState(() => _isLanguageMenuOpen = false);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: TextStyle(color: Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            if (isSelected) const Icon(Icons.check, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}