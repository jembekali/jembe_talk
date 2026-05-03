// lib/services/chat_message_service.dart (VERSION 2.40 - PRODUCTION READY WITH EDIT LOGIC)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'dart:developer';

class ChatMessageService {
  static final ChatMessageService instance = ChatMessageService._init();
  ChatMessageService._init();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 1. Gukurura ubutumwa buke buke (Pagination) kugira ngo App itanywa RAM nyinshi
  Future<List<Map<String, dynamic>>> getMessagesPaged({
    required String chatRoomID,
    required int limit,
    required int offset,
  }) async {
    try {
      final db = await _dbHelper.database;
      return await db.query(
        'messages',
        where: 'chatRoomID = ?',
        whereArgs: [chatRoomID],
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      log("Error fetching paged messages: $e");
      return [];
    }
  }

  /// 2. Kubika ubutumwa bushya mu bubiko bwa telefone (SQLite)
  Future<bool> saveMessage(Map<String, dynamic> messageData) async {
    return await _dbHelper.saveMessage(messageData);
  }

  /// 3. GUKOSORA UBUTUMWA (Edit Message Logic)
  /// Ibi bihindura ubutumwa haba muri Telefone no kuri Firebase ako kanya.
  Future<void> updateMessageContent({
    required String chatRoomID, 
    required String messageId, 
    required String newText
  }) async {
    try {
      // ✅ A. Hindura mu bubiko bwa telefone (Instant UI change)
      final db = await _dbHelper.database;
      await db.update(
        'messages',
        {
          'message': newText,
          'status': 'sent', 
          'isEdited': 1 // ✅ Emeza ko inkingi ishyirwamo 1
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );

      // ✅ B. Hindura kuri Firebase Server
      // Ibi bizatuma Receiver nawe SyncService ye imumenyesha ko ubutumwa bwahindutse
      await _firestore
          .collection('chat_rooms')
          .doc(chatRoomID)
          .collection('messages')
          .doc(messageId)
          .update({
            'message': newText,
            'isEdited': 1,
            'status': 'sent',
          });
          
      log("ChatMessageService: Message $messageId updated successfully on Server and Local.");
    } catch (e) {
      log("Error updating message content: $e");
      // Niba Server yanze (urugero: offline), busubize kuri 'pending' muri SQL 
      // kugira ngo SyncService izagerageze ubutaha internet yagarutse.
      await _dbHelper.updateMessageStatus(messageId, 'pending');
    }
  }

  /// 4. Gusiba ubutumwa muri telefone
  Future<void> deleteMessage(String messageId) async {
    await _dbHelper.deleteMessage(messageId);
  }

  /// 5. Gusiba amateka y'ibiganiro byose by'iyi chat (Clear Chat)
  Future<int> clearChatHistory(String chatRoomID) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'messages',
      where: 'chatRoomID = ?',
      whereArgs: [chatRoomID],
    );
  }

  /// 6. Guhindura Status y'ubutumwa (Sent, Delivered, Seen)
  Future<void> updateMessageStatus(String messageId, String status) async {
    await _dbHelper.updateMessageStatus(messageId, status);
  }

  /// 7. Kuvugurura aho Media (Ifoto/Video) ibitse muri telefone amaze kuyikurura
  Future<void> updateLocalPath(String messageId, String localPath) async {
    await _dbHelper.updateMessageLocalPath(messageId, localPath);
  }
  
  /// 8. Kubara umubare w'ubutumwa buri muri iyi chat
  Future<int> getMessageCount(String chatRoomID) async {
    try {
      final db = await _dbHelper.database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as total FROM messages WHERE chatRoomID = ?',
        [chatRoomID],
      );
      return result.first['total'] as int? ?? 0;
    } catch (e) { 
      return 0; 
    }
  }
}

// ✅ Singleton instance yo gukoresha muri App yose
final chatMessageService = ChatMessageService.instance;