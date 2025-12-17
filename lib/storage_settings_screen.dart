import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:shared_preferences/shared_preferences.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  Set<String> _wifiDownloads = {'photo', 'audio'};
  Set<String> _dataDownloads = {'photo'};
  bool _isLoading = true;

  // Iyi Map izakoresha keys gusa, amazina tuzayahindura dukoresheje lang.t()
  final List<String> _mediaTypes = ['photo', 'audio', 'video', 'document'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _wifiDownloads = Set<String>.from(prefs.getStringList('wifiDownloads') ?? ['photo', 'audio']);
        _dataDownloads = Set<String>.from(prefs.getStringList('dataDownloads') ?? ['photo']);
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('wifiDownloads', _wifiDownloads.toList());
    await prefs.setStringList('dataDownloads', _dataDownloads.toList());
  }

  void _showFeatureNotReady(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lang.t('feature_not_ready')),
        backgroundColor: Colors.blueGrey,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showAutoDownloadDialog(BuildContext context, String title, Set<String> currentSelections) async {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final Set<String> tempSelections = Set<String>.from(currentSelections);

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: theme.dialogBackgroundColor,
              title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _mediaTypes.map((key) {
                    // Guhindura izina rya media (Amafoto -> Photos...)
                    String localizedName = lang.t('storage_$key'); 
                    return _buildCheckbox(context, localizedName, key, tempSelections, setDialogState);
                  }).toList(),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(lang.t('btn_cancel'), style: TextStyle(color: theme.colorScheme.secondary)), // REKA
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: Text(lang.t('btn_confirm'), style: TextStyle(color: theme.colorScheme.secondary)), // EMEZA
                  onPressed: () {
                    setState(() {
                      if (title == lang.t('dialog_wifi')) {
                        _wifiDownloads = tempSelections;
                      } else {
                        _dataDownloads = tempSelections;
                      }
                    });
                    _saveSettings();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  Widget _buildCheckbox(BuildContext context, String title, String key, Set<String> selections, StateSetter setDialogState) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
      value: selections.contains(key),
      onChanged: (bool? value) {
        setDialogState(() {
          if (value == true) {
            selections.add(key);
          } else {
            selections.remove(key);
          }
        });
      },
      activeColor: theme.colorScheme.secondary,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  String _getSubtitle(Set<String> selections, LanguageProvider lang) {
    if (selections.isEmpty) return lang.t('storage_no_media');
    return selections.map((key) => lang.t('storage_$key')).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context); // Provider

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(lang.t('storage_title')), // "Ububiko bw'Amakuru"
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView(
            children: [
              _buildSettingsItem(
                context,
                icon: Icons.folder_open_outlined,
                title: lang.t('storage_manage'), // "Genzura ububiko"
                subtitle: lang.t('storage_manage_sub'),
                onTap: () => _showFeatureNotReady(context),
              ),
              _buildSettingsItem(
                context,
                icon: Icons.network_check_outlined,
                title: lang.t('storage_network'), // "Ikoreshwa rya Internet"
                subtitle: lang.t('storage_network_sub'),
                onTap: () => _showFeatureNotReady(context),
              ),
              Divider(color: theme.dividerColor.withAlpha(80)),
              _buildSectionHeader(context, lang.t('storage_auto_download')), // "GUTELESHARIJA..."
              _buildSettingsItem(
                context,
                icon: Icons.data_usage_outlined,
                title: lang.t('storage_mobile_data'), // "Iyo ukoresha Internet..."
                subtitle: _getSubtitle(_dataDownloads, lang),
                onTap: () => _showAutoDownloadDialog(context, lang.t('dialog_mobile_data'), _dataDownloads),
              ),
              _buildSettingsItem(
                context,
                icon: Icons.wifi_outlined,
                title: lang.t('storage_wifi'), // "Iyo ukoresha Wi-Fi"
                subtitle: _getSubtitle(_wifiDownloads, lang),
                onTap: () => _showAutoDownloadDialog(context, lang.t('dialog_wifi'), _wifiDownloads),
              ),
            ],
          ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 20.0, bottom: 8.0, right: 16.0),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSettingsItem(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.textTheme.bodyMedium?.color),
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8))),
      onTap: onTap,
    );
  }
}