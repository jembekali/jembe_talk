// lib/services/sync_service.dart (VERSION 14.0: FIXED METADATA & EXTENSIONS)

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/firebase_service.dart';
import 'package:path/path.dart' as path; // Twongereyemo path

class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FirebaseService _firebaseService = FirebaseService(); 
  final FirebaseStorage _storage = FirebaseStorage.instance;
  StreamSubscription? _connectivitySubscription;
  bool _isSyncingMessages = false;
  
  bool _syncAgainAfterCompletion = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final StreamController<Map<String, dynamic>> _progressController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get uploadProgressStream => _progressController.stream;

  final StreamController<String> _uiMessageUpdateController = StreamController.broadcast();
  Stream<String> get uiMessageUpdateStream => _uiMessageUpdateController.stream;

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
    syncPendingMessages();
  }

  void stop() {
    _connectivitySubscription?.cancel();
  }
  
  Future<void> pauseUpload(String messageId) async {
    final task = _activeUploadTasks[messageId];
    if (task != null) {
      bool success = await task.pause();
      if (success) {
        await _dbHelper.updateMessageStatus(messageId, 'paused');
        notifyUIMessageUpdate(messageId);
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
        notifyUIMessageUpdate(messageId);
        log("Upload for $messageId resumed.");
      }
    } else {
      log("Task for $messageId not found in memory, re-triggering sync.");
      triggerSync();
    }
  }
  
  Future<void> cancelUpload(String messageId) async {
    final task = _activeUploadTasks[messageId];
    if (task != null) {
      log("Tugiye guhagarika kwohereza ubutumwa: $messageId");
      await task.cancel();
    } else {
      log("Umurimo wa $messageId ntiwari muri memory. Turahindura status muri DB gusa.");
    }
    await _dbHelper.updateMessageStatus(messageId, 'canceled');
    notifyUIMessageUpdate(messageId);
    _activeUploadTasks.remove(messageId);
    updateUploadProgress(messageId, null);
    log("Kwohereza ubutumwa $messageId byahagaritswe n'umukoresha.");
  }

  // Helper function yo kumenya ContentType (Metadata)
  String _getContentType(String filePath, String messageType) {
    final ext = path.extension(filePath).toLowerCase();
    
    if (messageType == 'voice_note' || messageType == 'audio_file') {
      // Voice Notes akenshi ziba ari m4a cyangwa aac
      if (ext == '.m4a') return 'audio/m4a';
      if (ext == '.mp3') return 'audio/mpeg';
      if (ext == '.aac') return 'audio/aac';
      if (ext == '.wav') return 'audio/wav';
      return 'audio/mp4'; // Default audio
    } else if (messageType == 'video') {
      if (ext == '.mov') return 'video/quicktime';
      if (ext == '.avi') return 'video/x-msvideo';
      return 'video/mp4'; // Default video
    } else if (messageType == 'image') {
      if (ext == '.png') return 'image/png';
      if (ext == '.webp') return 'image/webp';
      return 'image/jpeg'; // Default image
    }
    return 'application/octet-stream'; // Default generic
  }

  Future<void> syncPendingMessages() async {
    if (_isSyncingMessages) {
      log("[SyncService] Indi sync y'ubutumwa iracyakora, turarinze.");
      _syncAgainAfterCompletion = true;
      return;
    }
    _isSyncingMessages = true;
    log("[SyncService] Ndatangiye kugenzura ubutumwa butaragenda...");

    try {
      final pendingMessages = await _dbHelper.getPendingMessages();
      if (pendingMessages.isEmpty) {
        return;
      }

      log("[SyncService] Nsanze ubutumwa ${pendingMessages.length} butegereje koherezwa.");

      for (var messageData in pendingMessages) {
        final messageId = messageData[DatabaseHelper.columnId];
        log("[SyncService] Ndimo kugenzura ubutumwa: $messageId");
        
        try {
          Map<String, dynamic> dataToSendToFirestore = Map.from(messageData);
          bool isFileMessage = ['image', 'video', 'voice_note', 'document', 'audio_file'].contains(messageData[DatabaseHelper.columnMessageType]);
          
          if (isFileMessage) {
            String? localPath = messageData[DatabaseHelper.columnLocalPath];
            String? fileUrl = messageData[DatabaseHelper.columnFileUrl];

            if (localPath != null && fileUrl == null) {
              if (!await File(localPath).exists()) {
                log("!!!!!! File ntabwo iboneka kuri telefone: $localPath");
                await _dbHelper.updateMessageStatus(messageId, 'failed');
                notifyUIMessageUpdate(messageId);
                continue;
              }

              String? thumbnailUrl;
              String? thumbnailLocalPath = messageData[DatabaseHelper.columnThumbnailLocalPath];
              
              // Upload Thumbnail niba ihari
              if (thumbnailLocalPath != null && await File(thumbnailLocalPath).exists()) {
                try {
                  final thumbRef = _storage.ref().child('chat_media/${messageData[DatabaseHelper.columnChatRoomID]}/$messageId/thumbnail.jpg');
                  // Thumbnail ni image/jpeg
                  final thumbMetadata = SettableMetadata(contentType: 'image/jpeg');
                  final thumbUploadTask = await thumbRef.putFile(File(thumbnailLocalPath), thumbMetadata);
                  thumbnailUrl = await thumbUploadTask.ref.getDownloadURL();
                  dataToSendToFirestore[DatabaseHelper.columnThumbnailUrl] = thumbnailUrl;
                  log("[SyncService] Thumbnail yoherejwe neza kuri ubutumwa: $messageId");
                } catch(e) {
                  log("!!!!!! Ikosa mu kohereza thumbnail ya $messageId: $e");
                }
              }

              if (_activeUploadTasks.containsKey(messageId) || messageData[DatabaseHelper.columnStatus] == 'paused') continue;

              log("[SyncService] Ifayiri nini ibonetse. Ndatangiye kohereza.");
              await _dbHelper.updateMessageStatus(messageId, 'uploading');
              notifyUIMessageUpdate(messageId);

              File file = File(localPath);
              final String storagePath = messageData['storagePath'];
              final ref = _storage.ref().child(storagePath);
              
              // === IMPINDUKA Y'INGENZI: Gushyiraho Metadata ===
              // Ibi nibyo bituma Cloud Functionimenya ko ari Video/Audio igakora akazi kayo
              final contentType = _getContentType(localPath, messageData[DatabaseHelper.columnMessageType]);
              final metadata = SettableMetadata(contentType: contentType);
              
              final uploadTask = ref.putFile(file, metadata);
              _activeUploadTasks[messageId] = uploadTask;

              uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
                updateUploadProgress(messageId, snapshot.bytesTransferred / snapshot.totalBytes);
              });

              final TaskSnapshot snapshot = await uploadTask;
              final newFileUrl = await snapshot.ref.getDownloadURL();
              
              // Hano SyncService ibonye Link ya Original.
              // Kubera ko Cloud Function yacu ubu ifite "updateChatMessageWithRetry",
              // Cloud Function izahita iza inyuma ihindure iyi link muri Firestore.
              
              await _dbHelper.updateMessageUrls(messageId, fileUrl: newFileUrl, thumbnailUrl: thumbnailUrl);
              dataToSendToFirestore[DatabaseHelper.columnFileUrl] = newFileUrl;
              
              updateUploadProgress(messageId, null);
              log("[SyncService] Dosiye nini yoherejwe neza: $messageId");
            }
          }
          
          dataToSendToFirestore.remove(DatabaseHelper.columnLocalPath);
          dataToSendToFirestore.remove(DatabaseHelper.columnThumbnailLocalPath);
          dataToSendToFirestore[DatabaseHelper.columnStatus] = 'sent';
          dataToSendToFirestore[DatabaseHelper.columnTimestamp] = Timestamp.fromMillisecondsSinceEpoch(dataToSendToFirestore[DatabaseHelper.columnTimestamp]);

          await _firestore
              .collection('chat_rooms')
              .doc(dataToSendToFirestore[DatabaseHelper.columnChatRoomID])
              .collection('messages')
              .doc(messageId)
              .set(dataToSendToFirestore);

          await _dbHelper.updateMessageStatus(messageId, 'sent');
          notifyUIMessageUpdate(messageId);

          log("[SyncService] Ubutumwa '$messageId' rurungitswe neza kuri Firestore.");

        } catch (e) {
          if (e is FirebaseException && e.code == 'canceled') {
            log("Kwohereza ubutumwa $messageId byahagaritswe n'umukoresha. Status ishyizwe kuri 'canceled'.");
            await _dbHelper.updateMessageStatus(messageId, 'canceled');
          } else {
            log("!!!!!! Habaye ikibazo mu kurungika ubutumwa '$messageId': $e");
            await _dbHelper.updateMessageStatus(messageId, 'failed');
          }
          notifyUIMessageUpdate(messageId);
          updateUploadProgress(messageId, null);
        } finally {
          _activeUploadTasks.remove(messageId);
        }
      }
    } finally {
      log("[SyncService] Igikorwa co kurungika ubutumwa kirangiye.");
      _isSyncingMessages = false;
      
      if (_syncAgainAfterCompletion) {
        log("[SyncService] Hari akandi kazi kategereje. Ndongera ntangire bundi bushya.");
        _syncAgainAfterCompletion = false;
        triggerSync();
      }
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

// Iyi code isubiye uko yahora, irakora neza
final SyncService syncService = SyncService();