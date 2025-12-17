import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/phone_auth_screen.dart';
import 'package:page_transition/page_transition.dart'; // <<<--- IMPORT YA PAKI NSHASHA

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Iyi variable idufasha kumenya niba menu yugaye canke yuguruye
  bool _isLanguageMenuOpen = false;

  void _toggleLanguageMenu() {
    setState(() {
      _isLanguageMenuOpen = !_isLanguageMenuOpen;
    });
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'ki': return 'Kirundi';
      case 'sw': return 'Kiswahili';
      case 'en': return 'English';
      case 'fr': return 'Français';
      default: return 'Kirundi';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 28, 41, 53),
      body: SafeArea(
        child: Stack(
          children: [
            // GICE C'INYUMA (Logo, Text, Button)
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
                      child: Image.asset(
                        'assets/images/welcome_logo.png',
                        height: 250.0,
                      ),
                    ),
                  ),
                  
                  Expanded(
                    flex: 3, 
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        
                        // AGASANDUGU K'IMENYEKESHA
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
                                    lang.t('terms_title'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                lang.t('welcome_terms'), 
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white, 
                                  fontSize: 13.0,
                                  height: 1.4, 
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ----------------------------------------

                        const SizedBox(height: 25.0),
                        
                        ElevatedButton(
                          onPressed: () {
                            // <<<--- HANO NI HO DUKORESHWA ANIMATION Y'UMUYAGA --->>>
                            Navigator.push(
                              context,
                              PageTransition(
                                type: PageTransitionType.rightToLeftWithFade, // Ica iburyo iza ibumoso ivanze no gukendera
                                child: const PhoneAuthScreen(),
                                duration: const Duration(milliseconds: 1000), // Isegonda 1 (Buke buke)
                                curve: Curves.easeInOut, // Kugenda nk'umuyaga (byihuta gato hagati, bigatinda kurangira)
                                isIos: true, // Bituma bigenda neza kuri iOS na Android
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color.fromARGB(255, 21, 29, 65),
                            minimumSize: const Size.fromHeight(55),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                            ),
                            elevation: 5.0,
                          ),
                          child: Text(
                            lang.t('login_phone_btn'),
                            style: const TextStyle(
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

            // MENU Y'INDIMI NA ANIMATION
            Positioned(
              top: 10,
              right: 24,
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
                          Text(
                            _getLanguageName(lang.currentLanguage),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 20, 24, 75), 
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge, 
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          _buildLangItem(context, lang, 'ki', 'Kirundi'),
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
        setState(() {
          _isLanguageMenuOpen = false;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: TextStyle(
                color: Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}