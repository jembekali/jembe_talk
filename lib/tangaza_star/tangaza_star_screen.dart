// lib/tangaza_star/tangaza_star_screen.dart (VERSION 33.56 - STABLE & OPTIMIZED)

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
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

class _TangazaStarScreenState extends State<TangazaStarScreen>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  List<Map<String, dynamic>> _starPosts = [];
  bool _isStarsLoading = true;
  bool _isScreenVisible = true;
  bool _isTransitionFinished = false;

  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addObserver(this);

    // KOSORA FREEZE: Kurinda ko video itangira mu gihe tab ikizunguzuka
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _isTransitionFinished = true);
        _startDataLoading();
      }
    });
  }

  void _startDataLoading() {
    context.read<FeedManager>().refreshFeed();
    _loadStarPosts();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    context.read<FeedManager>().forceCleanup();
  }

  Future<void> _loadStarPosts() async {
    final feedManager = context.read<FeedManager>();
    if (feedManager.cachedStars.isNotEmpty) {
      if (mounted) {
        setState(() {
          _starPosts = feedManager.cachedStars;
          _isStarsLoading = false;
        });
      }
      return;
    }
    try {
      final doc =
          await _firestore.collection('system').doc('global_feed').get();
      if (doc.exists) {
        final List<dynamic> starsData = doc.data()?['stars'] ?? [];
        final finalStars = List<Map<String, dynamic>>.from(starsData);
        feedManager.setCachedStars(finalStars);
        if (mounted) {
          setState(() {
            _starPosts = finalStars;
            _isStarsLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isStarsLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isStarsLoading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      context.read<FeedManager>().pauseAll();
      if (mounted) setState(() => _isScreenVisible = false);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => _isScreenVisible = true);
    }
  }

  Future<void> _navigateTo(Widget screen) async {
    if (!mounted) return;
    context.read<FeedManager>().pauseAll();
    setState(() => _isScreenVisible = false);
    await Navigator.of(context).push(CustomPageRoute(child: screen));
    if (mounted) setState(() => _isScreenVisible = true);
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String langCode = lang.currentLanguage;
    final feedManager = context.watch<FeedManager>();

    // Igihe cyo gutegereza transition ngo irangire (Kurinda freeze)
    if (!_isTransitionFinished) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) context.read<FeedManager>().pauseAll();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.black,
        body: Stack(children: [
          // 1. MAIN FEED (VERTICAL PAGEVIEW)
          Builder(builder: (context) {
            final posts = feedManager.posts;

            if (feedManager.isLoading && posts.isEmpty) {
              return const Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    CupertinoActivityIndicator(color: Colors.white, radius: 18),
                    SizedBox(height: 15),
                    Text("Jembe Talk...",
                        style: TextStyle(color: Colors.white70, fontSize: 13))
                  ]));
            }

            if (posts.isNotEmpty) {
              final int displayCount =
                  posts.length + (feedManager.isFetchingMore ? 1 : 0);
              return PageView.builder(
                key: const ValueKey('jembe_feed_scroller_final_release'),
                scrollDirection: Axis.vertical,
                itemCount: displayCount,
                controller: _pageController,
                physics: const SensitiveScrollPhysics(),
                allowImplicitScrolling: true,
                onPageChanged: (page) {
                  HapticFeedback.selectionClick();
                  if (mounted && page < posts.length) {
                    feedManager.setCurrentPage(page);
                  }
                },
                itemBuilder: (context, index) {
                  if (index == posts.length) {
                    return const Center(
                        child: CupertinoActivityIndicator(
                            color: Colors.white, radius: 15));
                  }

                  final String postId = posts[index][DatabaseHelper.colPostId];

                  return RepaintBoundary(
                    child: TiktokStylePost(
                      key: ValueKey(postId),
                      postData: posts[index],
                      isLiked:
                          posts[index][DatabaseHelper.colIsLikedByMe] ?? false,
                      // LOGIC: Ituma video ikina gusa niba screen yose ihabwa visibility
                      isVisible: (feedManager.activePostId == postId) &&
                          _isScreenVisible,
                      onLike: () => feedManager.toggleLikeStatus(postId),
                      onComment: () async {
                        feedManager.pauseAll();
                        final int? newCount =
                            await showCommentBottomSheet(context, posts[index]);
                        if (newCount != null && mounted) {
                          feedManager.updateCommentCount(postId, newCount);
                        }
                      },
                      onShare: () => ShareService.instance.sharePost(
                          postId: postId,
                          content: posts[index][DatabaseHelper.colText],
                          mediaUrl: posts[index]['networkVideoUrl'] ??
                              posts[index][DatabaseHelper.colImageUrl],
                          type: posts[index]['networkVideoUrl'] != null
                              ? 'video'
                              : 'image'),
                      onDownload: () {},
                      onReport: () => _handleReportPost(posts[index], langCode),
                    ),
                  );
                },
              );
            }
            return _buildNoPosts(langCode, feedManager);
          }),

          // 2. PREMIUM HEADER
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 40, bottom: 15),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.transparent
                ], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 45),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 6),
                          decoration: BoxDecoration(
                              color: const Color(0xFF00ACC1)
                                  .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(
                                  color: const Color(0xFF4DD0E1)
                                      .withValues(alpha: 0.4),
                                  width: 1),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.cyanAccent
                                        .withValues(alpha: 0.15),
                                    blurRadius: 10)
                              ]),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Tangaza Star",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5)),
                              SizedBox(width: 8),
                              Icon(Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 30,
                                  shadows: [
                                    Shadow(
                                        color: Colors.amberAccent,
                                        blurRadius: 20),
                                    Shadow(color: Colors.orange, blurRadius: 35)
                                  ]),
                            ],
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.search_rounded,
                                color: Colors.white, size: 28),
                            onPressed: () => _navigateTo(const SearchScreen())),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  StarsOfTheDaySection(
                      isLoading: _isStarsLoading,
                      starPosts: _starPosts,
                      onStarClick: (data) =>
                          _navigateTo(StarPostDetailScreen(postData: data))),
                ]),
              )),
        ]),

        // 3. CREATE FAB WITH PROFILE AVATAR
        floatingActionButton: _buildCreateFab(),
      ),
    );
  }

  Widget? _buildCreateFab() {
    if (_currentUserId == null) return null;
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(_currentUserId).get(),
      builder: (context, snapshot) {
        final photoUrl = (snapshot.data?.data() as Map?)?['photoUrl'];
        return GestureDetector(
          onTap: () => _navigateTo(const CreatePostScreen()),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10, right: 5),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [Colors.greenAccent, Colors.blueAccent])),
                  child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.black,
                      backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                          ? CachedNetworkImageProvider(photoUrl)
                          : null,
                      child: (photoUrl == null || photoUrl.isEmpty)
                          ? const Icon(Icons.person,
                              color: Colors.white, size: 30)
                          : null),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black, shape: BoxShape.circle),
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: const BoxDecoration(
                          color: Colors.greenAccent, shape: BoxShape.circle),
                      child:
                          const Icon(Icons.add, color: Colors.black, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoPosts(String langCode, FeedManager feedManager) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.auto_awesome_motion_rounded,
          color: Colors.white24, size: 80),
      const SizedBox(height: 20),
      Text(PostTranslations.t('no_posts_found', langCode),
          style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 20),
      ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white10, shape: const StadiumBorder()),
          onPressed: () => feedManager.refreshFeed(),
          child: Text(PostTranslations.t('retry_button', langCode),
              style: const TextStyle(color: Colors.white)))
    ]));
  }

  Future<void> _handleReportPost(
      Map<String, dynamic> postData, String langCode) async {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(langCode == 'ki' ? "Kurega?" : "Report?",
                  style: const TextStyle(color: Colors.white)),
              content: Text(
                  langCode == 'ki'
                      ? "Ese urashaka kurega iyi post?"
                      : "Are you sure you want to report this post?",
                  style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(langCode == 'ki' ? "Reka" : "Cancel")),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: const StadiumBorder()),
                    onPressed: () async {
                      await _firestore.collection('post_reports').add({
                        'postId': postData[DatabaseHelper.colPostId],
                        'reporterId': _currentUserId,
                        'status': 'pending',
                        'timestamp': FieldValue.serverTimestamp()
                      });
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Report sent."),
                                backgroundColor: Colors.orange));
                      }
                    },
                    child: Text(langCode == 'ki' ? "Emeza" : "Confirm")),
              ],
            ));
  }
}

