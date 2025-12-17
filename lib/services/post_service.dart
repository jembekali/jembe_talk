import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  // Stream yo gutega amatwi amaposita yose (nka kuri TangazaStar)
  Stream<List<Map<String, dynamic>>> getPostsStream() {
    return _firestore
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        final likedBy = List<String>.from(data['likedBy'] ?? []);
        data['isLikedByMe'] = likedBy.contains(_currentUserId);
        return data;
      }).toList();
    });
  }

  // Stream yo gutega amatwi amaposita y'umuntu umwe (kuri Profile)
  Stream<List<Map<String, dynamic>>> getPostsForUserStream(String userId) {
    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        final likedBy = List<String>.from(data['likedBy'] ?? []);
        data['isLikedByMe'] = likedBy.contains(_currentUserId);
        return data;
      }).toList();
    });
  }

  // Igikorwa cyo gukora "Like" cyangwa kuyikuraho
  Future<void> togglePostLike(String postId, bool isCurrentlyLiked) async {
    if (_currentUserId == null) return;
    try {
      await _firestore.collection('posts').doc(postId).update({
        'likes': FieldValue.increment(isCurrentlyLiked ? -1 : 1),
        'likedBy': isCurrentlyLiked
            ? FieldValue.arrayRemove([_currentUserId])
            : FieldValue.arrayUnion([_currentUserId]),
      });
    } catch (e) {
      // Ushobora gushyiramo ubutumwa bw'ikosa hano
      print("Guhindura like vyanse: $e");
    }
  }
}