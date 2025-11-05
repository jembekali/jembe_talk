// lib/tangaza_star/star_post_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:jembe_talk/services/database_helper.dart';

class StarPostDetailScreen extends StatelessWidget {
  final Map<String, dynamic> postData;

  const StarPostDetailScreen({super.key, required this.postData});

  @override
  Widget build(BuildContext context) {
    final String username = postData[DatabaseHelper.colUserName] ?? 'Unknown';
    final String? userImageUrl = postData[DatabaseHelper.colUserImageUrl];
    final String? postImageUrl = postData[DatabaseHelper.colImageUrl];
    final String? postVideoUrl = postData[DatabaseHelper.colVideoUrl];
    final String? postText = postData[DatabaseHelper.colText];

    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: userImageUrl != null ? NetworkImage(userImageUrl) : null,
              child: userImageUrl == null ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 10),
            Text(username),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Twerekana ifoto canke video (ubu ni placeholder gusa)
              if (postImageUrl != null)
                Expanded(
                  child: Center(
                    child: Image.network(
                      postImageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        return progress == null ? child : const Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                )
              else if (postVideoUrl != null)
                const Expanded(
                  child: Center(
                    child: Icon(Icons.videocam, size: 100, color: Colors.white),
                    // Hano hazoza Video Player yawe
                  ),
                ),
              
              const SizedBox(height: 20),

              // Twerekana amajambo
              if (postText != null && postText.isNotEmpty)
                Text(
                  postText,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}