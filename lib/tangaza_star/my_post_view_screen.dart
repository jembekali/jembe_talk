// lib/tangaza_star/my_post_view_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/tangaza_star/comment_screen.dart';
import 'post_card.dart';

class MyPostViewScreen extends StatefulWidget {
  final DocumentSnapshot post;
  const MyPostViewScreen({super.key, required this.post});

  @override
  State<MyPostViewScreen> createState() => _MyPostViewScreenState();
}

class _MyPostViewScreenState extends State<MyPostViewScreen> {
  final ValueNotifier<bool> _isScreenActive = ValueNotifier(true);
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _isScreenActive.dispose();
    super.dispose();
  }

  Future<void> _deletePost() async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gufuta Post'),
        content: const Text('Urifuza gufuta iyi post koko?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('OYA')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('EGO, FUTA'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('tangaza_posts').doc(widget.post.id).delete();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.post.data() as Map<String, dynamic>;
    
    // Tugira data Map ihuye n'ibyo DatabaseHelper (PostCard) yiteze
    final Map<String, dynamic> postMap = {
      DatabaseHelper.colPostId: widget.post.id,
      DatabaseHelper.colUserName: data['userName'] ?? 'Star',
      DatabaseHelper.colUserImageUrl: data['userImageUrl'],
      DatabaseHelper.colText: data['text'] ?? '',
      DatabaseHelper.colTitle: data['title'] ?? '',
      DatabaseHelper.colImageUrl: data['imageUrl'],
      DatabaseHelper.colVideoUrl: data['videoUrl'],
      DatabaseHelper.colLikes: data['likes'] ?? 0,
      DatabaseHelper.colCommentsCount: data['comments'] ?? 0,
      DatabaseHelper.colViews: data['views'] ?? 0,
      DatabaseHelper.colCategory: data['category'] ?? 'General',
      DatabaseHelper.colIsLikedByMe: (data['likedBy'] as List? ?? []).contains(_currentUserId) ? 1 : 0,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ijambo Ryanje'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _deletePost,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: PostCard(
            post: postMap,
            currentUserId: _currentUserId,
            isScreenActive: _isScreenActive,
            // Twandika utubuto (Functions) kuko ari "Required" muri PostCard
            onLike: (p) async {
              // Hano ushobora gushyiramo logic yo gu-liking niba ubishaka
            },
            onOpenComments: (p) {
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => CommentScreen(postData: p),
              ));
            },
            onShowOptions: (p) {
              // Show options niba ari ngombwa
            },
            onShowFullNews: (ctx, title, body, lang) {
              // Show full news logic
            },
            onShareStart: () {},
            onShareEnd: (success) {},
          ),
        ),
      ),
    );
  }
}