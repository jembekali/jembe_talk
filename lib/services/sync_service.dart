// lib/services/sync_service.dart (VERSION 48.9 - GHOST SOUND FIXED - NO CORE CHANGES)

import 'dart:async';
import 'dart:io';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/chat_repository.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

final SyncService syncService = SyncService();

class SyncService with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ChatRepository _chatRepository = ChatRepository();

  bool _isSyncing = false;
  bool _isListeningBackground = false;

  // 🔥 FIX: Ibi nibyo bidufasha guhagarika ghost sound
  int _syncStartTime = DateTime.now().millisecondsSinceEpoch;

  String? _currentActiveChatId;
  StreamSubscription? _activeChatSubscription;
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _roomsSubscription;
  StreamSubscription? _broadcastSubscription;

  String? get currentActiveChatId => _currentActiveChatId;

  set currentActiveChatId(String? val) {
    _currentActiveChatId = val;
    _startRoomStatusListener(val);
  }

  // --- CONTROLLERS ---
  final Map<String, http.Client> _activeDownloads = {};
  final _uploadProgressController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get uploadProgressStream =>
      _uploadProgressController.stream;

  final _uiMessageUpdateController = StreamController<String>.broadcast();
  Stream<String> get uiMessageUpdateStream => _uiMessageUpdateController.stream;

  static const List<String> _noMediaTypes = [
    'text',
    'large_emoji',
    'dame_invitation',
    'contact'
  ];
  final String _adminSystemId = 'jembe_talk_official_admin';

  Timer? _throttleTimer;

  // --- INITIALIZATION ---
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _startBackgroundListener();
    triggerSync();
    syncDeliveredStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startBackgroundListener();
      if (_currentActiveChatId != null) {
        _startRoomStatusListener(_currentActiveChatId);
      }
      triggerSync();
      syncDeliveredStatus();
    } else if (state == AppLifecycleState.paused) {
      _stopBackgroundListener();
    }
  }

  // --- 1. STATUS & SYNC LOGIC ---

  Future<void> syncDeliveredStatus() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      final pending =
          await _dbHelper.getMessagesByStatus('sent', currentUser.uid);
      if (pending.isEmpty) return;
      final batch = _firestore.batch();
      for (var msg in pending) {
        String rId = msg[DatabaseHelper.columnChatRoomID];
        String mId = msg[DatabaseHelper.columnId];
        batch.update(
            _firestore
                .collection('chat_rooms')
                .doc(rId)
                .collection('messages')
                .doc(mId),
            {'status': 'delivered'});
        await _dbHelper.updateMessageStatus(mId, 'delivered');
      }
      await batch.commit();
      notifyUIMessageUpdate("refresh_ui");
    } catch (e) {
      log("SyncDeliveredStatus Error: $e");
    }
  }

  Future<void> markChatAsSeen(String roomId, String otherUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      await _dbHelper.markMessagesAsRead(roomId, currentUser.uid);
      await _firestore.collection('chat_rooms').doc(roomId).set({
        'lastReadTimestamps': {currentUser.uid: FieldValue.serverTimestamp()}
      }, SetOptions(merge: true));
      final snap = await _firestore
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .where('receiverID', isEqualTo: currentUser.uid)
          .where('status', isNotEqualTo: 'seen')
          .get();
      if (snap.docs.isNotEmpty) {
        WriteBatch batch = _firestore.batch();
        for (var doc in snap.docs) {
          batch.update(doc.reference, {'status': 'seen'});
        }
        await batch.commit();
      }
      notifyUIMessageUpdate("refresh_badges");
    } catch (e) {
      log("MarkChatAsSeen Error: $e");
    }
  }

  Future<void> markVoiceNoteAsPlayed(
      String roomId, String messageId, String senderId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      await _dbHelper.updateMessagePlayedStatus(messageId, 1);
      if (currentUser.uid != senderId) {
        await _firestore
            .collection('chat_rooms')
            .doc(roomId)
            .collection('messages')
            .doc(messageId)
            .update({'isPlayed': 1, 'status': 'seen'});
        await _firestore.collection('chat_rooms').doc(roomId).set({
          'lastReadTimestamps': {currentUser.uid: FieldValue.serverTimestamp()}
        }, SetOptions(merge: true));
      }
      notifyUIMessageUpdate(messageId);
    } catch (e) {
      log("MarkVoiceNoteAsPlayed Error: $e");
    }
  }

  // --- 2. BACKGROUND DATA LISTENERS (OFFLINE-SYNC ENGINE) ---

  void _startBackgroundListener() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _stopBackgroundListener();
    _isListeningBackground = true;

    // 🔥 FIX: Igihe cyose listener itangiye, bika isaha byerekeyeho (kugira ngo udakina kera)
    _syncStartTime = DateTime.now().millisecondsSinceEpoch;

    int lastTsInSql = await _chatRepository.getLastMessageTimestamp();
    int safetyMargin = 10 * 1000;
    Timestamp startTime =
        Timestamp.fromMillisecondsSinceEpoch(lastTsInSql - safetyMargin);

    _messagesSubscription = _firestore
        .collectionGroup('messages')
        .where(Filter.or(Filter('receiverID', isEqualTo: currentUser.uid),
            Filter('senderID', isEqualTo: currentUser.uid)))
        .where('timestamp', isGreaterThan: startTime)
        .snapshots()
        .listen((snapshot) => _processRemoteChanges(snapshot));

    _roomsSubscription = _firestore
        .collection('chat_rooms')
        .where('users', arrayContains: currentUser.uid)
        .snapshots()
        .listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        final data = change.doc.data();
        if (data != null) {
          final String roomId = change.doc.id;
          final List users = data['users'] as List;
          final String? otherId = users
              .firstWhere((id) => id != currentUser.uid, orElse: () => null);
          final Map? timestamps = data['lastReadTimestamps'];
          if (otherId != null &&
              timestamps != null &&
              timestamps[otherId] != null) {
            int otherLastReadTs =
                (timestamps[otherId] as Timestamp).millisecondsSinceEpoch;
            await _dbHelper.markSentMessagesAsSeenLocally(
                roomId, currentUser.uid, otherLastReadTs);
          }
          if (otherId != null) {
            await _ensureContactExists(otherId);
          }
        }
      }
      notifyUIMessageUpdate("refresh_ui");
    });

    _broadcastSubscription = _firestore
        .collection('global_broadcasts')
        .doc('latest')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        _handleIncomingBroadcast(snapshot.data() as Map<String, dynamic>);
      }
    });
  }

  Future<void> _processRemoteChanges(QuerySnapshot snapshot) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    if (snapshot.docChanges.isEmpty) return;

    for (var change in snapshot.docChanges) {
      final String messageId = change.doc.id;
      if (change.type == DocumentChangeType.removed) {
        await _dbHelper.deleteMessage(messageId);
        continue;
      }

      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final serverMessage = Map<String, dynamic>.from(data);
      final String roomId = serverMessage['chatRoomID'] ??
          (change.doc.reference.parent.parent?.id ?? "");

      serverMessage['id'] = messageId;
      serverMessage['chatRoomID'] = roomId;

      int msgTs = 0;
      if (serverMessage['timestamp'] is Timestamp) {
        msgTs =
            (serverMessage['timestamp'] as Timestamp).millisecondsSinceEpoch;
        serverMessage['timestamp'] = msgTs;
      } else {
        msgTs = serverMessage['timestamp'] ?? 0;
      }

      // 🔥 FIX: Iyi ni yo logic ikiza ghost sound
      // Akajwi kavuga gusa niba:
      // 1. Message ari iyanjye (Receiver)
      // 2. Ari Message nsha muri Database (added)
      // 3. Igihe cyayo kikaba ari kinini kurenza igihe App yafunguriwe (_syncStartTime)
      if (serverMessage['receiverID'] == currentUser.uid &&
          change.type == DocumentChangeType.added &&
          msgTs > _syncStartTime) {
        _uiMessageUpdateController.add("message_received:$roomId");
      }

      final existing = await _dbHelper.getMessageById(messageId);
      if (existing != null && existing[DatabaseHelper.columnStatus] == 'seen') {
        serverMessage['status'] = 'seen';
      } else {
        if (serverMessage['receiverID'] == currentUser.uid) {
          if (roomId == _currentActiveChatId) {
            serverMessage['status'] = 'seen';
            _updateMessageStatusOnFirestore(roomId, messageId, 'seen');
          } else if (serverMessage['status'] == 'sent') {
            serverMessage['status'] = 'delivered';
            _updateMessageStatusOnFirestore(roomId, messageId, 'delivered');
          }
        }
      }

      await _dbHelper.saveMessage(serverMessage);

      if (serverMessage['receiverID'] == currentUser.uid &&
          serverMessage['messageType'] == 'voice_note') {
        String? url = serverMessage['fileUrl'] ?? serverMessage['onlineUrl'];
        if (url != null && url.isNotEmpty) {
          _triggerVoiceNoteAutoDownload(messageId, url);
        }
      }
    }
    notifyUIMessageUpdate("refresh_ui");
  }

  // --- 3. UPLOADS ENGINE (UNTOWCHED) ---

  Future<void> triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final pending = await _dbHelper.getPendingMessages();
      for (var m in pending) {
        if (_noMediaTypes.contains(m[DatabaseHelper.columnMessageType])) {
          await _uploadTextMessage(m);
        } else {
          await _uploadMediaMessage(m);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _uploadTextMessage(Map<String, dynamic> message) async {
    try {
      final String messageId = message[DatabaseHelper.columnId];
      final String roomId = message[DatabaseHelper.columnChatRoomID];
      final Map<String, dynamic> fsData = Map<String, dynamic>.from(message)
        ..remove(DatabaseHelper.columnId);
      fsData['status'] = 'sent';
      fsData['timestamp'] = FieldValue.serverTimestamp();
      fsData['expireAt'] =
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 4)));
      await _firestore
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .doc(messageId)
          .set(fsData);
      await _dbHelper.updateMessageStatus(messageId, 'sent');
      _uiMessageUpdateController.add("status_sent:$messageId");
    } catch (e) {
      log("UploadTextMessage Error: $e");
    }
  }

  Future<void> _uploadMediaMessage(Map<String, dynamic> message) async {
    final String messageId = message[DatabaseHelper.columnId];
    final String roomId = message[DatabaseHelper.columnChatRoomID];
    final String type = message[DatabaseHelper.columnMessageType] ?? 'image';
    try {
      await _dbHelper.updateMessageStatus(messageId, 'uploading');
      File f = File(message[DatabaseHelper.columnLocalPath]);
      int att = 0;
      while (!await f.exists() && att < 5) {
        await Future.delayed(Duration(milliseconds: 300 * (att + 1)));
        att++;
      }
      if (!await f.exists()) throw Exception("File not ready");
      String url = await R2Service().uploadFile(f, message['storagePath'],
          lookupMimeType(f.path) ?? 'application/octet-stream',
          onProgress: (p) => _uploadProgressController
              .add({'messageId': messageId, 'progress': p}));
      final Map<String, dynamic> fsData = Map<String, dynamic>.from(message)
        ..remove(DatabaseHelper.columnId);
      fsData['onlineUrl'] = url;
      fsData['fileUrl'] = url;
      fsData['status'] = 'sent';
      fsData['timestamp'] = FieldValue.serverTimestamp();
      fsData['expireAt'] =
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 4)));
      if (type == 'video' &&
          message[DatabaseHelper.columnThumbnailLocalPath] != null) {
        String tUrl = await R2Service().uploadFile(
            File(message[DatabaseHelper.columnThumbnailLocalPath]),
            "${message['storagePath']}_thumb.jpg",
            'image/jpeg');
        fsData['thumbnailUrl'] = tUrl;
      }
      await _firestore
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .doc(messageId)
          .set(fsData);
      await _dbHelper.updateMessageStatus(messageId, 'sent');
      _uiMessageUpdateController.add("status_sent:$messageId");
    } catch (e) {
      log("UploadMediaMessage Error: $e");
      await _dbHelper.updateMessageStatus(messageId, 'failed');
      notifyUIMessageUpdate(messageId);
    }
  }

  // --- 4. HELPERS ---

  Future<void> _handleIncomingBroadcast(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final String bId = data['id'] ?? 'bc_default';
    if ((await _dbHelper.getMessageById(bId)) == null) {
      List<String> ids = [user.uid, _adminSystemId]..sort();
      final msg = {
        'id': bId,
        'chatRoomID': ids.join('_'),
        'senderID': _adminSystemId,
        'receiverID': user.uid,
        'message': data['message'] ?? "",
        'messageType': 'text',
        'status': 'sent',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isPlayed': 0
      };
      await _dbHelper.saveMessage(msg);
      _uiMessageUpdateController.add("message_received:${ids.join('_')}");
    }
  }

  Future<void> _triggerVoiceNoteAutoDownload(
      String messageId, String url) async {
    if (_activeDownloads.containsKey(messageId)) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final localFile = File('${directory.path}/voice_notes/VN_$messageId.m4a');
      final client = http.Client();
      _activeDownloads[messageId] = client;
      final response = await client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (!await localFile.parent.exists()) {
          await localFile.parent.create(recursive: true);
        }
        await localFile.writeAsBytes(response.bodyBytes);
        await _dbHelper.updateMessageLocalPath(messageId, localFile.path);
        notifyUIMessageUpdate(messageId);
      }
    } catch (e) {
      log("VoiceNoteAutoDownload Error: $e");
    } finally {
      _activeDownloads.remove(messageId);
    }
  }

  void _startRoomStatusListener(String? roomId) {
    _activeChatSubscription?.cancel();
    if (roomId == null || _auth.currentUser == null) return;
    _activeChatSubscription = _firestore
        .collection('chat_rooms')
        .doc(roomId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      final Map? ts = data?['lastReadTimestamps'];
      final List users = data?['users'] as List;
      final String? otherId = users
          .firstWhere((id) => id != _auth.currentUser!.uid, orElse: () => null);
      if (otherId != null && ts?[otherId] != null) {
        int tsVal = (ts![otherId] as Timestamp).millisecondsSinceEpoch;
        await _dbHelper.markSentMessagesAsSeenLocally(
            roomId, _auth.currentUser!.uid, tsVal);
        notifyUIMessageUpdate("refresh_ui");
      }
    });
  }

  void _stopBackgroundListener() {
    _messagesSubscription?.cancel();
    _roomsSubscription?.cancel();
    _broadcastSubscription?.cancel();
    _activeChatSubscription?.cancel();
    _isListeningBackground = false;
  }

  void notifyUIMessageUpdate(String id) {
    if (id == "refresh_ui" || id.startsWith("refresh")) {
      if (_throttleTimer?.isActive ?? false) return;
      _throttleTimer = Timer(const Duration(milliseconds: 500), () {
        _uiMessageUpdateController.add("refresh_ui");
      });
    } else {
      _uiMessageUpdateController.add(id);
    }
  }

  Future<void> _updateMessageStatusOnFirestore(
      String roomId, String messageId, String status) async {
    try {
      await _firestore
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .doc(messageId)
          .update({'status': status});
    } catch (e) {
      log("UpdateMessageStatusOnFirestore Error: $e");
    }
  }

  Future<void> _ensureContactExists(String userId) async {
    try {
      if (await _dbHelper.getJembeContactById(userId) == null) {
        final doc = await _firestore.collection('users').doc(userId).get();
        if (doc.exists) {
          await _dbHelper.saveJembeContact(
              Map<String, dynamic>.from(doc.data()!)..['id'] = userId);
        }
      }
    } catch (e) {
      log("EnsureContactExists Error: $e");
    }
  }

  void cancelUpload(String mId) async {
    await _dbHelper.updateMessageStatus(mId, 'failed');
    notifyUIMessageUpdate(mId);
  }
}
