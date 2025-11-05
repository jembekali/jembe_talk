// lib/services/media_upload_service.dart (VERSION NSHYA YUZUYE)

import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img; // <<< IMPORT NSHYA

import 'sync_service.dart';

final MediaUploadService mediaUploadService = MediaUploadService();

class MediaUploadService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final SyncService _syncService = syncService;

  // <<< FUNCTION NSHYA YO KOHEREZA THUMBNAIL >>>
  Future<String?> _uploadThumbnail(String filePath, String chatRoomID, String messageId) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      
      final thumbnailRef = _storage.ref().child('chat_media/$chatRoomID/$messageId/thumbnail.jpg');
      final uploadTask = thumbnailRef.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Kohereza thumbnail byanze: $e");
      return null;
    }
  }

  Future<void> sendMediaMessage({
    required String chatRoomID,
    required String receiverID,
    required String localPath,
    required String messageType,
    String? text,
    int? duration,
    String? thumbnailLocalPath,
    String? fileName,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final messageId = const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final String actualFileName = fileName ?? path.basename(localPath);
    final String storagePath = 'chat_media/$chatRoomID/$messageId/$actualFileName';
    
    // <<< IMPINDUKA NYAMUKURU: GUKORA NO KOHEREZA THUMBNAIL MBRE YA BYOSE >>>
    String? thumbnailUrl;
    String? finalThumbnailLocalPath = thumbnailLocalPath;

    if (messageType == 'image') {
      try {
        final tempDir = await getTemporaryDirectory();
        final thumbFile = File(path.join(tempDir.path, 'thumb_$messageId.jpg'));
        
        final imageBytes = await File(localPath).readAsBytes();
        final image = img.decodeImage(imageBytes);
        if (image != null) {
          final thumbnail = img.copyResize(image, width: 200);
          await thumbFile.writeAsBytes(img.encodeJpg(thumbnail, quality: 70));
          finalThumbnailLocalPath = thumbFile.path;
        }
      } catch (e) {
        debugPrint("Gukora thumbnail y'ifoto byanze: $e");
      }
    }

    if (finalThumbnailLocalPath != null) {
      thumbnailUrl = await _uploadThumbnail(finalThumbnailLocalPath, chatRoomID, messageId);
    }
    
    final Map<String, dynamic> messageData = {
      DatabaseHelper.columnId: messageId,
      DatabaseHelper.columnChatRoomID: chatRoomID,
      DatabaseHelper.columnSenderID: currentUser.uid,
      DatabaseHelper.columnReceiverID: receiverID,
      DatabaseHelper.columnMessageType: messageType,
      DatabaseHelper.columnTimestamp: timestamp,
      DatabaseHelper.columnStatus: 'pending',
      DatabaseHelper.columnMessage: text,
      DatabaseHelper.columnLocalPath: localPath,
      DatabaseHelper.columnFileName: fileName, 
      DatabaseHelper.columnDuration: duration,
      DatabaseHelper.columnFileUrl: null,
      'storagePath': storagePath, 
      DatabaseHelper.columnThumbnailUrl: thumbnailUrl, // <<< TWONGEREYEMO URL YA THUMBNAIL
      DatabaseHelper.columnThumbnailLocalPath: finalThumbnailLocalPath, // <<< TUBIKA N'INZIRA YAYO >>>
    };

    await DatabaseHelper.instance.saveMessage(messageData);
    _syncService.triggerSync();
  }
  
  Future<Map<String, dynamic>?> sendContact(BuildContext context, {required String chatRoomID, required String receiverID}) async {
    if (!await FlutterContacts.requestPermission()) {
       if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Urwego rwo kubona imyirondoro ntirwatanzwe.")));
       }
       return null;
    }
    
    final contact = await FlutterContacts.openExternalPick();
    if (contact != null) {
      final messageId = const Uuid().v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      final contactData = {'name': contact.displayName, 'phone': contact.phones.isNotEmpty ? contact.phones.first.number : 'N/A'};
      final Map<String, dynamic> messageData = {
        DatabaseHelper.columnId: messageId,
        DatabaseHelper.columnChatRoomID: chatRoomID,
        DatabaseHelper.columnSenderID: currentUser.uid,
        DatabaseHelper.columnReceiverID: receiverID,
        DatabaseHelper.columnMessageType: 'contact',
        DatabaseHelper.columnTimestamp: timestamp,
        DatabaseHelper.columnStatus: 'pending',
        DatabaseHelper.columnMessage: jsonEncode(contactData),
      };
      
      await DatabaseHelper.instance.saveMessage(messageData);
      _syncService.triggerSync();
      
      return messageData;
    }
    return null;
  }
  
  Future<String?> generateThumbnail(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        quality: 50,
      );
      if (thumbnailPath != null) {
        return await saveFilePermanently(thumbnailPath);
      }
    } catch (e) {
      debugPrint("Gukora thumbnail byanze: $e");
    }
    return null;
  }

  Future<String> saveFilePermanently(String temporaryPath) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String permanentDir = path.join(appDir.path, 'chat_media');
    final Directory dir = Directory(permanentDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final String fileName = path.basename(temporaryPath);
    final String permanentPath = path.join(permanentDir, fileName);
    final File tempFile = File(temporaryPath);
    await tempFile.copy(permanentPath);
    return permanentPath;
  }
}