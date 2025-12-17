import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Import Provider
import 'package:jembe_talk/language_provider.dart'; // Import LanguageProvider
import 'package:jembe_talk/custom_page_route.dart';
import 'package:jembe_talk/privacy_settings_screen.dart';
import 'package:jembe_talk/security_settings_screen.dart';
import 'package:jembe_talk/change_number_info_screen.dart';
import 'package:jembe_talk/request_info_screen.dart';
import 'package:jembe_talk/delete_account_screen.dart';

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context); // Gukoresha Provider

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(lang.t('acc_title')), // "Konte"
        backgroundColor: theme.appBarTheme.backgroundColor, 
        elevation: 1
      ),
      body: ListView(
        children: [
          _buildSettingsItem(
            context: context, 
            icon: Icons.lock_outline, 
            title: lang.t('acc_privacy'), // "Ibibazo vy'ibanga"
            subtitle: lang.t('acc_privacy_sub'), 
            onTap: () => Navigator.push(context, SlideRightPageRoute(page: const PrivacySettingsScreen()))
          ),
          _buildSettingsItem(
            context: context, 
            icon: Icons.security_outlined, 
            title: lang.t('acc_security'), // "Umutekano"
            subtitle: lang.t('acc_security_sub'), 
            onTap: () => Navigator.push(context, SlideRightPageRoute(page: const SecuritySettingsScreen()))
          ),
          _buildSettingsItem(
            context: context, 
            icon: Icons.phone_outlined, 
            title: lang.t('acc_change_num'), // "Guhindura nimero"
            subtitle: lang.t('acc_change_num_sub'), 
            onTap: () => Navigator.push(context, SlideRightPageRoute(page: const ChangeNumberInfoScreen()))
          ),
          const Divider(thickness: 0.5, height: 20),
          _buildSettingsItem(
            context: context, 
            icon: Icons.description_outlined, 
            title: lang.t('acc_req_info'), // "Gusaba amakuru..."
            subtitle: lang.t('acc_req_info_sub'), 
            onTap: () => Navigator.push(context, SlideRightPageRoute(page: const RequestInfoScreen()))
          ),
          _buildSettingsItem(
            context: context, 
            icon: Icons.delete_forever_outlined, 
            title: lang.t('acc_delete'), // "Gufuta konte yanje"
            subtitle: lang.t('acc_delete_sub'), 
            onTap: () => Navigator.push(context, SlideRightPageRoute(page: const DeleteAccountScreen())), 
            isDestructive: true
          ),
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