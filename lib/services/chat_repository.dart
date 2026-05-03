// lib/services/chat_repository.dart (VERSION 30.6 - FULLY OPTIMIZED & SMART NAMES)

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

  // ---------------------------------------------------------
  // 1. ISOMA SQL (Kuri Contacts Tab)
  // ---------------------------------------------------------
  Future<List<ChatData>> getAllMatchedContacts(String currentUserId) async {
    try {
      final List<Map<String, dynamic>> maps = await _dbHelper.getJembeContacts();
      return maps.map((m) {
        String localName = m['localContactName']?.toString() ?? "";
        String firebaseName = m[DatabaseHelper.colDisplayName]?.toString() ?? "";
        String phone = m[DatabaseHelper.colPhoneNumber] ?? "";
        String uid = m[DatabaseHelper.colUserId] ?? "";
        
        // Priority Logic: Phonebook > Firebase > Phone
        String finalName = "";
        if (uid == 'jembe_talk_official_admin') {
          finalName = "Jembe Talk";
        } else if (localName.trim().isNotEmpty) {
          finalName = localName;
        } else if (firebaseName.trim().isNotEmpty) {
          finalName = firebaseName;
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
    } catch (e) { 
      log("Error getAllMatchedContacts: $e");
      return []; 
    }
  }

  // ---------------------------------------------------------
  // 2. RECENT CHATS (SOMA UBUTUMWA BWO KURI HOME)
  // ---------------------------------------------------------
  Future<List<ChatData>> getAllRecentChats(String currentUserId) async {
    try {
      // 1. Fata Room IDs zose zifite ubutumwa muri SQL
      final List<String> roomIds = await _dbHelper.getChatRoomIdsSortedByLastMessage();
      List<ChatData> recentChats = [];

      for (String roomId in roomIds) {
        // 2. Fata ubutumwa bwa nyuma muri iyi room
        final lastMsg = await _dbHelper.getLastMessage(roomId);
        if (lastMsg == null) continue; 
        
        // 3. Menya uwo muvugana (Other User ID)
        String otherUserId = lastMsg[DatabaseHelper.columnSenderID] == currentUserId 
            ? lastMsg[DatabaseHelper.columnReceiverID] 
            : lastMsg[DatabaseHelper.columnSenderID];
            
        // 4. Shaka amakuru ye muri Contacts table ya SQL
        final contactMap = await _dbHelper.getJembeContactById(otherUserId);
        
        // ✅ SMART DISPLAY NAME LOGIC: NO MORE UID LABELS ("Wko5...")
        String displayName = ""; 

        if (otherUserId == 'jembe_talk_official_admin') {
          displayName = "Jembe Talk";
        } else if (contactMap != null) {
          String? local = contactMap['localContactName']?.toString();
          String? fb = contactMap[DatabaseHelper.colDisplayName]?.toString();
          String? phone = contactMap[DatabaseHelper.colPhoneNumber]?.toString();

          // 1. Izina ryo muri telefone (Local)
          if (local != null && local.trim().isNotEmpty) {
            displayName = local;
          } 
          // 2. Izina ryo kuri Firebase (Urugero: "Ineza Odilo")
          else if (fb != null && fb.trim().isNotEmpty) {
            displayName = fb;
          } 
          // 3. Nimero ya telefone (Phone)
          else if (phone != null && phone.trim().isNotEmpty) {
            displayName = phone;
          } else {
            displayName = "Jembe User";
          }
        } else {
          // Niba SyncService ikirimo gufetch izina, erekana gusa "Jembe User" by'agateganyo
          displayName = "Jembe User";
        }

        // 5. Bara ubutumwa budasomye (Unread Count)
        int unread = await _dbHelper.getUnreadMessagesCount(roomId, currentUserId);

        recentChats.add(ChatData(
          userId: otherUserId,
          displayName: displayName,
          photoUrl: contactMap?[DatabaseHelper.colPhotoUrl],
          localPhotoPath: contactMap?[DatabaseHelper.columnLocalPhotoPath],
          lastMessageContent: lastMsg[DatabaseHelper.columnMessage] ?? "",
          lastMessageTimestamp: lastMsg[DatabaseHelper.columnTimestamp] ?? 0,
          lastMessageType: lastMsg[DatabaseHelper.columnMessageType],
          lastMessageStatus: lastMsg[DatabaseHelper.columnStatus],
          lastMessageSenderId: lastMsg[DatabaseHelper.columnSenderID],
          unreadCount: unread,
        ));
      }
      
      return recentChats;
    } catch (e) { 
      log("Error getAllRecentChats: $e");
      return []; 
    }
  }

  // ---------------------------------------------------------
  // 3. ULTRA FAST SYNC LOGIC (Guhuza Terefone na Firebase)
  // ---------------------------------------------------------
  Future<void> warmUpMatchedContacts(Map<String, String> localContactsMap) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // 1. Menya igihugu nyir'uwayo arimo (Gufetch country code)
      final myDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      String myFullPhone = myDoc.data()?['phoneNumber'] ?? "";
      
      IsoCode myIsoCode = IsoCode.BI;
      try {
        if (myFullPhone.isNotEmpty) {
          final myParsed = PhoneNumber.parse(myFullPhone);
          myIsoCode = myParsed.isoCode;
        }
      } catch (_) {}

      // 2. Tegura Map yo gushakisha vuba cyane
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

      searchList = searchList.toSet().toList(); // Kuramo duplicates
      if (searchList.isEmpty) return;

      // 3. PARALLEL FIRESTORE QUERIES (Inshuro 10 kuruta mbere)
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
          data['localContactName'] = normalizedToOriginalName[fbPhone];
          firebaseMatches.add(data);
        }
      }

      // 4. BATCH SAVE IN SQL (Ubu itandukaniro ni uko itasiba amazina ya Firebase)
      if (firebaseMatches.isNotEmpty) {
        await _dbHelper.saveJembeContactsInBatch(firebaseMatches);
      }

      syncService.notifyUIMessageUpdate("sync_done");
      
    } catch (e) { log("Ultra Sync Error: $e"); }
  }

  Future<int> getLastMessageTimestamp() async {
    try {
      final db = await _dbHelper.database;
      final result = await db.rawQuery('SELECT MAX(${DatabaseHelper.columnTimestamp}) as last_ts FROM ${DatabaseHelper.tableMessages}');
      return result.first['last_ts'] as int? ?? 0;
    } catch (e) { return 0; }
  }
}