// lib/services/sync_service.dart (VERSION NSHYA YUZUYE 100%)

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/firebase_service.dart';

class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FirebaseService _firebaseService = FirebaseService(); 
  final FirebaseStorage _storage = FirebaseStorage.instance;
  StreamSubscription? _connectivitySubscription;
  bool _isSyncingPosts = false;
  bool _isSyncingMessages = false;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final StreamController<Map<String, dynamic>> _progressController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get uploadProgressStream => _progressController.stream;

  final StreamController<String> _uiMessageUpdateController = StreamController.broadcast();
  Stream<String> get uiMessageUpdateStream => _uiMessageUpdateController.stream;

  // <<< IMPINDUKA #1: Iyi ni yo izobika imirimo iriko irakorwa >>>
  final Map<String, UploadTask> _activeUploadTasks = {};

  void notifyUIMessageUpdate(String messageId) {
    if (!_uiMessageUpdateController.isClosed) {
      _uiMessageUpdateController.add(messageId);
    }
  }

  void updateUploadProgress(String messageId, double? progress) {
    if (!_progressController.isClosed) {
      _progressController.add({
        'messageId': messageId,
        'progress': progress,
      });
    }
  }
  
  void start() {
    stop();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
        log("[SyncService] Internet irabonetse. Dutangiye gusanisha byose.");
        triggerSync();
      }
    });
    triggerSync();
  }
  
  void triggerSync() {
    log("[SyncService] triggerSync yahamagawe.");
    syncPendingPosts();
    syncPendingMessages();
  }

  void stop() {
    _connectivitySubscription?.cancel();
  }
  
  // <<< IMPINDUKA #2: Functions nshasha zo guhagarika no kubandanya >>>
  Future<void> pauseUpload(String messageId) async {
    final task = _activeUploadTasks[messageId];
    if (task != null) {
      bool success = await task.pause();
      if (success) {
        await _dbHelper.updateMessageStatus(messageId, 'paused');
        updateUploadProgress(messageId, null); // Guhagarika progress bar
        log("Upload for $messageId paused.");
      }
    }
  }

  Future<void> resumeUpload(String messageId) async {
    final task = _activeUploadTasks[messageId];
    if (task != null) {
      bool success = await task.resume();
      if (success) {
        await _dbHelper.updateMessageStatus(messageId, 'uploading');
        log("Upload for $messageId resumed.");
      }
    } else {
      // Niba umurimo utari ugihari (app yari yafunzwe), dutanguza bundi busha
      log("Task for $messageId not found in memory, re-triggering sync.");
      triggerSync();
    }
  }

  Future<void> syncPendingMessages() async {
    if (_isSyncingMessages) {
      log("[SyncService] Indi sync y'ubutumwa iracyakora, turarinze.");
      return;
    }
    _isSyncingMessages = true;
    log("[SyncService] Ndatangiye kugenzura ubutumwa butaragenda...");

    try {
      final pendingMessages = await _dbHelper.getPendingMessages();
      if (pendingMessages.isEmpty) {
        log("[SyncService] Nta butumwa bwa 'pending' nasanze.");
        _isSyncingMessages = false;
        return;
      }

      log("[SyncService] Nsanze ubutumwa ${pendingMessages.length} butegereje koherezwa.");

      for (var messageData in pendingMessages) {
        final messageId = messageData[DatabaseHelper.columnId];
        log("[SyncService] Ndimo kugenzura ubutumwa: $messageId");
        
        try {
          Map<String, dynamic> dataToSendToFirestore = Map.from(messageData);
          bool isFileMessage = ['image', 'video', 'voice_note', 'document', 'audio_file'].contains(messageData[DatabaseHelper.columnMessageType]);
          String? localPath = messageData[DatabaseHelper.columnLocalPath];
          String? fileUrl = messageData[DatabaseHelper.columnFileUrl];
          String? storagePath = messageData['storagePath'];

          if (isFileMessage && localPath != null && fileUrl == null) {
            if (storagePath == null || !await File(localPath).exists()) {
              await _dbHelper.updateMessageStatus(messageId, 'failed');
              continue;
            }
            
            // Igenzura ry'inyongera: Niba turiko turarungika canke twahagaritse, ntidusubira gutangura
            if (_activeUploadTasks.containsKey(messageId) || messageData[DatabaseHelper.columnStatus] == 'paused') continue;

            log("[SyncService] Ifayiri ibonetse. Ndatangiye kohereza kuri: '$storagePath'");
            await _dbHelper.updateMessageStatus(messageId, 'uploading');

            File file = File(localPath);
            final ref = _storage.ref().child(storagePath);
            
            final uploadTask = ref.putFile(
              file,
              SettableMetadata(
                customMetadata: {
                  'chatRoomID': messageData[DatabaseHelper.columnChatRoomID],
                  'messageID': messageId,
                  'receiverID': messageData[DatabaseHelper.columnReceiverID],
                },
              ),
            );

            _activeUploadTasks[messageId] = uploadTask;

            uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
              final double progress = snapshot.bytesTransferred / snapshot.totalBytes;
              updateUploadProgress(messageId, progress);
            });

            final TaskSnapshot snapshot = await uploadTask;
            final newFileUrl = await snapshot.ref.getDownloadURL();
            
            log(">>> [DEBUG - SyncService] Dosiye yoherejwe kuri '$storagePath'. URL yabonetse ni: $newFileUrl");

            await _dbHelper.updateMessageFileUrl(messageId, newFileUrl);
            dataToSendToFirestore[DatabaseHelper.columnFileUrl] = newFileUrl;
            
            updateUploadProgress(messageId, null);
            log("[SyncService] Dosiye yoherejwe neza. URL: $newFileUrl");
          }
          
          dataToSendToFirestore.remove(DatabaseHelper.columnLocalPath);
          dataToSendToFirestore[DatabaseHelper.columnStatus] = 'sent';
          dataToSendToFirestore[DatabaseHelper.columnTimestamp] = Timestamp.fromMillisecondsSinceEpoch(dataToSendToFirestore[DatabaseHelper.columnTimestamp]);

          await _firestore
              .collection('chat_rooms')
              .doc(dataToSendToFirestore[DatabaseHelper.columnChatRoomID])
              .collection('messages')
              .doc(messageId)
              .set(dataToSendToFirestore);

          await _dbHelper.updateMessageStatus(messageId, 'sent');
          log("[SyncService] Ubutumwa '$messageId' rurungitswe neza kuri Firestore.");

        } catch (e) {
          if (e is FirebaseException && e.code == 'canceled') {
            log("Upload for $messageId was canceled by user.");
            // Nta kintu dukora, status isigara ari 'paused'
          } else {
            log("!!!!!! Habaye ikibazo mu kurungika ubutumwa '$messageId': $e");
            await _dbHelper.updateMessageStatus(messageId, 'failed');
            updateUploadProgress(messageId, null);
          }
        } finally {
          _activeUploadTasks.remove(messageId);
        }
      }
    } finally {
      _isSyncingMessages = false;
      log("[SyncService] Igikorwa co kurungika ubutumwa kirangiye.");
    }
  }

  Future<void> syncPendingPosts({Function? onSyncComplete}) async {
    return;
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _progressController.close();
    _uiMessageUpdateController.close();
  }
}

final SyncService syncService = SyncService();