// lib/services/media_upload_service.dart (VERSION 2.5 - ASYNC COMPRESSION)

import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // Isolate support
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;
import 'dart:developer';

import 'sync_service.dart';

final MediaUploadService mediaUploadService = MediaUploadService();

class MediaUploadService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SyncService _syncService = syncService;
  
  // Iyi ni function ikora Compression itabangamiye UI (Runs in Isolate)
  static Map<String, String> _compressImageInIsolate(Map<String, dynamic> params) {
    final String localPath = params['localPath'];
    final String messageId = params['messageId'];
    final String tempDirPath = params['tempDirPath'];

    final File imageFile = File(localPath);
    final imageBytes = imageFile.readAsBytesSync();
    final image = img.decodeImage(imageBytes);

    if (image == null) return {};

    // 1. Compress Main Image (Quality 75, Max Width 1200)
    img.Image mainImg = image;
    if (image.width > 1200) {
      mainImg = img.copyResize(image, width: 1200);
    }
    final compPath = path.join(tempDirPath, 'comp_$messageId.jpg');
    File(compPath).writeAsBytesSync(img.encodeJpg(mainImg, quality: 75));

    // 2. Create Thumbnail (Width 200, Quality 50)
    final thumbPath = path.join(tempDirPath, 'thumb_$messageId.jpg');
    final thumbnail = img.copyResize(image, width: 200);
    File(thumbPath).writeAsBytesSync(img.encodeJpg(thumbnail, quality: 50));

    return {
      'compressedPath': compPath,
      'thumbnailPath': thumbPath,
    };
  }

  Future<void> sendMediaMessageFromData(Map<String, dynamic> messageData) async {
    final localPath = messageData[DatabaseHelper.columnLocalPath];
    final chatRoomID = messageData[DatabaseHelper.columnChatRoomID];
    final messageId = messageData[DatabaseHelper.columnId];
    
    if (messageData['storagePath'] == null || (messageData['storagePath'] as String).isEmpty) {
      final fileName = messageData[DatabaseHelper.columnFileName] ?? (localPath != null ? path.basename(localPath) : 'file');
      messageData['storagePath'] = 'chat/$chatRoomID/$messageId/$fileName';
    }

    // IMAGE COMPRESSION (Uburyo bw'ubwenge)
    if (messageData[DatabaseHelper.columnMessageType] == 'image' && localPath != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        
        // Ibi bikorerwa mu kindi gice (Isolate) kugira ngo App idategwa
        final result = await compute(_compressImageInIsolate, {
          'localPath': localPath,
          'messageId': messageId,
          'tempDirPath': tempDir.path,
        });

        if (result.isNotEmpty) {
          messageData[DatabaseHelper.columnLocalPath] = await saveFilePermanently(result['compressedPath']!);
          messageData[DatabaseHelper.columnThumbnailLocalPath] = await saveFilePermanently(result['thumbnailPath']!);
        }
      } catch (e) {
        log("Compression error: $e");
      }
    }
    
    // Kubika no gukangura Sync
    await DatabaseHelper.instance.saveMessage(messageData);
    _syncService.triggerSync();
  }
  
  // Logic ya Video (Thumbnail gusa, kuko compression yo ikorerwa muri ChatScreen)
  Future<String?> generateThumbnail(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        quality: 50,
      );
      if (thumbnailPath != null) return await saveFilePermanently(thumbnailPath);
    } catch (e) {
      log("Video thumbnail error: $e");
    }
    return null;
  }

  // --- Ibindi bice biguma uko byari biri (Contact, Permanent Save) ---

  Future<void> sendMediaMessage({
    required String chatRoomID,
    required String receiverID,
    String? localPath,
    required String messageType,
    String? text,
    int? duration,
    String? thumbnailLocalPath,
    String? fileName,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final messageId = const Uuid().v4();
    final messageData = {
      DatabaseHelper.columnId: messageId,
      DatabaseHelper.columnChatRoomID: chatRoomID,
      DatabaseHelper.columnSenderID: currentUser.uid,
      DatabaseHelper.columnReceiverID: receiverID,
      DatabaseHelper.columnMessageType: messageType,
      DatabaseHelper.columnTimestamp: DateTime.now().millisecondsSinceEpoch,
      DatabaseHelper.columnStatus: 'pending',
      DatabaseHelper.columnMessage: text,
      DatabaseHelper.columnLocalPath: localPath,
      DatabaseHelper.columnFileName: fileName,
      DatabaseHelper.columnDuration: duration,
      DatabaseHelper.columnThumbnailLocalPath: thumbnailLocalPath,
    };
    await sendMediaMessageFromData(messageData);
  }

  Future<void> sendContact(BuildContext context, {required String chatRoomID, required String receiverID}) async {
    try {
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final Contact? contact = await FlutterContacts.openExternalPick();
        if (contact != null && contact.phones.isNotEmpty) {
          final Map<String, String> contactData = {'name': contact.displayName, 'number': contact.phones.first.number};
          await sendMediaMessage(chatRoomID: chatRoomID, receiverID: receiverID, messageType: 'contact', text: jsonEncode(contactData));
        }
      }
    } catch (e) { log("Contact error: $e"); }
  }

  Future<String> saveFilePermanently(String temporaryPath) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String permanentDir = path.join(appDir.path, 'chat_media');
    final Directory dir = Directory(permanentDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final String fileName = path.basename(temporaryPath);
    final String permanentPath = path.join(permanentDir, fileName);
    final File tempFile = File(temporaryPath);
    if (await tempFile.exists()) {
      await tempFile.copy(permanentPath);
    }
    return permanentPath;
  }
}