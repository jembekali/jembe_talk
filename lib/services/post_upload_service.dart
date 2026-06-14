import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:jembe_talk/services/database_helper.dart';

class PostUploadService {
  static final PostUploadService instance = PostUploadService._();
  PostUploadService._();

  final _firestore = FirebaseFirestore.instance;
  final _rtdb = FirebaseDatabase.instance;
  final R2Service _r2Service = R2Service();

  Future<void> uploadPost({
    required String postId,
    required String title,
    required String content,
    required String uid,
    required File fileToUpload,
    required String type,
    required String category,
    String? localThumb,
  }) async {
    // 1. Upload File (Video/Image) kuri R2
    final String downloadUrl = await _r2Service.uploadFile(
      fileToUpload, 
      'posts/$uid/$postId.${type == 'image' ? 'jpg' : 'mp4'}', 
      type == 'image' ? 'image/jpeg' : 'video/mp4'
    );

    // 2. Upload Thumbnail niba ihari
    String? cloudThumbUrl;
    if (localThumb != null) {
      cloudThumbUrl = await _r2Service.uploadFile(File(localThumb), 'thumbnails/$uid/$postId.jpg', 'image/jpeg');
    }

    // 3. Initialize RTDB Counters (Likes/Views) - Ibi ni byo bituma App yihuta
    await _rtdb.ref("counters/$postId").set({ 'likes': 0, 'views': 0 });

    // 4. Save mu Firestore
    final userSnap = await _firestore.collection('users').doc(uid).get();
    final userData = userSnap.data();

    await _firestore.collection('posts').doc(postId).set({
      'id': postId, 'title': title, 'content': content, 'userId': uid,
      'authorName': userData?['displayName'] ?? "Star",
      'authorPhotoUrl': userData?['photoUrl'],
      'timestamp': FieldValue.serverTimestamp(),
      'imageUrl': type == 'image' ? downloadUrl : null,
      'videoUrl': type == 'video' ? downloadUrl : null,
      'thumbnailUrl': cloudThumbUrl,
      'likes': 0, 'commentsCount': 0, 'views': 0, 'likedBy': [],
      'category': category, 'isStar': false
    });
  }
}