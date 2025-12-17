// lib/services/media_upload_service.dart (IVUGURUYE NEZA)

import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
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

// Iyi code isubiye uko yahora, irakora neza
final MediaUploadService mediaUploadService = MediaUploadService();

class MediaUploadService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SyncService _syncService = syncService;
  
  Future<void> sendMediaMessageFromData(Map<String, dynamic> messageData) async {
    final localPath = messageData[DatabaseHelper.columnLocalPath];
    final chatRoomID = messageData[DatabaseHelper.columnChatRoomID];
    final messageId = messageData[DatabaseHelper.columnId];
    
    if (messageData['storagePath'] == null || (messageData['storagePath'] as String).isEmpty) {
      final fileName = messageData[DatabaseHelper.columnFileName] ?? (localPath != null ? path.basename(localPath) : '');
      messageData['storagePath'] = 'chat_media/$chatRoomID/$messageId/$fileName';
    }

    if (messageData[DatabaseHelper.columnMessageType] == 'image' && 
        messageData[DatabaseHelper.columnThumbnailLocalPath] == null && 
        localPath != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final thumbFile = File(path.join(tempDir.path, 'thumb_$messageId.jpg'));
        
        final imageBytes = await File(localPath).readAsBytes();
        final image = img.decodeImage(imageBytes);
        if (image != null) {
          final thumbnail = img.copyResize(image, width: 200);
          await thumbFile.writeAsBytes(img.encodeJpg(thumbnail, quality: 70));
          messageData[DatabaseHelper.columnThumbnailLocalPath] = await saveFilePermanently(thumbFile.path);
        }
      } catch (e) {
        log("Gukora thumbnail y'ifoto vyanse: $e");
      }
    }
    
    await DatabaseHelper.instance.saveMessage(messageData);
    _syncService.triggerSync();
  }
  
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
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
      DatabaseHelper.columnThumbnailLocalPath: thumbnailLocalPath,
    };
    
    await sendMediaMessageFromData(messageData);
  }
  
  Future<void> sendContact(
    BuildContext context, {
    required String chatRoomID,
    required String receiverID,
  }) async {
    try {
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final Contact? contact = await FlutterContacts.openExternalPick();

        if (contact != null) {
          if (contact.phones.isNotEmpty) {
            final String displayName = contact.displayName;
            final String phoneNumber = contact.phones.first.number;

            final Map<String, String> contactData = {
              'name': displayName,
              'number': phoneNumber,
            };

            final String contactJson = jsonEncode(contactData);

            await sendMediaMessage(
              chatRoomID: chatRoomID,
              receiverID: receiverID,
              messageType: 'contact',
              text: contactJson,
            );
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Contact wahisemo nta nomero ya telefone ifise.')),
              );
            }
          }
        }
      } else {
         if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ntushobora kurungika contact utaduhaye uburenganzira.')),
              );
            }
      }
    } catch (e) {
      log("CONTACT PICK ERROR: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Habaye ikosa mu guhitamo contact: $e")));
      }
    }
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
      log("Gukora thumbnail ya video vyanse: $e");
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