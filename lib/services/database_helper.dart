// lib/services/database_helper.dart (VERSION 33.8 - PERFORMANCE & STORAGE OPTIMIZED - ZERO DATA LOSS)

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:jembe_talk/models/call_data.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static const _databaseName = "JembeTalk.db";
  static const _databaseVersion = 33;

  static const int _postCacheLimit = 30;

  static const tableSettings = 'settings';
  static const tableMessages = 'messages';
  static const tableDeletedMessagesLog = 'deleted_messages_log';
  static const tableCalls = 'calls';
  static const tablePosts = 'posts';
  static const tableTangazaComments = 'tangaza_comments';
  static const tableJembeContacts = 'jembe_contacts';
  static const tableStarNotifications = 'star_notifications';
  static const tableStealthPosts = 'stealth_posts';

  static const columnKey = 'key';
  static const columnValue = 'value';
  static const columnId = 'id';
  static const columnTimestamp = 'timestamp';
  static const columnStatus = 'status';
  static const columnChatRoomID = 'chatRoomID';
  static const columnSenderID = 'senderID';
  static const columnReceiverID = 'receiverID';
  static const columnMessageType = 'messageType';
  static const columnMessage = 'message';
  static const columnFileUrl = 'fileUrl';
  static const columnLocalPath = 'localPath';
  static const columnOnlineUrl = 'onlineUrl';
  static const columnFileName = 'fileName';
  static const columnDuration = 'duration';
  static const columnWaveform = 'waveform';
  static const columnThumbnailLocalPath = 'thumbnailLocalPath';
  static const columnStoragePath = 'storagePath';
  static const columnThumbnailUrl = 'thumbnailUrl';
  static const columnReplyingTo = 'replyingTo';

  static const columnMessageId = 'messageId';
  static const columnDeletedTimestamp = 'deletedTimestamp';

  static const colCallId = 'callId';
  static const colCallerId = 'callerId';
  static const colCallerName = 'callerName';
  static const colReceiverId = 'receiverId';
  static const colReceiverName = 'receiverName';
  static const colStatus = 'status';
  static const colIsVideo = 'isVideo';
  static const colSeenByReceiver = 'seenByReceiver';
  static const colPostId = 'postId';
  static const colUserId = 'userId';
  static const colUserName = 'userName';
  static const colUserImageUrl = 'userImageUrl';
  static const colText = 'text';
  static const colImageUrl = 'imageUrl';
  static const colVideoUrl = 'videoUrl';
  static const colLikes = 'likes';
  static const colCommentsCount = 'commentsCount';
  static const colViews = 'views';
  static const colIsLikedByMe = 'isLikedByMe';
  static const colSyncStatus = 'syncStatus';
  static const colCommentId = 'commentId';
  static const colTimestamp = 'timestamp';
  static const String colAudioUrl = 'audioUrl';
  static const String colLikesCount = 'likesCount';
  static const String colLikedBy = 'likedBy';
  static const String colLikedByJson = 'likedBy_json';
  static const colIsStar = 'isStar';
  static const String colStarExpiryTimestamp = 'starExpiryTimestamp';
  static const String colEmail = 'email';
  static const colPhoneNumber = 'phoneNumber';
  static const colPhotoUrl = 'photoUrl';
  static const columnLocalPhotoPath = 'localPhotoPath';
  static const colDisplayName = 'displayName';
  static const colTitle = 'title';
  static const colBody = 'body';
  static const colRelatedPostId = 'relatedPostId';
  static const colBlockedUsers = 'blockedUsers';
  static const colCategory = 'category';

  static const colFriendStatus = 'friendStatus';
  static const colRequestedBy = 'requestedBy';
  static const colFriendshipId = 'friendshipId';

  static const colPostThumbnailLocalPath = 'postThumbnailLocalPath';
  static const colPostData = 'postData';
  static const colLocalContactName = 'localContactName';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(path,
        version: _databaseVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 19) {
      try {
        await db.execute(
            "ALTER TABLE $tableMessages ADD COLUMN $columnThumbnailLocalPath TEXT");
      } catch (_) {}
    }
    if (oldVersion < 20) {
      try {
        await db.execute(
            "ALTER TABLE $tableMessages ADD COLUMN $columnStoragePath TEXT");
      } catch (_) {}
    }
    if (oldVersion < 21) {
      try {
        await db.execute(
            "ALTER TABLE $tableMessages ADD COLUMN $columnThumbnailUrl TEXT");
      } catch (_) {}
    }
    if (oldVersion < 22) {
      try {
        await db.execute(
            "ALTER TABLE $tableJembeContacts ADD COLUMN $colBlockedUsers TEXT");
      } catch (_) {}
    }
    if (oldVersion < 23) {
      try {
        await db.execute(
            "ALTER TABLE $tableMessages ADD COLUMN $columnReplyingTo TEXT");
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE $tableJembeContacts ADD COLUMN $columnLocalPhotoPath TEXT");
      } catch (_) {}
    }
    if (oldVersion < 24) {
      try {
        await db.execute(
            ''' CREATE TABLE $tableDeletedMessagesLog ( $columnMessageId TEXT PRIMARY KEY, $columnDeletedTimestamp INTEGER NOT NULL )''');
      } catch (_) {}
    }
    if (oldVersion < 25) {
      try {
        await db.execute(
            "ALTER TABLE $tablePosts ADD COLUMN $colCategory TEXT DEFAULT 'General'");
      } catch (_) {}
    }
    if (oldVersion < 26) {
      try {
        await db.execute(
            "ALTER TABLE $tablePosts ADD COLUMN $colPostThumbnailLocalPath TEXT");
      } catch (_) {}
    }
    if (oldVersion < 27) {
      try {
        await db.execute("ALTER TABLE $tablePosts ADD COLUMN $colTitle TEXT");
      } catch (_) {}
    }
    if (oldVersion < 28) {
      try {
        await db.execute(
            ''' CREATE TABLE $tableStealthPosts ( $colPostId TEXT PRIMARY KEY, $colPostData TEXT, $columnLocalPath TEXT, $colTimestamp INTEGER )''');
      } catch (_) {}
    }
    if (oldVersion < 29) {
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_messages_chat_time ON $tableMessages ($columnChatRoomID, $columnTimestamp DESC)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON $tableJembeContacts ($colUserId)');
      } catch (_) {}
    }
    if (oldVersion < 30) {
      try {
        await db.execute(
            "ALTER TABLE $tableJembeContacts ADD COLUMN localContactName TEXT");
      } catch (_) {}
    }
    if (oldVersion < 31) {
      try {
        await db.execute(
            "ALTER TABLE $tableMessages ADD COLUMN isEdited INTEGER DEFAULT 0");
      } catch (_) {}
    }
    if (oldVersion < 32) {
      try {
        await db.execute(
            "ALTER TABLE $tableMessages ADD COLUMN isPlayed INTEGER DEFAULT 0");
      } catch (_) {}
    }

    if (oldVersion < 33) {
      try {
        await db.execute(
            "ALTER TABLE $tableJembeContacts ADD COLUMN $colFriendStatus TEXT");
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE $tableJembeContacts ADD COLUMN $colRequestedBy TEXT");
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE $tableJembeContacts ADD COLUMN $colFriendshipId TEXT");
      } catch (_) {}
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute(
        ''' CREATE TABLE $tableMessages ( $columnId TEXT PRIMARY KEY, $columnChatRoomID TEXT, $columnSenderID TEXT, $columnReceiverID TEXT, $columnMessageType TEXT, $columnMessage TEXT, $columnFileUrl TEXT, $columnOnlineUrl TEXT, $columnLocalPath TEXT, $columnFileName TEXT, $columnDuration INTEGER, $columnTimestamp INTEGER, $columnWaveform TEXT, $columnStatus TEXT, $columnThumbnailLocalPath TEXT, $columnStoragePath TEXT, $columnThumbnailUrl TEXT, $columnReplyingTo TEXT, isEdited INTEGER DEFAULT 0, isPlayed INTEGER DEFAULT 0 )''');
    await db.execute(
        ''' CREATE TABLE $tableDeletedMessagesLog ( $columnMessageId TEXT PRIMARY KEY, $columnDeletedTimestamp INTEGER NOT NULL )''');
    await db.execute(
        ''' CREATE TABLE $tableCalls ( $colCallId TEXT PRIMARY KEY, $colCallerId TEXT, $colCallerName TEXT, $colReceiverId TEXT, $colReceiverName TEXT, $colStatus TEXT, $colIsVideo INTEGER, $columnTimestamp INTEGER, $colSeenByReceiver INTEGER )''');
    await db.execute(
        ''' CREATE TABLE $tableSettings ( $columnKey TEXT PRIMARY KEY, $columnValue TEXT )''');
    await db.execute(
        ''' CREATE TABLE $tableJembeContacts ( $colUserId TEXT PRIMARY KEY, $colDisplayName TEXT, localContactName TEXT, $colPhotoUrl TEXT, $columnLocalPhotoPath TEXT, $colPhoneNumber TEXT, $colEmail TEXT, $colBlockedUsers TEXT, $colFriendStatus TEXT, $colRequestedBy TEXT, $colFriendshipId TEXT )''');
    await db.execute(
        ''' CREATE TABLE $tableStarNotifications ( $columnId TEXT PRIMARY KEY, $colTitle TEXT, $colBody TEXT, $columnTimestamp INTEGER, $colRelatedPostId TEXT )''');
    await db.execute(
        ''' CREATE TABLE $tablePosts ( $colPostId TEXT PRIMARY KEY, $colUserId TEXT, $colUserName TEXT, $colUserImageUrl TEXT, $colTitle TEXT, $colText TEXT, $colImageUrl TEXT, $colVideoUrl TEXT, $colLikes INTEGER DEFAULT 0, $colCommentsCount INTEGER DEFAULT 0, $colViews INTEGER DEFAULT 0, $colTimestamp INTEGER NOT NULL, $colIsLikedByMe INTEGER DEFAULT 0, $colSyncStatus TEXT, $colIsStar INTEGER DEFAULT 0, $colLikedByJson TEXT, $colStarExpiryTimestamp INTEGER, $colCategory TEXT, $colPostThumbnailLocalPath TEXT )''');
    await db.execute(
        ''' CREATE TABLE $tableTangazaComments ( $colCommentId TEXT PRIMARY KEY, $colPostId TEXT NOT NULL, $colUserId TEXT, $colUserName TEXT, $colText TEXT, $colAudioUrl TEXT, $colLikesCount INTEGER DEFAULT 0, $colLikedBy TEXT, $colTimestamp INTEGER NOT NULL, $colSyncStatus TEXT NOT NULL )''');
    await db.execute(
        ''' CREATE TABLE $tableStealthPosts ( $colPostId TEXT PRIMARY KEY, $colPostData TEXT, $columnLocalPath TEXT, $colTimestamp INTEGER )''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_chat_time ON $tableMessages ($columnChatRoomID, $columnTimestamp DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON $tableJembeContacts ($colUserId)');
  }

  // 🔥 METHODS FOR OFFLINE FEED HYBRID (ADDED WITHOUT DELETING ANYTHING)
  Future<void> saveTopFivePosts(List<Map<String, dynamic>> posts) async {
    try {
      final db = await database;
      await db.delete(tableStealthPosts);
      for (var i = 0; i < (posts.length < 5 ? posts.length : 5); i++) {
        await db.insert(tableStealthPosts, {
          colPostId: posts[i]['id'] ?? posts[i][colPostId],
          colPostData: jsonEncode(posts[i]),
          columnLocalPath: '',
          colTimestamp: DateTime.now().millisecondsSinceEpoch,
        });
      }
      debugPrint("DatabaseHelper: Top 5 posts cached.");
    } catch (e) {
      debugPrint("DatabaseHelper Error (saveTopFive): $e");
    }
  }

  Future<List<Map<String, dynamic>>> getCachedFivePosts() async {
    try {
      final db = await database;
      final result = await db.query(tableStealthPosts,
          orderBy: '$colTimestamp DESC', limit: 5);
      return result
          .map((row) =>
              jsonDecode(row[colPostData] as String) as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint("DatabaseHelper Error (getCachedFive): $e");
      return [];
    }
  }

  // --- MESSAGES METHODS (PRESERVED) ---
  Future<int> insertMessage(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert(tableMessages, row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> saveMessage(Map<String, dynamic> messageData) async {
    final db = await database;
    final messageId = messageData[columnId];
    if (messageId == null) return false;
    if (await isMessageDeleted(messageId)) return false;
    final List<String> allowedColumns = [
      columnId,
      columnChatRoomID,
      columnSenderID,
      columnReceiverID,
      columnMessageType,
      columnMessage,
      columnFileUrl,
      columnOnlineUrl,
      columnLocalPath,
      columnFileName,
      columnDuration,
      columnTimestamp,
      columnWaveform,
      columnStatus,
      columnThumbnailLocalPath,
      columnStoragePath,
      columnThumbnailUrl,
      columnReplyingTo,
      'isEdited',
      'isPlayed'
    ];
    final Map<String, dynamic> messageToSave = {};
    for (var key in allowedColumns) {
      if (messageData.containsKey(key)) {
        messageToSave[key] = messageData[key];
      }
    }
    final List<Map<String, dynamic>> existing = await db
        .query(tableMessages, where: '$columnId = ?', whereArgs: [messageId]);
    if (existing.isNotEmpty) {
      final old = existing.first;
      if (messageToSave[columnLocalPath] == null)
        messageToSave[columnLocalPath] = old[columnLocalPath];
      if (messageToSave[columnFileName] == null)
        messageToSave[columnFileName] = old[columnFileName];
      if (messageToSave[columnThumbnailLocalPath] == null)
        messageToSave[columnThumbnailLocalPath] = old[columnThumbnailLocalPath];
      if (messageToSave[columnStoragePath] == null)
        messageToSave[columnStoragePath] = old[columnStoragePath];
      if (messageToSave['isEdited'] == null)
        messageToSave['isEdited'] = old['isEdited'];
      if (messageToSave['isPlayed'] == null)
        messageToSave['isPlayed'] = old['isPlayed'];
    }
    messageToSave.putIfAbsent(columnWaveform, () => null);
    await db.insert(tableMessages, messageToSave,
        conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<void> batchSaveMessages(List<Map<String, dynamic>> messages) async {
    for (var m in messages) await saveMessage(m);
  }

  Future<void> clearChat(String chatRoomID) async {
    final db = await database;
    final msgs = await db.query(tableMessages,
        columns: [columnId],
        where: '$columnChatRoomID = ?',
        whereArgs: [chatRoomID]);
    final batch = db.batch();
    for (var m in msgs) {
      final mid = m[columnId] as String;
      batch.delete(tableMessages, where: '$columnId = ?', whereArgs: [mid]);
      batch.insert(
          tableDeletedMessagesLog,
          {
            columnMessageId: mid,
            columnDeletedTimestamp: DateTime.now().millisecondsSinceEpoch
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    final batch = db.batch();
    batch.delete(tableMessages, where: '$columnId = ?', whereArgs: [messageId]);
    batch.insert(
        tableDeletedMessagesLog,
        {
          columnMessageId: messageId,
          columnDeletedTimestamp: DateTime.now().millisecondsSinceEpoch
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  Future<void> updateStatusToSeenUpTo(String roomId, int timestamp) async {
    final db = await database;
    await db.update(tableMessages, {'status': 'seen'},
        where: 'chatRoomID = ? AND timestamp <= ? AND status != ?',
        whereArgs: [roomId, timestamp, 'seen']);
  }

  Future<bool> isMessageDeleted(String messageId) async {
    final db = await database;
    final res = await db.query(tableDeletedMessagesLog,
        where: '$columnMessageId = ?', whereArgs: [messageId], limit: 1);
    return res.isNotEmpty;
  }

  Future<void> cleanupDeletedMessagesLog() async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 4)).millisecondsSinceEpoch;
    await db.delete(tableDeletedMessagesLog,
        where: '$columnDeletedTimestamp < ?', whereArgs: [cutoff]);
  }

  // Media Update Methods (PRESERVED)
  Future<void> updateMessageStatus(String messageId, String status) async {
    final db = await database;
    await db.update(tableMessages, {columnStatus: status},
        where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageLocalPath(
      String messageId, String localPath) async {
    final db = await database;
    await db.update(tableMessages, {columnLocalPath: localPath},
        where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageFileUrl(String messageId, String fileUrl) async {
    final db = await database;
    await db.update(tableMessages, {columnFileUrl: fileUrl},
        where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageUrls(String messageId,
      {String? fileUrl, String? thumbnailUrl}) async {
    final db = await database;
    Map<String, dynamic> data = {};
    if (fileUrl != null) data[columnFileUrl] = fileUrl;
    if (thumbnailUrl != null) data[columnThumbnailUrl] = thumbnailUrl;
    if (data.isNotEmpty)
      await db.update(tableMessages, data,
          where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageThumbnailLocalPath(
      String messageId, String thumbnailLocalPath) async {
    final db = await database;
    await db.update(
        tableMessages, {columnThumbnailLocalPath: thumbnailLocalPath},
        where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageStoragePathAndUrl(
      String messageId, String storagePath, String? fileUrl) async {
    final db = await database;
    await db.update(
        tableMessages,
        {
          columnStoragePath: storagePath,
          columnFileUrl: fileUrl,
          columnStatus: 'sent'
        },
        where: '$columnId = ?',
        whereArgs: [messageId]);
  }

  Future<void> updateMessageStatusAndOnlineUrl(
      String messageId, String status, String? onlineUrl) async {
    final db = await database;
    final vals = {columnStatus: status};
    if (onlineUrl != null) vals[columnOnlineUrl] = onlineUrl;
    await db.update(tableMessages, vals,
        where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageStatusAndFileUrl(
      String messageId, String status, String? fileUrl) async {
    final db = await database;
    final vals = {columnStatus: status};
    if (fileUrl != null) vals[columnFileUrl] = fileUrl;
    await db.update(tableMessages, vals,
        where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageFilePath(String messageId, String localPath) async {
    final db = await database;
    await db.update(tableMessages, {columnLocalPath: localPath},
        where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageMediaDetails(
      String messageId, String fileUrl, String storagePath) async {
    final db = await database;
    await db.update(
        tableMessages, {columnFileUrl: fileUrl, columnStoragePath: storagePath},
        where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessagePlayedStatus(String messageId, int isPlayed) async {
    final db = await database;
    await db.update(tableMessages, {'isPlayed': isPlayed},
        where: 'id = ?', whereArgs: [messageId]);
  }

  // Get Helpers (PRESERVED)
  Future<List<Map<String, dynamic>>> getMessagesByStatus(
      String status, String receiverId) async {
    final db = await database;
    return await db.query(tableMessages,
        where: '$columnStatus = ? AND $columnReceiverID = ?',
        whereArgs: [status, receiverId]);
  }

  Future<void> markSentMessagesAsSeenLocally(
      String roomId, String myId, int otherLastReadTs) async {
    final db = await database;
    await db.update(tableMessages, {columnStatus: 'seen'},
        where:
            '$columnChatRoomID = ? AND $columnSenderID = ? AND $columnTimestamp <= ? AND $columnStatus != ?',
        whereArgs: [roomId, myId, otherLastReadTs, 'seen']);
  }

  Future<List<Map<String, dynamic>>> getPendingMessages() async {
    final db = await database;
    return await db.query(tableMessages,
        where:
            '$columnStatus = ? OR $columnStatus = ? OR $columnStatus = ? OR $columnStatus = ?',
        whereArgs: ['pending', 'failed', 'uploading', 'paused']);
  }

  Future<Map<String, dynamic>?> getMessageById(String id) async {
    final db = await database;
    final maps = await db.query(tableMessages,
        where: '$columnId = ?', whereArgs: [id], limit: 1);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<List<Map<String, dynamic>>> getMessagesForChatRoom(
      String chatRoomID) async {
    final db = await database;
    return await db.query(tableMessages,
        where: '$columnChatRoomID = ?',
        whereArgs: [chatRoomID],
        orderBy: '$columnTimestamp ASC');
  }

  Future<Map<String, dynamic>?> getLastMessage(String chatRoomID) async {
    final db = await database;
    final maps = await db.query(tableMessages,
        where: '$columnChatRoomID = ?',
        whereArgs: [chatRoomID],
        orderBy: '$columnTimestamp DESC',
        limit: 1);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<List<String>> getChatRoomIdsSortedByLastMessage() async {
    final db = await database;
    final maps = await db.query(tableMessages,
        columns: [columnChatRoomID],
        groupBy: columnChatRoomID,
        orderBy: 'MAX($columnTimestamp) DESC');
    return List.generate(
        maps.length, (i) => maps[i][columnChatRoomID] as String);
  }

  Future<String?> getLocalPathForMessage(String messageId) async {
    final db = await database;
    final maps = await db.query(tableMessages,
        columns: [columnLocalPath],
        where: '$columnId = ?',
        whereArgs: [messageId],
        limit: 1);
    return maps.isNotEmpty ? maps.first[columnLocalPath] as String? : null;
  }

  Future<List<Map<String, dynamic>>> getMediaMessages(String chatRoomID,
      {int limit = 10}) async {
    final db = await database;
    return await db.query(tableMessages,
        where: 'chatRoomID = ? AND (messageType = ? OR messageType = ?)',
        whereArgs: [chatRoomID, 'image', 'video'],
        orderBy: 'timestamp DESC',
        limit: limit);
  }

  // --- CONTACTS METHODS (ENHANCED FOR FRIENDS SYNC) ---
  Future<void> saveJembeContact(Map<String, dynamic> userData) async {
    final db = await database;
    final List<Map<String, dynamic>> existing = await db.query(
        tableJembeContacts,
        where: '$colUserId = ?',
        whereArgs: [userData['id'] ?? userData[colUserId]]);
    String? localName;
    if (existing.isNotEmpty) localName = existing.first['localContactName'];
    await db.insert(
        tableJembeContacts,
        {
          colUserId: userData['id'] ?? userData[colUserId],
          colDisplayName: userData[colDisplayName],
          'localContactName': userData['localContactName'] ?? localName,
          colPhotoUrl: userData[colPhotoUrl],
          columnLocalPhotoPath: userData[columnLocalPhotoPath],
          colPhoneNumber: userData[colPhoneNumber],
          colEmail: userData[colEmail],
          colBlockedUsers: userData[colBlockedUsers] is List
              ? jsonEncode(userData[colBlockedUsers])
              : userData[colBlockedUsers],
          colFriendStatus: userData['status'] ?? userData[colFriendStatus],
          colRequestedBy: userData['requestedBy'] ?? userData[colRequestedBy],
          colFriendshipId:
              userData['friendshipId'] ?? userData[colFriendshipId],
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveJembeContactsInBatch(
      List<Map<String, dynamic>> contacts) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var userData in contacts) {
        final List<Map<String, dynamic>> existing = await txn.query(
            tableJembeContacts,
            where: '$colUserId = ?',
            whereArgs: [userData['id'] ?? userData[colUserId]]);
        String? finalDisplayName = userData[colDisplayName];
        if (finalDisplayName == null || finalDisplayName.isEmpty) {
          if (existing.isNotEmpty)
            finalDisplayName = existing.first[colDisplayName];
        }
        await txn.insert(
            tableJembeContacts,
            {
              colUserId: userData['id'] ?? userData[colUserId],
              colDisplayName: finalDisplayName,
              'localContactName': userData['localContactName'],
              colPhotoUrl: userData[colPhotoUrl],
              columnLocalPhotoPath: userData[columnLocalPhotoPath],
              colPhoneNumber: userData[colPhoneNumber],
              colEmail: userData[colEmail],
              colBlockedUsers: userData[colBlockedUsers] is List
                  ? jsonEncode(userData[colBlockedUsers])
                  : userData[colBlockedUsers]
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<Map<String, dynamic>?> getJembeContactById(String userId) async {
    final db = await database;
    final maps = await db.query(tableJembeContacts,
        where: '$colUserId = ?', whereArgs: [userId]);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<List<Map<String, dynamic>>> getJembeContacts() async {
    final db = await database;
    return await db.query(tableJembeContacts, orderBy: '$colDisplayName ASC');
  }

  Future<void> clearAllJembeContacts() async {
    final db = await database;
    await db.delete(tableJembeContacts);
  }

  // --- UNREAD & READ METHODS (PRESERVED) ---
  Future<int> getTotalUnreadCount(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM $tableMessages WHERE $columnReceiverID = ? AND $columnStatus != ?',
        [userId, 'seen']);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getUnreadMessagesCount(String chatRoomID, String userId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM $tableMessages WHERE $columnChatRoomID = ? AND $columnReceiverID = ? AND $columnStatus != ?',
        [chatRoomID, userId, 'seen']);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markMessagesAsSeen(String chatRoomID, String userId) async {
    final db = await database;
    await db.update(tableMessages, {columnStatus: 'seen'},
        where:
            '$columnChatRoomID = ? AND $columnReceiverID = ? AND $columnStatus != ?',
        whereArgs: [chatRoomID, userId, 'seen']);
  }

  Future<void> markMessagesAsRead(String roomId, String currentUserId) async {
    final db = await database;
    await db.update(tableMessages, {columnStatus: 'seen'},
        where:
            '$columnChatRoomID = ? AND $columnReceiverID = ? AND $columnStatus != ?',
        whereArgs: [roomId, currentUserId, 'seen']);
  }

  Future<void> markAdminMessagesAsRead(String currentUserId) async {
    final db = await database;
    await db.update(tableMessages, {columnStatus: 'seen'},
        where: '$columnSenderID = ? AND $columnStatus != ?',
        whereArgs: ['jembe_talk_official_admin', 'seen']);
  }

  // --- POSTS METHODS (PRESERVED) ---
  Future<void> savePost(Map<String, dynamic> postData) async {
    final db = await database;
    await db.insert(tablePosts, postData,
        conflictAlgorithm: ConflictAlgorithm.replace);
    await cleanupOldPosts();
  }

  Future<void> cachePosts(List<Map<String, dynamic>> posts) async {
    if (posts.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (var post in posts)
      batch.insert(tablePosts, post,
          conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
    await _enforcePostLimit();
  }

  Future<void> clearRegularPostsCache() async {
    final db = await database;
    await db.delete(tablePosts, where: '$colIsStar = ?', whereArgs: [0]);
  }

  Future<void> _enforcePostLimit() async {
    final db = await database;
    final countRes = await db
        .rawQuery('SELECT COUNT(*) FROM $tablePosts WHERE $colIsStar = 0');
    final count = Sqflite.firstIntValue(countRes) ?? 0;
    if (count > _postCacheLimit) {
      final excess = count - _postCacheLimit;
      await db.execute(
          'DELETE FROM $tablePosts WHERE $colPostId IN (SELECT $colPostId FROM $tablePosts WHERE $colIsStar = 0 ORDER BY $colTimestamp ASC LIMIT $excess)');
    }
  }

  Future<void> incrementPostView(String postId) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE $tablePosts SET $colViews = $colViews + 1 WHERE $colPostId = ?',
        [postId]);
  }

  Future<void> togglePostLikeStatus(
      String postId, bool isCurrentlyLiked) async {
    final db = await database;
    await db.update(tablePosts, {colIsLikedByMe: isCurrentlyLiked ? 1 : 0},
        where: '$colPostId = ?', whereArgs: [postId]);
  }

  Future<void> incrementPostCommentCount(String postId) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE $tablePosts SET $colCommentsCount = $colCommentsCount + 1 WHERE $colPostId = ?',
        [postId]);
  }

  Future<void> decrementPostCommentCount(String postId) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE $tablePosts SET $colCommentsCount = $colCommentsCount - 1 WHERE $colPostId = ? AND $colCommentsCount > 0',
        [postId]);
  }

  Future<void> deletePost(String postId) async {
    final db = await database;
    final List<Map<String, dynamic>> post = await db.query(tablePosts,
        columns: [colPostThumbnailLocalPath, colVideoUrl, colImageUrl],
        where: '$colPostId = ?',
        whereArgs: [postId]);
    if (post.isNotEmpty) {
      final paths = [
        post.first[colPostThumbnailLocalPath],
        post.first[colVideoUrl],
        post.first[colImageUrl]
      ];
      for (var p in paths) {
        if (p != null && p.isNotEmpty && !p.startsWith('http')) {
          final f = File(p);
          if (await f.exists()) await f.delete();
        }
      }
    }
    await db.delete(tablePosts, where: '$colPostId = ?', whereArgs: [postId]);
  }

  Future<void> updatePostThumbnail(String postId, String localPath) async {
    final db = await database;
    await db.update(tablePosts, {colPostThumbnailLocalPath: localPath},
        where: '$colPostId = ?', whereArgs: [postId]);
  }

  Future<void> updatePostSyncStatus(String postId, String status) async {
    final db = await database;
    await db.update(tablePosts, {colSyncStatus: status},
        where: '$colPostId = ?', whereArgs: [postId]);
  }

  Future<void> updatePostRemoteUrls(String postId,
      {String? imageUrl, String? videoUrl}) async {
    final db = await database;
    final vals = <String, dynamic>{};
    if (imageUrl != null) vals[colImageUrl] = imageUrl;
    if (videoUrl != null) vals[colVideoUrl] = videoUrl;
    if (vals.isNotEmpty)
      await db.update(tablePosts, vals,
          where: '$colPostId = ?', whereArgs: [postId]);
  }

  Future<List<Map<String, dynamic>>> getPostsByUserId(String userId) async {
    await cleanupOldPosts();
    final db = await database;
    return await db.query(tablePosts,
        where: '$colUserId = ?',
        whereArgs: [userId],
        orderBy: '$colTimestamp DESC');
  }

  Future<List<Map<String, dynamic>>> getAllRegularPostsFromCache() async {
    await cleanupOldPosts();
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    return await db.query(tablePosts,
        where: '$colIsStar = 0 AND $colTimestamp > ?',
        whereArgs: [cutoff],
        orderBy: '$colTimestamp DESC',
        limit: 6);
  }

  Future<void> cleanupOldPosts() async {
    try {
      final db = await database;
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;
      final List<Map<String, dynamic>> oldPosts = await db.query(tablePosts,
          columns: [
            colPostId,
            colVideoUrl,
            colImageUrl,
            colPostThumbnailLocalPath
          ],
          where: '$colTimestamp < ? AND $colIsStar = 0',
          whereArgs: [cutoff]);
      if (oldPosts.isEmpty) return;
      for (var post in oldPosts) {
        final paths = [
          post[colVideoUrl],
          post[colImageUrl],
          post[colPostThumbnailLocalPath]
        ];
        for (var p in paths) {
          if (p != null && p.isNotEmpty && !p.toString().startsWith('http')) {
            final f = File(p.toString());
            if (await f.exists())
              await f.exists().then((e) async {
                if (e) await f.delete();
              });
          }
        }
      }
      await db.delete(tablePosts,
          where: '$colTimestamp < ? AND $colIsStar = 0', whereArgs: [cutoff]);
    } catch (e) {
      log("Cleanup Error: $e");
    }
  }

  // --- COMMENTS METHODS ---
  Future<void> saveComment(Map<String, dynamic> commentData) async {
    final db = await database;
    await db.insert(tableTangazaComments, commentData,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getCommentsForPost(String postId) async {
    final db = await database;
    return await db.query(tableTangazaComments,
        where: '$colPostId = ?',
        whereArgs: [postId],
        orderBy: '$colTimestamp ASC');
  }

  Future<void> toggleCommentLike(String commentId, String userId) async {
    final db = await database;
    final comment = await db.query(tableTangazaComments,
        where: '$colCommentId = ?', whereArgs: [commentId]);
    if (comment.isNotEmpty) {
      List<String> likedBy =
          (jsonDecode(comment.first[colLikedBy] as String? ?? '[]') as List)
              .cast<String>();
      likedBy.contains(userId) ? likedBy.remove(userId) : likedBy.add(userId);
      await db.update(tableTangazaComments,
          {colLikedBy: jsonEncode(likedBy), colLikesCount: likedBy.length},
          where: '$colCommentId = ?', whereArgs: [commentId]);
    }
  }

  Future<void> deleteComment(String commentId) async {
    final db = await database;
    await db.delete(tableTangazaComments,
        where: '$colCommentId = ?', whereArgs: [commentId]);
  }

  Future<void> updateComment(String commentId, String newText) async {
    final db = await database;
    await db.update(tableTangazaComments, {colText: newText},
        where: '$colCommentId = ?', whereArgs: [commentId]);
  }

  // --- STEALTH POSTS ---
  Future<bool> checkIfStealthExists(String postId) async {
    final db = await database;
    final res = await db.query(tableStealthPosts,
        where: '$colPostId = ?', whereArgs: [postId], limit: 1);
    return res.isNotEmpty;
  }

  Future<void> saveStealthPost(
      {required String postId,
      required String postDataJson,
      required String localPath}) async {
    final db = await database;
    await db.insert(
        tableStealthPosts,
        {
          colPostId: postId,
          colPostData: postDataJson,
          columnLocalPath: localPath,
          colTimestamp: DateTime.now().millisecondsSinceEpoch
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getStealthPosts() async {
    final db = await database;
    return await db.query(tableStealthPosts, orderBy: '$colTimestamp DESC');
  }

  Future<void> deleteStealthPost(String postId) async {
    final db = await database;
    final List<Map<String, dynamic>> res = await db
        .query(tableStealthPosts, where: '$colPostId = ?', whereArgs: [postId]);
    if (res.isNotEmpty) {
      final String? path = res.first[columnLocalPath] as String?;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
    await db.delete(tableStealthPosts,
        where: '$colPostId = ?', whereArgs: [postId]);
  }

  Future<void> clearAllStealthPosts() async {
    final db = await database;
    await db.delete(tableStealthPosts);
  }

  // --- CALLS & SETTINGS & NOTIFS ---
  Future<void> saveCall(CallData call) async {
    final db = await database;
    await db.insert(tableCalls, call.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteOldCalls() async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await db
        .delete(tableCalls, where: '$columnTimestamp < ?', whereArgs: [cutoff]);
  }

  Future<List<Map<String, dynamic>>> getCallsForUser(
      String currentUserId) async {
    final db = await database;
    return await db.query(tableCalls,
        where: '$colCallerId = ? OR $colReceiverId = ?',
        whereArgs: [currentUserId, currentUserId],
        orderBy: '$columnTimestamp DESC');
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(tableSettings, {columnKey: key, columnValue: value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db
        .query(tableSettings, where: '$columnKey = ?', whereArgs: [key]);
    return maps.isNotEmpty ? maps.first[columnValue] as String? : null;
  }

  Future<void> saveStarNotifications(
      List<Map<String, dynamic>> notifications) async {
    final db = await database;
    final batch = db.batch();
    for (var n in notifications)
      batch.insert(tableStarNotifications, n,
          conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getStarNotifications() async {
    final db = await database;
    return await db.query(tableStarNotifications,
        orderBy: '$columnTimestamp DESC');
  }

  // 🔥 WIPE ALL DATA (PRESERVED EXACTLY AS IT WAS)
  Future<void> clearAllData() async {
    await wipeAllData();
  }

  Future<void> wipeAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(tableMessages);
      await txn.delete(tableDeletedMessagesLog);
      await txn.delete(tableCalls);
      await txn.delete(tableSettings);
      await txn.delete(tableJembeContacts);
      await txn.delete(tableStarNotifications);
      await txn.delete(tablePosts);
      await txn.delete(tableTangazaComments);
      await txn.delete(tableStealthPosts);
    });
  }
}
