// lib/tangaza_star/user_profile_screen.dart (VERSION YUZUYE NEZA KANDI ISUKUYE)

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
import 'package:jembe_talk/tangaza_star/comment_bubble.dart';
import 'package:jembe_talk/tangaza_star/create_post_screen.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    // Kurikirana: Duhamagara LanguageProvider hano kugira n'amakosa ahinduke
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (!mounted) return;
    setState(() { _isLoading = true; _error = ''; });
    
    if (currentUserId == null) {
      setState(() => _error = lang.t('profile_error_no_current_user'));
      return;
    }
    
    if (widget.userId == currentUserId) {
      setState(() { _friendshipStatus = 'self'; });
    }
    
    try {
      final userDoc = await _firestore.collection('users').doc(widget.userId).get().timeout(const Duration(seconds: 10));
      
      if (userDoc.exists) {
        if(mounted) {
          setState(() {
             _userData = userDoc.data();
          });
        }
      } else {
        throw lang.t('profile_error_user_not_found');
      }

      if (widget.userId != currentUserId) {
        await _fetchFriendshipStatus(currentUserId!);
      }
    } catch (e) {
      String friendlyMessage = lang.t('profile_error_loading_data');
      String errorString = e.toString().toLowerCase();
      
      if (errorString.contains('unavailable') || 
          errorString.contains('network') || 
          errorString.contains('offline') ||
          errorString.contains('timeout')) {
        friendlyMessage = lang.t('profile_error_no_internet');
      }
      
      if (mounted) setState(() => _error = friendlyMessage);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFriendshipStatus(String currentUserId) async {
    try {
      List<String> ids = [currentUserId, widget.userId];
      ids.sort();
      _friendshipDocId = ids.join('_');
      final doc = await _firestore.collection('friendships').doc(_friendshipDocId).get();
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
    } catch (e) {
      debugPrint("Friendship status fetch error: $e");
    }
  }
  
  Future<void> _sendFriendRequest() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (currentUserId == null || _friendshipDocId == null) return;
    setState(() => _isProcessingRequest = true);
    try {
      await _firestore.collection('friendships').doc(_friendshipDocId).set({'users': [currentUserId, widget.userId], 'requestedBy': currentUserId, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp()});
      if(mounted) setState(() => _friendshipStatus = 'pending_sent');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('profile_friend_request_sent_snackbar')} ${_userData?['displayName'] ?? ''}!"), backgroundColor: Colors.green));
      }
    } catch(e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('profile_generic_error_snackbar')), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isProcessingRequest = false);
    }
  }
  
  Future<void> _acceptFriendRequest() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_friendshipDocId == null) return;
    setState(() => _isProcessingRequest = true);
    try {
      await _firestore.collection('friendships').doc(_friendshipDocId).update({'status': 'accepted'});
      if(mounted) setState(() => _friendshipStatus = 'friends');
    } catch(e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('profile_generic_error_snackbar')), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isProcessingRequest = false);
    }
  }
  
  Future<void> _declineOrCancelRequest() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_friendshipDocId == null) return;
    setState(() => _isProcessingRequest = true);
    try {
      await _firestore.collection('friendships').doc(_friendshipDocId).delete();
      if(mounted) setState(() => _friendshipStatus = 'not_friends');
    } catch(e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('profile_generic_error_snackbar')), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isProcessingRequest = false);
    }
  }
  
  Future<void> _handleFabClick() async {
    await Navigator.of(context).push(CustomPageRoute(child: const CreatePostScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text(_userData?['displayName'] ?? lang.t('profile_title')), backgroundColor: Colors.blueGrey[900]),
      backgroundColor: Colors.blueGrey[800],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.signal_wifi_off, size: 60, color: Colors.white54),
                        const SizedBox(height: 16),
                        Text(
                          _error, 
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 16)
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadProfileData,
                          icon: const Icon(Icons.refresh),
                          label: Text(lang.t('profile_button_retry')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white
                          ),
                        )
                      ],
                    ),
                  ),
                )
              : _userData == null
                  ? Center(child: Text(lang.t('profile_error_user_not_found'), style: const TextStyle(color: Colors.white70)))
                  : _buildProfileContent(),
      floatingActionButton: (widget.userId != currentUserId) 
        ? null
        : StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('users').doc(currentUserId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data?.data() == null) {
                return _buildCustomFab(photoUrl: null); 
              }
              final userData = snapshot.data!.data() as Map<String, dynamic>;
              final photoUrl = userData['photoUrl'] as String?;
              return _buildCustomFab(photoUrl: photoUrl);
            },
          ),
    );
  }

  Widget _buildProfileContent() {
    return Column(
      children: [
        _buildProfileHeader(),
        Divider(color: Colors.blueGrey[700], height: 1, thickness: 1),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _postService.getPostsForUserStream(widget.userId),
            builder: (context, snapshot) {
              final lang = Provider.of<LanguageProvider>(context);
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                 return Center(child: Text(lang.t('profile_error_loading_posts'), style: const TextStyle(color: Colors.white70)));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(child: Text(lang.t('profile_no_posts'), style: const TextStyle(color: Colors.white70, fontSize: 16)));
              }
              final userPosts = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.only(top: 8),
                itemCount: userPosts.length,
                itemBuilder: (context, index) {
                  return ProfilePostCard(
                    key: ValueKey(userPosts[index]['id']),
                    postData: userPosts[index],
                    userData: _userData,
                    postService: _postService,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildProfileHeader() {
    final lang = Provider.of<LanguageProvider>(context);
    final photoUrl = _userData?['photoUrl'] as String?;
    final heroTag = 'user-profile-photo-${widget.userId}';

    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.blueGrey[900],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () { if (photoUrl != null && photoUrl.isNotEmpty) { Navigator.push(context, MaterialPageRoute(builder: (context) => FullPhotoScreen(imageUrl: photoUrl, heroTag: heroTag, isLocalFile: false))); } },
                child: Hero(
                  tag: heroTag,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.blueGrey.shade700,
                    backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
                    child: photoUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white54) : null,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _postService.getPostsForUserStream(widget.userId),
                  builder: (context, snapshot) {
                    int postCount = 0;
                    int totalLikes = 0;
                    if (snapshot.hasData) {
                      postCount = snapshot.data!.length;
                      totalLikes = snapshot.data!.fold(0, (sum, post) => sum + (post['likes'] as int? ?? 0));
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatItem(lang.t('profile_posts_stat'), postCount.toString()),
                        _buildStatItem(lang.t('profile_likes_stat'), totalLikes.toString()),
                      ],
                    );
                  }
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_userData?['displayName'] ?? lang.t('search_users_unknown_name'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          if(_userData?['about'] != null && (_userData!['about'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_userData!['about'], style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
          const SizedBox(height: 12),
          _buildFriendshipButton(),
        ],
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }

  Widget _buildFriendshipButton() {
    final lang = Provider.of<LanguageProvider>(context);
    final displayName = _userData?['displayName'] ?? lang.t('search_users_unknown_name');

    if (_isProcessingRequest || _friendshipStatus == 'loading') {
      return const SizedBox(height: 36, child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (_friendshipStatus == 'self') return const SizedBox(height: 36);
    switch (_friendshipStatus) {
      case 'not_friends':
        return SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _sendFriendRequest, icon: const Icon(Icons.person_add_alt_1), label: Text(lang.t('profile_friend_request_button')), style: ElevatedButton.styleFrom(backgroundColor: Colors.lightGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))));
      case 'pending_sent':
        return SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _declineOrCancelRequest, icon: const Icon(Icons.cancel_schedule_send), label: Text(lang.t('profile_request_sent_button')), style: OutlinedButton.styleFrom(foregroundColor: Colors.amber, side: const BorderSide(color: Colors.amber), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))));
      case 'pending_received':
        return Row(children: [
          Expanded(child: OutlinedButton(onPressed: _declineOrCancelRequest, child: Text(lang.t('profile_decline_button')), style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)))),
          const SizedBox(width: 16),
          Expanded(child: ElevatedButton(onPressed: _acceptFriendRequest, child: Text(lang.t('profile_accept_button')))),
        ]);
      case 'friends':
        return SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () => Navigator.push(context, CustomPageRoute(child: ChatScreenWrapper(receiverID: widget.userId, receiverEmail: displayName))), 
          icon: const Icon(Icons.chat_bubble_outline), 
          label: Text(lang.t('profile_send_message_button')), 
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))
        ));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCustomFab({String? photoUrl}) {
    return GestureDetector(
      onTap: _handleFabClick,
      child: Stack(
        clipBehavior: Clip.none, alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 28, backgroundColor: Colors.grey.shade400,
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) : null,
            child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person, size: 30, color: Colors.white) : null,
          ),
          Positioned(
            right: -4, bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.lightGreen, shape: BoxShape.circle, border: Border.all(color: Colors.blueGrey[800]!, width: 2)),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfilePostCard extends StatefulWidget {
  final Map<String, dynamic> postData;
  final Map<String, dynamic>? userData;
  final PostService postService;
  
  const ProfilePostCard({
    super.key, 
    required this.postData, 
    this.userData, 
    required this.postService
  });

  @override
  State<ProfilePostCard> createState() => _ProfilePostCardState();
}

