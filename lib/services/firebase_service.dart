// lib/services/firebase_service.dart (VERSION NSHYA YUZUYE 100%)

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <<< Twongeyemo iyi import
import 'package:firebase_messaging/firebase_messaging.dart'; // <<< Twongeyemo iyi import
import 'package:firebase_storage/firebase_storage.dart';
import 'package:jembe_talk/services/database_helper.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // <<< Twongeyemo iyi variable

  // =========================================================================
  // ----> IYI NI YO FUNCTION NSHYA KANDI Y'INGENZI <----
  // Iyi function izajya ifata FCM token ya telefoni ikayibika kuri user muri Firestore
  // =========================================================================
  Future<void> saveUserFcmToken() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    try {
      // Saba uruhushya rwo kohereza notifications (ni byiza kubikora hano)
      await FirebaseMessaging.instance.requestPermission();
      
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(currentUser.uid).set(
          {'fcmToken': token},
          SetOptions(merge: true), // 'merge: true' ni ngombwa kugira ngo idasiba andi makuru ya user
        );
        print("FCM Token saved successfully for user ${currentUser.uid}");
      }
    } catch (e) {
      print("Error saving FCM token: $e");
    }
  }

  Future<String> getFreshDownloadUrl(String storagePath) async {
    print(">>> [DEBUG - getFreshDownloadUrl] Turimo gusaba URL ku nzira: '$storagePath'");
    try {
      final ref = _storage.ref().child(storagePath);
      final downloadUrl = await ref.getDownloadURL();
      print(">>> [DEBUG - getFreshDownloadUrl] URL YABONETSE: $downloadUrl");
      return downloadUrl;
    } catch (e) {
      print("!!!!!! [DEBUG - getFreshDownloadUrl] IKOSA RIKOMEYE: Ntibishobotse kubona URL ku nzira '$storagePath'. Impamvu: $e");
      throw Exception("Ntibishobotse kubona URL nshya y'ifayiri.");
    }
  }
  
  Future<String> uploadChatMedia({
    required String localFilePath, 
    required String storagePath,
    Function(double progress)? onProgress,
  }) async {
    if (!File(localFilePath).existsSync()) {
      throw Exception("Iyi dosiye ntibonetse: $localFilePath");
    }
    
    File file = File(localFilePath);
    try {
      print(">>> [DEBUG - uploadChatMedia] Turimo kohereza idosiye ku nzira twakiriye: '$storagePath'");

      Reference ref = _storage.ref().child(storagePath);
      UploadTask uploadTask = ref.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });

      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
      
    } catch (e) {
      print("!!!!!! [DEBUG - uploadChatMedia] Ikibazo gikomeye mu kohereza dosiye: $e");
      throw Exception("Kohereza dosiye byaranze.");
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
      print("Ikibazo mu kurungika ifoto/video kuri Firebase: $e");
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
      print("Ikibazo mu kurungika post kuri Firestore: $e");
      throw Exception('Kwohereza post kuri Firestore byaranze.');
    }
  }
}