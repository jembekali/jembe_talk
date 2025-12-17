// lib/tangaza_star/tangaza_star_screen.dart (VERSION IKOSOYE - NO OVERFLOW)

import 'dart:convert';
import 'dart:io'; 
import 'dart:developer'; 
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
import 'package:liquid_swipe/liquid_swipe.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:jembe_talk/search_screen.dart';
import 'package:jembe_talk/widgets/comment_bottom_sheet_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

// IMPORTS
import 'feed_manager.dart';
import 'tiktok_style_post.dart';
import 'create_post_screen.dart';
import 'star_post_detail_screen.dart';
import 'package:jembe_talk/language_provider.dart';

// Iyi import niyo ituma dukoresha FileStorageService iri muri services
import 'package:jembe_talk/services/file_storage_service.dart'; 

class TangazaStarScreen extends StatefulWidget {
  final String? targetPostId;
  const TangazaStarScreen({super.key, this.targetPostId});
  @override
  State<TangazaStarScreen> createState() => _TangazaStarScreenState();
}

class _TangazaStarScreenState extends State<TangazaStarScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

  List<Map<String, dynamic>> _starPosts = [];
  bool _isStarsLoading = true;
  
  int _currentPage = 0;
  bool _isScreenVisible = true;
  final ScrollController _starScrollController = ScrollController();

  late AnimationController _animationController;
  
  final LiquidController _liquidController = LiquidController();
  bool _hasProcessedInitialJump = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _loadStarPosts();
  }
  
  @override
  void dispose() {
    _starScrollController.dispose();
    _animationController.dispose(); 
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) { if (mounted) setState(() => _isScreenVisible = false); } 
    else if (state == AppLifecycleState.resumed) { if (mounted) setState(() => _isScreenVisible = true); }
  }

  String _calculateTimeAgo(dynamic timestamp, LanguageProvider lang) {
    if (timestamp == null) return '';
    
    DateTime date;
    try {
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else {
        return '';
      }

      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inSeconds < 60) {
        return lang.t('time_ago_now');
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}${lang.t('time_ago_minutes_suffix')}';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}${lang.t('time_ago_hours_suffix')}';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}${lang.t('time_ago_days_suffix')}';
      } else {
        return '${date.day}/${date.month}/${date.year.toString().substring(2)}';
      }
    } catch (e) {
      return '';
    }
  }

  Future<void> _loadStarPosts() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (mounted) setState(() => _isStarsLoading = true);
    final prefs = await SharedPreferences.getInstance();

    final cachedStarsString = prefs.getString('cachedStarPosts');
    final cacheExpiryString = prefs.getString('starPostsCacheExpiry');
    
    if (cachedStarsString != null && cacheExpiryString != null) {
      final expiryDate = DateTime.parse(cacheExpiryString);
      if (DateTime.now().isBefore(expiryDate)) {
        final List<dynamic> decodedList = jsonDecode(cachedStarsString);
        final cachedPosts = decodedList.cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() {
            _starPosts = cachedPosts;
            _isStarsLoading = false;
          });
        }
        return;
      }
    }

    try {
      final now = Timestamp.now();
      final starPostsSnapshot = await _firestore
          .collection('posts')
          .where('isStar', isEqualTo: true)
          .where('starExpiryTimestamp', isGreaterThan: now)
          .get();

      if (starPostsSnapshot.docs.isEmpty) {
        if (mounted) setState(() { _starPosts = []; _isStarsLoading = false; });
        await prefs.remove('cachedStarPosts');
        await prefs.remove('starPostsCacheExpiry');
        return;
      }

      final userIds = starPostsSnapshot.docs.map((doc) => doc.data()['userId'] as String).toSet().toList();
      Map<String, dynamic> usersMap = {};
      if (userIds.isNotEmpty) {
        final usersSnapshot = await _firestore.collection('users').where(FieldPath.documentId, whereIn: userIds).get();
        usersMap = {for (var doc in usersSnapshot.docs) doc.id: doc.data()};
      }
      
      final validStarPosts = starPostsSnapshot.docs.map((doc) {
        final postData = doc.data();
        
        if (postData['videoUrl'] != null && postData['videoUrl'].toString().isNotEmpty) {
          return null; 
        }

        final authorId = postData['userId'] as String;
        final authorData = usersMap[authorId];
        final likedByList = List<String>.from(postData['likedBy'] ?? []);
        final timestamp = postData['timestamp'] as Timestamp?;
        return {
          DatabaseHelper.colPostId: doc.id,
          DatabaseHelper.colUserId: authorId,
          DatabaseHelper.colUserName: authorData?['displayName'] ?? lang.t('no_author_name'),
          DatabaseHelper.colUserImageUrl: authorData?['photoUrl'],
          DatabaseHelper.colText: postData['content'],
          DatabaseHelper.colImageUrl: postData['imageUrl'],
          DatabaseHelper.colVideoUrl: postData['videoUrl'],
          DatabaseHelper.colLikes: postData['likes'] ?? 0,
          DatabaseHelper.colCommentsCount: postData['commentsCount'] ?? 0,
          DatabaseHelper.colViews: postData['views'] ?? 0,
          'timestamp_server': timestamp,
          DatabaseHelper.colIsLikedByMe: likedByList.contains(currentUserId),
        };
      })
      .where((element) => element != null)
      .cast<Map<String, dynamic>>()
      .toList();

      if (mounted) {
        setState(() {
          _starPosts = validStarPosts;
          _isStarsLoading = false;
        });
        
        final encodableStarPosts = validStarPosts.map((post) {
          final newPost = Map<String, dynamic>.from(post);
          if (newPost['timestamp_server'] is Timestamp) {
            newPost['timestamp_server'] = (newPost['timestamp_server'] as Timestamp).millisecondsSinceEpoch;
          }
          return newPost;
        }).toList();

        final String starsJson = jsonEncode(encodableStarPosts);

        final nowForExpiry = DateTime.now();
        DateTime nextExpiry = DateTime(nowForExpiry.year, nowForExpiry.month, nowForExpiry.day, 17, 55);
        if (nowForExpiry.isAfter(nextExpiry)) {
          final tomorrow = nowForExpiry.add(const Duration(days: 1));
          nextExpiry = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17, 55);
        }

        await prefs.setString('cachedStarPosts', starsJson);
        await prefs.setString('starPostsCacheExpiry', nextExpiry.toIso8601String());
      }
    } catch (e) {
      debugPrint("${lang.t('error_loading_stars')}: $e");
      if (mounted) setState(() => _isStarsLoading = false);
    }
  }

  Future<void> _incrementPostView(String postId) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (currentUserId == null) return;
    final viewDocId = '${currentUserId}_$postId';
    final viewRef = _firestore.collection('post_views').doc(viewDocId);
    try {
      await viewRef.set({
        'userId': currentUserId, 'postId': postId, 'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("${lang.t('error_writing_view')}: $e");
    }
  }

  Future<void> _handleFabClick() async {
    setState(() => _isScreenVisible = false);
    await Navigator.of(context).push(CustomPageRoute(child: const CreatePostScreen()));
    setState(() => _isScreenVisible = true);
  }
  
  void _toggleLike(String postId) {
    context.read<FeedManager>().toggleLikeStatus(postId);
  }
  
  Future<void> _openComments(Map<String, dynamic> postData) async {
    setState(() => _isScreenVisible = false);
    await showCommentBottomSheet(context, postData, controller: _animationController);
    setState(() => _isScreenVisible = true);
  }

  Future<void> _sharePost(Map<String, dynamic> post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final postId = post[DatabaseHelper.colPostId];
    final content = post[DatabaseHelper.colText] as String? ?? '';
    final imageUrl = post[DatabaseHelper.colImageUrl] as String?;
    final videoUrl = post[DatabaseHelper.colVideoUrl] as String?;

    StringBuffer shareTextBuffer = StringBuffer();
    shareTextBuffer.write(lang.t('share_post_text'));
    if (content.isNotEmpty) {
      shareTextBuffer.write('\n\n"$content"');
    }
    shareTextBuffer.write('\n\nhttps://jembe-talk.web.app/post?id=$postId');
    final shareText = shareTextBuffer.toString();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(lang.t('preparing_share_snackbar')),
      duration: const Duration(seconds: 2),
    ));

    try {
      final List<XFile> filesToShare = [];
      final tempDir = await getTemporaryDirectory();

      Future<XFile?> getFileForShare(String url) async {
        try {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(url));
          final response = await request.close();
          if (response.statusCode != 200) return null;
          
          final bytes = await consolidateHttpClientResponseBytes(response);
          final fileName = 'share_${DateTime.now().millisecondsSinceEpoch}.${url.endsWith('mp4') ? 'mp4' : 'jpg'}';
          final filePath = '${tempDir.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(bytes);
          return XFile(filePath);
        } catch (e) {
          debugPrint("Share file download error: $e");
          return null;
        }
      }

      String? mediaPath = imageUrl ?? videoUrl;
      if (mediaPath != null) {
        XFile? file = await getFileForShare(mediaPath);
        if (file != null) filesToShare.add(file);
      }

      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(filesToShare, text: shareText);
      } else {
        await Share.share(shareText);
      }
      
      if (currentUserId != null) {
         _firestore.collection('user_shares').add({'userId': currentUserId, 'postId': postId, 'timestamp': FieldValue.serverTimestamp()});
      }

    } catch (e) {
      debugPrint("${lang.t('error_sharing_post')}: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('share_failed_snackbar'))));
    }
  }
  
  Future<void> _downloadMedia(Map<String, dynamic> post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final postId = post[DatabaseHelper.colPostId];
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lang.t('download_started_snackbar')), duration: const Duration(seconds: 1)),
    );

    String? downloadUrl;
    bool isVideo = false;

    try {
      final docSnapshot = await _firestore.collection('posts').doc(postId).get();
      if (docSnapshot.exists) {
        final freshData = docSnapshot.data();
        downloadUrl = freshData?['imageUrl'] ?? freshData?['videoUrl'];
        isVideo = freshData?['videoUrl'] != null;
      }
    } catch (e) {
      log("DB Fetch failed, falling back to local data");
    }

    if (downloadUrl == null) {
      downloadUrl = post[DatabaseHelper.colImageUrl] ?? post[DatabaseHelper.colVideoUrl];
      isVideo = post[DatabaseHelper.colVideoUrl] != null;
    }

    if (downloadUrl == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('no_media_to_download'))));
      return;
    }

    await _performDownload(downloadUrl, isVideo, retryOn404: true);
  }

  Future<void> _performDownload(String url, bool isVideo, {bool retryOn404 = false}) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final StorageDirectoryType dirType = isVideo ? StorageDirectoryType.video : StorageDirectoryType.images;
    final extension = isVideo ? 'mp4' : 'jpg'; 
    final fileName = 'Jembe_Talk_${DateTime.now().millisecondsSinceEpoch}.$extension';

    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      
      if (response.statusCode == 404 && retryOn404) {
        log("404 Detected on Original URL. Attempting to guess Optimized URL...");
        final guessedUrl = _guessOptimizedUrl(url, isVideo);
        if (guessedUrl != null) {
          log("Retrying with guessed URL: $guessedUrl");
          await _performDownload(guessedUrl, isVideo, retryOn404: false); 
          return;
        }
      }

      if (response.statusCode != 200) {
        throw Exception("Server responded with ${response.statusCode}");
      }
      
      final bytes = await consolidateHttpClientResponseBytes(response);
      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/$fileName';
      final tempFile = File(tempFilePath);
      await tempFile.writeAsBytes(bytes);

      final savedPath = await FileStorageService.instance.saveFileToPublicDirectory(
        tempFilePath: tempFilePath, 
        dirType: dirType, 
        fileName: fileName
      );

      if (mounted) {
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lang.t('download_success_snackbar')),
              backgroundColor: Colors.green,
              action: SnackBarAction(label: 'OK', onPressed: () {}, textColor: Colors.white),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lang.t('download_failed_snackbar')), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Error downloading: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(lang.t('download_error_snackbar')), backgroundColor: Colors.red),
        );
      }
    }
  }

  String? _guessOptimizedUrl(String originalUrl, bool isVideo) {
    try {
      final Uri uri = Uri.parse(originalUrl);
      final String path = uri.path; 
      final List<String> parts = path.split('%2F');
      if (parts.isEmpty) return null;

      final String lastPart = parts.last; 
      final String id = lastPart.split('.').first; 
      
      final String newExt = isVideo ? 'mp4' : 'webp';
      final String newFilename = 'optimized_$id.$newExt';
      
      final String newPath = path.replaceAll(lastPart, newFilename);
      return uri.replace(path: newPath, queryParameters: {'alt': 'media'}).toString();
    } catch (e) {
      log("Failed to guess URL: $e");
      return null;
    }
  }
  
  Future<void> _reportPost(Map<String, dynamic> post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final postId = post[DatabaseHelper.colPostId];
    if (currentUserId == null) return;

    try {
      await _firestore.collection('post_reports').add({
        'postId': postId,
        'reporterId': currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'postContent': post[DatabaseHelper.colText],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang.t('report_success_snackbar')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Ikosa ryo kurungika ikirego: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang.t('report_failed_snackbar')),
            backgroundColor: Colors.red,
          ),
        );
      }
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
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
            child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person, size: 30, color: Colors.white) : null,
          ),
          Positioned(
            right: -4, bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.lightGreen, shape: BoxShape.circle, border: Border.all(color: Colors.blueGrey[900]!, width: 2)),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.blueGrey[900],
      body: Stack(
        children: [
          Consumer<FeedManager>(
            builder: (context, feedManager, child) {
              final regularPosts = feedManager.posts;

              if (feedManager.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (regularPosts.isEmpty && !feedManager.isFetchingMore) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(lang.t('no_posts_available'), style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => context.read<FeedManager>().refreshFeed(),
                      icon: const Icon(Icons.refresh), 
                      label: Text(lang.t('try_refresh_button'))
                    )
                  ],),);
              }

              int initialPageToUse = 0;
              if (widget.targetPostId != null && !_hasProcessedInitialJump && regularPosts.isNotEmpty) {
                final targetIndex = regularPosts.indexWhere((p) => p[DatabaseHelper.colPostId] == widget.targetPostId);
                if (targetIndex != -1) {
                  initialPageToUse = targetIndex;
                  _currentPage = targetIndex;
                  _hasProcessedInitialJump = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                     context.read<FeedManager>().setCurrentPage(targetIndex);
                  });
                }
              } else {
                initialPageToUse = _currentPage;
              }

              return LiquidSwipe(
                  liquidController: _liquidController,
                  initialPage: initialPageToUse,
                  pages: List.generate(regularPosts.length + (feedManager.isFetchingMore ? 1 : 0), (index) {
                    if (index == regularPosts.length) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final postData = regularPosts[index];
                    final bool isLiked = postData[DatabaseHelper.colIsLikedByMe] ?? false;
                    
                    final Map<String, dynamic> postDataWithTime = Map<String, dynamic>.from(postData);
                    final rawTimestamp = postDataWithTime['timestamp'] ?? postDataWithTime['timestamp_server'];
                    postDataWithTime['displayTime'] = _calculateTimeAgo(rawTimestamp, lang);

                    return Container(
                      color: Colors.blueGrey[900],
                      child: TiktokStylePost(
                        key: ValueKey(postData[DatabaseHelper.colPostId]),
                        postData: postDataWithTime, 
                        isLiked: isLiked, 
                        isPlaying: index == _currentPage && _isScreenVisible,
                        onLike: () => _toggleLike(postData[DatabaseHelper.colPostId]),
                        onComment: () => _openComments(postData), 
                        onShare: () => _sharePost(postData),
                        onDownload: () => _downloadMedia(postData), 
                        onReport: () => _reportPost(postData),
                      ),
                    );
                  }),
                  onPageChangeCallback: (page) {
                    setState(() => _currentPage = page);
                    context.read<FeedManager>().setCurrentPage(page);

                    if (regularPosts.length > page) { 
                      _incrementPostView(regularPosts[page][DatabaseHelper.colPostId]);
                      if (page >= regularPosts.length - 2) {
                        context.read<FeedManager>().fetchMorePosts();
                      }
                    }
                  },
                  waveType: WaveType.liquidReveal, slideIconWidget: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  positionSlideIcon: 0.8, enableLoop: false,
                );
            },
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withOpacity(0.7), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              child: SafeArea(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                          Text(lang.t('screen_title'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 5.0, color: Colors.black54)])),
                          const SizedBox(width: 10),
                          Container(
                            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.7), blurRadius: 10.0, spreadRadius: 1.0)]),
                            child: Icon(Icons.star_rounded, color: Colors.amber.shade400, size: 35),
                          ),
                        ],),
                      ),
                      StarsOfTheDaySection(isLoading: _isStarsLoading, starPosts: _starPosts, scrollController: _starScrollController, highlightedPostId: widget.targetPostId),
                    ],),
                    Positioned(
                      left: 0, top: 0,
                      child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.of(context).pop(), tooltip: lang.t('back_tooltip')),
                    ),
                    Positioned(
                      right: 0, top: 0,
                      child: IconButton(
                        icon: const Icon(Icons.search, color: Colors.white, size: 28), 
                        onPressed: () => Navigator.push(context, CustomPageRoute(child: const SearchScreen())),
                        tooltip: lang.t('search_tooltip'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: (currentUserId == null)
        ? const SizedBox.shrink()
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
}

class StarsOfTheDaySection extends StatelessWidget {
  final bool isLoading;
  final List<Map<String, dynamic>> starPosts;
  final ScrollController scrollController;
  final String? highlightedPostId;

  const StarsOfTheDaySection({super.key, required this.isLoading, required this.starPosts, required this.scrollController, this.highlightedPostId});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Column(
      children: [
        const SizedBox(height: 12),
        // HANO NIHO TWAHINDURIYE HEIGHT (KUVAVA KURI 85 -> 110)
        SizedBox(
          height: 110,
          child: isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : starPosts.isEmpty
                  ? Center(child: Text(lang.t('no_new_stars'), style: const TextStyle(color: Colors.white54, fontSize: 12)))
                  : ListView.builder(
                      controller: scrollController, scrollDirection: Axis.horizontal, itemCount: starPosts.length,
                      itemBuilder: (context, index) {
                        final starData = starPosts[index];
                        final postImageUrl = starData[DatabaseHelper.colUserImageUrl] as String?;
                        final username = starData[DatabaseHelper.colUserName] as String?;
                        final bool isHighlighted = highlightedPostId == starData[DatabaseHelper.colPostId];
                        return GestureDetector(
                          onTap: () {
                              final postData = Map<String, dynamic>.from(starData);
                              if (postData['timestamp_server'] is int) {
                                postData['timestamp_server'] = Timestamp.fromMillisecondsSinceEpoch(postData['timestamp_server']);
                              }
                              Navigator.of(context).push(MaterialPageRoute(builder: (context) => StarPostDetailScreen(postData: postData)));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 500), padding: const EdgeInsets.all(2.0),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: isHighlighted ? Border.all(color: Colors.amber.shade300, width: 2.5) : null,
                                boxShadow: isHighlighted ? [BoxShadow(color: Colors.amber.withOpacity(0.7), blurRadius: 10.0, spreadRadius: 2.0)] : [],
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                CircleAvatar(
                                  radius: 30, backgroundColor: Colors.blueGrey.shade700,
                                  backgroundImage: (postImageUrl != null && postImageUrl.isNotEmpty) ? NetworkImage(postImageUrl) : null,
                                  child: (postImageUrl == null || postImageUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white54) : null,
                                ),
                                const SizedBox(height: 4),
                                SizedBox(width: 60, child: Text(username ?? lang.t('unknown_username'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70), overflow: TextOverflow.ellipsis, maxLines: 1)),
                              ],),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}