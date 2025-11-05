import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:social_media_recorder/screen/social_media_recorder.dart';
import 'comment_bubble.dart';

class CommentScreen extends StatefulWidget {
  final Map<String, dynamic> postData;
  const CommentScreen({super.key, required this.postData});

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  final User? currentUser = FirebaseAuth.instance.currentUser;
  late Future<List<Map<String, dynamic>>> _commentsFuture;

  VideoPlayerController? _videoController;
  Future<void>? _initializeVideoPlayerFuture;

  @override
  void initState() {
    super.initState();
    _refreshComments();
    _initializePostPreview();
  }

  void _initializePostPreview() {
    final videoUrl = widget.postData[DatabaseHelper.colVideoUrl] as String?;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      _videoController = VideoPlayerController.file(File(videoUrl));
      _initializeVideoPlayerFuture = _videoController?.initialize();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _refreshComments() {
    if (mounted) {
      setState(() {
        _commentsFuture = DatabaseHelper.instance.getCommentsForPost(widget.postData[DatabaseHelper.colPostId]);
      });
    }
  }

  Future<void> _postComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty || currentUser == null) return;
    _commentController.clear();
    FocusScope.of(context).unfocus();

    final newCommentData = {
      DatabaseHelper.colCommentId: const Uuid().v4(),
      DatabaseHelper.colPostId: widget.postData[DatabaseHelper.colPostId],
      DatabaseHelper.colUserId: currentUser!.uid,
      DatabaseHelper.colUserName: currentUser!.displayName ?? 'Ata zina',
      DatabaseHelper.colText: commentText,
      DatabaseHelper.colAudioUrl: null,
      DatabaseHelper.colTimestamp: DateTime.now().millisecondsSinceEpoch,
      DatabaseHelper.colSyncStatus: 'pending',
    };
    await DatabaseHelper.instance.saveComment(newCommentData);
    await DatabaseHelper.instance.incrementPostCommentCount(widget.postData[DatabaseHelper.colPostId]);
    _refreshComments();
  }

  Future<void> _postVoiceComment(File soundFile) async {
    if (currentUser == null) return;
    FocusScope.of(context).unfocus();

    final newCommentData = {
      DatabaseHelper.colCommentId: const Uuid().v4(),
      DatabaseHelper.colPostId: widget.postData[DatabaseHelper.colPostId],
      DatabaseHelper.colUserId: currentUser!.uid,
      DatabaseHelper.colUserName: currentUser!.displayName ?? 'Ata zina',
      DatabaseHelper.colText: null,
      DatabaseHelper.colAudioUrl: soundFile.path,
      DatabaseHelper.colTimestamp: DateTime.now().millisecondsSinceEpoch,
      DatabaseHelper.colSyncStatus: 'pending',
    };
    await DatabaseHelper.instance.saveComment(newCommentData);
    await DatabaseHelper.instance.incrementPostCommentCount(widget.postData[DatabaseHelper.colPostId]);
    _refreshComments();
  }
  
  Future<void> _toggleCommentLike(String commentId) async {
    if (currentUser == null) return;
    await DatabaseHelper.instance.toggleCommentLike(commentId, currentUser!.uid);
    _refreshComments();
  }

  Future<void> _deleteComment(String commentId) async {
    await DatabaseHelper.instance.deleteComment(commentId);
    await DatabaseHelper.instance.decrementPostCommentCount(widget.postData[DatabaseHelper.colPostId]);
    _refreshComments();
  }

  Future<void> _editComment(String commentId, String newText) async {
    await DatabaseHelper.instance.updateComment(commentId, newText);
    _refreshComments();
  }

  Future<void> _showEditCommentDialog(String commentId, String currentText) async {
    final TextEditingController editController = TextEditingController(text: currentText);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Gukosora Iciyumviro'),
          content: TextField(
            controller: editController,
            autofocus: true,
            maxLines: null,
            decoration: const InputDecoration(hintText: "Kosora iciyumviro cawe"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Guhagarika'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Kubika'),
              onPressed: () {
                Navigator.of(context).pop();
                _editComment(commentId, editController.text.trim());
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteConfirmation(String commentId) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Gufuta Iciyumviro"),
          content: const Text("Vyukuri urashaka gufuta?"),
          actions: <Widget>[
            TextButton(
              child: const Text("Oya"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text("Ego, futa", style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteComment(commentId);
              },
            ),
          ],
        );
      },
    );
  }

  void _showCommentOptions(Map<String, dynamic> commentData) {
    final commentId = commentData[DatabaseHelper.colCommentId];
    final isMyComment = commentData[DatabaseHelper.colUserId] == currentUser?.uid;
    final isTextComment = commentData[DatabaseHelper.colAudioUrl] == null;

    if (!isMyComment) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: <Widget>[
            if (isTextComment)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Gukosora'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditCommentDialog(commentId, commentData[DatabaseHelper.colText] ?? '');
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Gufuta', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(commentId);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 19, 4, 4),
      appBar: AppBar(
        title: const Text("Ivyiyumviro"),
        backgroundColor: const Color.fromARGB(255, 11, 52, 189),
        foregroundColor: Colors.black,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildPostPreview(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _commentsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text("Nta ciyumviro kiratangwa.", style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                            const SizedBox(height: 8),
                             Text("Ba uwambere!", style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                          ],
                        ),
                      );
                    }
                    
                    final comments = snapshot.data!;
                    return ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final commentData = comments[index];
                        final likedByRaw = commentData[DatabaseHelper.colLikedBy] as String?;
                        final List<dynamic> likedByList = (likedByRaw != null && likedByRaw.isNotEmpty) ? jsonDecode(likedByRaw) : [];

                        return CommentBubble(
                          userName: commentData[DatabaseHelper.colUserName] ?? 'Ata zina',
                          text: commentData[DatabaseHelper.colText],
                          audioUrl: commentData[DatabaseHelper.colAudioUrl],
                          timestamp: commentData[DatabaseHelper.colTimestamp],
                          likesCount: commentData[DatabaseHelper.colLikesCount] ?? 0,
                          isLikedByMe: likedByList.contains(currentUser?.uid),
                          onLike: () => _toggleCommentLike(commentData[DatabaseHelper.colCommentId]),
                          isMyComment: commentData[DatabaseHelper.colUserId] == currentUser?.uid,
                          onShowOptions: () => _showCommentOptions(commentData),
                          syncStatus: commentData[DatabaseHelper.colSyncStatus],
                        );
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 34, 41, 105),
                    boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -5))]),
                child: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration( color: const Color.fromARGB(255, 69, 71, 153), borderRadius: BorderRadius.circular(24)),
                          child: TextField(
                            controller: _commentController,
                            onChanged: (text) => setState(() {}),
                            decoration: const InputDecoration(
                                hintText: "Andika iciyumviro...",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric( horizontal: 16, vertical: 10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_commentController.text.isNotEmpty)
                        IconButton(
                            icon: const Icon(Icons.send, color: Colors.teal),
                            onPressed: _postComment),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
                  // swipe iburyo -> delete action
                  // aha ushobora guhamagara function ya delete last recording cyangwa logic wifuza
                  debugPrint("Swipe iburyo kuri mic = delete action");
                }
              },
              child: SocialMediaRecorder(
                sendRequestFunction: (File soundFile, String duration) {
                  _postVoiceComment(soundFile);
                },
                recordIcon: const Icon(Icons.mic, color: Colors.teal),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostPreview() {
     final imageUrl = widget.postData[DatabaseHelper.colImageUrl] as String?;
    final videoUrl = widget.postData[DatabaseHelper.colVideoUrl] as String?;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.25,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            Image.file(File(imageUrl), fit: BoxFit.cover)
          else if (videoUrl != null && _videoController != null)
            FutureBuilder(
              future: _initializeVideoPlayerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && _videoController!.value.isInitialized) {
                  return FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  );
                }
                return Container(color: Colors.black);
              },
            )
          else
            Container(color: Colors.grey.shade800),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.5, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}