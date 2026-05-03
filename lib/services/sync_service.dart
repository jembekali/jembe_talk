// lib/services/sync_service.dart (VERSION 42.1 - FIXED TYPO & LINTER WARNINGS)

import 'dart:async';
import 'dart:io';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/chat_repository.dart'; 
import 'package:jembe_talk/services/r2_service.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

final SyncService syncService = SyncService();

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ChatRepository _chatRepository = ChatRepository(); 
  
  bool _isSyncing = false;
  bool _isListeningBackground = false; 

  // --- ACTIVE CHAT TRACKING ---
  String? _currentActiveChatId;
  StreamSubscription? _activeChatSubscription;

  String? get currentActiveChatId => _currentActiveChatId;

  set currentActiveChatId(String? val) {
    _currentActiveChatId = val;
    _startRoomStatusListener(val); 
  }

  // Trackers
  final Map<String, http.Client> _activeDownloads = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _playedMessageIds = {};
  final Map<String, bool> _activeUploadsStatus = {};
  
  final _uploadProgressController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get uploadProgressStream => _uploadProgressController.stream;
  
  final _uiMessageUpdateController = StreamController<String>.broadcast();
  Stream<String> get uiMessageUpdateStream => _uiMessageUpdateController.stream;

  static const List<String> _noMediaTypes = ['text', 'large_emoji', 'dame_invitation', 'dame_invitation_declined', 'contact', 'deleted'];
  final String _adminSystemId = 'jembe_talk_official_admin';

  void start() { 
    _startBackgroundListener(); 
    triggerSync(); 
  }

  // --- UI HELPERS ---
  bool isDownloading(String msgId) => _activeDownloads.containsKey(msgId);
  double getDownloadProgress(String msgId) => _downloadProgress[msgId] ?? 0.0;

  void cancelDownload(String messageId) {
    if (_activeDownloads.containsKey(messageId)) {
      _activeDownloads[messageId]?.close();
      _activeDownloads.remove(messageId);
      _downloadProgress.remove(messageId);
      notifyUIMessageUpdate(messageId);
    }
  }

  // --- ROOM STATUS LISTENER (Real-time Seen & Played) ---
  void _startRoomStatusListener(String? roomId) {
    _activeChatSubscription?.cancel();
    if (roomId == null || _auth.currentUser == null) {
      return;
    }
    _activeChatSubscription = _firestore.collection('chat_rooms').doc(roomId).collection('messages').orderBy('timestamp', descending: true).limit(30).snapshots().listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null) {
            final String msgId = change.doc.id;
            final existing = await _dbHelper.getMessageById(msgId);
            if (existing != null) {
              bool needsUpdate = false;
              if (existing['status'] != data['status']) { 
                await _dbHelper.updateMessageStatus(msgId, data['status'] ?? 'sent'); 
                needsUpdate = true; 
              }
              if (existing['isPlayed'] != data['isPlayed']) { 
                await _dbHelper.updateMessagePlayedStatus(msgId, data['isPlayed'] ?? 0); 
                needsUpdate = true; 
              }
              if (needsUpdate) {
                notifyUIMessageUpdate("status_updated:$msgId");
              }
            }
          }
        }
      }
    });
  }

  // --- CONTACT AUTO-SYNC ---
  Future<void> _ensureContactExists(String userId) async {
    if (userId == _adminSystemId) {
      return;
    }
    try {
      final existing = await _dbHelper.getJembeContactById(userId);
      if (existing == null || existing[DatabaseHelper.colDisplayName] == null) {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists && userDoc.data() != null) {
          final data = Map<String, dynamic>.from(userDoc.data()!);
          data['id'] = userId;
          await _dbHelper.saveJembeContact(data);
          notifyUIMessageUpdate("refresh_ui"); 
        }
      }
    } catch (_) {}
  }

  // --- BACKGROUND LISTENERS ---
  void _startBackgroundListener() async {
    final currentUser = _auth.currentUser; if (currentUser == null || _isListeningBackground) return;
    _isListeningBackground = true;
    int lastTsInSql = await _chatRepository.getLastMessageTimestamp();
    
    _firestore.collectionGroup('messages')
      .where(Filter.or(Filter('receiverID', isEqualTo: currentUser.uid), Filter('senderID', isEqualTo: currentUser.uid)))
      .where('timestamp', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastTsInSql))
      .snapshots().listen((snapshot) => _processRemoteChanges(snapshot));

    _firestore.collection('chat_rooms').where('users', arrayContains: currentUser.uid).snapshots().listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        final data = change.doc.data();
        if (data != null) {
          final List users = data['users'] as List;
          final otherId = users.firstWhere((id) => id != currentUser.uid, orElse: () => null);
          if (otherId != null) {
            await _ensureContactExists(otherId);
          }
        }
      }
    });

    _firestore.collection('global_broadcasts').doc('latest').snapshots().listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        _handleIncomingBroadcast(snapshot.data() as Map<String, dynamic>);
      }
    });
  }

  Future<void> _processRemoteChanges(QuerySnapshot snapshot) async {
    final currentUser = _auth.currentUser; if (currentUser == null) return;
    for (var change in snapshot.docChanges) {
      final String messageId = change.doc.id;
      if (change.type == DocumentChangeType.removed) { 
        await _dbHelper.deleteMessage(messageId); 
        notifyUIMessageUpdate("refresh_ui"); 
        continue; 
      }
      
      final data = change.doc.data() as Map<String, dynamic>?; if (data == null) continue;
      final serverMessage = Map<String, dynamic>.from(data);
      final String roomId = (change.doc.reference.parent.parent != null) 
          ? change.doc.reference.parent.parent!.id 
          : (serverMessage['chatRoomID'] ?? "");
      
      await _ensureContactExists(serverMessage['senderID'] == currentUser.uid ? serverMessage['receiverID'] : serverMessage['senderID']);

      serverMessage['id'] = messageId;
      serverMessage['chatRoomID'] = roomId;
      serverMessage['isPlayed'] = data['isPlayed'] ?? 0;
      if (serverMessage['timestamp'] is Timestamp) {
        serverMessage['timestamp'] = (serverMessage['timestamp'] as Timestamp).millisecondsSinceEpoch;
      }
      
      if (serverMessage['receiverID'] == currentUser.uid) {
        if (roomId == currentActiveChatId) {
          serverMessage['status'] = 'seen';
          _updateMessageStatusOnFirestore(roomId, messageId, 'seen');
        } else if (serverMessage['status'] == 'sent') {
          serverMessage['status'] = 'delivered';
          _updateMessageStatusOnFirestore(roomId, messageId, 'delivered');
        }
      }

      final bool alreadyExists = (await _dbHelper.getMessageById(messageId)) != null;
      await _dbHelper.saveMessage(serverMessage);
      
      if (serverMessage['receiverID'] == currentUser.uid && serverMessage['messageType'] == 'voice_note' && roomId == currentActiveChatId) {
        String? url = serverMessage['fileUrl'] ?? serverMessage['onlineUrl'];
        if (url != null && url.isNotEmpty) {
          _triggerVoiceNoteAutoDownload(messageId, url);
        }
      }

      if (serverMessage['receiverID'] == currentUser.uid && !alreadyExists && !_playedMessageIds.contains(messageId)) {
        _playedMessageIds.add(messageId);
        notifyUIMessageUpdate("message_received:$roomId");
        if (_playedMessageIds.length > 100) {
          _playedMessageIds.remove(_playedMessageIds.first);
        }
      } else { 
        notifyUIMessageUpdate(messageId); 
      }
    }
  }

  Future<void> _triggerVoiceNoteAutoDownload(String messageId, String url) async {
    if (_activeDownloads.containsKey(messageId)) return;
    try {
      final client = http.Client(); _activeDownloads[messageId] = client;
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode == 200) {
        final List<int> bytes = []; 
        final int total = response.contentLength ?? -1;
        await for (var chunk in response.stream) { 
          bytes.addAll(chunk); 
          if (total != -1) { 
            _downloadProgress[messageId] = bytes.length / total; 
            notifyUIMessageUpdate(messageId); 
          } 
        }
        final directory = await getApplicationDocumentsDirectory();
        final localFile = File('${directory.path}/voice_notes/VN_$messageId.m4a');
        if (!await localFile.parent.exists()) {
          await localFile.parent.create(recursive: true);
        }
        await localFile.writeAsBytes(bytes);
        await _dbHelper.updateMessageLocalPath(messageId, localFile.path);
      }
    } catch (_) {} finally { 
      _activeDownloads.remove(messageId); 
      _downloadProgress.remove(messageId); 
      notifyUIMessageUpdate(messageId); 
    }
  }

  // --- UPLOAD METHODS ---
  Future<void> _uploadTextMessage(Map<String, dynamic> message) async {
    try {
      final String messageId = message[DatabaseHelper.columnId];
      final String roomId = message[DatabaseHelper.columnChatRoomID];
      final Map<String, dynamic> firestoreData = Map<String, dynamic>.from(message)..remove(DatabaseHelper.columnId);
      firestoreData['status'] = 'sent'; 
      firestoreData['timestamp'] = FieldValue.serverTimestamp();
      firestoreData['expireAt'] = Timestamp.fromDate(DateTime.now().add(const Duration(days: 4)));
      await _firestore.collection('chat_rooms').doc(roomId).collection('messages').doc(messageId).set(firestoreData);
      await _updateChatRoomLastMessage(roomId, message['message'] ?? "", message['senderID'], message['messageType'] ?? 'text');
      await _dbHelper.updateMessageStatus(messageId, 'sent');
      notifyUIMessageUpdate(messageId);
    } catch (_) {}
  }

  Future<void> _uploadMediaMessage(Map<String, dynamic> message) async {
    final String messageId = message[DatabaseHelper.columnId];
    final String roomId = message[DatabaseHelper.columnChatRoomID];
    final String type = message[DatabaseHelper.columnMessageType] ?? 'image';
    _activeUploadsStatus[messageId] = true;
    try {
      await _dbHelper.updateMessageStatus(messageId, 'uploading');
      List<Future<String>> uploadTasks = [];
      File fileToUpload = File(message[DatabaseHelper.columnLocalPath]);
      uploadTasks.add(R2Service().uploadFile(fileToUpload, message['storagePath'], lookupMimeType(fileToUpload.path) ?? 'application/octet-stream', onProgress: (p) => _uploadProgressController.add({'messageId': messageId, 'progress': p})));
      
      String? thumbPath = message[DatabaseHelper.columnThumbnailLocalPath];
      if (type == 'video' && thumbPath != null && File(thumbPath).existsSync()) {
        uploadTasks.add(R2Service().uploadFile(File(thumbPath), "${message['storagePath']}_thumb.jpg", 'image/jpeg'));
      }
      
      final results = await Future.wait(uploadTasks);
      final Map<String, dynamic> firestoreData = Map<String, dynamic>.from(message)..remove(DatabaseHelper.columnId);
      firestoreData['onlineUrl'] = results[0]; 
      firestoreData['fileUrl'] = results[0];
      if (results.length > 1) {
        firestoreData['thumbnailUrl'] = results[1];
      }
      firestoreData['status'] = 'sent'; 
      firestoreData['timestamp'] = FieldValue.serverTimestamp();
      firestoreData['expireAt'] = Timestamp.fromDate(DateTime.now().add(const Duration(days: 4)));
      
      await _firestore.collection('chat_rooms').doc(roomId).collection('messages').doc(messageId).set(firestoreData);
      String preview = (type == 'image') ? "Photo 📷" : (type == 'video' ? "Video 🎥" : "Media 📂");
      await _updateChatRoomLastMessage(roomId, preview, message['senderID'], type);
      await _dbHelper.updateMessageStatus(messageId, 'sent');
      notifyUIMessageUpdate(messageId);
    } catch (_) { 
      await _dbHelper.updateMessageStatus(messageId, 'failed'); 
      notifyUIMessageUpdate(messageId); 
    } finally { 
      _activeUploadsStatus.remove(messageId); 
    }
  }

  Future<void> _updateChatRoomLastMessage(String roomId, String text, String senderId, String type) async {
    await _firestore.collection('chat_rooms').doc(roomId).update({ 
      'lastMessage': text, 
      'lastMessageSenderID': senderId, 
      'lastMessageTimestamp': FieldValue.serverTimestamp(), 
      'lastMessageType': type 
    });
  }

  // --- SYNC TOOLS ---
  Future<void> markChatAsSeen(String roomId, String otherUserId) async {
    final currentUser = _auth.currentUser; if (currentUser == null) return;
    try {
      await _dbHelper.markMessagesAsRead(roomId, currentUser.uid);
      notifyUIMessageUpdate("refresh_badges");
      final messagesSnap = await _firestore.collection('chat_rooms').doc(roomId).collection('messages').where('receiverID', isEqualTo: currentUser.uid).where('status', isNotEqualTo: 'seen').get();
      if (messagesSnap.docs.isNotEmpty) {
        WriteBatch batch = _firestore.batch();
        for (var doc in messagesSnap.docs) {
          batch.update(doc.reference, {'status': 'seen'});
        }
        await batch.commit();
      }
    } catch (_) {}
  }

  Future<void> markVoiceNoteAsPlayed(String roomId, String messageId) async {
    try {
      await _dbHelper.updateMessagePlayedStatus(messageId, 1);
      await _firestore.collection('chat_rooms').doc(roomId).collection('messages').doc(messageId).update({'isPlayed': 1});
      notifyUIMessageUpdate(messageId);
    } catch (_) {}
  }

  Future<void> _updateMessageStatusOnFirestore(String roomId, String messageId, String status) async {
    try { 
      await _firestore.collection('chat_rooms').doc(roomId).collection('messages').doc(messageId).update({'status': status}); 
    } catch (_) {}
  }

  Future<void> triggerSync() async {
    if (_isSyncing) return; _isSyncing = true;
    try {
      final pending = await _dbHelper.getPendingMessages();
      for (var m in pending) { 
        if (_noMediaTypes.contains(m[DatabaseHelper.columnMessageType])) {
          await _uploadTextMessage(m); 
        } else {
          await _uploadMediaMessage(m); 
        }
      }
    } finally { _isSyncing = false; }
  }

  Future<void> _handleIncomingBroadcast(Map<String, dynamic> data) async {
    final user = _auth.currentUser; if (user == null) return;
    final String broadcastId = data['id'] ?? 'bc_default';
    if ((await _dbHelper.getMessageById(broadcastId)) == null) {
      List<String> ids = [user.uid, _adminSystemId]..sort();
      final msgData = { 
        'id': broadcastId, 
        'chatRoomID': ids.join('_'), 
        'senderID': _adminSystemId, 
        'receiverID': user.uid, 
        'message': data['message'] ?? "", 
        'messageType': 'text', 
        'status': 'sent', 
        'timestamp': DateTime.now().millisecondsSinceEpoch, 
        'isPlayed': 0 
      };
      await _dbHelper.saveMessage(msgData);
      notifyUIMessageUpdate("message_received:${ids.join('_')}");
    }
  }

  void cancelUpload(String messageId) async { 
    _activeUploadsStatus[messageId] = false; 
    await _dbHelper.updateMessageStatus(messageId, 'failed'); 
    notifyUIMessageUpdate(messageId); 
  }
  
  void notifyUIMessageUpdate(String id) { 
    _uiMessageUpdateController.add(id); 
  }
}