import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart'; // Twakoresheje iyi kuko yo ihari
import 'package:provider/provider.dart'; 
import 'package:jembe_talk/language_provider.dart'; 
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _conversationTones = true;
  String _messageTone = "Jembe Tone";
  String _messageVibrate = "Ubusanzwe"; 
  String _callTone = "Umuduri"; 
  String _callVibrate = "Nde-nde"; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllNotificationSettings();
  }

  Future<void> _loadAllNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _conversationTones = prefs.getBool('notifications_tones_enabled') ?? true;
        _messageTone = prefs.getString('notifications_message_tone') ?? 'Jembe Tone';
        _messageVibrate = prefs.getString('notifications_message_vibrate') ?? 'Ibisanzwe';
        _callTone = prefs.getString('notifications_call_tone') ?? 'Umuduri';
        _callVibrate = prefs.getString('notifications_call_vibrate') ?? 'Nde-nde';
        _isLoading = false;
      });
    }
  }

  // ... (Ibindi bice bya kodi biguma uko byari biri kugeza kuri ToneSelectionDialog)

  void _selectTone(bool isForCall) async {
    final selectedTone = await showDialog<String>(context: context, builder: (context) => const ToneSelectionDialog());
    if (selectedTone != null) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        if (isForCall) {
          _callTone = selectedTone;
          prefs.setString('notifications_call_tone', selectedTone);
        } else {
          _messageTone = selectedTone;
          prefs.setString('notifications_message_tone', selectedTone);
        }
      });
    }
  }

  void _selectVibrateMode(bool isForCall) async {
    final selectedMode = await showDialog<String>(context: context, builder: (context) => const VibrateSelectionDialog());
    if (selectedMode != null) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        if (isForCall) {
          _callVibrate = selectedMode;
          prefs.setString('notifications_call_vibrate', selectedMode);
        } else {
          _messageVibrate = selectedMode;
          prefs.setString('notifications_message_vibrate', selectedMode);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);

    String getLocalizedVibrate(String mode) {
      if (mode == 'Ibisanzwe' || mode == 'Default') return lang.t('vib_default');
      if (mode == 'Ngufi' || mode == 'Short') return lang.t('vib_short');
      if (mode == 'Nde-nde' || mode == 'Long') return lang.t('vib_long');
      if (mode == 'Ntibikogwa' || mode == 'Off') return lang.t('vib_off');
      return mode;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(lang.t('notif_title')), backgroundColor: theme.appBarTheme.backgroundColor),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView(
        children: [
          SwitchListTile(
            title: Text(lang.t('notif_conv_tones'), style: TextStyle(color: theme.textTheme.bodyLarge?.color)), 
            subtitle: Text(lang.t('notif_conv_tones_sub'), style: TextStyle(color: theme.textTheme.bodyMedium?.color)), 
            value: _conversationTones, 
            onChanged: (v) => _toggleConversationTones(v), 
            activeColor: theme.colorScheme.secondary, 
            secondary: Icon(Icons.music_note_outlined, color: theme.textTheme.bodyMedium?.color)
          ),
          Divider(color: theme.dividerColor.withAlpha(80), height: 1), 
          const SizedBox(height: 10),
          
          _buildSectionHeader(context, lang.t('notif_header_msg')), 
          _buildSettingsItem(context, icon: Icons.notifications_outlined, title: lang.t('notif_msg_tone'), subtitle: _messageTone, onTap: () => _selectTone(false)),
          _buildSettingsItem(context, icon: Icons.vibration_outlined, title: lang.t('notif_vibrate'), subtitle: getLocalizedVibrate(_messageVibrate), onTap: () => _selectVibrateMode(false)),
          
          const SizedBox(height: 10),
          _buildSectionHeader(context, lang.t('notif_header_call')), 
          _buildSettingsItem(context, icon: Icons.ring_volume_outlined, title: lang.t('notif_call_tone'), subtitle: _callTone, onTap: () => _selectTone(true)),
          _buildSettingsItem(context, icon: Icons.vibration_outlined, title: lang.t('notif_vibrate'), subtitle: getLocalizedVibrate(_callVibrate), onTap: () => _selectVibrateMode(true)),
        ],
      ),
    );
  }

  Future<void> _toggleConversationTones(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _conversationTones = value);
    await prefs.setBool('notifications_tones_enabled', value);
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0), child: Text(title, style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold, fontSize: 12)));
  }

  Widget _buildSettingsItem(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.textTheme.bodyMedium?.color), 
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color)), 
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8))), 
      onTap: onTap
    );
  }
}

class ToneSelectionDialog extends StatefulWidget {
  const ToneSelectionDialog({super.key});
  @override
  State<ToneSelectionDialog> createState() => _ToneSelectionDialogState();
}

class _ToneSelectionDialogState extends State<ToneSelectionDialog> {
  final AudioPlayer _player = AudioPlayer();
  final Map<String, String> _sounds = {'Jembe Tone': 'jembe_tone.mp3',  'Come To Me': 'come_to_me.mp3', 'Guitar': 'guitar.mp3', 'Indingiti': 'indingiti.mp3', 'Ntacobitwaye': 'ntacobitwaye.mp3', 'Mama': 'pawan.mp3', 'Piano': 'piano.mp3', 'Umuduri': 'umuduri.mp3', 'Nta jwi': 'none'};
  String? _currentlyPlaying;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _playSound(String displayName, String fileName) async {
    if (fileName == 'none') return;
    setState(() => _currentlyPlaying = displayName);
    try {
      await _player.setAsset('assets/audio/$fileName');
      await _player.play();
    } catch (e) {
      debugPrint("Error playing audio: $e");
    } finally {
      if (mounted) setState(() => _currentlyPlaying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    return AlertDialog(
      title: Text(lang.t('notif_dialog_tone_title')), 
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: _sounds.entries.map((entry) {
            return ListTile(
              title: Text(entry.key),
              trailing: _currentlyPlaying == entry.key ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: () => Navigator.of(context).pop(entry.key),
              leading: IconButton(icon: const Icon(Icons.play_circle_outline), onPressed: () => _playSound(entry.key, entry.value)),
            );
          }).toList(),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(lang.t('btn_close')))],
    );
  }
}

class VibrateSelectionDialog extends StatelessWidget {
  const VibrateSelectionDialog({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final Map<String, String> modes = {'Ibisanzwe': lang.t('vib_default'), 'Ngufi': lang.t('vib_short'), 'Nde-nde': lang.t('vib_long'), 'Ntibikogwa': lang.t('vib_off')};
    return AlertDialog(
      title: Text(lang.t('notif_dialog_vibrate_title')), 
      content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: modes.length, itemBuilder: (context, index) {
        return ListTile(title: Text(modes.values.elementAt(index)), onTap: () => Navigator.of(context).pop(modes.keys.elementAt(index)));
      })),
    );
  }
}