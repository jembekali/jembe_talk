// lib/tangaza_star/feed_manager.dart (VERSION IKOSOYE VYOSE)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import '../services/database_helper.dart';

class FeedManager with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  DocumentSnapshot? _lastDocument;
  bool _hasMorePosts = true;
  
  final Map<String, VideoPlayerController> _videoControllers = {};
  int _currentPage = 0;
  static const int _preloadNextCount = 2;
  static const int _keepBehindCount = 3;

  final Map<String, StreamSubscription> _postSubscriptions = {};

  List<Map<String, dynamic>> get posts => _posts;
  bool get isLoading => _isLoading;
  bool get isFetchingMore => _isFetchingMore;

  FeedManager() {
    refreshFeed();
  }

  void setCurrentPage(int page) {
    if (page == _currentPage) return;
    _currentPage = page;
    _manageVideoControllers();
  }
  
  String? _getOptimizedUrl(String? originalUrl, {required bool forVideoPlayer}) {
    if (originalUrl == null || originalUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(originalUrl);
      String path = uri.path;
      String encodedFileName = path.split('%2F').last;
      String originalFileName = Uri.decodeComponent(encodedFileName);

      if (originalFileName.startsWith('optimized_') || originalFileName.startsWith('thumb_')) {
        if (forVideoPlayer && originalFileName.startsWith('thumb_')) {
          return originalUrl.replaceFirst('thumb_', 'optimized_').replaceFirst('.jpg', '.mp4');
        }
        return originalUrl;
      }

      String baseName = originalFileName.contains('.') ? originalFileName.substring(0, originalFileName.lastIndexOf('.')) : originalFileName;
      
      String newPrefix = forVideoPlayer ? 'optimized_' : 'thumb_';
      String newExtension = forVideoPlayer ? 'mp4' : 'jpg';
      
      String newFileName = '$newPrefix$baseName.$newExtension';
      String encodedNewFileName = Uri.encodeComponent(newFileName);
      
      return originalUrl.replaceAll(encodedFileName, encodedNewFileName);
    } catch (e) {
      debugPrint("Ikosa ryo guhimba URL nshya ($originalUrl): $e");
      return originalUrl;
    }
  }

  void _manageVideoControllers() {
    final allPostIds = _posts.map((p) => p[DatabaseHelper.colPostId] as String).toList();
    final Set<String> idsToKeep = {};

    for (int i = 0; i <= _preloadNextCount; i++) {
      int indexToPreload = _currentPage + i;
      if (indexToPreload < allPostIds.length) {
        final postId = allPostIds[indexToPreload];
        idsToKeep.add(postId);
        _preloadControllerFor(postId);
      }
    }

    for (int i = 1; i <= _keepBehindCount; i++) {
      int indexToKeep = _currentPage - i;
      if (indexToKeep >= 0) {
        idsToKeep.add(allPostIds[indexToKeep]);
      }
    }

    final Set<String> currentControllers = _videoControllers.keys.toSet();
    final Set<String> controllersToRemove = currentControllers.difference(idsToKeep);

    for (var postId in controllersToRemove) {
      _videoControllers[postId]?.dispose();
      _videoControllers.remove(postId);
      debugPrint("Video Controller ya $postId yasivye.");
    }
  }

  void _preloadControllerFor(String postId) {
    if (_videoControllers.containsKey(postId)) return;

    final postIndex = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (postIndex == -1) return;

    final post = _posts[postIndex];
    final originalVideoUrl = post[DatabaseHelper.colVideoUrl] as String?;
    final videoUrl = _getOptimizedUrl(originalVideoUrl, forVideoPlayer: true);

    if (videoUrl != null && videoUrl.isNotEmpty) {
      debugPrint("Ndiko ndategura video ya: $postId kuri URL: $videoUrl");
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _videoControllers[postId] = controller;
      controller.initialize().then((_) {
        controller.setVolume(0);
      }).catchError((e) {
        debugPrint("Kunanirwa gutegura video $postId: $e");
        _videoControllers.remove(postId);
      });
    }
  }
  
  VideoPlayerController? getPreloadedControllerFor(String postId) {
    return _videoControllers[postId];
  }

  Future<void> refreshFeed() async {
    _isLoading = true;
    _posts = [];
    _lastDocument = null;
    _hasMorePosts = true;
    _cancelAllSubscriptions();
    _cancelAllVideoControllers();
    notifyListeners();

    try {
      // Intambwe ya 1: Gukurura amaposita abiri ya mbere
      final hotPostsQuery = _firestore.collection('posts').orderBy('hotScore', descending: true).limit(2);
      final snapshot = await hotPostsQuery.get();
      List<Map<String, dynamic>> initialPosts = [];

      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        initialPosts = await _processPostDocs(snapshot.docs);
        _posts = initialPosts;
        _listenToPostChanges(initialPosts);
        _manageVideoControllers();
        notifyListeners(); // Twerekana amaposita abiri ya mbere ako kanya
      }
      
      // Intambwe ya 2: Gukurura "For You Feed" yose
      final fullFeedPosts = await _fetchFullFeed();
      
      // Intambwe ya 3: Guhuza amaposita yose
      if (fullFeedPosts.isNotEmpty) {
        final existingPostIds = _posts.map((p) => p[DatabaseHelper.colPostId]).toSet();
        final uniqueNewPosts = fullFeedPosts.where((p) => !existingPostIds.contains(p[DatabaseHelper.colPostId])).toList();
        
        _posts.addAll(uniqueNewPosts);
        _listenToPostChanges(uniqueNewPosts);
        _manageVideoControllers();

        // <--- IKI NI CO GICE CAHINDUTSE --->
        // Uwu murongo uca umenyesha UI ko urutonde rwose rwuzuye kandi ruhari.
        notifyListeners(); 
      }

    } catch (e) {
      debugPrint("Ikosa mu gutanguza feed: $e");
    } finally {
      _isLoading = false;
      notifyListeners(); // Tumyesha UI bundi bushya n'urutonde rwose
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFullFeed() async {
    if (_isFetchingMore || !_hasMorePosts) return [];
    _isFetchingMore = true;

    try {
      final callable = _functions.httpsCallable('getForYouFeed');
      final result = await callable.call();
      final List<dynamic> postsFromServer = result.data as List<dynamic>;

      if (postsFromServer.isNotEmpty) {
        return await _processRawPosts(postsFromServer);
      }
    } catch (e) {
      debugPrint("Ikosa ryo gukurura feed yose: $e");
    } finally {
      _isFetchingMore = false;
    }
    return [];
  }
  
  Future<void> fetchMorePosts() async {
    if (_isFetchingMore || !_hasMorePosts) {
      return;
    }

    _isFetchingMore = true;
    notifyListeners();

    try {
      Query query = _firestore.collection('posts').orderBy('hotScore', descending: true);
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }
      final snapshot = await query.limit(5).get();

      if (snapshot.docs.isEmpty) {
        _hasMorePosts = false;
      } else {
        _lastDocument = snapshot.docs.last;
        final morePosts = await _processPostDocs(snapshot.docs);
        _posts.addAll(morePosts);
        _listenToPostChanges(morePosts);
        _manageVideoControllers();
      }
    } catch (e) {
      debugPrint("Ikosa mu telecharga andi maposita: $e");
    } finally {
      _isFetchingMore = false;
      notifyListeners();
    }
  }
  
  void _listenToPostChanges(List<Map<String, dynamic>> postsToListen) {
    for (var post in postsToListen) {
      final postId = post[DatabaseHelper.colPostId] as String;
      if (_postSubscriptions.containsKey(postId)) continue;
      
      final subscription = _firestore.collection('posts').doc(postId).snapshots().listen((snapshot) {
        if (snapshot.exists) {
          _updatePostData(postId, snapshot.data()!);
        } else {
          _removePost(postId);
        }
      });
      _postSubscriptions[postId] = subscription;
    }
  }

  void _updatePostData(String postId, Map<String, dynamic> newData) {
    final postIndex = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (postIndex != -1) {
      _posts[postIndex][DatabaseHelper.colLikes] = newData['likes'] ?? _posts[postIndex][DatabaseHelper.colLikes];
      _posts[postIndex][DatabaseHelper.colCommentsCount] = newData['commentsCount'] ?? _posts[postIndex][DatabaseHelper.colCommentsCount];
      notifyListeners();
    }
  }

  void _removePost(String postId) {
    final postIndex = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (postIndex != -1) {
      _posts.removeAt(postIndex);
      _postSubscriptions.remove(postId)?.cancel();
      _videoControllers.remove(postId)?.dispose();
      notifyListeners();
    }
  }

  void toggleLikeStatus(String postId) {
    if (currentUserId == null) return;
    final postIndex = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (postIndex == -1) return;
    final post = _posts[postIndex];
    final bool isCurrentlyLiked = post[DatabaseHelper.colIsLikedByMe] ?? false;
    post[DatabaseHelper.colIsLikedByMe] = !isCurrentlyLiked;
    post[DatabaseHelper.colLikes] = (post[DatabaseHelper.colLikes] ?? 0) + (isCurrentlyLiked ? -1 : 1);
    notifyListeners();
    _firestore.collection('posts').doc(postId).update({
      'likes': FieldValue.increment(isCurrentlyLiked ? -1 : 1),
      'likedBy': isCurrentlyLiked ? FieldValue.arrayRemove([currentUserId]) : FieldValue.arrayUnion([currentUserId]),
    }).catchError((e) {
      debugPrint("Ikosa ryo guhindura like kuri server: $e");
      post[DatabaseHelper.colIsLikedByMe] = isCurrentlyLiked;
      post[DatabaseHelper.colLikes] = (post[DatabaseHelper.colLikes] ?? 0) - (isCurrentlyLiked ? -1 : 1);
      notifyListeners();
    });
    if (!isCurrentlyLiked) {
      _firestore.collection('user_likes').add({'userId': currentUserId, 'postId': postId});
    }
  }

  void _cancelAllSubscriptions() {
    _postSubscriptions.forEach((key, subscription) {
      subscription.cancel();
    });
    _postSubscriptions.clear();
  }
  
  void _cancelAllVideoControllers() {
    _videoControllers.forEach((key, controller) {
      controller.dispose();
    });
    _videoControllers.clear();
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    _cancelAllVideoControllers();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _processPostDocs(List<QueryDocumentSnapshot> docs) async {
    final List<Future<Map<String, dynamic>>> postFutures = docs.map((doc) async {
      final postData = doc.data() as Map<String, dynamic>;
      final postId = doc.id;
      if (postData['commentsCount'] == null) {
        final commentsSnapshot = await _firestore.collection('posts').doc(postId).collection('comments').get();
        postData['commentsCount'] = commentsSnapshot.size;
      }
      return {'id': postId, ...postData};
    }).toList();
    final rawPosts = await Future.wait(postFutures);
    return _processRawPosts(rawPosts);
  }

  Future<List<Map<String, dynamic>>> _processRawPosts(List<dynamic> rawPosts) async {
    final userIds = rawPosts.map((post) => post['userId'] as String?).where((id) => id != null).toSet().toList();
    Map<String, dynamic> usersMap = {};
    if (userIds.isNotEmpty) {
      final usersSnapshot = await _firestore.collection('users').where(FieldPath.documentId, whereIn: userIds).get();
      usersMap = {for (var doc in usersSnapshot.docs) doc.id: doc.data()};
    }
    return rawPosts.map<Map<String, dynamic>>((postData) {
      final authorId = postData['userId'] as String?;
      final authorData = usersMap[authorId];
      final likedByList = List<String>.from(postData['likedBy'] ?? []);
      
      final dynamic rawTimestamp = postData['timestamp'];
      Timestamp? timestamp;
      if (rawTimestamp is Map) {
        final seconds = rawTimestamp['_seconds'] as int?;
        final nanoseconds = rawTimestamp['_nanoseconds'] as int?;
        if (seconds != null && nanoseconds != null) {
          timestamp = Timestamp(seconds, nanoseconds);
        }
      } else if (rawTimestamp is Timestamp) {
        timestamp = rawTimestamp;
      }

      return {
        DatabaseHelper.colPostId: postData['id'], 
        DatabaseHelper.colText: postData['content'], 
        DatabaseHelper.colUserId: postData['userId'],
        'timestamp_server': timestamp,
        DatabaseHelper.colLikes: postData['likes'] ?? 0,
        DatabaseHelper.colCommentsCount: postData['commentsCount'] ?? 0, 
        DatabaseHelper.colViews: postData['views'] ?? 0,
        DatabaseHelper.colIsStar: postData['isStar'] ?? false,
        DatabaseHelper.colUserName: authorData?['displayName'] ?? 'Ata Zina', 
        DatabaseHelper.colUserImageUrl: authorData?['photoUrl'],
        DatabaseHelper.colIsLikedByMe: likedByList.contains(currentUserId),
        DatabaseHelper.colImageUrl: postData['imageUrl'], 
        DatabaseHelper.colVideoUrl: postData['videoUrl'],
      };
    }).toList();
  }
}