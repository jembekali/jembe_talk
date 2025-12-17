// lib/services/friends_service.dart (VERSION IKOSOYe)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:jembe_talk/services/database_helper.dart';

class UnifiedFriend {
  final String userId;
  String displayName;
  final String? photoUrl;
  final String? localPhotoPath; 
  final String? phoneNumber;
  final String source;

  UnifiedFriend({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.localPhotoPath,
    this.phoneNumber,
    required this.source,
  });
}

class FriendsService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  FriendsService._privateConstructor();
  static final FriendsService instance = FriendsService._privateConstructor();

  Future<List<UnifiedFriend>> getUnifiedFriendsList() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return [];

    Map<String, UnifiedFriend> friendsMap = {};
    final phoneContactsMap = await getPhoneContactsMap(); // <<< Yabaye public
    final jembeContactsFromDb = await _dbHelper.getJembeContacts();

    for (var contact in jembeContactsFromDb) {
      String phoneNumber = contact['phoneNumber'] ?? '';
      String normalizedPhone = normalizePhoneNumber(phoneNumber); // <<< Yabaye public
      
      if (phoneContactsMap.containsKey(normalizedPhone)) {
        friendsMap[contact['userId']] = UnifiedFriend(
          userId: contact['userId'],
          displayName: phoneContactsMap[normalizedPhone]!,
          photoUrl: contact['photoUrl'],
          localPhotoPath: contact['localPhotoPath'],
          phoneNumber: phoneNumber,
          source: 'phone',
        );
      }
    }
    
    final tangazaFriendsSnapshot = await _firestore.collection('friendships').where('users', arrayContains: currentUserId).where('status', isEqualTo: 'accepted').get();
    for (var doc in tangazaFriendsSnapshot.docs) {
      final data = doc.data();
      final friendId = (data['users'] as List).firstWhere((id) => id != currentUserId);
      if (!friendsMap.containsKey(friendId)) {
        final userDoc = await _firestore.collection('users').doc(friendId).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          friendsMap[friendId] = UnifiedFriend(
            userId: friendId,
            displayName: userData['displayName'] ?? 'Ata Zina',
            photoUrl: userData['photoUrl'],
            phoneNumber: userData['phoneNumber'],
            source: 'tangaza',
          );
        }
      }
    }
    
    final unifiedList = friendsMap.values.toList();
    unifiedList.sort((a, b) => a.displayName.compareTo(b.displayName));
    return unifiedList;
  }

  // <<<--- IYI FUNCTION YABAYE PUBLIC (TWAKUYEMO '_') ---<<<
  Future<Map<String, String>> getPhoneContactsMap() async {
    Map<String, String> phoneContactsMap = {};
    if (await FlutterContacts.requestPermission()) {
      try {
        List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true);
        for (var contact in contacts) {
          for (var phone in contact.phones) {
            if (phone.number.isNotEmpty) {
              String normalizedPhone = normalizePhoneNumber(phone.number);
              if (!phoneContactsMap.containsKey(normalizedPhone)) {
                phoneContactsMap[normalizedPhone] = contact.displayName;
              }
            }
          }
        }
      } catch (e) { /* Handle error */ }
    }
    return phoneContactsMap;
  }
  
  // <<<--- N'IYI YABAYE PUBLIC (TWAKUYEMO '_') ---<<<
  String normalizePhoneNumber(String phone) {
    String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length >= 8) {
        String potentialNumber = digitsOnly.substring(digitsOnly.length - 8);
        if (potentialNumber.startsWith('6') || potentialNumber.startsWith('7')) { return '+257$potentialNumber'; }
    }
    if (phone.trim().startsWith('+')) { return phone.replaceAll(RegExp(r'[\s-()]'), ''); }
    return digitsOnly;
  }
}