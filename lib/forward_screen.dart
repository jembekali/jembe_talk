// lib/forward_screen.dart (VERSION 13.8: With Search Functionality)

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ForwardContact {
  final String userId;
  final String displayName;
  final String? localPhotoPath;
  final String? photoUrl;
  final String? phoneNumber;

  ForwardContact({
    required this.userId, 
    required this.displayName,
    this.localPhotoPath,
    this.photoUrl,
    this.phoneNumber,
  });

  factory ForwardContact.fromJson(Map<String, dynamic> json) {
    return ForwardContact(
      userId: json['userId'] ?? '',
      displayName: json['displayName'] ?? 'Amazina ntazwi',
      localPhotoPath: json['localPhotoPath'],
      photoUrl: json['photoUrl'],
      phoneNumber: json['phoneNumber'],
    );
  }
}

class ForwardScreen extends StatefulWidget {
  final List<Map<String, dynamic>> messagesToForward;

  const ForwardScreen({super.key, required this.messagesToForward});

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  
  List<ForwardContact> _allContacts = [];
  List<ForwardContact> _filteredContacts = [];
  final Set<String> _selectedUserIds = {};
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchController.addListener(_filterContacts);
  }
  
  @override
  void dispose() {
    _searchController.removeListener(_filterContacts);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('forwarding_contacts');

    if (jsonString == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final List<dynamic> jsonList = jsonDecode(jsonString);
    final contacts = jsonList.map((json) => ForwardContact.fromJson(json)).toList();
    
    if(mounted) {
      setState(() {
        _allContacts = contacts;
        _filteredContacts = contacts;
        _isLoading = false;
      });
    }
  }
  
  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredContacts = _allContacts.where((contact) {
        return contact.displayName.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _forwardMessages() async {
    if (_selectedUserIds.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    for (final userId in _selectedUserIds) {
      for (final originalMessage in widget.messagesToForward) {
        final messageId = const Uuid().v4();
        
        List<String> ids = [currentUser.uid, userId];
        ids.sort();
        String chatRoomID = ids.join('_');
        
        final forwardedMessage = Map<String, dynamic>.from(originalMessage);
        
        forwardedMessage[DatabaseHelper.columnId] = messageId;
        forwardedMessage[DatabaseHelper.columnChatRoomID] = chatRoomID;
        forwardedMessage[DatabaseHelper.columnSenderID] = currentUser.uid;
        forwardedMessage[DatabaseHelper.columnReceiverID] = userId;
        forwardedMessage[DatabaseHelper.columnTimestamp] = DateTime.now().millisecondsSinceEpoch;
        forwardedMessage[DatabaseHelper.columnStatus] = 'pending';
        forwardedMessage[DatabaseHelper.columnReplyingTo] = null;

        await DatabaseHelper.instance.saveMessage(forwardedMessage);
      }
    }

    syncService.triggerSync();
    
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ubutumwa bwasangijwe abantu ${_selectedUserIds.length}.')),
      );
    }
  }

  AppBar _buildSearchAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchController.clear();
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Shakisha...',
          border: InputBorder.none,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _searchController.clear(),
        )
      ],
    );
  }

  AppBar _buildDefaultAppBar() {
    return AppBar(
      title: const Text('Sangiza kuri...'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              _isSearching = true;
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: _isSearching ? _buildSearchAppBar() : _buildDefaultAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredContacts.isEmpty
          ? const Center(child: Text("Nta muntu abonetse."))
          : ListView.builder(
              itemCount: _filteredContacts.length,
              itemBuilder: (context, index) {
                final contact = _filteredContacts[index];
                final userId = contact.userId;
                final isSelected = _selectedUserIds.contains(userId);

                ImageProvider? profileImageProvider;
                if (contact.localPhotoPath != null && File(contact.localPhotoPath!).existsSync()) {
                  profileImageProvider = FileImage(File(contact.localPhotoPath!));
                } else if (contact.photoUrl != null) {
                  profileImageProvider = NetworkImage(contact.photoUrl!);
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: profileImageProvider,
                    child: profileImageProvider == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(contact.displayName),
                  subtitle: Text(contact.phoneNumber ?? ''),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                      : const Icon(Icons.circle_outlined),
                  onTap: () => _toggleSelection(userId),
                );
              },
            ),
      floatingActionButton: _selectedUserIds.isNotEmpty
          ? FloatingActionButton(
              onPressed: _forwardMessages,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.send),
            )
          : null,
    );
  }
}