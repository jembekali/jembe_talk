// lib/last_seen_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/services/database_helper.dart';

class LastSeenSettingsScreen extends StatefulWidget {
  const LastSeenSettingsScreen({super.key});

  @override
  State<LastSeenSettingsScreen> createState() => _LastSeenSettingsScreenState();
}

class _LastSeenSettingsScreenState extends State<LastSeenSettingsScreen> {
  // Dutangura ibikoresho vyacu
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Ibi bizadufasha kumenya aho umukoresha ahisemwo n'iyo ariko arabika
  String? _currentSelection; // ('everyone', 'my_contacts', 'nobody')
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Iyo paji ifungutse, dusoma muri telefone kugirango tumenye aho yahisemo
    _loadCurrentSetting();
  }

  /// Soma agaciro kari muri database ya telefone
  Future<void> _loadCurrentSetting() async {
    final value = await _dbHelper.getSetting('privacy_lastSeen');
    if (mounted) {
      setState(() {
        // Niba ntarabihitamo, dufata 'everyone' nk'ihitamo ry'ibanze
        _currentSelection = value ?? 'everyone';
      });
    }
  }

  /// Bika ihitamo rishya muri telefone no kuri internet
  Future<void> _updateLastSeenSetting(String newValue) async {
    // Niba atari muri konti, ntakintu dukora
    if (_auth.currentUser == null) return;
    if (mounted) setState(() => _isSaving = true);

    // Intambwe ya 1: Hindura ku isura no muri telefone ako kanya
    setState(() => _currentSelection = newValue);
    await _dbHelper.saveSetting('privacy_lastSeen', newValue);

    // Intambwe ya 2: Bika kuri Firestore (internet) mu ibanga
    try {
      await _firestore.collection('users').doc(_auth.currentUser!.uid).set(
        { 'lastSeenPrivacy': newValue },
        SetOptions(merge: true), // 'merge: true' ituma tudasiba andi makuru
      );
      // Emeza ko byabitswe neza
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Ibyahinduwe byabitswe neza."),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Garagaza ko habaye ikibazo
       if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Habayeho ikibazo mu kubika: $e"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // Iyo birangiye (byakunze cyangwa byananiranye), duhindura status
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101D25),
      appBar: AppBar(
        title: const Text("Igihe Waherukiyeho"),
        backgroundColor: const Color(0xFF202C33),
        // Garagaza ko hari igikorwa kirimo kuba
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 20.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white,))),
            ),
        ],
      ),
      body: _currentSelection == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildSectionHeader(context, "Ninde ushobora kubona igihe naherukiye kugaragara?"),
                _buildRadioOption(
                  context,
                  title: 'Bose',
                  value: 'everyone',
                ),
                _buildRadioOption(
                  context,
                  title: 'Abo mfite gusa',
                  value: 'my_contacts',
                ),
                _buildRadioOption(
                  context,
                  title: 'Ntawe',
                  value: 'nobody',
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 20.0, bottom: 8.0, right: 16.0),
      child: Text(
        title,
        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
      ),
    );
  }

  Widget _buildRadioOption(BuildContext context, {required String title, required String value}) {
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      value: value,
      groupValue: _currentSelection,
      onChanged: (selectedValue) {
        if (selectedValue != null && !_isSaving) {
          _updateLastSeenSetting(selectedValue);
        }
      },
      activeColor: Colors.tealAccent,
      tileColor: Colors.white.withOpacity(0.05),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}