class _ProfilePostCardState extends State<ProfilePostCard> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
  
  bool _showCommentsOverlay = false;
  bool _isLoadingComments = false;
  List<Map<String, dynamic>> _comments = [];
  final TextEditingController _commentController = TextEditingController();

  late AnimationController _bottomSheetController;

  @override
  void initState() {
    super.initState();
    _bottomSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), 
      reverseDuration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _bottomSheetController.dispose();
    super.dispose();
  }

  String? _getOptimizedUrl(String? originalUrl, {required bool isImage}) {
    if (originalUrl == null || originalUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(originalUrl);
      String path = uri.path;
      String encodedFileName = path.split('%2F').last;
      String originalFileName = Uri.decodeComponent(encodedFileName);
      if (originalFileName.startsWith('optimized_')) return originalUrl;
      String baseName = originalFileName.contains('.') ? originalFileName.substring(0, originalFileName.lastIndexOf('.')) : originalFileName;
      String newExtension = isImage ? 'webp' : 'mp4';
      String newFileName = 'optimized_$baseName.$newExtension';
      String encodedNewFileName = Uri.encodeComponent(newFileName);
      return originalUrl.replaceAll(encodedFileName, encodedNewFileName);
    } catch (e) {
      return originalUrl;
    }
  }

  Future<void> _toggleCommentsOverlay() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (!mounted) return;
    final bool opening = !_showCommentsOverlay;
    setState(() {
      _showCommentsOverlay = opening;
      if (opening) {
        _isLoadingComments = true;
      }
    });

    if (opening) {
      try {
        final postId = widget.postData['id'];
        final querySnapshot = await _firestore
            .collection('posts').doc(postId).collection('comments')
            .orderBy('timestamp', descending: true).get();
            
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
            'commentId': doc.id,
            'userId': data['userId'],
            'userName': authorData?['displayName'] ?? data['userName'] ?? lang.t('no_author_name'),
            'text': data['text'],
            'timestamp': (data['timestamp'] as Timestamp?)?.millisecondsSinceEpoch,
          };
        }).toList();

        if(mounted) {
          setState(() {
            _comments = serverComments;
            _isLoadingComments = false;
          });
        }
      } catch (e) {
        if(mounted) setState(() => _isLoadingComments = false);
      }
    }
  }

  Future<void> _postComment() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final text = _commentController.text.trim();
    if(text.isEmpty || currentUserId == null) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    final postId = widget.postData['id'];
    final commentId = const Uuid().v4();

    final newCommentForUi = {
      'commentId': commentId,
      'userId': currentUserId,
      'userName': currentUser?.displayName ?? lang.t('no_author_name'),
      'text': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    final newCommentForServer = {
      'text': text,
      'userId': currentUserId,
      'userName': currentUser?.displayName ?? lang.t('no_author_name'),
      'userImageUrl': currentUser?.photoURL,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': 0,
    };

    if(mounted) {
      setState(() { 
        _comments.insert(0, Map<String, dynamic>.from(newCommentForUi));
        widget.postData['commentsCount'] = (widget.postData['commentsCount'] ?? 0) + 1;
      });
    }
    
    _commentController.clear();
    FocusScope.of(context).unfocus();
    
    try {
      final postRef = _firestore.collection('posts').doc(postId);
      final commentRef = postRef.collection('comments').doc(commentId);

      final batch = _firestore.batch();
      batch.set(commentRef, newCommentForServer);
      batch.update(postRef, {'commentsCount': FieldValue.increment(1)});
      
      await batch.commit();
    } catch (e) {
      if(mounted) {
        setState(() {
          _comments.removeAt(0);
          widget.postData['commentsCount'] = (widget.postData['commentsCount'] ?? 1) - 1;
        });
      }
    }
  }

  void _showFullText(String fullText) {
    showModalBottomSheet(
      context: context,
      transitionAnimationController: _bottomSheetController,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Colors.blueGrey[900]!.withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 25),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(fullText, style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final isLikedByMe = widget.postData['isLikedByMe'] ?? false;
    final likesCount = widget.postData['likes'] ?? 0;
    final commentsCount = widget.postData['commentsCount'] ?? 0;
    
    final timestamp = widget.postData['timestamp'] as Timestamp?;
    final formattedTime = (timestamp != null) ? DateFormat('MMM d, yyyy  HH:mm').format(timestamp.toDate()) : lang.t('unknown_time');
    final imageUrl = _getOptimizedUrl(widget.postData['imageUrl'], isImage: true);
    final videoUrl = _getOptimizedUrl(widget.postData['videoUrl'], isImage: false);
    final heroTag = 'post-image-${widget.postData['id']}';
    final postText = widget.postData['content'] as String?;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8), 
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.1), 
        borderRadius: BorderRadius.circular(30.0), 
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.2))
      ),
      clipBehavior: Clip.hardEdge, 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20, 
                backgroundImage: widget.userData?['photoUrl'] != null ? CachedNetworkImageProvider(widget.userData!['photoUrl']) : null, 
                child: widget.userData?['photoUrl'] == null ? const Icon(Icons.person, size: 20, color: Colors.white) : null
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.userData?['displayName'] ?? lang.t('search_users_unknown_name'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    Row(children: [Text(formattedTime, style: TextStyle(color: Colors.white.withAlpha(178), fontSize: 12))]),
                  ],
                ),
              ),
            ],
          ),
          
          if (postText != null && postText.isNotEmpty) ...[
            const SizedBox(height: 12), 
            Builder(
              builder: (context) {
                const int maxLength = 90;
                final bool isLong = postText.length > maxLength;
                
                if (isLong) {
                   return Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(
                         '${postText.substring(0, maxLength)}...', 
                         style: TextStyle(fontSize: 16, color: Colors.white.withAlpha(230)),
                       ),
                       const SizedBox(height: 4),
                       GestureDetector(
                         onTap: () => _showFullText(postText),
                         child: Container(
                           padding: const EdgeInsets.symmetric(vertical: 4.0),
                           child: Text(
                             lang.t('read_more_text'), 
                             style: const TextStyle(
                               color: Colors.lightBlueAccent, 
                               fontWeight: FontWeight.w900,   
                               fontSize: 18,                  
                             )
                           ),
                         ),
                       ),
                     ],
                   );
                } else {
                  return Text(postText, style: TextStyle(fontSize: 16, color: Colors.white.withAlpha(230)));
                }
              }
            ),
          ],

          if (imageUrl != null || videoUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.0), 
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: (imageUrl != null && imageUrl.isNotEmpty)
                          ? GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FullPhotoScreen(imageUrl: imageUrl, heroTag: heroTag))), 
                              child: Hero(
                                tag: heroTag, 
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  placeholder: (context, url) => Container(color: Colors.grey[800]),
                                  errorWidget: (context, url, error) => const Center(child: Icon(Icons.error)),
                                )
                              )
                            )
                          : (videoUrl != null && videoUrl.isNotEmpty) ? _VideoPostDisplay(videoPath: videoUrl) : const SizedBox.shrink(),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 700),
                      transitionBuilder: (child, animation) {
                        final offsetAnimation = Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero)
                            .animate(CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic));
                        return SlideTransition(position: offsetAnimation, child: child);
                      },
                      child: _showCommentsOverlay
                          ? ClipRRect(
                              key: const ValueKey('comments_overlay'),
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  height: 400,
                                  decoration: BoxDecoration(color: Colors.blueGrey[900]!.withOpacity(0.9)),
                                  child: Column(
                                    children: [
                                      Align(alignment: Alignment.topRight, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _toggleCommentsOverlay)),
                                      Expanded(
                                        child: _isLoadingComments 
                                            ? const Center(child: CircularProgressIndicator()) 
                                            : _comments.isEmpty 
                                                ? Center(child: Text(lang.t('no_comments_yet'), style: const TextStyle(color: Colors.white70)))
                                                : ListView.builder(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    itemCount: _comments.length,
                                                    itemBuilder: (context, index) {
                                                      final comment = _comments[index];
                                                      return CommentBubble(
                                                        userName: comment['userName'] ?? lang.t('no_author_name'), 
                                                        text: comment['text'],
                                                        timestamp: comment['timestamp'], 
                                                        isMyComment: comment['userId'] == currentUserId,
                                                        likesCount: 0,
                                                        isLikedByMe: false,
                                                        onLike: () {}, 
                                                        onShowOptions: () {},
                                                      );
                                                    }
                                                  ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).viewInsets.bottom > 0 ? MediaQuery.of(context).viewInsets.bottom + 8 : 16),
                                        color: Colors.black.withOpacity(0.3),
                                        child: Row(children: [
                                          Expanded(child: TextField(
                                            controller: _commentController,
                                            style: const TextStyle(color: Colors.white), 
                                            textCapitalization: TextCapitalization.sentences,
                                            keyboardType: TextInputType.multiline,
                                            maxLines: null,
                                            decoration: InputDecoration(hintText: lang.t('comment_placeholder'), hintStyle: const TextStyle(color: Colors.white54), border: InputBorder.none),
                                            onChanged: (text) => setState(() {}),
                                          )),
                                          if(_commentController.text.trim().isNotEmpty)
                                            IconButton(icon: const Icon(Icons.send, color: Colors.lightGreen), onPressed: _postComment)
                                        ]),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('no_comments_overlay')),
                    )
                  ],
                ),
              ),
            ),
          Divider(height: 20, color: Colors.white.withAlpha(51)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionPostButton(
                icon: isLikedByMe ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined, 
                label: "$likesCount ${lang.t('likes_label')}", 
                onPressed: () => widget.postService.togglePostLike(widget.postData['id'], isLikedByMe),
                color: isLikedByMe ? Colors.blueAccent : Colors.white.withAlpha(204)
              ),
              _buildActionPostButton(
                icon: Icons.comment_outlined, 
                label: "$commentsCount ${lang.t('comments_label')}", 
                onPressed: _toggleCommentsOverlay
              ),
              _buildActionPostButton(
                icon: Icons.share_outlined, 
                label: lang.t('share_menu_item'), 
                onPressed: () async {
                 final postId = widget.postData['id'];
                 final postText = widget.postData['content'] as String?;
                 final imgUrl = widget.postData['imageUrl'] as String?;
                 
                 StringBuffer shareTextBuffer = StringBuffer();
                 shareTextBuffer.write(lang.t('share_post_text'));
                 if (postText != null && postText.isNotEmpty) {
                   shareTextBuffer.write('\n\n"$postText"');
                 }
                 shareTextBuffer.write('\n\nhttps://jembe-talk.web.app/post?id=$postId');
                 final shareText = shareTextBuffer.toString();

                 try {
                   final List<XFile> filesToShare = [];
                   final tempDir = await getTemporaryDirectory();

                   if (imgUrl != null && imgUrl.isNotEmpty) {
                      final httpClient = HttpClient();
                      final request = await httpClient.getUrl(Uri.parse(imgUrl));
                      final response = await request.close();
                      final bytes = await consolidateHttpClientResponseBytes(response);
                      final filePath = '${tempDir.path}/share_temp_${DateTime.now().millisecondsSinceEpoch}.jpg';
                      final file = File(filePath);
                      await file.writeAsBytes(bytes);
                      filesToShare.add(XFile(filePath));
                   }

                   if (filesToShare.isNotEmpty) {
                     await Share.shareXFiles(filesToShare, text: shareText);
                   } else {
                     await Share.share(shareText);
                   }
                 } catch (e) {
                   debugPrint("Share error: $e");
                   Share.share(shareText);
                 }
                }
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionPostButton({required IconData icon, required String label, required VoidCallback onPressed, Color? color}) {
    return TextButton.icon(
      onPressed: onPressed, 
      icon: Icon(icon, size: 18, color: color ?? Colors.white.withAlpha(204)), 
      label: Text(label, style: TextStyle(color: color ?? Colors.white.withAlpha(230))),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }
}

class _VideoPostDisplay extends StatefulWidget {
  final String videoPath;
  const _VideoPostDisplay({required this.videoPath});
  @override
  State<_VideoPostDisplay> createState() => _VideoPostdiplayState();
}

class _VideoPostdiplayState extends State<_VideoPostDisplay> {
  VideoPlayerController? _controller;
  bool _isVideoInitialized = false;
  @override
  void initState() {
    super.initState();
    if (widget.videoPath.isEmpty) return;
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoPath));
    _controller?.initialize().then((_) {
      if (mounted) {
        setState(() { _isVideoInitialized = true; });
        _controller?.setLooping(true);
      }
    });
  }
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (_isVideoInitialized && _controller != null) {
      return GestureDetector(
        onTap: () => setState(() { _controller?.value.isPlaying ?? false ? _controller?.pause() : _controller?.play(); }),
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller!),
              if (!(_controller?.value.isPlaying ?? false))
                const Icon(Icons.play_circle_outline, color: Colors.white, size: 60),
            ],
          ),
        ),
      );
    } 
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}