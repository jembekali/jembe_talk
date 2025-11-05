// lib/tangaza_star/my_post_view_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'post_card.dart'; // Ubu iyi dosiye ibayeho!

class MyPostViewScreen extends StatelessWidget {
  final DocumentSnapshot post;

  const MyPostViewScreen({super.key, required this.post});

  Future<void> _deletePost(BuildContext context) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gusiba Post'),
        content: const Text('Urifuza gusiba iyi post koko?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('OYA')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('EGO, SIBA'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('tangaza_posts').doc(post.id).delete();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _editPost(BuildContext context) {
    // Iyi code izakoreshwa hanyuma
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Igice co guhindura post kizoza hanyuma.'))
    );
  }

  @override
  Widget build(BuildContext context) {
    final postData = post.data() as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ijambo Ryanje'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.blue),
            onPressed: () => _editPost(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _deletePost(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: PostCard(
          postId: post.id,
          userName: postData['userName'] ?? 'Ata zina',
          userImageUrl: postData['userImageUrl'] ?? '', 
          postText: postData['text'] ?? '', 
          imageUrl: postData['imageUrl'] as String?,
          likes: postData['likes'] ?? 0,
          likedBy: List.from(postData['likedBy'] ?? []),
          comments: postData['comments'] ?? 0,
          views: postData['views'] ?? 0,
        ),
      ),
    );
  }
}