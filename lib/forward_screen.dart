// lib/forward_screen.dart (VERSION 2.1 - FIXED FOR INSTANT FORWARDING)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/post_translations.dart';

class ForwardContact {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final String? localPhotoPath;
  final String? phoneNumber;
  final int lastMessageTimestamp;

  ForwardContact({
    required this.userId, required this.displayName,
    this.photoUrl, this.localPhotoPath, this.phoneNumber,
    this.lastMessageTimestamp = 0,
  });
}

class ForwardScreen extends StatefulWidget {
  final List<Map<String, dynamic>> messagesToForward;
  const ForwardScreen({super.key, required this.messagesToForward});
  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<ForwardContact> _allContacts = [];
  List<ForwardContact> _filteredContacts = [];
  final Set<String> _selectedUserIds = {};
  bool _isLoading = true;
  bool _isSending = false; // ✅ Added to show loading while sending
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _searchController.addListener(_filterContacts);
  }

  Future<void> _loadAllData() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      final contactMapsFromDb = await _dbHelper.getJembeContacts();
      List<ForwardContact> recentChats = [];
      List<ForwardContact> otherContacts = [];

      for (var map in contactMapsFromDb) {
        if (map['userId'] == currentUser.uid) continue;
        String userId = map['userId'];
        List<String> ids = [currentUser.uid, userId]; ids.sort();
        final lastMsg = await _dbHelper.getLastMessage(ids.join('_'));
        final timestamp = lastMsg?['timestamp'] as int? ?? 0;

        final contact = ForwardContact(
          userId: userId, displayName: map['displayName'] ?? map['phoneNumber'] ?? 'User',
          photoUrl: map['photoUrl'], localPhotoPath: map['localPhotoPath'],
          phoneNumber: map['phoneNumber'], lastMessageTimestamp: timestamp,
        );

        if (timestamp > 0) recentChats.add(contact); else otherContacts.add(contact);
      }
      recentChats.sort((a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));
      otherContacts.sort((a, b) => a.displayName.compareTo(b.displayName));

      if (mounted) setState(() { _allContacts = [...recentChats, ...otherContacts]; _filteredContacts = _allContacts; _isLoading = false; });
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredContacts = _allContacts.where((contact) => contact.displayName.toLowerCase().contains(query) || (contact.phoneNumber?.contains(query) ?? false)).toList();
    });
  }

  void _toggleSelection(String userId) {
    if (_isSending) return;
    setState(() { if (_selectedUserIds.contains(userId)) _selectedUserIds.remove(userId); else _selectedUserIds.add(userId); });
  }

  // ✅ KOSORA LOGIC YO KOHEREZA
  Future<void> _forwardMessages(String langCode) async {
    if (_selectedUserIds.isEmpty || _isSending) return;
    
    setState(() => _isSending = true);

    final currentUser = _auth.currentUser; 
    if (currentUser == null) {
      setState(() => _isSending = false);
      return;
    }

    try {
      // Gukoresha WriteBatch bituma ubutumwa bwose bugenda rimwe kuri Firestore (Faster)
      final WriteBatch batch = _firestore.batch();

      for (final userId in _selectedUserIds) {
        for (final originalMessage in widget.messagesToForward) {
          final messageId = const Uuid().v4();
          List<String> ids = [currentUser.uid, userId]; 
          ids.sort();
          final String chatRoomId = ids.join('_');

          // Kora kopi y'ubutumwa
          final forwardedMessage = Map<String, dynamic>.from(originalMessage);
          forwardedMessage['id'] = messageId;
          forwardedMessage['chatRoomID'] = chatRoomId;
          forwardedMessage['senderID'] = currentUser.uid;
          forwardedMessage['receiverID'] = userId;
          forwardedMessage['timestamp'] = DateTime.now().millisecondsSinceEpoch;
          
          // Niba ari Media ifite URL cyangwa ari Inyandiko isanzwe, byose bihabwa 'sent' kuko bihari
          forwardedMessage['status'] = 'sent';

          // 1. Shira muri Firestore Batch
          DocumentReference msgRef = _firestore
              .collection('chat_rooms')
              .doc(chatRoomId)
              .collection('messages')
              .doc(messageId);
          
          batch.set(msgRef, forwardedMessage);

          // 2. Bika muri SQLite (Hano twabika tutarindiriye ngo Firestore irangize)
          await _dbHelper.saveMessage(forwardedMessage);
        }
      }

      // Kohereza kuri Firestore byose icyarimwe
      await batch.commit();

      syncService.triggerSync();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${PostTranslations.t('shared_with', langCode)} ${_selectedUserIds.length}.'))
        );
        Navigator.of(context).pop(); 
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error forwarding messages. Please try again.")));
      }
    }
  }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);
    final String langCode = lang.currentLanguage;
    
    return Stack(
      children: [
        Scaffold(
          appBar: _isSearching 
            ? AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() { _isSearching = false; _searchController.clear(); })), title: TextField(controller: _searchController, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: PostTranslations.t('search_people', langCode), hintStyle: const TextStyle(color: Colors.white70), border: InputBorder.none)))
            : AppBar(title: Text(PostTranslations.t('forward_to', langCode)), actions: [IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _isSearching = true))]),
          body: _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : _filteredContacts.isEmpty 
              ? Center(child: Text(PostTranslations.t('no_one_found', langCode))) 
              : ListView.builder(
                  itemCount: _filteredContacts.length,
                  itemBuilder: (context, index) {
                    final contact = _filteredContacts[index];
                    final bool isRecent = contact.lastMessageTimestamp > 0;
                    bool showSectionHeader = (index == 0 && isRecent) || (index > 0 && isRecent == false && _filteredContacts[index-1].lastMessageTimestamp > 0);
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (showSectionHeader) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(isRecent ? PostTranslations.t('recent_chats', langCode) : PostTranslations.t('other_people', langCode), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13))),
                        ListTile(
                          leading: CircleAvatar(backgroundImage: contact.localPhotoPath != null && File(contact.localPhotoPath!).existsSync() ? FileImage(File(contact.localPhotoPath!)) : (contact.photoUrl != null ? NetworkImage(contact.photoUrl!) : null) as ImageProvider?, child: (contact.localPhotoPath == null && contact.photoUrl == null) ? const Icon(Icons.person) : null),
                          title: Text(contact.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(contact.phoneNumber ?? ''),
                          trailing: Checkbox(value: _selectedUserIds.contains(contact.userId), onChanged: (_) => _toggleSelection(contact.userId), shape: const CircleBorder()),
                          onTap: () => _toggleSelection(contact.userId),
                        ),
                    ]);
                  },
                ),
          floatingActionButton: _selectedUserIds.isNotEmpty 
            ? FloatingActionButton.extended(
                onPressed: _isSending ? null : () => _forwardMessages(langCode), 
                label: Text("${PostTranslations.t('forward_button', langCode)} (${_selectedUserIds.length})"), 
                icon: _isSending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send), 
                backgroundColor: _isSending ? Colors.grey : theme.colorScheme.primary
              ) 
            : null,
        ),
        // Overlay kigaragaza ko biri koherezwa
        if (_isSending)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}