class SensitiveScrollPhysics extends PageScrollPhysics {
  const SensitiveScrollPhysics({super.parent});
  @override
  SensitiveScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      SensitiveScrollPhysics(parent: buildParent(ancestor));
  @override
  double get minFlingVelocity => 5.0;
  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => true;
}

class StarsOfTheDaySection extends StatelessWidget {
  final bool isLoading;
  final List<Map<String, dynamic>> starPosts;
  final Function(Map<String, dynamic>) onStarClick;
  const StarsOfTheDaySection(
      {super.key,
      required this.isLoading,
      required this.starPosts,
      required this.onStarClick});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
          height: 80,
          child:
              Center(child: CupertinoActivityIndicator(color: Colors.amber)));
    }
    if (starPosts.isEmpty) return const SizedBox.shrink();
    return SizedBox(
        height: 85,
        child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            itemCount: starPosts.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final star = starPosts[index];
              final String name = star['authorName'] ?? "Star";
              final String? photo = star['authorPhotoUrl'] ?? star['photoUrl'];
              return GestureDetector(
                  onTap: () => onStarClick(star),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(children: [
                        Container(
                            padding: const EdgeInsets.all(2.0),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.amber, width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.amber.withValues(alpha: 0.2),
                                      blurRadius: 5)
                                ]),
                            child: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.black,
                                backgroundImage:
                                    (photo != null && photo.isNotEmpty)
                                        ? CachedNetworkImageProvider(photo)
                                        : null,
                                child: (photo == null || photo.isEmpty)
                                    ? const Icon(Icons.person,
                                        color: Colors.white, size: 18)
                                    : null)),
                        const SizedBox(height: 4),
                        SizedBox(
                            width: 58,
                            child: Text(name,
                                maxLines: 1,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center)),
                      ])));
            }));
  }
}
