// lib/services/database_helper.dart (VERSION NSHYA YUZUYE)

import 'dart:developer';
import 'dart:io';
import 'package:jembe_talk/models/call_data.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _databaseName = "JembeTalk.db";
  // <<< IMPINDUKA: Twongeye version kugira ngo database yiyuburure >>>
  static const _databaseVersion = 21; 

  static const int _postCacheLimit = 30;

  static const tableSettings = 'settings';
  static const tableMessages = 'messages';
  static const tableCalls = 'calls';
  static const tablePosts = 'posts';
  static const tableTangazaComments = 'tangaza_comments';
  static const tableJembeContacts = 'jembe_contacts';
  static const tableStarNotifications = 'star_notifications';

  // --- Amazina y'inkingi ---
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
  // <<< ONGERAMO IYI NKINGI NSHYA >>>
  static const columnThumbnailUrl = 'thumbnailUrl';

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
  static const colEmail = 'email';
  static const colPhoneNumber = 'phoneNumber';
  static const colPhotoUrl = 'photoUrl';
  static const colDisplayName = 'displayName';
  static const colTitle = 'title';
  static const colBody = 'body';
  static const colRelatedPostId = 'relatedPostId';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();

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
        await db.execute("ALTER TABLE $tableMessages ADD COLUMN $columnThumbnailLocalPath TEXT");
        log("Successfully added thumbnailLocalPath column.");
      } catch (e) {
        log("Could not add thumbnailLocalPath column (maybe it exists?): $e");
      }
    }
    if (oldVersion < 20) {
      try {
        await db.execute("ALTER TABLE $tableMessages ADD COLUMN $columnStoragePath TEXT");
        log("Successfully added storagePath column.");
      } catch (e) {
        log("Could not add storagePath column (maybe it exists?): $e");
      }
    }
    // <<< ONGERAMO IKI GICE GISHYA CYO KONGERA INKINGI NSHYA >>>
    if (oldVersion < 21) {
      try {
        await db.execute("ALTER TABLE $tableMessages ADD COLUMN $columnThumbnailUrl TEXT");
        log("Successfully added thumbnailUrl column.");
      } catch (e) {
        log("Could not add thumbnailUrl column (maybe it exists?): $e");
      }
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute(''' CREATE TABLE $tableMessages (
      $columnId TEXT PRIMARY KEY, 
      $columnChatRoomID TEXT, 
      $columnSenderID TEXT, 
      $columnReceiverID TEXT, 
      $columnMessageType TEXT, 
      $columnMessage TEXT, 
      $columnFileUrl TEXT, 
      $columnOnlineUrl TEXT, 
      $columnLocalPath TEXT,
      $columnFileName TEXT, 
      $columnDuration INTEGER, 
      $columnTimestamp INTEGER, 
      $columnWaveform TEXT, 
      $columnStatus TEXT,
      $columnThumbnailLocalPath TEXT,
      $columnStoragePath TEXT,
      $columnThumbnailUrl TEXT 
      )''');
      
    await db.execute(''' CREATE TABLE $tableCalls (
      $colCallId TEXT PRIMARY KEY, $colCallerId TEXT, $colCallerName TEXT, $colReceiverId TEXT, $colReceiverName TEXT, $colStatus TEXT, $colIsVideo INTEGER, $columnTimestamp INTEGER, $colSeenByReceiver INTEGER
      )''');
    await db.execute(''' CREATE TABLE $tableSettings ( $columnKey TEXT PRIMARY KEY, $columnValue TEXT )''');
    await db.execute(''' CREATE TABLE $tableJembeContacts (
        $colUserId TEXT PRIMARY KEY, $colDisplayName TEXT, $colPhotoUrl TEXT, $colPhoneNumber TEXT, $colEmail TEXT
      )''');
    await db.execute(''' CREATE TABLE $tableStarNotifications (
        $columnId TEXT PRIMARY KEY,
        $colTitle TEXT,
        $colBody TEXT,
        $columnTimestamp INTEGER,
        $colRelatedPostId TEXT
      )''');
    await db.execute(''' CREATE TABLE $tablePosts ( 
      $colPostId TEXT PRIMARY KEY, $colUserId TEXT, $colUserName TEXT, $colUserImageUrl TEXT, $colText TEXT, $colImageUrl TEXT, $colVideoUrl TEXT, $colLikes INTEGER DEFAULT 0, $colCommentsCount INTEGER DEFAULT 0, $colViews INTEGER DEFAULT 0, $colTimestamp INTEGER NOT NULL, $colIsLikedByMe INTEGER DEFAULT 0, $colSyncStatus TEXT, $colIsStar INTEGER DEFAULT 0, $colLikedByJson TEXT, $colStarExpiryTimestamp INTEGER 
    )''');
    await db.execute(''' CREATE TABLE $tableTangazaComments ( $colCommentId TEXT PRIMARY KEY, $colPostId TEXT NOT NULL, $colUserId TEXT, $colUserName TEXT, $colText TEXT, $colAudioUrl TEXT, $colLikesCount INTEGER DEFAULT 0, $colLikedBy TEXT, $colTimestamp INTEGER NOT NULL, $colSyncStatus TEXT NOT NULL )''');
  }

  Future<void> saveMessage(Map<String, dynamic> messageData) async {
    final db = await database;
    final messageId = messageData[columnId];
    if (messageId == null) return;

    final List<Map<String, dynamic>> existingMessages = await db.query(
      tableMessages,
      where: '$columnId = ?',
      whereArgs: [messageId],
    );

    final Map<String, dynamic> messageToSave = Map.from(messageData);

    if (existingMessages.isNotEmpty) {
      final existingMessage = existingMessages.first;
      
      if (messageToSave[columnLocalPath] == null && existingMessage[columnLocalPath] != null) {
        messageToSave[columnLocalPath] = existingMessage[columnLocalPath];
      }
      if (messageToSave[columnFileName] == null && existingMessage[columnFileName] != null) {
        messageToSave[columnFileName] = existingMessage[columnFileName];
      }
      if (messageToSave[columnThumbnailLocalPath] == null && existingMessage[columnThumbnailLocalPath] != null) {
        messageToSave[columnThumbnailLocalPath] = existingMessage[columnThumbnailLocalPath];
      }
      if (messageToSave[columnStoragePath] == null && existingMessage[columnStoragePath] != null) {
        messageToSave[columnStoragePath] = existingMessage[columnStoragePath];
      }
    }
    
    messageToSave.putIfAbsent(columnWaveform, () => null);
    
    await db.insert(tableMessages, messageToSave,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  Future<void> updateMessageStatus(String messageId, String status) async {
      final db = await database;
      await db.update(
          tableMessages,
          {columnStatus: status},
          where: '$columnId = ?',
          whereArgs: [messageId],
      );
  }

  Future<void> updateMessageLocalPath(String messageId, String localPath) async {
    final db = await database;
    await db.update(
      tableMessages,
      {columnLocalPath: localPath},
      where: '$columnId = ?',
      whereArgs: [messageId],
    );
  }
  
  Future<void> updateMessageFileUrl(String messageId, String fileUrl) async {
    final db = await instance.database;
    await db.update(
      tableMessages,
      {columnFileUrl: fileUrl},
      where: '$columnId = ?',
      whereArgs: [messageId],
    );
    log("DatabaseHelper: URL y'ifayiri y'ubutumwa $messageId yavuguruwe.");
  }

  Future<void> updateMessageThumbnailLocalPath(String messageId, String thumbnailLocalPath) async {
    final db = await database;
    await db.update(
      tableMessages,
      {columnThumbnailLocalPath: thumbnailLocalPath},
      where: '$columnId = ?',
      whereArgs: [messageId],
    );
  }
  
  Future<void> updateMessageStoragePathAndUrl(String messageId, String storagePath, String? fileUrl) async {
    final db = await instance.database;
    await db.update(
      tableMessages,
      {
        columnStoragePath: storagePath,
        columnFileUrl: fileUrl,
        columnStatus: 'sent',
      },
      where: '$columnId = ?',
      whereArgs: [messageId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingMessages() async {
    final db = await instance.database;
    return await db.query(tableMessages, where: '$columnStatus = ? OR $columnStatus = ?', whereArgs: ['pending', 'failed']);
  }
  
  Future<List<Map<String, dynamic>>> getMessagesForChatRoom(String chatRoomID) async {
    final db = await instance.database;
    return await db.query(tableMessages, where: '$columnChatRoomID = ?', whereArgs: [chatRoomID], orderBy: '$columnTimestamp ASC');
  }

  Future<void> saveStarNotifications(List<Map<String, dynamic>> notifications) async {
    final db = await database;
    final batch = db.batch();
    for (var notification in notifications) {
      batch.insert(tableStarNotifications, notification,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getStarNotifications() async {
    final db = await database;
    return await db.query(tableStarNotifications, orderBy: '$columnTimestamp DESC');
  }

  Future<void> cachePosts(List<Map<String, dynamic>> posts) async {
    if (posts.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (var post in posts) {
      batch.insert(tablePosts, post, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await _enforcePostLimit();
  }

  Future<void> _enforcePostLimit() async {
    final db = await database;
    final countResult = await db.rawQuery('SELECT COUNT(*) FROM $tablePosts WHERE $colIsStar = 0');
    final count = Sqflite.firstIntValue(countResult);

    if (count != null && count > _postCacheLimit) {
      final postsToDelete = count - _postCacheLimit;
      final oldestPosts = await db.query(tablePosts, columns: [colPostId], where: '$colIsStar = ?', whereArgs: [0], orderBy: '$colTimestamp ASC', limit: postsToDelete);
      if (oldestPosts.isNotEmpty) {
        final idsToDelete = oldestPosts.map((row) => row[colPostId] as String).toList();
        await db.delete(tablePosts, where: '$colPostId IN (${List.filled(idsToDelete.length, '?').join(',')})', whereArgs: idsToDelete);
      }
    }
  }

  Future<List<Map<String, dynamic>>> getAllRegularPostsFromCache() async {
    final db = await instance.database;
    return await db.query(tablePosts, where: '$colIsStar = ?', whereArgs: [0], orderBy: '$colTimestamp DESC');
  }
  
  Future<List<Map<String, dynamic>>> getStarPosts() async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.query(tablePosts, where: '$colIsStar = ? AND ($colStarExpiryTimestamp IS NULL OR $colStarExpiryTimestamp > ?)', whereArgs: [1, now], orderBy: '$colTimestamp DESC', limit: 5);
  }

  Future<void> incrementPostView(String postId) async {
    final db = await instance.database;
    await db.rawUpdate('UPDATE $tablePosts SET $colViews = $colViews + 1 WHERE $colPostId = ?', [postId]);
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(tableSettings, {columnKey: key, columnValue: value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(tableSettings, where: '$columnKey = ?', whereArgs: [key]);
    if (maps.isNotEmpty) return maps.first[columnValue] as String?;
    return null;
  }
  
  Future<void> batchSaveMessages(List<Map<String, dynamic>> messages) async {
    if (messages.isEmpty) return;
    final db = await database;
    for (var message in messages) {
      await saveMessage(message); 
    }
  }

  Future<void> clearChat(String chatRoomID) async {
    final db = await database;
    await db.delete(tableMessages, where: '$columnChatRoomID = ?', whereArgs: [chatRoomID]);
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete(tableMessages, where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageStatusAndOnlineUrl(String messageId, String status, String? onlineUrl) async {
    final db = await database;
    final values = {columnStatus: status};
    if (onlineUrl != null) {
      values[columnOnlineUrl] = onlineUrl;
    }
    await db.update(tableMessages, values, where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageStatusAndFileUrl(String messageId, String status, String? fileUrl) async {
    final db = await database;
    final values = {columnStatus: status};
    if (fileUrl != null) {
      values[columnFileUrl] = fileUrl;
    }
    await db.update(tableMessages, values, where: '$columnId = ?', whereArgs: [messageId]);
  }

  Future<void> updateMessageFilePath(String messageId, String localPath) async {
    final db = await database;
    await db.update(
      tableMessages,
      {columnLocalPath: localPath}, 
      where: '$columnId = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> saveCall(CallData call) async {
    final db = await database;
    await db.insert(tableCalls, call.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteOldCalls() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    await db.delete(tableCalls, where: '$columnTimestamp < ?', whereArgs: [cutoff]);
  }

  Future<void> saveJembeContact(Map<String, dynamic> userData) async {
    final db = await database;
    await db.insert(
      tableJembeContacts,
      {
        colUserId: userData['id'] ?? userData[colUserId],
        colDisplayName: userData[colDisplayName],
        colPhotoUrl: userData[colPhotoUrl],
        colPhoneNumber: userData[colPhoneNumber],
        colEmail: userData[colEmail],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getJembeContactById(String userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(tableJembeContacts, where: '$colUserId = ?', whereArgs: [userId]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<void> savePost(Map<String, dynamic> postData) async {
    final db = await database;
    await db.insert(tablePosts, postData, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  Future<List<String>> getChatRoomIdsSortedByLastMessage() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableMessages,
      columns: [columnChatRoomID],
      groupBy: columnChatRoomID,
      orderBy: 'MAX($columnTimestamp) DESC',
    );
    return List.generate(maps.length, (i) => maps[i][columnChatRoomID] as String);
  }

  Future<String?> getLocalPathForMessage(String messageId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableMessages,
      columns: [columnLocalPath], 
      where: '$columnId = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first[columnLocalPath] as String?;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getCallsForUser(String currentUserId) async {
    final db = await instance.database;
    return await db.query(tableCalls, where: '$colCallerId = ? OR $colReceiverId = ?', whereArgs: [currentUserId, currentUserId], orderBy: '$columnTimestamp DESC');
  }

  Future<List<Map<String, dynamic>>> getJembeContacts() async {
    final db = await instance.database;
    return await db.query(tableJembeContacts, orderBy: '$colDisplayName ASC');
  }
  
  Future<List<Map<String, dynamic>>> getPosts({String? syncStatus, String order = 'DESC'}) async { 
    final db = await instance.database;
    if (syncStatus != null) {
      return await db.query(tablePosts, where: '$colSyncStatus = ?', whereArgs: [syncStatus], orderBy: '$colTimestamp $order');
    }
    return await db.query(tablePosts, orderBy: '$colTimestamp $order');
  }
  
  Future<List<Map<String, dynamic>>> getPostsByUserId(String userId) async {
    final db = await instance.database;
    final result = await db.query(tablePosts, where: '$colUserId = ?', whereArgs: [userId], orderBy: '$colTimestamp DESC');
    return result.toList();
  }

  Future<void> updatePostSyncStatus(String postId, String status) async {
    final db = await database;
    await db.update(tablePosts, {colSyncStatus: status}, where: '$colPostId = ?', whereArgs: [postId]);
  }

  Future<void> updatePostRemoteUrls(String postId, {String? imageUrl, String? videoUrl}) async {
    final db = await database;
    final values = <String, dynamic>{};
    if (imageUrl != null) values[colImageUrl] = imageUrl;
    if (videoUrl != null) values[colVideoUrl] = videoUrl;
    if (values.isNotEmpty) {
      await db.update(tablePosts, values, where: '$colPostId = ?', whereArgs: [postId]);
    }
  }

  Future<void> saveComment(Map<String, dynamic> commentData) async { /* ... */ }
  Future<List<Map<String, dynamic>>> getCommentsForPost(String postId) async { return []; }
  Future<void> toggleCommentLike(String commentId, String userId) async { /* ... */ }
  Future<void> togglePostLikeStatus(String postId, bool isCurrentlyLiked) async { /* ... */ }
  Future<void> incrementPostCommentCount(String postId) async { /* ... */ }
  Future<void> decrementPostCommentCount(String postId) async { /* ... */ }
  Future<void> deleteComment(String commentId) async { /* ... */ }
  Future<void> deletePost(String postId) async { /* ... */ }
  Future<void> updateComment(String commentId, String newText) async { /* ... */ }

  Future<Map<String, dynamic>?> getLastMessage(String chatRoomID) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableMessages,
      where: '$columnChatRoomID = ?',
      whereArgs: [chatRoomID],
      orderBy: '$columnTimestamp DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }
  
  Future<void> updateMessageMediaDetails(String messageId, String fileUrl, String storagePath) async {
    final db = await database;
    await db.update(
      tableMessages,
      {
        columnFileUrl: fileUrl,
        columnStoragePath: storagePath,
      },
      where: '$columnId = ?',
      whereArgs: [messageId],
    );
    log("Local DB updated by FCM for message $messageId with new media paths.");
  }
}