import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
import 'package:liquid_swipe/liquid_swipe.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/search_screen.dart';
import 'package:jembe_talk/widgets/comment_bottom_sheet_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jembe_talk/services/share_service.dart';
import 'package:jembe_talk/post_translations.dart';

import 'feed_manager.dart';
import 'tiktok_style_post.dart';
import 'create_post_screen.dart';
import 'star_post_detail_screen.dart';
import 'package:jembe_talk/language_provider.dart';

class TangazaStarScreen extends StatefulWidget {
  final String? targetPostId;
  const TangazaStarScreen({super.key, this.targetPostId});
  
  @override
  State<TangazaStarScreen> createState() => _TangazaStarScreenState();
}

class _TangazaStarScreenState extends State<TangazaStarScreen> with WidgetsBindingObserver {
  final _firestore = FirebaseFirestore.instance;
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  List<Map<String, dynamic>> _starPosts = [];
  bool _isStarsLoading = true;
  int _currentPage = 0;
  bool _isScreenVisible = true; 
  final LiquidController _liquidController = LiquidController();
  final ScrollController _starScrollController = ScrollController();
  
  final Set<String> _cachedPostIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFeed(); 
    _loadStarPosts(); 
  }

  void _initFeed() {
    Future.microtask(() {
      if (!mounted) return;
      final feedManager = context.read<FeedManager>();
      feedManager.addListener(_onFeedUpdated);
      
      if (widget.targetPostId != null) {
        feedManager.loadTargetPostThenFeed(widget.targetPostId!);
      } else {
        feedManager.refreshFeed();
      }
    });
  }

  void _onFeedUpdated() {
    if (!mounted) return;
    final posts = context.read<FeedManager>().posts;
    if (posts.isEmpty) return;
    
    // Precache logic for smoother scrolling
    for (var post in posts.skip(_currentPage).take(5)) {
      final String postId = post[DatabaseHelper.colPostId];
      if (!_cachedPostIds.contains(postId)) {
        final String? imageUrl = post[DatabaseHelper.colImageUrl];
        if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
          String thumbUrl = imageUrl.contains('auth=') ? imageUrl : "${R2Service.workerUrl}${Uri.parse(imageUrl).path}?auth=${R2Service.workerSecretKey}";
          precacheImage(CachedNetworkImageProvider(thumbUrl, headers: {'X-Jembe-Auth': R2Service.workerSecretKey}), context);
          _cachedPostIds.add(postId);
        }
      }
    }
  }
  
  @override
  void dispose() {
    _starScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    try { context.read<FeedManager>().removeListener(_onFeedUpdated); } catch(_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (mounted) {
        setState(() => _isScreenVisible = false);
        context.read<FeedManager>().pauseAll();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => _isScreenVisible = true);
    }
  }

  Future<void> _navigateTo(Widget screen) async {
    if (!mounted) return;
    final feedManager = context.read<FeedManager>();
    feedManager.pauseAll(); 
    setState(() => _isScreenVisible = false);
    await Navigator.of(context).push(CustomPageRoute(child: screen));
    if (!mounted) return;
    setState(() => _isScreenVisible = true);
  }

  Future<void> _loadStarPosts() async {
    try {
      final snap = await _firestore.collection('posts')
          .where('isStar', isEqualTo: true)
          .where('starExpiryTimestamp', isGreaterThan: Timestamp.now())
          .limit(10).get();
      final List<Map<String, dynamic>> valid = [];
      for (var doc in snap.docs) { valid.add({ DatabaseHelper.colPostId: doc.id, ...doc.data() }); }
      if (mounted) setState(() { _starPosts = valid; _isStarsLoading = false; });
    } catch (_) { if (mounted) setState(() => _isStarsLoading = false); }
  }

  Future<void> _handleReportPost(Map<String, dynamic> postData, String langCode) async {
    if (_currentUserId == null) return;
    
    final Map<String, Map<String, String>> reportLang = {
      'ki': {'title': 'Kurega iyi Post?', 'msg': 'Rega iyi post nimba itubahiriza amategeko?', 'success': 'Ikirego cakiriwe. Reka dusuzume.', 'btnConfirm': 'Ego, Rega', 'btnCancel': 'Reka'},
      'sw': {'title': 'Ripoti Posti hii?', 'msg': 'Je, unathibitisha unataka kuripoti posti hii kwa kukiuka sheria?', 'success': 'Ripoti imepokelewa. Tutafuatilia.', 'btnConfirm': 'Ripoti', 'btnCancel': 'Ghairi'},
      'en': {'title': 'Report this Post?', 'msg': 'Are you sure you want to report this post for violating rules?', 'success': 'Report received. We will investigate.', 'btnConfirm': 'Report', 'btnCancel': 'Cancel'},
      'fr': {'title': 'Signaler ce Post ?', 'msg': 'Voulez-vous vraiment signaler ce post pour violation des règles ?', 'success': 'Signalement reçu. Nous allons enquêter.', 'btnConfirm': 'Signaler', 'btnCancel': 'Annuler'},
    };

    final currentT = reportLang[langCode] ?? reportLang['en']!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(currentT['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(currentT['msg']!, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(currentT['btnCancel']!, style: const TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _firestore.collection('post_reports').add({
                  'postId': postData[DatabaseHelper.colPostId],
                  'reporterId': _currentUserId,
                  'timestamp': FieldValue.serverTimestamp(),
                  'status': 'pending',
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(currentT['success']!), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
                }
              } catch (e) { debugPrint("Report Error: $e"); }
            },
            child: Text(currentT['btnConfirm']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String langCode = lang.currentLanguage;
    final feedManager = context.watch<FeedManager>();
    
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Hagarika video ariko ureke posts zigume muri RAM
          context.read<FeedManager>().pauseAll();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true, 
        backgroundColor: Colors.black,
        body: Stack(children: [
            Builder(builder: (context) {
                final posts = feedManager.posts;

                if (posts.isNotEmpty) {
                  return LiquidSwipe.builder(
                      // ✅ IYI KEY NIYO Y'INGENZI: Ivugurura UI iyo amadata aje
                      key: ValueKey('swipe_feed_${posts.length}'), 
                      itemCount: posts.length, 
                      liquidController: _liquidController, 
                      initialPage: _currentPage, 
                      itemBuilder: (context, index) {
                        if (index >= posts.length) return const SizedBox.shrink();
                        return TiktokStylePost(
                            key: ValueKey(posts[index][DatabaseHelper.colPostId]), 
                            postData: posts[index], 
                            isLiked: posts[index][DatabaseHelper.colIsLikedByMe] ?? false, 
                            isVisible: index == _currentPage && _isScreenVisible, 
                            onLike: () => feedManager.toggleLikeStatus(posts[index][DatabaseHelper.colPostId]),
                            onComment: () async {
                              feedManager.pauseAll();
                              final int? newCount = await showCommentBottomSheet(context, posts[index]);
                              if (newCount != null && mounted) {
                                feedManager.updateCommentCount(posts[index][DatabaseHelper.colPostId], newCount);
                              }
                            }, 
                            onShare: () => ShareService.instance.sharePost(
                              postId: posts[index][DatabaseHelper.colPostId], 
                              content: posts[index][DatabaseHelper.colText], 
                              mediaUrl: posts[index][DatabaseHelper.colVideoUrl] ?? posts[index][DatabaseHelper.colImageUrl], 
                              type: posts[index][DatabaseHelper.colVideoUrl] != null ? 'video' : 'image'
                            ),
                            onDownload: () {}, 
                            onReport: () => _handleReportPost(posts[index], langCode),
                        );
                      },
                      onPageChangeCallback: (page) { 
                        if (mounted) { 
                          setState(() => _currentPage = page); 
                          feedManager.setCurrentPage(page); 
                        } 
                      },
                      waveType: WaveType.liquidReveal, 
                      enableLoop: false,
                  );
                }

                if (feedManager.isLoading) return const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1.5));
                
                return Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 80),
                    const SizedBox(height: 20),
                    Text(PostTranslations.t('no_posts_found', langCode), style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 20),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white10), onPressed: () => feedManager.refreshFeed(), child: Text(PostTranslations.t('retry_button', langCode), style: const TextStyle(color: Colors.white))),
                  ]),
                );
            }),

            Positioned(top: 0, left: 0, right: 0, child: Container(
              padding: const EdgeInsets.only(top: 45, bottom: 15),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              child: Column(children: [
                 Padding(padding: const EdgeInsets.symmetric(horizontal: 15), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(lang.t('screen_title'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8), const Icon(Icons.stars_rounded, color: Color(0xFFFFD700), size: 28),
                 ])),
                 const SizedBox(height: 12),
                 StarsOfTheDaySection(isLoading: _isStarsLoading, starPosts: _starPosts, scrollController: _starScrollController, onStarClick: (data) => _navigateTo(StarPostDetailScreen(postData: data))),
              ]),
            )),

            Positioned(top: 45, left: 10, child: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white), onPressed: () => Navigator.pop(context))),
            Positioned(top: 45, right: 10, child: IconButton(icon: const Icon(Icons.search_rounded, color: Colors.white, size: 28), onPressed: () => _navigateTo(const SearchScreen()))),
        ]),

        floatingActionButton: (_currentUserId == null) ? null : StreamBuilder<DocumentSnapshot>(
          stream: _firestore.collection('users').doc(_currentUserId).snapshots(),
          builder: (context, snapshot) {
            final photoUrl = (snapshot.data?.data() as Map?)?['photoUrl'];
            return GestureDetector(
              onTap: () => _navigateTo(const CreatePostScreen()),
              child: Stack(alignment: Alignment.center, children: [
                CircleAvatar(radius: 28, backgroundColor: Colors.blueGrey[800], backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) : null, child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white) : null),
                Positioned(right: -2, bottom: -2, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.lightGreen, shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 18))),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class StarsOfTheDaySection extends StatelessWidget {
  final bool isLoading; 
  final List<Map<String, dynamic>> starPosts; 
  final ScrollController scrollController; 
  final Function(Map<String, dynamic>) onStarClick;
  const StarsOfTheDaySection({super.key, required this.isLoading, required this.starPosts, required this.scrollController, required this.onStarClick});

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator(color: Color(0xFFFFD700), strokeWidth: 1.5)));
    if (starPosts.isEmpty) return const SizedBox.shrink();
    return SizedBox(height: 95, child: ListView.builder(
      controller: scrollController, 
      scrollDirection: Axis.horizontal, 
      padding: const EdgeInsets.symmetric(horizontal: 10), 
      itemCount: starPosts.length, 
      itemBuilder: (context, index) {
          final star = starPosts[index]; 
          final String userId = star['userId'] ?? "";
          return GestureDetector(onTap: () => onStarClick(star), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(), 
            builder: (context, snapshot) {
                  final userData = snapshot.data?.data() as Map<String, dynamic>?;
                  final String liveName = userData?['displayName'] ?? star['authorName'] ?? "Star";
                  final String? livePhoto = userData?['photoUrl'] ?? star['authorPhotoUrl'];
                  return Column(children: [
                    Container(padding: const EdgeInsets.all(2.5), decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFDB931), Color(0xFFB8860B)])), child: CircleAvatar(radius: 26, backgroundColor: Colors.black, backgroundImage: (livePhoto != null && livePhoto.isNotEmpty) ? CachedNetworkImageProvider(livePhoto) : null, child: (livePhoto == null || livePhoto.isEmpty) ? const Icon(Icons.person, color: Colors.white) : null)),
                    const SizedBox(height: 6), 
                    SizedBox(width: 60, child: Text(liveName, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                  ]);
                })));
        }));
  }
}