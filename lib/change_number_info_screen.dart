import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/change_number_input_screen.dart';

class ChangeNumberInfoScreen extends StatelessWidget {
  const ChangeNumberInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context); // Provider

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(lang.t('chg_num_title')), // "Guhindura Nimero"
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phonelink_setup_outlined, size: 80, color: Colors.tealAccent),
                  const SizedBox(height: 24),
                  Text(
                    lang.t('chg_num_header'), // "Guhindura nimero..."
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoPoint(
                    context,
                    icon: Icons.move_up_outlined,
                    text: lang.t('chg_num_info1'), // "Guhindura nimero bizokwimura..."
                  ),
                  const SizedBox(height: 20),
                  _buildInfoPoint(
                    context,
                    icon: Icons.sms_outlined,
                    text: lang.t('chg_num_info2'), // "Imbere yo kubandanya..."
                  ),
                ],
              ),
            ),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pushReplacement(context, SlideRightPageRoute(page: const ChangeNumberInputScreen()));
                },
                child: Text(lang.t('btn_continue'), style: const TextStyle(fontSize: 16)), // "BANDANYA"
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPoint(BuildContext context, {required IconData icon, required String text}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: theme.textTheme.bodyMedium?.color?.withAlpha(180)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 15, color: theme.textTheme.bodyMedium?.color, height: 1.4)),
        ),
      ],
    );
  }
}