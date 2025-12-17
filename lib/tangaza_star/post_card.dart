// lib/tangaza_star/post_card.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jembe_talk/tangaza_star/comment_screen.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jembe_talk/services/database_helper.dart'; // <<< IMPINDUKA: NONGEREYEHO UYU MURONGO

class PostCard extends StatefulWidget {
  final String postId;
  final String userName;
  final String userImageUrl;
  final String postText;
  final String? imageUrl; 
  final int likes;
  final List<dynamic> likedBy;
  final int comments;
  final int views;

  const PostCard({
    super.key,
    required this.postId,
    required this.userName,
    required this.userImageUrl,
    required this.postText,
    this.imageUrl, 
    required this.likes,
    required this.likedBy,
    required this.comments,
    required this.views,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _isLiked;
  late int _likeCount;
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.likedBy.contains(currentUserId);
    _likeCount = widget.likes;
  }

  void _toggleLike() async {
    if (currentUserId == null) return;
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _likeCount++;
      } else {
        _likeCount--;
      }
    });
    final postRef = FirebaseFirestore.instance.collection('tangaza_posts').doc(widget.postId);
    if (_isLiked) {
      await postRef.update({'likedBy': FieldValue.arrayUnion([currentUserId]), 'likes': FieldValue.increment(1)});
    } else {
      await postRef.update({'likedBy': FieldValue.arrayRemove([currentUserId]), 'likes': FieldValue.increment(-1)});
    }
  }

  // >>>>> IMPINDUKA NYAMUKURU IRI HANO <<<<<
  void _openComments() {
    // Turema agasanduku k'amakuru (Map) CommentScreen ikeneye
    final postDataForComment = {
      DatabaseHelper.colPostId: widget.postId,
      DatabaseHelper.colImageUrl: widget.imageUrl,
      // videoUrl ntiri muri PostCard, rero CommentScreen izabona null, kandi irabizi kubyitwaramo
      DatabaseHelper.colVideoUrl: null, 
    };

    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CommentScreen(postData: postDataForComment),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      elevation: 2.0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: widget.userImageUrl.isNotEmpty ? CachedNetworkImageProvider(widget.userImageUrl) : null,
                  child: widget.userImageUrl.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                ),
                const SizedBox(width: 10),
                Text(widget.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Text(widget.postText, style: const TextStyle(fontSize: 15)),
          ),
          
          if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => Container(
                  height: 200,
                  color: Colors.grey[300],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(4.0, 0, 12.0, 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, color: _isLiked ? Colors.red : Colors.grey, size: 22),
                      onPressed: _toggleLike,
                    ),
                    Text(_likeCount.toString()),
                  ],
                ),
                InkWell(
                  onTap: _openComments,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.comment_outlined, size: 20, color: Colors.grey),
                        const SizedBox(width: 5),
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('tangaza_posts').doc(widget.postId).snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return Text(widget.comments.toString());
                            final data = snapshot.data!.data() as Map<String, dynamic>;
                            return Text((data['comments'] ?? 0).toString());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_outlined, size: 20, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text('${widget.views.toString()} Views'),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}