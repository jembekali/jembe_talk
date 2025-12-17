// lib/tangaza_star/comment_screen.dart (VERSION IKOSOYE)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
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
  late int _commentCount;

  @override
  void initState() {
    super.initState();
    _commentCount = widget.postData[DatabaseHelper.colCommentsCount] ?? 0;
    _listenToComments();
    _commentController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _commentsSubscription?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _listenToComments() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (!mounted) return;
    setState(() { _isLoading = true; });

    final postId = widget.postData[DatabaseHelper.colPostId];
    final commentsStream = _firestore.collection('posts').doc(postId).collection('comments').orderBy('timestamp', descending: true).snapshots();

    _commentsSubscription = commentsStream.listen((querySnapshot) async {
      final userIds = querySnapshot.docs.map((doc) => doc.data()['userId'] as String?).where((id) => id != null).toSet().toList();
        
      Map<String, dynamic> usersMap = {};
      if (userIds.isNotEmpty) {
        final usersSnapshot = await _firestore.collection('users').where(FieldPath.documentId, whereIn: userIds).get();
        usersMap = {for (var doc in usersSnapshot.docs) doc.id: doc.data()};
      }

      final serverComments = querySnapshot.docs.map((doc) {
        final data = doc.data();
        final authorId = data['userId'];
        final authorData = usersMap[authorId];

        return {
          DatabaseHelper.colCommentId: doc.id,
          DatabaseHelper.colPostId: postId,
          DatabaseHelper.colUserId: data['userId'],
          DatabaseHelper.colUserName: authorData?['displayName'] ?? data['userName'] ?? lang.t('no_author_name'),
          DatabaseHelper.colText: data['text'],
          DatabaseHelper.colAudioUrl: data['audioUrl'],
          DatabaseHelper.colLikesCount: data['likes'] ?? 0,
          DatabaseHelper.colLikedBy: '[]',
          DatabaseHelper.colTimestamp: (data['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
          DatabaseHelper.colSyncStatus: 'synced',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _comments = serverComments;
          _isLoading = false;
        });
      }
    }, onError: (error) {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    });
  }

  Future<void> _postComment() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty || currentUser == null) return;

    final postId = widget.postData[DatabaseHelper.colPostId];
    final commentId = const Uuid().v4();

    final serverCommentData = {
      'text': commentText,
      'userId': currentUser!.uid,
      'userName': currentUser!.displayName ?? lang.t('no_author_name'),
      'userImageUrl': currentUser!.photoURL,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': 0,
    };

    _commentController.clear();
    FocusScope.of(context).unfocus();

    try {
      final postRef = _firestore.collection('posts').doc(postId);
      final commentRef = postRef.collection('comments').doc(commentId);

      final batch = _firestore.batch();
      batch.set(commentRef, serverCommentData);
      batch.update(postRef, {'commentsCount': FieldValue.increment(1)});
      
      await batch.commit();
      _signalInterest(postId);
      
    } catch (e) {
      // Handle error, maybe show a snackbar
    }
  }

  void _signalInterest(String postId) {
    if (currentUser == null) return;
    _firestore.collection('user_likes').add({'userId': currentUser!.uid, 'postId': postId});
  }

  Future<void> _toggleCommentLike(String commentId) async {
    // Logic for liking a comment on the server
  }

  Future<void> _deleteComment(String commentId) async {
    final postId = widget.postData[DatabaseHelper.colPostId];

    try {
      final postRef = _firestore.collection('posts').doc(postId);
      final commentRef = postRef.collection('comments').doc(commentId);

      final batch = _firestore.batch();
      batch.delete(commentRef);
      batch.update(postRef, {'commentsCount': FieldValue.increment(-1)});
      await batch.commit();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _editComment(String commentId, String newText) async {
    try {
      final postId = widget.postData[DatabaseHelper.colPostId];
      await _firestore.collection('posts').doc(postId).collection('comments').doc(commentId).update({'text': newText});
    } catch(e) {
      // Handle error
    }
  }

  Future<void> _showEditCommentDialog(String commentId, String currentText) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final TextEditingController editController = TextEditingController(text: currentText);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(lang.t('edit_comment_title')),
          content: TextField(controller: editController, autofocus: true, maxLines: null, decoration: InputDecoration(hintText: lang.t('edit_comment_hint'))),
          actions: <Widget>[
            TextButton(child: Text(lang.t('dialog_cancel')), onPressed: () => Navigator.of(context).pop()),
            TextButton(child: Text(lang.t('btn_save')), onPressed: () { Navigator.of(context).pop(); _editComment(commentId, editController.text.trim()); }),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteConfirmation(String commentId) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(lang.t('delete_comment_title')), content: Text(lang.t('delete_comment_confirm')),
          actions: <Widget>[
            TextButton(child: Text(lang.t('dialog_no')), onPressed: () => Navigator.of(context).pop()),
            TextButton(child: Text(lang.t('dialog_yes_delete'), style: const TextStyle(color: Colors.red)), onPressed: () { Navigator.of(context).pop(); _deleteComment(commentId); }),
          ],
        );
      },
    );
  }

  void _showCommentOptions(Map<String, dynamic> commentData) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
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
              ListTile(leading: const Icon(Icons.edit_outlined), title: Text(lang.t('edit_option')), onTap: () { Navigator.pop(context); _showEditCommentDialog(commentId, commentData[DatabaseHelper.colText] ?? ''); }),
            ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: Text(lang.t('delete_option'), style: const TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _showDeleteConfirmation(commentId); }),
          ],
        );
      },
    );
  }

  void _popWithResult() {
    Navigator.of(context).pop(_commentCount);
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final bool canSend = _commentController.text.trim().isNotEmpty;
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _popWithResult();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text("${lang.t('comments_title')} (${_comments.length})"),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _popWithResult,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: Colors.white.withOpacity(0.2),
              height: 1.0,
            ),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            children: [
              Expanded(
                child: isKeyboardVisible
                    ? const SizedBox.shrink()
                    : ClipRRect(
                        child: _isLoading 
                          ? const Center(child: CircularProgressIndicator())
                          : _comments.isEmpty
                              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(lang.t('no_comments_yet'), style: TextStyle(fontSize: 18, color: Colors.grey[200])),
                                  const SizedBox(height: 8),
                                  Text(lang.t('be_the_first'), style: TextStyle(fontSize: 16, color: Colors.grey[300])),
                                ]))
                              : ListView.builder(
                                  controller: widget.scrollController,
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
                                  itemCount: _comments.length,
                                  itemBuilder: (context, index) {
                                    final commentData = _comments[index];
                                    final likedByRaw = commentData[DatabaseHelper.colLikedBy] as String?;
                                    final List<dynamic> likedByList = (likedByRaw != null && likedByRaw.isNotEmpty) ? jsonDecode(likedByRaw) : [];
                                    return CommentBubble(
                                      userName: commentData[DatabaseHelper.colUserName] ?? lang.t('no_author_name'),
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
                                ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                ),
                child: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.2))
                          ),
                          child: TextField(
                            controller: _commentController,
                            style: const TextStyle(color: Colors.white),
                            textCapitalization: TextCapitalization.sentences,
                            autocorrect: true,
                            keyboardType: TextInputType.multiline,
                            maxLines: null,
                            decoration: InputDecoration(hintText: lang.t('comment_placeholder'), hintStyle: const TextStyle(color: Colors.white70), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric( horizontal: 16, vertical: 10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        color: canSend ? Colors.lightGreenAccent : Colors.grey,
                        onPressed: canSend ? _postComment : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}