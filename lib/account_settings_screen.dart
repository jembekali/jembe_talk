// Code ya: JEMBE TALK APP
// Dosiye: lib/account_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/privacy_settings_screen.dart';
import 'package:jembe_talk/security_settings_screen.dart';
import 'package:jembe_talk/change_number_info_screen.dart';
import 'package:jembe_talk/request_info_screen.dart';
import 'package:jembe_talk/delete_account_screen.dart'; // TWONGEREYEMWO IYI DOSIYE NSHASHA

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Konti"), backgroundColor: theme.appBarTheme.backgroundColor, elevation: 1),
      body: ListView(
        children: [
          _buildSettingsItem(context: context, icon: Icons.lock_outline, title: "Ibibazo vy'ibanga", subtitle: "Ababona amakuru yawe, abahagaritswe...", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const PrivacySettingsScreen()))),
          _buildSettingsItem(context: context, icon: Icons.security_outlined, title: "Umutekano", subtitle: "Notification y'umutekano, n'ibindi...", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const SecuritySettingsScreen()))),
          _buildSettingsItem(context: context, icon: Icons.phone_outlined, title: "Guhindura nimero", subtitle: "Hindura nimero ya terefone ifatanije na konte", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const ChangeNumberInfoScreen()))),
          const Divider(thickness: 0.5, height: 20),
          _buildSettingsItem(context: context, icon: Icons.description_outlined, title: "Gusaba amakuru ya konte", subtitle: "Saba raporo y'amakuru ya konte yawe", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const RequestInfoScreen()))),
          // UBU IKI GICE CA NYUMA KIRAKORA
          _buildSettingsItem(context: context, icon: Icons.delete_forever_outlined, title: "Gufuta konte yanje", subtitle: "Futa konte yawe burundu, ntisubirako", onTap: () => Navigator.push(context, SlideRightPageRoute(page: const DeleteAccountScreen())), isDestructive: true),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({required BuildContext context, required IconData icon, required String title, required String subtitle, required VoidCallback onTap, bool isDestructive = false}) {
    final theme = Theme.of(context);
    final titleColor = isDestructive ? Colors.redAccent : theme.textTheme.bodyLarge?.color;
    final iconColor = isDestructive ? Colors.redAccent : theme.textTheme.bodyMedium?.color?.withAlpha(180);
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: TextStyle(color: titleColor)),
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withAlpha(180))),
      onTap: onTap,
    );
  }
}