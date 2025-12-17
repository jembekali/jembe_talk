import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _conversationTones = true;
  String _messageTone = "Jembe Tone";
  String _messageVibrate = "Ubusanzwe"; // Ibi bizahinduka kuri UI
  String _callTone = "Umuduri"; 
  String _callVibrate = "Nde-nde"; // Ibi bizahinduka kuri UI
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

  Future<void> _toggleConversationTones(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _conversationTones = value);
    await prefs.setBool('notifications_tones_enabled', value);
  }

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

    // Guhindura amazina ya vibration bijyanye n'ururimi kuri display gusa
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
            onChanged: _toggleConversationTones, 
            activeColor: theme.colorScheme.secondary, 
            secondary: Icon(Icons.music_note_outlined, color: theme.textTheme.bodyMedium?.color)
          ),
          Divider(color: theme.dividerColor.withAlpha(80), height: 1), 
          const SizedBox(height: 10),
          
          _buildSectionHeader(context, lang.t('notif_header_msg')), // "UBUTUMWA"
          _buildSettingsItem(
            context, 
            icon: Icons.notifications_outlined, 
            title: lang.t('notif_msg_tone'), // "Ijwi ry'ubutumwa"
            subtitle: _messageTone, // Izina ry'ijwi riguma uko riri
            onTap: () => _selectTone(false)
          ),
          _buildSettingsItem(
            context, 
            icon: Icons.vibration_outlined, 
            title: lang.t('notif_vibrate'), // "Kunyiganyiza"
            subtitle: getLocalizedVibrate(_messageVibrate), 
            onTap: () => _selectVibrateMode(false)
          ),
          
          const SizedBox(height: 10),
          _buildSectionHeader(context, lang.t('notif_header_call')), // "AMAHAMAGARA"
          _buildSettingsItem(
            context, 
            icon: Icons.ring_volume_outlined, 
            title: lang.t('notif_call_tone'), // "Ijwi ry'ihamagara"
            subtitle: _callTone, 
            onTap: () => _selectTone(true)
          ),
          _buildSettingsItem(
            context, 
            icon: Icons.vibration_outlined, 
            title: lang.t('notif_vibrate'), 
            subtitle: getLocalizedVibrate(_callVibrate), 
            onTap: () => _selectVibrateMode(true)
          ),
        ],
      ),
    );
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

// ==========================================================
// DIALOGS ZIFITE LANGUAGE PROVIDER
// ==========================================================
class ToneSelectionDialog extends StatefulWidget {
  const ToneSelectionDialog({super.key});
  @override
  State<ToneSelectionDialog> createState() => _ToneSelectionDialogState();
}

class _ToneSelectionDialogState extends State<ToneSelectionDialog> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _sounds = {'Jembe Tone': 'jembe_tone.mp3', 'Chime': 'chime.mp3', 'Come To Me': 'come_to_me.mp3', 'Furaha': 'furaha.mp3', 'Good Morning': 'good_morning.mp3', 'Guitar': 'guitar.mp3', 'Indingiti': 'indingiti.mp3', 'Ntacobitwaye': 'ntacobitwaye.mp3', 'Pawan': 'pawan.mp3', 'Piano': 'piano.mp3', 'Tweet': 'tweet.mp3', 'Umuduri': 'umuduri.mp3', 'Nta jwi': 'none'};
  String? _currentlyPlaying;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _playSound(String displayName, String fileName) async {
    if (_currentlyPlaying != null) await _audioPlayer.stop();
    setState(() => _currentlyPlaying = displayName);
    if (fileName != 'none') {
      try {
        await _audioPlayer.play(AssetSource('audio/$fileName'));
        _audioPlayer.onPlayerComplete.first.then((_) {
          if (mounted) setState(() => _currentlyPlaying = null);
        });
      } catch (e) {
        if (mounted) setState(() => _currentlyPlaying = null);
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _currentlyPlaying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    return AlertDialog(
      title: Text(lang.t('notif_dialog_tone_title')), // "Hitamwo ijwi"
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
    // Hano dukoresha keys kugira tubike (values), ariko tugaragaza amazina (labels)
    final Map<String, String> modes = {
      'Ibisanzwe': lang.t('vib_default'),
      'Ngufi': lang.t('vib_short'),
      'Nde-nde': lang.t('vib_long'),
      'Ntibikogwa': lang.t('vib_off'),
    };

    return AlertDialog(
      title: Text(lang.t('notif_dialog_vibrate_title')), // "Hitamwo uko Vibration ikora"
      content: SizedBox(
        width: double.maxFinite, 
        child: ListView.builder(
          shrinkWrap: true, 
          itemCount: modes.length, 
          itemBuilder: (context, index) {
            String key = modes.keys.elementAt(index);
            String label = modes.values.elementAt(index);
            return ListTile(
              title: Text(label), 
              onTap: () => Navigator.of(context).pop(key) // Tubika Key (Kirundi original) kugira code itavangirwa
            );
          }
        )
      ),
    );
  }
}