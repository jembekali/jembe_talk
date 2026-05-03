// lib/services/firebase_service.dart (VERSION IYIHUTISHIJE - OPTIMIZED)

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'dart:developer';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // SPEED ENGINE: Ibi bituma iyo App yashatse URL imwe, idasubira kuri Storage 
  // kuyishaka bwa kabiri kuko iyibika mu mutwe (Memory Cache).
  static final Map<String, String> _urlCache = {};

  FirebaseService();

  Future<void> saveUserFcmToken() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    try {
      // Ibi tubikore mu mudehezo (Background) kugira ngo bitahanga UI
      FirebaseMessaging.instance.requestPermission();
      
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        // Koresha update aho gukoresha set(merge:true) niba user asanzwe ahari kuko yihuta
        await _firestore.collection('users').doc(currentUser.uid).update(
          {'fcmToken': token}
        ).catchError((e) {
           // Niba user atari yarigeze abaho, hano niho dukoresha set
           return _firestore.collection('users').doc(currentUser.uid).set(
             {'fcmToken': token}, SetOptions(merge: true)
           );
        });
        log("FCM Token saved.");
      }
    } catch (e) {
      log("Error saving FCM token: $e");
    }
  }

  // IYIHUTISHIJE: Iyi function ubu ifite 'Cache'
  Future<String> getFreshDownloadUrl(String storagePath) async {
    if (_urlCache.containsKey(storagePath)) {
      return _urlCache[storagePath]!;
    }

    try {
      final ref = _storage.ref().child(storagePath);
      final downloadUrl = await ref.getDownloadURL();
      _urlCache[storagePath] = downloadUrl; // Bika mu mutwe
      return downloadUrl;
    } catch (e) {
      log("Error getFreshDownloadUrl: $e");
      throw Exception("URL not found");
    }
  }
  
  Future<String> uploadChatMedia({
    required String localFilePath, 
    required String storagePath,
    Function(double progress)? onProgress,
  }) async {
    File file = File(localFilePath);
    if (!file.existsSync()) throw Exception("File not found");
    
    try {
      Reference ref = _storage.ref().child(storagePath);
      UploadTask uploadTask = ref.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });

      TaskSnapshot snapshot = await uploadTask;
      String url = await snapshot.ref.getDownloadURL();
      _urlCache[storagePath] = url; // Bika mu mutwe kugira ngo App itayishaka bwa kabiri
      return url;
      
    } catch (e) {
      log("UploadChatMedia Error: $e");
      throw Exception("Upload failed");
    }
  }

  // Upload y'ama-posts yagizwe WebP muri Cloud Functions
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
      log("Error uploading media: $e");
      return null;
    }
  }

  Future<void> uploadPost(Map<String, dynamic> postData) async {
    try {
      final String postId = postData[DatabaseHelper.colPostId];
      Map<String, dynamic> remoteData = Map.from(postData);
      
      remoteData.remove(DatabaseHelper.colSyncStatus);
      remoteData.remove(DatabaseHelper.colIsLikedByMe);
      
      // Serialization: Koresha int nka timestamp (iyihutisha Firestore indexing)
      remoteData[DatabaseHelper.columnTimestamp] = Timestamp.fromMillisecondsSinceEpoch(postData[DatabaseHelper.columnTimestamp]);

      await _firestore.collection('posts').doc(postId).set(remoteData);
    } catch (e) {
      log("Error uploading post: $e");
      throw Exception('Post upload failed.');
    }
  }
}