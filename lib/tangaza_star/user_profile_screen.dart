// lib/tangaza_star/user_profile_screen.dart

import 'dart:ui';
import 'dart:io'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    setState(() { _isLoading = true; _error = ''; });
    
    if (currentUserId == null) {
      if(mounted) setState(() => _error = lang.t('profile_error_no_current_user'));
      return;
    }
    
    try {
      final userDoc = await _firestore.collection('users').doc(widget.userId)
          .get(const GetOptions(source: Source.serverAndCache)) 
          .timeout(const Duration(seconds: 10));

      if (userDoc.exists) {
        if(mounted) setState(() => _userData = userDoc.data());
      } else {
        throw lang.t('profile_error_user_not_found');
      }

      if (widget.userId != currentUserId) {
        await _fetchFriendshipStatus(currentUserId!);
      } else {
        if(mounted) setState(() => _friendshipStatus = 'self');
      }
    } catch (e) {
      if (mounted) setState(() => _error = lang.t('profile_error_loading_data'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFriendshipStatus(String currentUserId) async {
    try {
      List<String> ids = [currentUserId, widget.userId];
      ids.sort();
      _friendshipDocId = ids.join('_');
      final doc = await _firestore.collection('friendships').doc(_friendshipDocId!).get();
      if (!doc.exists) {
        if(mounted) setState(() => _friendshipStatus = 'not_friends');
      } else {
        final data = doc.data()!;
        if(mounted) {
          if (data['status'] == 'pending') {
            setState(() => _friendshipStatus = data['requestedBy'] == currentUserId ? 'pending_sent' : 'pending_received');
          } else if (data['status'] == 'accepted') {
            setState(() => _friendshipStatus = 'friends');
          } else {
            setState(() => _friendshipStatus = 'not_friends');
          }
        }
      }
    } catch (e) { debugPrint("Friendship fetch error: $e"); }
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
      if(mounted) setState(() => _friendshipStatus = 'pending_sent');
    } catch(e) {} finally { if(mounted) setState(() => _isProcessingRequest = false); }
  }
  
  Future<void> _acceptFriendRequest() async {
    if (_friendshipDocId == null) return;
    setState(() => _isProcessingRequest = true);
    try {
      await _firestore.collection('friendships').doc(_friendshipDocId!).update({'status': 'accepted'});
      if(mounted) setState(() => _friendshipStatus = 'friends');
    } catch(e) {} finally { if(mounted) setState(() => _isProcessingRequest = false); }
  }

  Future<void> _declineOrCancelRequest() async {
    if (_friendshipDocId == null) return;
    setState(() => _isProcessingRequest = true);
    try {
      await _firestore.collection('friendships').doc(_friendshipDocId!).delete();
      if(mounted) setState(() => _friendshipStatus = 'not_friends');
    } catch(e) {} finally { if(mounted) setState(() => _isProcessingRequest = false); }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(_userData?['displayName'] ?? lang.t('profile_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.blueGrey[900],
        centerTitle: true,
      ),
      backgroundColor: Colors.blueGrey[800],
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator(color: Colors.white))
          : _error.isNotEmpty
              ? _buildErrorView(lang)
              : _buildProfileContent(),
      floatingActionButton: (currentUserId == null || isKeyboardOpen) ? null : _buildFabStream(),
    );
  }

  Widget _buildErrorView(LanguageProvider lang) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.signal_wifi_off, size: 60, color: Colors.white54),
      const SizedBox(height: 16),
      Text(_error, style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: _loadProfileData, child: Text(lang.t('profile_button_retry')))
    ]));
  }

  Widget _buildFabStream() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(currentUserId).snapshots(),
      builder: (context, snapshot) {
        final photoUrl = (snapshot.data?.data() as Map?)?['photoUrl'];
        return GestureDetector(
          onTap: () async {
            setState(() => _isScreenActive = false);
            await Navigator.of(context).push(CustomPageRoute(child: const CreatePostScreen()));
            if (mounted) setState(() => _isScreenActive = true);
          },
          child: Stack(alignment: Alignment.center, children: [
            CircleAvatar(radius: 28, backgroundColor: Colors.blueGrey[700], backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) : null, child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white) : null),
            Positioned(right: -2, bottom: -2, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.lightGreen, shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 18)))
          ])
        );
      },
    );
  }

  Widget _buildProfileContent() {
    return Column(children: [
      _buildProfileHeader(),
      const Divider(height: 1, color: Colors.white10),
      Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _postService.getPostsForUserStream(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CupertinoActivityIndicator(color: Colors.white));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return Center(child: Text(Provider.of<LanguageProvider>(context).t('profile_no_posts'), style: const TextStyle(color: Colors.white70)));
          
          final userPosts = snapshot.data!;
          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(top: 12), 
            itemCount: userPosts.length, 
            itemBuilder: (context, index) => ProfilePostCard(
              key: ValueKey(userPosts[index]['id']), 
              postData: userPosts[index], 
              userData: _userData,
              isParentActive: _isScreenActive,
            )
          );
        }
      ))
    ]);
  }
  
  Widget _buildProfileHeader() {
    final lang = Provider.of<LanguageProvider>(context);
    final photoUrl = _userData?['photoUrl'] as String?;
    final heroTag = 'user-profile-photo-${widget.userId}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      color: Colors.blueGrey[900], 
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () { if (photoUrl != null) Navigator.push(context, MaterialPageRoute(builder: (context) => FullPhotoScreen(imageUrl: photoUrl, heroTag: heroTag, isLocalFile: false))); }, 
            child: Hero(tag: heroTag, child: CircleAvatar(radius: 40, backgroundColor: Colors.blueGrey.shade700, backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null, child: photoUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white) : null))
          ),
          const SizedBox(width: 20),
          Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(stream: _postService.getPostsForUserStream(widget.userId), builder: (context, snapshot) {
            int postCount = snapshot.hasData ? snapshot.data!.length : 0;
            int totalLikes = snapshot.hasData ? snapshot.data!.fold(0, (sum, post) => sum + (post['likes'] as int? ?? 0)) : 0;
            return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _buildStatDetail(lang.t('profile_posts_stat'), postCount.toString()), 
              _buildStatDetail(lang.t('profile_likes_stat'), totalLikes.toString())
            ]);
          })),
        ]),
        const SizedBox(height: 15),
        Text(_userData?['displayName'] ?? "User", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        if(_userData?['about'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_userData!['about'], style: const TextStyle(color: Colors.white70, fontSize: 14))),
        const SizedBox(height: 15),
        _buildFriendshipButton(),
      ]),
    );
  }
  
  Widget _buildStatDetail(String label, String value) {
    return Column(children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))]);
  }

  Widget _buildFriendshipButton() {
    final lang = Provider.of<LanguageProvider>(context);
    if (_isProcessingRequest || _friendshipStatus == 'loading') return const SizedBox(height: 35, child: Center(child: CupertinoActivityIndicator(radius: 10)));
    if (_friendshipStatus == 'self') return const SizedBox.shrink();
    
    switch (_friendshipStatus) {
      case 'not_friends': 
        return SizedBox(height: 42, width: double.infinity, child: ElevatedButton(onPressed: _sendFriendRequest, style: ElevatedButton.styleFrom(backgroundColor: Colors.lightGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(lang.t('profile_friend_request_button'), style: const TextStyle(fontWeight: FontWeight.bold))));
      
      case 'pending_sent': 
        return SizedBox(height: 42, width: double.infinity, child: OutlinedButton(onPressed: _declineOrCancelRequest, style: OutlinedButton.styleFrom(foregroundColor: Colors.amber, side: const BorderSide(color: Colors.amber), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(lang.t('profile_request_sent_button'))));
      
      case 'pending_received': 
        return Row(children: [Expanded(child: SizedBox(height: 42, child: ElevatedButton(onPressed: _acceptFriendRequest, child: Text(lang.t('profile_accept_button'))))), const SizedBox(width: 10), Expanded(child: SizedBox(height: 42, child: OutlinedButton(onPressed: _declineOrCancelRequest, child: Text(lang.t('profile_decline_button')))))]);
      
      case 'friends': 
        return SizedBox(height: 42, width: double.infinity, child: ElevatedButton(onPressed: () async {
          setState(() => _isScreenActive = false);
          await Navigator.push(context, CustomPageRoute(child: ChatScreenWrapper(receiverID: widget.userId, receiverEmail: _userData?['displayName'])));
          if (mounted) setState(() => _isScreenActive = true);
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(lang.t('profile_send_message_button'), style: const TextStyle(fontWeight: FontWeight.bold))));
      
      default: return const SizedBox.shrink();
    }
  }
}

class ProfilePostCard extends StatefulWidget {
  final Map<String, dynamic> postData;
  final Map<String, dynamic>? userData;
  final bool isParentActive;

  const ProfilePostCard({super.key, required this.postData, this.userData, required this.isParentActive});
  @override
  State<ProfilePostCard> createState() => _ProfilePostCardState();
}

class _ProfilePostCardState extends State<ProfilePostCard> with TickerProviderStateMixin, WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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
    if (oldWidget.isParentActive && !widget.isParentActive) {
      _pauseVideo();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pauseVideo();
    }
  }

  void _pauseVideo() {
    if (_controller != null && _controller!.value.isPlaying) {
      _controller!.pause();
      WakelockPlus.disable();
      if(mounted) setState(() {});
    }
  }

  void _initializeVideo() {
    if (_userStartedPlay) return;
    
    final String? rawUrl = widget.postData['videoUrl'];
    if (rawUrl == null) return;

    setState(() { _userStartedPlay = true; });

    final String finalUrl = rawUrl.contains('r2') || rawUrl.contains('cloudflarestorage') 
        ? "${R2Service.workerUrl}${Uri.parse(rawUrl).path}?auth=${R2Service.workerSecretKey}" 
        : rawUrl;

    _controller = CachedVideoPlayerPlusController.networkUrl(
      Uri.parse(finalUrl), 
      httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey}
    );

    _controller!.initialize().then((_) {
      if(mounted) {
        setState(() => _isInitialized = true);
        _controller!.play();
        _controller!.setLooping(true);
        WakelockPlus.enable();
      }
    });
  }

  void _togglePlayback() {
    if (!_userStartedPlay) {
      _initializeVideo();
      return;
    }
    if (_controller == null || !_isInitialized) return;

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

  String? _getWorkerUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    if (!rawUrl.contains('cloudflarestorage') && !rawUrl.contains('r2')) return rawUrl;
    try { 
      return "${R2Service.workerUrl}${Uri.parse(rawUrl).path}?auth=${R2Service.workerSecretKey}"; 
    } catch (e) { return rawUrl; }
  }

  Future<void> _toggleLike() async {
    if (currentUserId == null) return;
    final postId = widget.postData['id'];
    final bool isLiked = (widget.postData['likedBy'] as List?)?.contains(currentUserId) ?? false;
    if(mounted) setState(() {
      if (isLiked) { (widget.postData['likedBy'] as List).remove(currentUserId); widget.postData['likes'] = (widget.postData['likes'] ?? 1) - 1; }
      else { widget.postData['likedBy'] = [...(widget.postData['likedBy'] ?? []), currentUserId]; widget.postData['likes'] = (widget.postData['likes'] ?? 0) + 1; }
    });
    await _firestore.collection('posts').doc(postId).update({'likes': FieldValue.increment(isLiked ? -1 : 1), 'likedBy': isLiked ? FieldValue.arrayRemove([currentUserId]) : FieldValue.arrayUnion([currentUserId])});
  }

  Future<void> _toggleCommentsOverlay() async {
    if (!mounted) return;
    final bool opening = !_showCommentsOverlay;
    setState(() { _showCommentsOverlay = opening; if (opening) _isLoadingComments = true; });
    if (opening) {
      try {
        final querySnapshot = await _firestore.collection('posts').doc(widget.postData['id']).collection('comments').orderBy('timestamp', descending: true).get();
        final serverComments = querySnapshot.docs.map((doc) => {'commentId': doc.id, ...doc.data()}).toList();
        if(mounted) setState(() { _comments = serverComments; _isLoadingComments = false; });
      } catch (e) { if(mounted) setState(() => _isLoadingComments = false); }
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if(text.isEmpty || currentUserId == null) return;
    final postId = widget.postData['id'];
    final commentId = const Uuid().v4();
    
    _commentController.clear();
    try {
      await _firestore.collection('posts').doc(postId).collection('comments').doc(commentId).set({
        'text': text, 
        'userId': currentUserId, 
        'timestamp': FieldValue.serverTimestamp()
      });
      await _firestore.collection('posts').doc(postId).update({'commentsCount': FieldValue.increment(1)});
      
      if(mounted) {
        setState(() {
          _comments.insert(0, {'commentId': commentId, 'userId': currentUserId, 'text': text, 'timestamp': Timestamp.now()});
          widget.postData['commentsCount'] = (widget.postData['commentsCount'] ?? 0) + 1;
        });
      }
    } catch (e) {}
  }

  // =========================================================
  // FIX: DELETE COMMENT METHOD
  // =========================================================
  Future<void> _deleteComment(String commentId) async {
    final bool? confirm = await showCupertinoDialog<bool>(
      context: context, 
      builder: (context) => CupertinoAlertDialog(
        title: const Text("Delete Comment?"), 
        actions: [
          CupertinoDialogAction(child: const Text("Cancel"), onPressed: () => Navigator.pop(context, false)),
          CupertinoDialogAction(isDestructiveAction: true, child: const Text("Delete"), onPressed: () => Navigator.pop(context, true)),
        ]
      )
    );

    if (confirm != true) return;

    try {
      final postId = widget.postData['id'];
      await _firestore.collection('posts').doc(postId).collection('comments').doc(commentId).delete();
      await _firestore.collection('posts').doc(postId).update({'commentsCount': FieldValue.increment(-1)});
      
      if (mounted) {
        setState(() {
          _comments.removeWhere((c) => (c['commentId'] ?? c['id']) == commentId);
          widget.postData['commentsCount'] = (widget.postData['commentsCount'] ?? 1) - 1;
        });
      }
    } catch (e) {
      debugPrint("Error deleting comment: $e");
    }
  }

  void _showFullNewsModal(BuildContext context, String title, String body, String langCode) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => Container(height: MediaQuery.of(context).size.height * 0.75, decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))), padding: const EdgeInsets.all(25), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))), const SizedBox(height: 25), if (title.isNotEmpty) Text(title, style: const TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 15), const Divider(color: Colors.white10), const SizedBox(height: 15), Expanded(child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: Text(body, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6))))])));
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String langCode = lang.currentLanguage;
    final String title = widget.postData['title'] ?? "";
    final String content = widget.postData['content'] ?? "";
    
    final String? thumbUrl = _getWorkerUrl(widget.postData['imageUrl'] ?? widget.postData['thumbnailUrl']);
    final String? videoUrl = widget.postData['videoUrl'];
    
    final bool isLikedByMe = (widget.postData['likedBy'] as List?)?.contains(currentUserId) ?? false;
    final heroTag = 'profile-post-${widget.postData['id']}';
    
    String line1 = title; String line2 = "";
    if (title.length > 15) { line1 = title.substring(0, 15); line2 = title.substring(15); }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), 
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20.0), border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green.withOpacity(0.2))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 12, backgroundImage: widget.userData?['photoUrl'] != null ? CachedNetworkImageProvider(widget.userData!['photoUrl']) : null, child: widget.userData?['photoUrl'] == null ? const Icon(Icons.person, size: 12, color: Colors.white) : null),
            const SizedBox(width: 8),
            Text(widget.userData?['displayName'] ?? "User", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
            const SizedBox(width: 6),
            Text(widget.postData['timestamp'] != null ? DateFormat('MMM d').format((widget.postData['timestamp'] as Timestamp).toDate()) : "", style: const TextStyle(color: Colors.white54, fontSize: 10))
          ]),
        ),

        if (title.isNotEmpty) 
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: Text.rich(maxLines: 2, overflow: TextOverflow.ellipsis, TextSpan(children: [
                  TextSpan(text: "$line1${line2.isNotEmpty ? '\n' : ''}$line2", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
                  if (content.isNotEmpty) WidgetSpan(alignment: PlaceholderAlignment.middle, child: GestureDetector(onTap: () => _showFullNewsModal(context, title, content, langCode),
                    child: Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.green.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
                      child: Text(PostTranslations.t('read_more', langCode), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))))),
              ])),
            ),
          ),
        
        const SizedBox(height: 12),
        
        ClipRRect(
          borderRadius: BorderRadius.circular(15.0), 
          child: Stack(alignment: Alignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 500), 
              child: (videoUrl == null && thumbUrl != null) 
                ? GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FullPhotoScreen(imageUrl: thumbUrl, heroTag: heroTag, isLocalFile: false))), child: Hero(tag: heroTag, child: CachedNetworkImage(imageUrl: thumbUrl, httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey}, fit: BoxFit.contain, width: double.infinity, placeholder: (c, u) => const Center(child: CupertinoActivityIndicator())))) 
                : GestureDetector(
                    onTap: _togglePlayback,
                    child: Stack(alignment: Alignment.center, children: [
                        if (!_userStartedPlay && thumbUrl != null)
                          CachedNetworkImage(imageUrl: thumbUrl, httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey}, fit: BoxFit.cover, width: double.infinity),
                        
                        if (_userStartedPlay)
                          _isInitialized && _controller != null
                            ? AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: CachedVideoPlayerPlus(_controller!))
                            : const SizedBox(height: 200, child: Center(child: CupertinoActivityIndicator(color: Colors.white))),

                        if (!_userStartedPlay || (_isInitialized && !_controller!.value.isPlaying))
                          const CircleAvatar(backgroundColor: Colors.black45, radius: 30, child: Icon(Icons.play_arrow, color: Colors.white, size: 40)),
                      ]),
                  )
            ),
            if (_showCommentsOverlay) _buildCommentsOverlay(lang)
          ])
        ),

        const Divider(height: 25, color: Colors.white12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _actionButton(icon: isLikedByMe ? Icons.favorite : Icons.favorite_border, label: "${widget.postData['likes'] ?? 0}", color: isLikedByMe ? Colors.redAccent : Colors.white70, onPressed: _toggleLike),
          _actionButton(icon: Icons.chat_bubble_outline_rounded, label: "${widget.postData['commentsCount'] ?? 0}", onPressed: _toggleCommentsOverlay),
          _actionButton(icon: Icons.ios_share, label: PostTranslations.t('forward_button', langCode), onPressed: () => ShareService.instance.sharePost(postId: widget.postData['id'], content: widget.postData['content'])),
        ])
      ]),
    );
  }

  Widget _buildCommentsOverlay(LanguageProvider lang) {
    return Container(height: 350, decoration: BoxDecoration(color: Colors.black.withOpacity(0.95)), child: Column(children: [
      Align(alignment: Alignment.topRight, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _toggleCommentsOverlay)),
      Expanded(child: _isLoadingComments ? const Center(child: CupertinoActivityIndicator()) : _comments.isEmpty ? Center(child: Text(lang.t('profile_no_comments') ?? "Nta bitekerezo.", style: const TextStyle(color: Colors.white54))) : ListView.builder(itemCount: _comments.length, itemBuilder: (context, index) {
        final comment = _comments[index];
        final commenterId = comment['userId'];
        final commentId = comment['commentId'] ?? comment['id'];
        
        return StreamBuilder<DocumentSnapshot>(
          stream: _firestore.collection('users').doc(commenterId).snapshots(),
          builder: (context, userSnap) {
            String liveDisplayName = "User";
            if (userSnap.hasData && userSnap.data!.exists) {
              final uData = userSnap.data!.data() as Map<String, dynamic>;
              liveDisplayName = uData['displayName'] ?? "User";
            }
            
            return CommentBubble(
              userName: liveDisplayName, 
              text: comment['text'], 
              isMyComment: commenterId == currentUserId, 
              timestamp: 0, 
              likesCount: 0, 
              isLikedByMe: false, 
              onLike: () {}, 
              // HANO NIHO HAKOSOWE: Iyo akanda kuri comment ye, imuha uburyo bwo kuyisiba
              onShowOptions: (commenterId == currentUserId) ? () => _deleteComment(commentId) : () {},
            );
          },
        );
      })),
      Padding(padding: const EdgeInsets.all(8.0), child: Row(children: [Expanded(child: TextField(controller: _commentController, style: const TextStyle(color: Colors.white, fontSize: 14), decoration: const InputDecoration(hintText: "Comment...", hintStyle: TextStyle(color: Colors.white54), border: InputBorder.none))), IconButton(icon: const Icon(Icons.send, color: Colors.blueAccent), onPressed: _postComment)]))
    ]));
  }

  Widget _actionButton({required IconData icon, required String label, required VoidCallback onPressed, Color? color}) {
    return TextButton.icon(onPressed: onPressed, icon: Icon(icon, size: 20, color: color ?? Colors.white70), label: Text(label, style: TextStyle(color: color ?? Colors.white70, fontSize: 13)));
  }
}