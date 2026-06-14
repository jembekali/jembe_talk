// lib/services/chat_repository.dart (VERSION 49.1 - LAST MESSAGE FIX - STABLE)

import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart'; 
import 'package:jembe_talk/models/home_models.dart'; 
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/sync_service.dart'; 

class ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ---------------------------------------------------------------------------
  // 1. RECENT CHATS: Igarura chats zose n'amazina (Priority: Local > Firebase)
  // ---------------------------------------------------------------------------
  Future<List<ChatData>> getAllRecentChats(String currentUserId) async {
    try {
      final db = await _dbHelper.database;

      // 🔥 FIX: Ubu SQL ikoresha Timestamp aho gukoresha ID kugira ngo ubutumwa bwoherejwe n'ubwakiriye bwose buboneke
      final List<Map<String, dynamic>> lastMsgs = await db.rawQuery('''
        SELECT * FROM ${DatabaseHelper.tableMessages} 
        WHERE ${DatabaseHelper.columnTimestamp} IN (
          SELECT MAX(${DatabaseHelper.columnTimestamp}) 
          FROM ${DatabaseHelper.tableMessages} 
          GROUP BY ${DatabaseHelper.columnChatRoomID}
        )
        ORDER BY ${DatabaseHelper.columnTimestamp} DESC
      ''');

      if (lastMsgs.isEmpty) return [];

      final List<Map<String, dynamic>> allContacts = await _dbHelper.getJembeContacts();
      final Map<String, Map<String, dynamic>> contactCache = {};
      for (var c in allContacts) {
        String? uid = c[DatabaseHelper.colUserId]?.toString();
        if (uid != null) contactCache[uid] = c;
      }

      List<ChatData> recentChats = [];
      for (var msg in lastMsgs) {
        String sID = msg[DatabaseHelper.columnSenderID]?.toString() ?? "";
        String rID = msg[DatabaseHelper.columnReceiverID]?.toString() ?? "";
        String roomId = msg[DatabaseHelper.columnChatRoomID]?.toString() ?? "";
        String otherUserId = (sID == currentUserId) ? rID : sID;
        if (otherUserId.isEmpty) continue;

        final contact = contactCache[otherUserId];
        String displayName = "";
        
        if (otherUserId == 'jembe_talk_official_admin') {
          displayName = "Jembe Talk";
        } else if (contact != null) {
          String local = contact['localContactName']?.toString() ?? "";
          String fb = contact[DatabaseHelper.colDisplayName]?.toString() ?? "";
          String phone = contact[DatabaseHelper.colPhoneNumber]?.toString() ?? "";

          if (local.trim().isNotEmpty) displayName = local;
          else if (fb.trim().isNotEmpty) displayName = fb;
          else if (phone.trim().isNotEmpty) displayName = phone;
          else displayName = "Jembe User";
        } else {
          displayName = "Jembe User (${otherUserId.substring(0, 4)})";
          _triggerImmediateContactSync(otherUserId);
        }

        int unread = await _dbHelper.getUnreadMessagesCount(roomId, currentUserId);
        
        recentChats.add(ChatData(
          userId: otherUserId,
          displayName: displayName,
          photoUrl: contact?[DatabaseHelper.colPhotoUrl],
          localPhotoPath: contact?[DatabaseHelper.columnLocalPhotoPath],
          // ✅ IYI NIYO FIX: Igarura content y'ubutumwa bwanyuma hatitawe ku wabwohereje
          lastMessageContent: msg[DatabaseHelper.columnMessage] ?? "",
          lastMessageTimestamp: msg[DatabaseHelper.columnTimestamp] ?? 0,
          lastMessageType: msg[DatabaseHelper.columnMessageType],
          lastMessageStatus: msg[DatabaseHelper.columnStatus],
          lastMessageSenderId: sID,
          unreadCount: unread,
        ));
      }
      return recentChats;
    } catch (e) { return []; }
  }

  // ---------------------------------------------------------------------------
  // 2. CONTACTS TAB: Igarura abantu bose bari muri SQL bafite App (Saved Contacts)
  // ---------------------------------------------------------------------------
  Future<List<ChatData>> getAllMatchedContacts(String currentUserId) async {
    try {
      final List<Map<String, dynamic>> maps = await _dbHelper.getJembeContacts();
      
      if (maps.isEmpty) return [];

      return maps.map((m) {
        String uid = m[DatabaseHelper.colUserId]?.toString() ?? "";
        String local = m[DatabaseHelper.colLocalContactName]?.toString() ?? "";
        String fb = m[DatabaseHelper.colDisplayName]?.toString() ?? "";
        String phone = m[DatabaseHelper.colPhoneNumber]?.toString() ?? "";

        String finalName = "Jembe User";
        if (uid == 'jembe_talk_official_admin') {
          finalName = "Jembe Talk";
        } else if (local.trim().isNotEmpty) {
          finalName = local;
        } else if (fb.trim().isNotEmpty) {
          finalName = fb;
        } else {
          finalName = phone.isNotEmpty ? phone : "Jembe User";
        }

        return ChatData(
          userId: uid, 
          displayName: finalName, 
          photoUrl: m[DatabaseHelper.colPhotoUrl], 
          localPhotoPath: m[DatabaseHelper.columnLocalPhotoPath], 
          phoneNumber: phone, 
          lastMessageTimestamp: 0
        );
      }).toList();
    } catch (e) { return []; }
  }

  // ---------------------------------------------------------------------------
  // 3. FULL SYNC: Gushaka abantu bose muri telefone bafite App (Saved Contacts)
  // ---------------------------------------------------------------------------
  Future<void> warmUpMatchedContacts(Map<String, String> localContactsMap) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final myDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      String myFullPhone = myDoc.data()?['phoneNumber'] ?? "";
      
      IsoCode myIsoCode = IsoCode.BI;
      try {
        if (myFullPhone.isNotEmpty) {
          final myParsed = PhoneNumber.parse(myFullPhone);
          myIsoCode = myParsed.isoCode;
        }
      } catch (_) {}

      Map<String, String> normalizedToOriginalName = {};
      List<String> searchList = [];

      localContactsMap.forEach((num, name) {
        try {
          final parsed = PhoneNumber.parse(num, destinationCountry: myIsoCode);
          String international = parsed.isValid() 
              ? parsed.international.replaceAll(RegExp(r'\s+'), '') 
              : num.replaceAll(RegExp(r'\D'), '');
          
          if (international.isNotEmpty) {
            if (!international.startsWith('+')) international = '+$international';
            String key = international.replaceAll(RegExp(r'\s+'), '');
            searchList.add(key);
            normalizedToOriginalName[key] = name;
          }
        } catch (_) {}
      });

      searchList = searchList.toSet().toList();
      if (searchList.isEmpty) return;

      List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];
      for (var i = 0; i < searchList.length; i += 30) {
        var end = (i + 30 < searchList.length) ? i + 30 : searchList.length;
        var chunk = searchList.sublist(i, end);
        futures.add(_firestore.collection('users').where('phoneNumber', whereIn: chunk).get());
      }

      final snapshots = await Future.wait(futures);

      List<Map<String, dynamic>> firebaseMatches = [];
      for (var snap in snapshots) {
        for (var doc in snap.docs) {
          var data = doc.data();
          data['id'] = doc.id;
          String fbPhone = (data['phoneNumber'] ?? "").toString().replaceAll(RegExp(r'\s+'), '');
          data[DatabaseHelper.colLocalContactName] = normalizedToOriginalName[fbPhone];
          firebaseMatches.add(data);
        }
      }

      if (firebaseMatches.isNotEmpty) {
        await _dbHelper.saveJembeContactsInBatch(firebaseMatches);
      }
      
      syncService.notifyUIMessageUpdate("refresh_ui");
    } catch (e) { log("Sync Engine Error: $e"); }
  }

  Future<void> _triggerImmediateContactSync(String userId) async {
    if (userId == 'jembe_talk_official_admin') return;
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        final d = Map<String, dynamic>.from(doc.data()!)..['id'] = userId;
        await _dbHelper.saveJembeContact(d);
        syncService.notifyUIMessageUpdate("refresh_ui");
      }
    } catch (_) {}
  }

  Future<int> getLastMessageTimestamp() async {
    try {
      final db = await _dbHelper.database;
      final result = await db.rawQuery('SELECT MAX(${DatabaseHelper.columnTimestamp}) as last_ts FROM ${DatabaseHelper.tableMessages}');
      return result.first['last_ts'] as int? ?? 0;
    } catch (e) { return 0; }
  }
}