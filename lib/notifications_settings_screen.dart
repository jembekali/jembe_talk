// Code ya: JEMBE TALK APP
// Dosiye: lib/notifications_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Twakuye DatabaseHelper, dushiramwo SharedPreferences

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _conversationTones = true;
  String _messageTone = "Jembe Tone";
  String _messageVibrate = "Ubusanzwe";
  String _callTone = "Umuduri"; // Dutangurana ijwi ritandukanye
  String _callVibrate = "Nde-nde";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllNotificationSettings();
  }

  // Ubu dusoma muri SharedPreferences
  Future<void> _loadAllNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _conversationTones = prefs.getBool('notifications_tones_enabled') ?? true;
        _messageTone = prefs.getString('notifications_message_tone') ?? 'Jembe Tone';
        _messageVibrate = prefs.getString('notifications_message_vibrate') ?? 'Ubusanzwe';
        _callTone = prefs.getString('notifications_call_tone') ?? 'Umuduri';
        _callVibrate = prefs.getString('notifications_call_vibrate') ?? 'Nde-nde';
        _isLoading = false;
      });
    }
  }

  // Ubu tubika muri SharedPreferences
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
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Udusonere"), backgroundColor: theme.appBarTheme.backgroundColor),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView(
        children: [
          SwitchListTile(
            title: Text("Amajwi y'ibiganiro", style: TextStyle(color: theme.textTheme.bodyLarge?.color)), 
            subtitle: Text("Vuza amajwi ku butumwa bwinjira n'ubusohoka.", style: TextStyle(color: theme.textTheme.bodyMedium?.color)), 
            value: _conversationTones, 
            onChanged: _toggleConversationTones, 
            activeColor: theme.colorScheme.secondary, 
            secondary: Icon(Icons.music_note_outlined, color: theme.textTheme.bodyMedium?.color)
          ),
          Divider(color: theme.dividerColor.withAlpha(80), height: 1), // Gukosora withOpacity
          const SizedBox(height: 10),
          
          _buildSectionHeader(context, "UBUTUMWA"),
          _buildSettingsItem(context, icon: Icons.notifications_outlined, title: "Ijwi rya notification", subtitle: _messageTone, onTap: () => _selectTone(false)),
          _buildSettingsItem(context, icon: Icons.vibration_outlined, title: "Kunyiganyiza (Vibration)", subtitle: _messageVibrate, onTap: () => _selectVibrateMode(false)),
          
          const SizedBox(height: 10),
          _buildSectionHeader(context, "AMAHAMAGARA"),
          _buildSettingsItem(context, icon: Icons.ring_volume_outlined, title: "Ijwi ry'ihamagara", subtitle: _callTone, onTap: () => _selectTone(true)),
          _buildSettingsItem(context, icon: Icons.vibration_outlined, title: "Kunyiganyiza (Vibration)", subtitle: _callVibrate, onTap: () => _selectVibrateMode(true)),
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
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8))), // Gukosora withOpacity
      onTap: onTap
    );
  }
}

// ==========================================================
// >>>>>>>>> IZI DIALOGS NTIZAHINDUTSE <<<<<<<<<<<
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
    return AlertDialog(
      title: const Text("Hitamwo ijwi"),
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
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Ugara"))],
    );
  }
}

class VibrateSelectionDialog extends StatelessWidget {
  const VibrateSelectionDialog({super.key});
  @override
  Widget build(BuildContext context) {
    final modes = ['Ibisanzwe', 'Ngufi', 'Nde-nde', 'Ntibikogwa'];
    return AlertDialog(
      title: const Text("Hitamwo uko Vibration ikora"),
      content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: modes.length, itemBuilder: (context, index) => ListTile(title: Text(modes[index]), onTap: () => Navigator.of(context).pop(modes[index])))),
    );
  }
}