// Code ya: JEMBE TALK APP
// Dosiye: lib/change_number_info_screen.dart

import 'package:flutter/material.dart';
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/change_number_input_screen.dart'; // Ubu iyi dosiye irahari

class ChangeNumberInfoScreen extends StatelessWidget {
  const ChangeNumberInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Guhindura Nimero"),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phonelink_setup_outlined, size: 80, color: Colors.tealAccent),
                  SizedBox(height: 24),
                  Text(
                    "Guhindura nimero yawe ya terefone",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                    text: "Guhindura nimero bizokwimura amakuru ya konte yawe yose bishigwe kuri nimero nshasha.",
                  ),
                  const SizedBox(height: 20),
                  _buildInfoPoint(
                    context,
                    icon: Icons.sms_outlined,
                    text: "Imbere yo kubandanya, ni ngombwa ko wemeza neza ko nimero yawe nshasha ishobora kwakira SMS.",
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
                  // <<--- AHA NIHO HARI IMPINDUKA NKOZE --- >>
                  // Ubu tuja kuri paje ikurikira
                  Navigator.pushReplacement(context, SlideRightPageRoute(page: const ChangeNumberInputScreen()));
                },
                child: const Text("BANDANYA", style: TextStyle(fontSize: 16)),
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