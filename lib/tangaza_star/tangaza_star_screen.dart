// lib/screens/tangaza_star_screen.dart (VERSION NTAKUKA IKEMURA IKIBAZO 100%)

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:liquid_swipe/liquid_swipe.dart';
import 'tiktok_style_post.dart';
import 'create_post_screen.dart';
import 'comment_screen.dart';
import 'star_post_detail_screen.dart';

class TangazaStarScreen extends StatefulWidget {
  final String? targetPostId;

  const TangazaStarScreen({super.key, this.targetPostId});
  @override
  State<TangazaStarScreen> createState() => _TangazaStarScreenState();
}

class _TangazaStarScreenState extends State<TangazaStarScreen>
    with WidgetsBindingObserver {
  final _firestore = FirebaseFirestore.instance;
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

  List<Map<String, dynamic>> _starPosts = [];
  List<Map<String, dynamic>> _regularPosts = [];

  bool _isStarsLoading = true;
  bool _isInitialLoading = true;
  bool _isSyncing = false;

  // <<<--- ICYAHINDUWE #1: Twongereyemo iyi variable nshya ---<<<
  bool _isLoadingFirstTime = true;

  int _initialPage = 0;
  bool _initialPageHasBeenSet = false;
  int _currentPageIndex = 0;

  bool _isScreenVisible = true;
  final Set<String> _viewedPostIds = {};
  final ScrollController _starScrollController = ScrollController();
  final LiquidController _liquidController = LiquidController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startFetchingBatches();
  }

  @override
  void dispose() {
    _starScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      if (mounted) setState(() => _isScreenVisible = false);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => _isScreenVisible = true);
    }
  }

  Future<void> _startFetchingBatches({bool isRefresh = false}) async {
    if (_isSyncing && !isRefresh) return;

    if (isRefresh) {
      setState(() {
        _initialPageHasBeenSet = false;
        _initialPage = 0;
        _currentPageIndex = 0;
      });
    }

    if (isRefresh || _regularPosts.isEmpty) {
      setState(() => _isInitialLoading = true);
    }
    setState(() => _isSyncing = true);

    try {
      if (!isRefresh) {
        await _loadPostsFromCache();
      }
      
      await _fetchNextBatch(lastDocument: null, batchNumber: 1, isRefresh: isRefresh);

    } catch (e) {
      debugPrint("Ikosa ryo gutangura gukurura: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _isSyncing = false;
          // <<<--- ICYAHINDUWE #2: Iyo gukurura bwa mbere birangiye, tuyihindura false ---<<<
          _isLoadingFirstTime = false;
        });
      }
    }
  }
  
  Future<void> _fetchNextBatch({DocumentSnapshot? lastDocument, required int batchNumber, bool isRefresh = false}) async {
    if (batchNumber > 3 || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    Query query = _firestore
        .collection('posts')
        .where('isStar', isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .limit(5);

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    } else if (!isRefresh) {
      final lastTimestamp = prefs.getInt('lastViewedPostTimestamp');
      if (lastTimestamp != null) {
        query = query.startAfter([Timestamp.fromMillisecondsSinceEpoch(lastTimestamp)]);
      }
    }

    final snapshot = await query.get();

    if (snapshot.docs.isNotEmpty) {
      final newPosts = await _processFirebaseDocs(snapshot.docs);
      await DatabaseHelper.instance.cachePosts(newPosts);
      
      await _loadPostsFromCache();
      
      final newLastDocument = snapshot.docs.last;
      await _fetchNextBatch(lastDocument: newLastDocument, batchNumber: batchNumber + 1, isRefresh: isRefresh);
    }
  }


  Future<void> _loadPostsFromCache() async {
    final allStarPostsData = await DatabaseHelper.instance.getStarPosts();
    final allRegularPosts =
        await DatabaseHelper.instance.getAllRegularPostsFromCache();

    if (mounted) {
      final oldListLength = _regularPosts.length;
      final newListLength = allRegularPosts.length;

      setState(() {
        _starPosts = allStarPostsData;
        _regularPosts = allRegularPosts;
        _isStarsLoading = false;
      });

      if (!_initialPageHasBeenSet && _regularPosts.isNotEmpty) {
        await _calculateAndSetInitialPage();
      } else if (newListLength > oldListLength) {
        final difference = newListLength - oldListLength;
        setState(() {
          _initialPage = _currentPageIndex + difference;
          _currentPageIndex = _initialPage;
        });
      }
    }
  }

  Future<void> _calculateAndSetInitialPage() async {
    final prefs = await SharedPreferences.getInstance();
    final lastPostId = prefs.getString('lastViewedPostId');
    int targetPage = 0;

    if (lastPostId != null) {
      final lastIndex = _regularPosts
          .indexWhere((p) => p[DatabaseHelper.colPostId] == lastPostId);

      if (lastIndex != -1) {
        targetPage = (lastIndex > 0) ? lastIndex - 1 : 0;
      }
    }

    if (mounted) {
      setState(() {
        _initialPage = targetPage;
        _currentPageIndex = targetPage;
        _initialPageHasBeenSet = true;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _processFirebaseDocs(
      List<QueryDocumentSnapshot> docs) async {
    final List<Map<String, dynamic>> processedPosts = [];
    final userIds = docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .map((data) => data['userId'] as String?)
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<String, dynamic> usersMap = {};
    if (userIds.isNotEmpty) {
      final usersSnapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: userIds)
          .get();
      usersMap = {for (var doc in usersSnapshot.docs) doc.id: doc.data()};
    }

    for (var doc in docs) {
      final postData = doc.data() as Map<String, dynamic>;
      final authorId = postData['userId'] as String?;
      final authorData = usersMap[authorId];
      final likedByList = List<String>.from(postData['likedBy'] ?? []);

      processedPosts.add({
        DatabaseHelper.colPostId: doc.id,
        DatabaseHelper.colText: postData['content'],
        DatabaseHelper.colUserId: postData['userId'],
        DatabaseHelper.colTimestamp:
            (postData['timestamp'] as Timestamp).millisecondsSinceEpoch,
        DatabaseHelper.colLikes: postData['likes'] ?? 0,
        DatabaseHelper.colCommentsCount: postData['commentsCount'] ?? 0,
        DatabaseHelper.colViews: postData['views'] ?? 0,
        DatabaseHelper.colIsStar: (postData['isStar'] ?? false) ? 1 : 0,
        DatabaseHelper.colStarExpiryTimestamp:
            (postData['starExpiryTimestamp'] as Timestamp?)
                ?.millisecondsSinceEpoch,
        DatabaseHelper.colUserName: authorData?['displayName'] ?? 'Ata Zina',
        DatabaseHelper.colUserImageUrl: authorData?['photoUrl'],
        DatabaseHelper.colIsLikedByMe:
            likedByList.contains(currentUserId) ? 1 : 0,
        DatabaseHelper.colImageUrl: postData['imageUrl'],
        DatabaseHelper.colVideoUrl: postData['videoUrl'],
      });
    }
    return processedPosts;
  }

  Future<void> _incrementPostView(String postId) async {
    if (!_viewedPostIds.contains(postId)) {
      await _firestore
          .collection('posts')
          .doc(postId)
          .update({'views': FieldValue.increment(1)});
      if (mounted) {
        setState(() {
          _viewedPostIds.add(postId);
          final postIndex = _regularPosts
              .indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
          if (postIndex != -1) {
            _regularPosts[postIndex][DatabaseHelper.colViews] =
                (_regularPosts[postIndex][DatabaseHelper.colViews] ?? 0) + 1;
          }
        });
      }
    }
  }

  Future<void> _handleFabClick() async {
    setState(() => _isScreenVisible = false);
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const CreatePostScreen()));
    setState(() => _isScreenVisible = true);
    await _startFetchingBatches(isRefresh: true);
  }

  Future<void> _toggleLike(String postId, bool isCurrentlyLiked) async {
    if (currentUserId == null) return;

    final postIndex = _regularPosts
        .indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (postIndex != -1) {
      setState(() {
        final post = _regularPosts[postIndex];
        final currentLikes = post[DatabaseHelper.colLikes] ?? 0;
        post[DatabaseHelper.colIsLikedByMe] = isCurrentlyLiked ? 0 : 1;
        post[DatabaseHelper.colLikes] =
            isCurrentlyLiked ? (currentLikes - 1) : (currentLikes + 1);
      });
    }

    try {
      await _firestore.collection('posts').doc(postId).update({
        'likes': FieldValue.increment(isCurrentlyLiked ? -1 : 1),
        'likedBy': isCurrentlyLiked
            ? FieldValue.arrayRemove([currentUserId])
            : FieldValue.arrayUnion([currentUserId]),
      });
    } catch (e) {
      debugPrint("Ikosa ryo guhindura like muri Firebase: $e");
    }
  }

  Future<void> _openComments(Map<String, dynamic> postData) async {
    setState(() => _isScreenVisible = false);
    final result = await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CommentScreen(postData: postData),
    ));
    setState(() => _isScreenVisible = true);

    if (result is int) {
      final postIndex = _regularPosts.indexWhere(
          (p) => p[DatabaseHelper.colPostId] == postData[DatabaseHelper.colPostId]);
      if (postIndex != -1) {
        setState(() {
          _regularPosts[postIndex][DatabaseHelper.colCommentsCount] = result;
        });
      }
    }
  }

  void _onSearchChanged(String query) {}
  Future<void> _sharePost(Map<String, dynamic> post) async {}
  Future<void> _downloadMedia(Map<String, dynamic> post) async {}
  Future<void> _reportPost(Map<String, dynamic> post) async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Tangaza Star"),
            const SizedBox(width: 8),
            Icon(Icons.star_rate_rounded, color: Colors.amber[600], size: 35),
          ],
        ),
        backgroundColor: Colors.blueGrey[900],
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(150.0),
          child: StarsOfTheDaySection(
            isLoading: _isStarsLoading,
            starPosts: _starPosts,
            onSearchChanged: _onSearchChanged,
            onSearchToggled: (isSearching) =>
                setState(() => _isScreenVisible = !isSearching),
            scrollController: _starScrollController,
            highlightedPostId: widget.targetPostId,
          ),
        ),
      ),
      backgroundColor: Colors.blueGrey[900],
      body: RefreshIndicator(
        onRefresh: () => _startFetchingBatches(isRefresh: true),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Expanded(
              // <<<--- ICYAHINDUWE #3: Ubu tubanza kureba niba ari ubwa mbere ---<<<
              child: _isLoadingFirstTime
                  ? const Center(child: CircularProgressIndicator())
                  : _regularPosts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Nta post zihari...',
                                  style: TextStyle(color: Colors.white70)),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _startFetchingBatches(isRefresh: true),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Gerageza Gukurura'),
                              )
                            ],
                          ),
                        )
                      : Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: LiquidSwipe(
                                  initialPage: _initialPage,
                                  liquidController: _liquidController,
                                  pages: List.generate(_regularPosts.length,
                                      (index) {
                                    final postData = _regularPosts[index];
                                    final bool isLiked =
                                        (postData[DatabaseHelper.colIsLikedByMe] ??
                                                0) ==
                                            1;
                                    final List<Map<String, dynamic>>
                                        subsequentPosts = (index <
                                                _regularPosts.length - 1)
                                            ? _regularPosts.sublist(index + 1)
                                            : [];
                                            
                                    return Container(
                                      color: Colors.blueGrey[900],
                                      child: TiktokStylePost(
                                        key: ValueKey(
                                            postData[DatabaseHelper.colPostId]),
                                        postData: postData,
                                        subsequentPosts: subsequentPosts,
                                        isLiked: isLiked,
                                        isPlaying:
                                            index == _currentPageIndex &&
                                                _isScreenVisible,
                                        onLike: () => _toggleLike(
                                            postData[DatabaseHelper.colPostId],
                                            isLiked),
                                        onComment: () => _openComments(postData),
                                        onShare: () => _sharePost(postData),
                                        onDownload: () =>
                                            _downloadMedia(postData),
                                        onReport: () => _reportPost(postData),
                                      ),
                                    );
                                  }),
                                  onPageChangeCallback: (page) {
                                    setState(() {
                                      _currentPageIndex = page;
                                    });
                                    _handlePageChangeLogic(page);
                                  },
                                  waveType: WaveType.liquidReveal,
                                  slideIconWidget: const Icon(
                                      Icons.arrow_back_ios,
                                      color: Colors.white),
                                  positionSlideIcon: 0.8,
                                  enableLoop: false,
                                ),
                              ),
                            ),
                            if (_isSyncing && !_isLoadingFirstTime)
                              Positioned(
                                top: 15,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius:
                                          BorderRadius.circular(20)),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white)),
                                        SizedBox(width: 8),
                                        Text("Biriko birakururwa...",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12)),
                                      ]),
                                ),
                              )
                          ],
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleFabClick,
        backgroundColor: Colors.lightGreen,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _handlePageChangeLogic(int page) async {
    if (_regularPosts.length > page) {
      final currentPost = _regularPosts[page];
      final postId = currentPost[DatabaseHelper.colPostId];
      final postTimestamp = currentPost[DatabaseHelper.colTimestamp];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastViewedPostId', postId);
      if (postTimestamp is int) {
        await prefs.setInt('lastViewedPostTimestamp', postTimestamp);
      }
      _incrementPostView(postId);
    }
    if (page >= _regularPosts.length - 3 && !_isSyncing) {
      _startFetchingBatches();
    }
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, spreadRadius: 1, blurRadius: 3)
            ]),
        child: Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87)));
  }
}

