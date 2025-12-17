// lib/services/firebase_service.dart (VERSION ISUBIYE UKO YARI KANDI IKORA)

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'dart:developer'; // << Twongeyemwo iyi kugira dukoreshe log()

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // << Constructor yagarutse uko yari isanzwe >>
  FirebaseService();

  Future<void> saveUserFcmToken() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    try {
      await FirebaseMessaging.instance.requestPermission();
      
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(currentUser.uid).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
        log("FCM Token saved successfully for user ${currentUser.uid}");
      }
    } catch (e) {
      log("Error saving FCM token: $e");
    }
  }

  Future<String> getFreshDownloadUrl(String storagePath) async {
    log(">>> [DEBUG - getFreshDownloadUrl] Requesting URL for path: '$storagePath'");
    try {
      final ref = _storage.ref().child(storagePath);
      final downloadUrl = await ref.getDownloadURL();
      log(">>> [DEBUG - getFreshDownloadUrl] URL RECEIVED: $downloadUrl");
      return downloadUrl;
    } catch (e) {
      log("!!!!!! [DEBUG - getFreshDownloadUrl] FATAL ERROR: Could not get URL for '$storagePath'. Reason: $e");
      throw Exception("Could not get a fresh URL for the file."); // Ubutumwa bworoshe
    }
  }
  
  Future<String> uploadChatMedia({
    required String localFilePath, 
    required String storagePath,
    Function(double progress)? onProgress,
  }) async {
    if (!File(localFilePath).existsSync()) {
      throw Exception("This file was not found: $localFilePath");
    }
    
    File file = File(localFilePath);
    try {
      log(">>> [DEBUG - uploadChatMedia] Uploading file to provided path: '$storagePath'");

      Reference ref = _storage.ref().child(storagePath);
      UploadTask uploadTask = ref.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });

      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
      
    } catch (e) {
      log("!!!!!! [DEBUG - uploadChatMedia] Critical error during file upload: $e");
      throw Exception("File upload failed."); // Ubutumwa bworoshe
    }
  }

  Future<String?> uploadMedia(String? localFilePath, String postId) async {
    if (localFilePath == null || !File(localFilePath).existsSync()) return null;
    
    File file = File(localFilePath);
    try {
      String fileName = 'posts/$postId/${DateTime.now().millisecondsSinceEpoch}';
      Reference ref = _storage.ref().child(fileName);
      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      log("Error uploading media for post: $e");
      return null;
    }
  }

  Future<void> uploadPost(Map<String, dynamic> postData) async {
    try {
      final String postId = postData[DatabaseHelper.colPostId];
      Map<String, dynamic> remotePostData = Map.from(postData);
      
      remotePostData.remove(DatabaseHelper.colSyncStatus);
      remotePostData.remove(DatabaseHelper.colIsLikedByMe);
      
      remotePostData[DatabaseHelper.columnTimestamp] = Timestamp.fromMillisecondsSinceEpoch(postData[DatabaseHelper.columnTimestamp]);

      await _firestore.collection('posts').doc(postId).set(remotePostData);
    } catch (e) {
      log("Error uploading post: $e");
      throw Exception('Post upload failed.'); // Ubutumwa bworoshe
    }
  }
}