import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // 🔥 RTDB Engine
import 'package:intl/intl.dart';
import 'package:jembe_talk/chat_screen.dart';
import 'package:jembe_talk/full_photo_screen.dart';
import 'package:jembe_talk/services/post_service.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:jembe_talk/tangaza_star/comment_bubble.dart';
import 'package:jembe_talk/tangaza_star/create_post_screen.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/services/share_service.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/post_translations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final PostService _postService = PostService();

  String _friendshipStatus = 'loading';
  String? _friendshipDocId;
  bool _isProcessingRequest = false;
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  String _error = '';
  bool _isScreenActive = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = '';
    });
    if (currentUserId == null) return;

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(widget.userId)
          .get(const GetOptions(source: Source.serverAndCache));
      if (userDoc.exists) {
        if (mounted) setState(() => _userData = userDoc.data());
      }
      if (widget.userId != currentUserId) {
        await _fetchFriendshipStatus(currentUserId!);
      } else {
        if (mounted) setState(() => _friendshipStatus = 'self');
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = lang.t('profile_error_loading_data'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFriendshipStatus(String currentUserId) async {
    try {
      List<String> ids = [currentUserId, widget.userId];
      ids.sort();
      _friendshipDocId = ids.join('_');
      final doc = await _firestore
          .collection('friendships')
          .doc(_friendshipDocId!)
          .get();
      if (mounted) {
        if (!doc.exists) {
          setState(() => _friendshipStatus = 'not_friends');
        } else {
          final data = doc.data()!;
          if (data['status'] == 'pending') {
            setState(() => _friendshipStatus =
                data['requestedBy'] == currentUserId
                    ? 'pending_sent'
                    : 'pending_received');
          } else if (data['status'] == 'accepted') {
            setState(() => _friendshipStatus = 'friends');
          }
        }
      }
    } catch (e) {}
  }

  Future<void> _sendFriendRequest() async {
    if (currentUserId == null || _friendshipDocId == null) return;
    setState(() => _isProcessingRequest = true);
    try {
      await _firestore.collection('friendships').doc(_friendshipDocId!).set({
        'users': [currentUserId, widget.userId],
        'requestedBy': currentUserId,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp()
      });
      if (mounted) setState(() => _friendshipStatus = 'pending_sent');
    } finally {
      if (mounted) setState(() => _isProcessingRequest = false);
    }
  }

  Future<void> _acceptFriendRequest() async {
    if (_friendshipDocId == null) return;
    setState(() => _isProcessingRequest = true);
    try {
      await _firestore
          .collection('friendships')
          .doc(_friendshipDocId!)
          .update({'status': 'accepted'});
      if (mounted) setState(() => _friendshipStatus = 'friends');
    } finally {
      if (mounted) setState(() => _isProcessingRequest = false);
    }
  }

  Future<void> _declineOrCancelRequest() async {
    if (_friendshipDocId == null) return;
    setState(() => _isProcessingRequest = true);
    try {
      await _firestore
          .collection('friendships')
          .doc(_friendshipDocId!)
          .delete();
      if (mounted) setState(() => _friendshipStatus = 'not_friends');
    } finally {
      if (mounted) setState(() => _isProcessingRequest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        title: Text(_userData?['displayName'] ?? lang.t('profile_title'),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(
              child: CupertinoActivityIndicator(color: Colors.greenAccent))
          : _buildProfileContent(),
      floatingActionButton:
          (currentUserId == null || isKeyboardOpen) ? null : _buildFabStream(),
    );
  }

  Widget _buildFabStream() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(currentUserId).snapshots(),
      builder: (context, snapshot) {
        final photoUrl = (snapshot.data?.data() as Map?)?['photoUrl'];
        return GestureDetector(
            onTap: () async {
              setState(() => _isScreenActive = false);
              await Navigator.of(context)
                  .push(CustomPageRoute(child: const CreatePostScreen()));
              if (mounted) setState(() => _isScreenActive = true);
            },
            child: Stack(alignment: Alignment.center, children: [
              CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.blueGrey[700],
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                      ? CachedNetworkImageProvider(photoUrl)
                      : null,
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white)
                      : null),
              Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.lightGreen, shape: BoxShape.circle),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 18)))
            ]));
      },
    );
  }

  Widget _buildProfileContent() {
    return Column(children: [
      _buildProfileHeader(),
      const Divider(height: 1, color: Colors.white10),
      Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _postService.getPostsForUserStream(widget.userId),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty)
                  return Center(
                      child: Text(
                          Provider.of<LanguageProvider>(context)
                              .t('profile_no_posts'),
                          style: const TextStyle(color: Colors.white70)));
                final userPosts = snapshot.data!;
                return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(top: 12),
                    itemCount: userPosts.length,
                    itemBuilder: (context, index) => ProfilePostCard(
                        key: ValueKey(userPosts[index]['id']),
                        postData: userPosts[index],
                        userData: _userData,
                        isParentActive: _isScreenActive));
              }))
    ]);
  }

  Widget _buildProfileHeader() {
    final lang = Provider.of<LanguageProvider>(context);
    final photoUrl = _userData?['photoUrl'] as String?;
    final heroTag = 'user-profile-photo-${widget.userId}';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      color: Colors.black,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
              onTap: () {
                if (photoUrl != null)
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => FullPhotoScreen(
                              imageUrl: photoUrl,
                              heroTag: heroTag,
                              isLocalFile: false)));
              },
              child: Hero(
                  tag: heroTag,
                  child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey[900],
                      backgroundImage: photoUrl != null
                          ? CachedNetworkImageProvider(photoUrl)
                          : null,
                      child: photoUrl == null
                          ? const Icon(Icons.person,
                              size: 40, color: Colors.white)
                          : null))),
          const SizedBox(width: 20),
          Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _postService.getPostsForUserStream(widget.userId),
                  builder: (context, postSnap) {
                    int postCount =
                        postSnap.hasData ? postSnap.data!.length : 0;
                    return StreamBuilder<DatabaseEvent>(
                      stream: _rtdb
                          .ref("user_stats/${widget.userId}/totalLikes")
                          .onValue,
                      builder: (context, likeSnap) {
                        int totalLikes = 0;
                        if (likeSnap.hasData &&
                            likeSnap.data!.snapshot.value != null) {
                          totalLikes = int.tryParse(
                                  likeSnap.data!.snapshot.value.toString()) ??
                              0;
                        }
                        return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatDetail(lang.t('profile_posts_stat'),
                                  postCount.toString()),
                              _buildStatDetail(lang.t('profile_likes_stat'),
                                  totalLikes.toString())
                            ]);
                      },
                    );
                  })),
        ]),
        const SizedBox(height: 15),
        Text(_userData?['displayName'] ?? "User",
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        if (_userData?['about'] != null)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_userData!['about'],
                  style: const TextStyle(color: Colors.white70, fontSize: 14))),
        const SizedBox(height: 15),
        _buildFriendshipButton(),
      ]),
    );
  }

  Widget _buildStatDetail(String label, String value) {
    return Column(children: [
      Text(value,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))
    ]);
  }

  Widget _buildFriendshipButton() {
    final lang = Provider.of<LanguageProvider>(context);
    if (_isProcessingRequest || _friendshipStatus == 'loading')
      return const SizedBox(
          height: 35,
          child: Center(child: CupertinoActivityIndicator(radius: 10)));
    if (_friendshipStatus == 'self') return const SizedBox.shrink();
    switch (_friendshipStatus) {
      case 'not_friends':
        return SizedBox(
            height: 42,
            width: double.infinity,
            child: ElevatedButton(
                onPressed: _sendFriendRequest,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black),
                child: Text(lang.t('profile_friend_request_button'))));
      case 'pending_sent':
        return SizedBox(
            height: 42,
            width: double.infinity,
            child: OutlinedButton(
                onPressed: _declineOrCancelRequest,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.amber),
                child: Text(lang.t('profile_request_sent_button'))));
      case 'pending_received':
        return Row(children: [
          Expanded(
              child: ElevatedButton(
                  onPressed: _acceptFriendRequest,
                  child: Text(lang.t('profile_accept_button')))),
          const SizedBox(width: 10),
          Expanded(
              child: OutlinedButton(
                  onPressed: _declineOrCancelRequest,
                  child: Text(lang.t('profile_decline_button'))))
        ]);
      case 'friends':
        return SizedBox(
            height: 42,
            width: double.infinity,
            child: ElevatedButton(
                onPressed: () async {
                  setState(() => _isScreenActive = false);
                  await Navigator.push(
                      context,
                      CustomPageRoute(
                          child: ChatScreenWrapper(
                              receiverID: widget.userId,
                              receiverEmail: _userData?['displayName'])));
                  if (mounted) setState(() => _isScreenActive = true);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                child: Text(lang.t('profile_send_message_button'))));
      default:
        return const SizedBox.shrink();
    }
  }
}