class StarsOfTheDaySection extends StatefulWidget {
  final bool isLoading;
  final List<Map<String, dynamic>> starPosts;
  final Function(String) onSearchChanged;
  final Function(bool) onSearchToggled;
  final ScrollController scrollController;
  final String? highlightedPostId;

  const StarsOfTheDaySection({
    super.key,
    required this.isLoading,
    required this.starPosts,
    required this.onSearchChanged,
    required this.onSearchToggled,
    required this.scrollController,
    this.highlightedPostId,
  });

  @override
  State<StarsOfTheDaySection> createState() => _StarsOfTheDaySectionState();
}

class _StarsOfTheDaySectionState extends State<StarsOfTheDaySection> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchVisible = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch(bool isVisible) {
    setState(() => _isSearchVisible = isVisible);
    widget.onSearchToggled(isVisible);
    if (!isVisible) {
      _searchController.clear();
      widget.onSearchChanged('');
    }
  }

  Widget _buildSearchOrHeader() {
    if (_isSearchVisible) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15.0),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: widget.onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Rondera post y\'umuntu...',
            prefixIcon: const Icon(Icons.search, color: Colors.white70),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () => _toggleSearch(false),
            ),
            filled: true,
            fillColor: Colors.blueGrey[800],
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30.0),
                borderSide: BorderSide.none),
            contentPadding: EdgeInsets.zero,
            hintStyle: const TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
        ),
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('📰 Inkuru Rusangi',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 24),
            onPressed: () => _toggleSearch(true),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionHeader(title: '🌟 Stars of the Day'),
        const SizedBox(height: 10),
        SizedBox(
          height: 70,
          child: widget.isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : ListView.builder(
                  controller: widget.scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  itemBuilder: (context, index) {
                    if (index < widget.starPosts.length) {
                      final starData = widget.starPosts[index];
                      final postImageUrl =
                          starData[DatabaseHelper.colUserImageUrl] as String?;
                      final username =
                          starData[DatabaseHelper.colUserName] as String?;
                      final bool isHighlighted =
                          widget.highlightedPostId ==
                              starData[DatabaseHelper.colPostId];

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) =>
                                StarPostDetailScreen(postData: starData),
                          ));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            padding: const EdgeInsets.all(2.0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: isHighlighted
                                  ? Border.all(
                                      color: Colors.amber.shade300, width: 2.5)
                                  : null,
                              boxShadow: isHighlighted
                                  ? [
                                      BoxShadow(
                                        color: Colors.amber.withOpacity(0.7),
                                        blurRadius: 10.0,
                                        spreadRadius: 2.0,
                                      )
                                    ]
                                  : [],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: Colors.blueGrey.shade700,
                                  backgroundImage: (postImageUrl != null &&
                                          postImageUrl.isNotEmpty)
                                      ? NetworkImage(postImageUrl)
                                      : null,
                                  child: (postImageUrl == null ||
                                          postImageUrl.isEmpty)
                                      ? const Icon(Icons.person,
                                          color: Colors.white54)
                                      : null,
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    username ?? 'Unknown',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white70),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    } else {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: Colors.blueGrey.shade800,
                              child: const Icon(Icons.star_border,
                                  color: Colors.white24, size: 28),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 60,
                              child: Text('',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white70)),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
        ),
        const SizedBox(height: 4),
        _buildSearchOrHeader(),
      ],
    );
  }
}