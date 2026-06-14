// lib/tangaza_star/comment_screen.dart

import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/post_translations.dart';
import 'comment_bubble.dart';

class CommentScreen extends StatefulWidget {
  final Map<String, dynamic> postData;
  final ScrollController? scrollController;

  const CommentScreen({
    super.key,
    required this.postData,
    this.scrollController,
  });

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? _commentsSubscription;
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Tanga akanya gato ngo context ibe ready
    Future.delayed(Duration.zero, () {
      _listenToComments();
    });
  }

  @override
  void dispose() {
    _commentsSubscription?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _listenToComments() {
    if (!mounted) return;
    final postId =
        widget.postData[DatabaseHelper.colPostId] ?? widget.postData['id'];

    _commentsSubscription = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((querySnapshot) async {
      final userIds = querySnapshot.docs
          .map((doc) => doc.data()['userId'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();
      Map<String, dynamic> usersMap = {};

      if (userIds.isNotEmpty) {
        try {
          final usersSnapshot = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: userIds)
              .get();
          usersMap = {for (var doc in usersSnapshot.docs) doc.id: doc.data()};
        } catch (e) {
          log("Error fetching users: $e");
        }
      }

      final serverComments = querySnapshot.docs.map((doc) {
        final data = doc.data();
        final authorData = usersMap[data['userId']];
        return {
          DatabaseHelper.colCommentId: doc.id,
          DatabaseHelper.colUserName:
              authorData?['displayName'] ?? data['userName'] ?? "User",
          DatabaseHelper.colText: data['text'],
          DatabaseHelper.colAudioUrl: data['audioUrl'],
          DatabaseHelper.colLikesCount: data['likes'] ?? 0,
          DatabaseHelper.colTimestamp:
              (data['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch,
          DatabaseHelper.colUserId: data['userId'],
        };
      }).toList();

      if (mounted)
        setState(() {
          _comments = serverComments;
          _isLoading = false;
        });
    });
  }

  Future<void> _postComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty || currentUser == null) return;
    final postId =
        widget.postData[DatabaseHelper.colPostId] ?? widget.postData['id'];
    _commentController.clear();

    try {
      await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(const Uuid().v4())
          .set({
        'text': commentText,
        'userId': currentUser!.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0
      });
      await _firestore
          .collection('posts')
          .doc(postId)
          .update({'commentsCount': FieldValue.increment(1)});
    } catch (e) {
      log("Error posting: $e");
    }
  }

  void _showCommentOptions(Map<String, dynamic> commentData) {
    if (commentData[DatabaseHelper.colUserId] != currentUser?.uid) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final String l = lang.currentLanguage;

    showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E293B),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(PostTranslations.t('delete_comment_confirm', l),
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(commentData);
                  })
            ]));
  }

  void _confirmDelete(Map<String, dynamic> commentData) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final String l = lang.currentLanguage;

    showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
              title: Text(PostTranslations.t('delete_comment_title', l)),
              actions: [
                CupertinoDialogAction(
                    child: Text(PostTranslations.t('delete_comment_cancel', l)),
                    onPressed: () => Navigator.pop(context)),
                CupertinoDialogAction(
                    isDestructiveAction: true,
                    child:
                        Text(PostTranslations.t('delete_comment_confirm', l)),
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteComment(commentData[DatabaseHelper.colCommentId]);
                    }),
              ],
            ));
  }

  Future<void> _deleteComment(String commentId) async {
    final postId =
        widget.postData[DatabaseHelper.colPostId] ?? widget.postData['id'];
    await _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .delete();
    await _firestore
        .collection('posts')
        .doc(postId)
        .update({'commentsCount': FieldValue.increment(-1)});
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String l = lang.currentLanguage;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // Hitamo Izina rya Title bitandukanye n'izina rya Profile (kugira ngo bibe professional)
    String headerTitle = "Comments";
    if (l == 'ki')
      headerTitle = "Ivyiyumviro";
    else if (l == 'sw')
      headerTitle = "Maoni";
    else if (l == 'fr') headerTitle = "Commentaires";

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 5),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10))),
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text("$headerTitle (${_comments.length})",
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16))),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CupertinoActivityIndicator(color: Colors.white))
                    : _comments.isEmpty
                        ? Center(
                            child: Text(
                                PostTranslations.t('profile_no_comments', l),
                                style: const TextStyle(color: Colors.white38)))
                        : ListView.builder(
                            controller: widget.scrollController,
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, bottom: 20),
                            itemCount: _comments.length,
                            itemBuilder: (context, index) => CommentBubble(
                              userName: _comments[index]
                                  [DatabaseHelper.colUserName],
                              text: _comments[index][DatabaseHelper.colText],
                              timestamp: _comments[index]
                                  [DatabaseHelper.colTimestamp],
                              likesCount: _comments[index]
                                  [DatabaseHelper.colLikesCount],
                              isLikedByMe: false,
                              onLike: () {},
                              isMyComment: _comments[index]
                                      [DatabaseHelper.colUserId] ==
                                  currentUser?.uid,
                              onShowOptions: () =>
                                  _showCommentOptions(_comments[index]),
                            ),
                          ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    border: Border(
                        top:
                            BorderSide(color: Colors.white.withOpacity(0.05)))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white12)),
                        child: TextField(
                          controller: _commentController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                          maxLines: 4,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                              hintText:
                                  PostTranslations.t('edit_content_hint', l),
                              hintStyle: const TextStyle(
                                  color: Colors.white38, fontSize: 14),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10)),
                          onChanged: (v) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _commentController.text.trim().isNotEmpty
                          ? _postComment
                          : null,
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor:
                            _commentController.text.trim().isNotEmpty
                                ? Colors.lightGreenAccent
                                : Colors.white10,
                        child: Icon(Icons.send_rounded,
                            color: _commentController.text.trim().isNotEmpty
                                ? Colors.black
                                : Colors.white24,
                            size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
