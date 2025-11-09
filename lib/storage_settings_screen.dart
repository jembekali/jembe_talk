// Code ya: JEMBE TALK APP
// Dosiye: lib/storage_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  // Igenekerezo tuzobika
  Set<String> _wifiDownloads = {'photo', 'audio'};
  Set<String> _dataDownloads = {'photo'};
  bool _isLoading = true;

  // Amazina y'amadosiye n'utubuto twayo
  final Map<String, String> _mediaTypeNames = {
    'photo': 'Amafoto',
    'audio': 'Amajwi',
    'video': 'Amavideo',
    'document': 'Inyandiko',
  };

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Iki gice ntikirakora. Kizoshirwamwo vuba."),
        backgroundColor: Colors.blueGrey,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showAutoDownloadDialog(BuildContext context, String title, Set<String> currentSelections) async {
    final theme = Theme.of(context);
    // Dukora kopi y'amahitamwo kugira ngo umukoresha ashobore kureka ivyo yahinduye
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
                  // Aha nzotegerezwa kwama nibukako nubaka amahitamwo nkoresheje ya Map nakoze hejuru
                  children: _mediaTypeNames.entries.map((entry) {
                    return _buildCheckbox(context, entry.value, entry.key, tempSelections, setDialogState);
                  }).toList(),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('UGARA', style: TextStyle(color: theme.colorScheme.secondary)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: Text('EMEZA', style: TextStyle(color: theme.colorScheme.secondary)),
                  onPressed: () {
                    setState(() {
                      if (title.contains("Wi-Fi")) {
                        _wifiDownloads = tempSelections;
                      } else {
                        _dataDownloads = tempSelections;
                      }
                    });
                    _saveSettings(); // Turabika impinduka
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
      controlAffinity: ListTileControlAffinity.leading, // Dushize imbere
    );
  }

  // Ubu twerekana amazina y'Ikirundi yuzuye
  String _getSubtitle(Set<String> selections) {
    if (selections.isEmpty) return "Nta dosiye iboneka";
    return selections.map((key) => _mediaTypeNames[key] ?? '').where((name) => name.isNotEmpty).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Ububiko bw'Amakuru"),
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView(
            children: [
              _buildSettingsItem(
                context,
                icon: Icons.folder_open_outlined,
                title: "Genzura ububiko",
                subtitle: "Menya umwanya dosiye zawe zifata",
                onTap: () => _showFeatureNotReady(context),
              ),
              _buildSettingsItem(
                context,
                icon: Icons.network_check_outlined,
                title: "Ikoreshwa rya Internet",
                subtitle: "Raba ingene Internet yawe ikoreshwa",
                onTap: () => _showFeatureNotReady(context),
              ),
              Divider(color: theme.dividerColor.withAlpha(80)),
              _buildSectionHeader(context, "GUTELESHARIJA AMADOSIYE KU BURYO BWIKORA"),
              _buildSettingsItem(
                context,
                icon: Icons.data_usage_outlined,
                title: "Iyo ukoresha Internet ya terefone",
                subtitle: _getSubtitle(_dataDownloads),
                onTap: () => _showAutoDownloadDialog(context, "Kuri Enterineti ya Terefone", _dataDownloads),
              ),
              _buildSettingsItem(
                context,
                icon: Icons.wifi_outlined,
                title: "Iyo ukoresha Wi-Fi",
                subtitle: _getSubtitle(_wifiDownloads),
                onTap: () => _showAutoDownloadDialog(context, "Kuri Wi-Fi", _wifiDownloads),
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