class ProfilePostCard extends StatefulWidget {
  final Map<String, dynamic> postData;
  final Map<String, dynamic>? userData;
  final bool isParentActive;
  const ProfilePostCard(
      {super.key,
      required this.postData,
      this.userData,
      required this.isParentActive});
  @override
  State<ProfilePostCard> createState() => _ProfilePostCardState();
}

class _ProfilePostCardState extends State<ProfilePostCard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
  bool _showCommentsOverlay = false;
  bool _isLoadingComments = false;
  List<Map<String, dynamic>> _comments = [];
  final TextEditingController _commentController = TextEditingController();
  CachedVideoPlayerPlusController? _controller;
  bool _isInitialized = false;
  bool _userStartedPlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ProfilePostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isParentActive && !widget.isParentActive) _pauseVideo();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pauseVideo();
  }

  void _pauseVideo() {
    if (_controller != null && _controller!.value.isPlaying) {
      _controller!.pause();
      WakelockPlus.disable();
      setState(() {});
    }
  }

  void _initializeVideo() {
    if (_userStartedPlay) return;
    final String? rawUrl = widget.postData['videoUrl'];
    if (rawUrl == null) return;
    setState(() => _userStartedPlay = true);
    final String finalUrl = rawUrl.contains('auth=')
        ? rawUrl
        : "${R2Service.workerUrl}${Uri.parse(rawUrl).path}?auth=${R2Service.workerSecretKey}";
    _controller = CachedVideoPlayerPlusController.networkUrl(
        Uri.parse(finalUrl),
        httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey},
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _controller!.initialize().then((_) {
      if (mounted) {
        setState(() => _isInitialized = true);
        _controller!.play();
        _controller!.setLooping(true);
        WakelockPlus.enable();
      }
    });
  }

  void _togglePlayback() {
    if (_controller == null || !_isInitialized) {
      _initializeVideo();
      return;
    }
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        WakelockPlus.disable();
      } else {
        _controller!.play();
        WakelockPlus.enable();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commentController.dispose();
    _controller?.pause();
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _toggleLike(bool currentlyLiked) async {
    if (currentUserId == null) return;
    final postId = widget.postData['id'];
    final String authorId = widget.postData['userId'] ?? "";
    final int diff = currentlyLiked ? -1 : 1;
    try {
      _rtdb.ref("counters/$postId/likes").set(ServerValue.increment(diff));
      if (authorId.isNotEmpty) {
        _rtdb
            .ref("user_stats/$authorId/totalLikes")
            .set(ServerValue.increment(diff));
      }
      if (currentlyLiked) {
        _rtdb.ref("user_likes/$currentUserId/$postId").remove();
      } else {
        _rtdb.ref("user_likes/$currentUserId/$postId").set(true);
      }
    } catch (e) {}
  }

  // 🔥 FIKISIYE: READ MORE MODAL
  void _showFullContent(String title, String content) {
    _pauseVideo(); // Pauxa video mbere yo gufungura
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(25),
              decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(35))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Container(
                            width: 45,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 25),
                    if (title.isNotEmpty)
                      Text(title,
                          style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 15),
                    Expanded(
                        child: SingleChildScrollView(
                            child: Text(content.isEmpty ? title : content,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1.6)))),
                  ]),
            ));
  }

  Future<void> _toggleCommentsOverlay() async {
    final bool opening = !_showCommentsOverlay;
    setState(() {
      _showCommentsOverlay = opening;
      if (opening) _isLoadingComments = true;
    });
    if (opening) {
      try {
        final querySnapshot = await _firestore
            .collection('posts')
            .doc(widget.postData['id'])
            .collection('comments')
            .orderBy('timestamp', descending: true)
            .get();
        final serverComments = querySnapshot.docs
            .map((doc) => {'commentId': doc.id, ...doc.data()})
            .toList();
        if (mounted)
          setState(() {
            _comments = serverComments;
            _isLoadingComments = false;
          });
      } catch (e) {
        if (mounted) setState(() => _isLoadingComments = false);
      }
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || currentUserId == null) return;
    final postId = widget.postData['id'];
    final commentId = const Uuid().v4();
    _commentController.clear();
    try {
      await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .set({
        'text': text,
        'userId': currentUserId,
        'timestamp': FieldValue.serverTimestamp()
      });
      await _firestore
          .collection('posts')
          .doc(postId)
          .update({'commentsCount': FieldValue.increment(1)});
      if (mounted)
        setState(() {
          _comments.insert(0, {
            'commentId': commentId,
            'userId': currentUserId,
            'text': text,
            'timestamp': Timestamp.now()
          });
          widget.postData['commentsCount'] =
              (widget.postData['commentsCount'] ?? 0) + 1;
        });
    } catch (e) {}
  }

  Future<void> _deleteComment(String commentId) async {
    final postId = widget.postData['id'];
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
    if (mounted)
      setState(() {
        _comments.removeWhere((c) => (c['commentId'] ?? c['id']) == commentId);
        widget.postData['commentsCount'] =
            (widget.postData['commentsCount'] ?? 1) - 1;
      });
  }

  @override
  Widget build(BuildContext context) {
    final langCode = Provider.of<LanguageProvider>(context).currentLanguage;
    final String title = widget.postData['title'] ?? "";
    final String content =
        widget.postData['content'] ?? widget.postData['text'] ?? "";
    final String? videoUrl = widget.postData['videoUrl'];
    final bool isVideo = videoUrl != null && videoUrl.isNotEmpty;
    final String? thumbUrl =
        widget.postData['imageUrl'] ?? widget.postData['thumbnailUrl'];
    final heroTag = 'profile-post-${widget.postData['id']}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeaderRow(),

        // Post Title and Read More
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              GestureDetector(
                onTap: () => _showFullContent(title, content),
                child: Text(PostTranslations.t('read_more', langCode),
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
          ),

        const SizedBox(height: 12),

        // Media Section
        ClipRRect(
          borderRadius: BorderRadius.circular(15.0),
          child: GestureDetector(
            onTap: isVideo
                ? _togglePlayback
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (c) => FullPhotoScreen(
                            imageUrl: thumbUrl!,
                            heroTag: heroTag,
                            isLocalFile: false))),
            child: Stack(alignment: Alignment.center, children: [
              if (thumbUrl != null)
                Hero(
                    tag: heroTag,
                    child: CachedNetworkImage(
                        imageUrl: thumbUrl,
                        fit: BoxFit.cover,
                        width: double.infinity)),
              if (isVideo && _userStartedPlay && _isInitialized)
                AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CachedVideoPlayerPlus(_controller!)),
              if (isVideo &&
                  (!_userStartedPlay ||
                      (_isInitialized && !_controller!.value.isPlaying)))
                const CircleAvatar(
                    backgroundColor: Colors.black45,
                    radius: 25,
                    child: Icon(Icons.play_arrow, color: Colors.white)),
            ]),
          ),
        ),

        const Divider(height: 25, color: Colors.white12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          StreamBuilder<DatabaseEvent>(
            stream: _rtdb
                .ref("user_likes/$currentUserId/${widget.postData['id']}")
                .onValue,
            builder: (context, statusSnap) {
              final bool isLiked =
                  statusSnap.hasData && statusSnap.data!.snapshot.value == true;
              return StreamBuilder<DatabaseEvent>(
                stream: _rtdb
                    .ref("counters/${widget.postData['id']}/likes")
                    .onValue,
                builder: (context, countSnap) {
                  int likes = 0;
                  if (countSnap.hasData &&
                      countSnap.data!.snapshot.value != null) {
                    likes = int.tryParse(
                            countSnap.data!.snapshot.value.toString()) ??
                        0;
                  }
                  return _actionButton(
                      icon: isLiked ? Icons.favorite : Icons.favorite_border,
                      label: "$likes",
                      color: isLiked ? Colors.redAccent : Colors.white70,
                      onPressed: () => _toggleLike(isLiked));
                },
              );
            },
          ),
          _actionButton(
              icon: Icons.chat_bubble_outline_rounded,
              label: "${widget.postData['commentsCount'] ?? 0}",
              onPressed: _toggleCommentsOverlay),
          _actionButton(
              icon: Icons.ios_share,
              label: PostTranslations.t('forward_button', langCode),
              onPressed: () => ShareService.instance.sharePost(
                  postId: widget.postData['id'],
                  content: widget.postData['content'])),
        ]),
        if (_showCommentsOverlay) _buildCommentsOverlay(),
      ]),
    );
  }

  Widget _buildHeaderRow() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(
          radius: 12,
          backgroundImage: widget.userData?['photoUrl'] != null
              ? CachedNetworkImageProvider(widget.userData!['photoUrl'])
              : null,
          child: widget.userData?['photoUrl'] == null
              ? const Icon(Icons.person, size: 12)
              : null),
      const SizedBox(width: 8),
      Text(widget.userData?['displayName'] ?? "User",
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
      const SizedBox(width: 6),
      Text(
          widget.postData['timestamp'] != null
              ? DateFormat('MMM d')
                  .format((widget.postData['timestamp'] as Timestamp).toDate())
              : "",
          style: const TextStyle(color: Colors.white54, fontSize: 10))
    ]);
  }

  Widget _buildCommentsOverlay() {
    return Container(
        height: 250,
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
            color: Colors.black45, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Expanded(
              child: _isLoadingComments
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView.builder(
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        return ListTile(
                            title: Text(comment['text'],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                            trailing: (comment['userId'] == currentUserId)
                                ? IconButton(
                                    icon: const Icon(Icons.delete, size: 16),
                                    onPressed: () =>
                                        _deleteComment(comment['commentId']))
                                : null);
                      })),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _commentController,
                    style: const TextStyle(color: Colors.white))),
            IconButton(icon: const Icon(Icons.send), onPressed: _postComment)
          ])
        ]));
  }

  Widget _actionButton(
      {required IconData icon,
      required String label,
      required VoidCallback onPressed,
      Color? color}) {
    return TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: color ?? Colors.white70),
        label: Text(label,
            style: TextStyle(color: color ?? Colors.white70, fontSize: 13)));
  }
}
