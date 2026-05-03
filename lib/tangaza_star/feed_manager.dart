import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; 

import '../services/database_helper.dart';
import '../services/r2_service.dart';
import '../services/feed_cache_manager.dart'; 

class FeedManager with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

  String get workerUrl => R2Service.workerUrl;
  String get secretKey => R2Service.workerSecretKey;

  static const int batchSize = 30; 
  static const int triggerThreshold = 10; 

  List<Map<String, dynamic>> _posts = [];
  final List<String> _seenPostIds = []; 
  
  bool _isLoading = true; 
  bool _isFetchingMore = false;
  int _currentPage = 0;

  CachedVideoPlayerPlusController? _activeController;
  String? _activePostId;

  List<Map<String, dynamic>> get posts => _posts;
  bool get isLoading => _isLoading;
  String? get activePostId => _activePostId;

  @override 
  void notifyListeners() { if (hasListeners) super.notifyListeners(); }

  Future<void> refreshFeed() async {
    _disposeActiveController();
    try {
      final cachedRaw = await DatabaseHelper.instance.getStealthPosts();
      if (cachedRaw.isNotEmpty) {
        _posts = _processDbPosts(cachedRaw);
        notifyListeners(); 
      }
    } catch (_) {}

    _isLoading = true; 
    notifyListeners();

    try {
      await _fetchBatch(isRefresh: true);
    } catch (e) {
      debugPrint("⚠️ Network Error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchBatch({bool isRefresh = false}) async {
    if (_isFetchingMore) return;
    _isFetchingMore = true;

    try {
      final result = await _functions.httpsCallable('getForYouFeed').call({
        'seenIds': isRefresh ? [] : _seenPostIds,
        'limit': batchSize
      });

      if (result.data != null && result.data is List) {
        final List<Map<String, dynamic>> cloudPosts = _processRawPosts(result.data as List);

        if (isRefresh) {
          _posts = cloudPosts;
          _seenPostIds.clear();
          await DatabaseHelper.instance.clearAllStealthPosts(); 
          for (var p in cloudPosts.take(15)) {
            await DatabaseHelper.instance.saveStealthPost(
              postId: p[DatabaseHelper.colPostId],
              postDataJson: jsonEncode(p),
              localPath: "" 
            );
          }
        } else {
          for (var p in cloudPosts) {
            if (!_posts.any((x) => x[DatabaseHelper.colPostId] == p[DatabaseHelper.colPostId])) {
              _posts.add(p);
            }
          }
        }

        for (var p in cloudPosts) {
          if (!_seenPostIds.contains(p[DatabaseHelper.colPostId])) {
            _seenPostIds.add(p[DatabaseHelper.colPostId]);
          }
        }
      }
    } catch (e) {
      debugPrint("Fetch batch error: $e");
    } finally {
      _isFetchingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadTargetPostThenFeed(String targetPostId) async {
    _isLoading = true; 
    _disposeActiveController(); 
    _posts.clear(); 
    _seenPostIds.clear();
    notifyListeners();

    try {
      final doc = await _firestore.collection('posts').doc(targetPostId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _posts = _processRawPosts([{...data, 'id': doc.id}]);
        _seenPostIds.add(doc.id);
        _isLoading = false;
        notifyListeners();
      }
      await _fetchBatch(isRefresh: false);
    } catch (e) { 
      await refreshFeed(); 
    } finally { 
      _isLoading = false; 
      notifyListeners(); 
    }
  }

  void setCurrentPage(int index) {
    if (index < 0 || index >= _posts.length) return;
    // Niba page ihindutse, hagarika buri kantu kose (Hard Stop)
    if (_currentPage != index) {
      _disposeActiveController();
    }
    _currentPage = index;
    if (index >= _posts.length - triggerThreshold) { _fetchBatch(); }
    notifyListeners();
  }

  Future<void> initializeAndPlayVideo(String postId) async {
    // 1. Niba isanzwe ivuga, hagarara
    if (_activePostId == postId && _activeController != null) return;
    
    // 2. Hagarika indi yari iriho (dispose)
    _disposeActiveController();
    
    final postIndex = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (postIndex == -1) return;
    
    final networkUrl = _posts[postIndex]['networkVideoUrl'] ?? "";
    if (networkUrl.isEmpty) return;
    
    // Bika iyi ID turi gushaka gufungura
    String currentAttemptId = postId;
    _activePostId = postId;
    notifyListeners(); 
    
    try {
      String finalUrl = _formatCloudUrl(networkUrl);
      final controller = CachedVideoPlayerPlusController.networkUrl(
        Uri.parse(finalUrl),
        httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey},
      );
      
      // ✅ HARD LOCK: Genzura niba internet imaze kurangiza, ariko tukanareba niba umukoresha 
      // yaba yaramaze kurenga iyi post (currentAttemptId != _activePostId).
      await controller.initialize();

      if (_activePostId != currentAttemptId) {
        debugPrint("DEBUG: User swiped away during loading. Killing controller.");
        controller.pause();
        controller.dispose();
        return; 
      }
      
      controller.setLooping(true);
      controller.play();
      _activeController = controller;
      
      WakelockPlus.enable(); 
      notifyListeners(); 
    } catch (e) { 
      if (_activePostId == currentAttemptId) {
        _activePostId = null;
        WakelockPlus.disable();
        notifyListeners();
      }
    }
  }

  void _disposeActiveController() {
    if (_activeController != null) {
      try {
        _activeController!.pause();
        _activeController!.setVolume(0);
        _activeController!.dispose();
      } catch (e) {
        debugPrint("Dispose error: $e");
      }
      _activeController = null;
      _activePostId = null;
    }
    // Ibi bituma niba hari video yari iri "Loading" nayo imenya ko igomba guhagarara
    _activePostId = null; 
    WakelockPlus.disable();
  }

  void togglePlayback() {
    if (_activeController != null && _activeController!.value.isInitialized) {
      if (_activeController!.value.isPlaying) {
        _activeController!.pause();
        WakelockPlus.disable();
      } else {
        _activeController!.play();
        WakelockPlus.enable();
      }
      notifyListeners();
    }
  }

  void pauseAll() { 
    _disposeActiveController(); // Koresha dispose mu mwanya wa pause gusa (Hard kill)
    notifyListeners(); 
  }

  void clearSession() async { 
    _disposeActiveController(); 
    _seenPostIds.clear(); 
    _currentPage = 0; 
    try {
      await DatabaseHelper.instance.clearAllStealthPosts();
    } catch (_) {}
    _posts.clear(); 
    _isLoading = true; 
    notifyListeners(); 
  }

  CachedVideoPlayerPlusController? get activeController => _activeController;

  List<Map<String, dynamic>> _processDbPosts(List<Map<String, dynamic>> dbData) {
    return dbData.map((c) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(jsonDecode(c[DatabaseHelper.colPostData]));
      return { ...data, DatabaseHelper.colPostId: c[DatabaseHelper.colPostId], 'id': c[DatabaseHelper.colPostId] };
    }).toList();
  }

  List<Map<String, dynamic>> _processRawPosts(List<dynamic> rawPosts) {
    return rawPosts.map<Map<String, dynamic>>((p) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(p as Map);
      final String postId = data['id'] ?? '';
      return {
        DatabaseHelper.colPostId: postId,
        'id': postId,
        'title': data['title'] ?? '',
        DatabaseHelper.colText: data['content'] ?? '',
        DatabaseHelper.colUserId: data['userId'] ?? data['uid'] ?? '',
        DatabaseHelper.colLikes: data['likes'] ?? 0,
        DatabaseHelper.colCommentsCount: data['commentsCount'] ?? 0,
        DatabaseHelper.colViews: data['views'] ?? 0,
        DatabaseHelper.colUserName: data['authorName'] ?? data['displayName'] ?? 'Star',
        DatabaseHelper.colUserImageUrl: data['authorPhotoUrl'] ?? data['photoUrl'],
        DatabaseHelper.colIsLikedByMe: (List<String>.from(data['likedBy'] ?? [])).contains(currentUserId),
        DatabaseHelper.colImageUrl: data['imageUrl'],
        'thumbnailUrl': data['thumbnailUrl'],
        'networkVideoUrl': data['videoUrl'],
        'timestamp': data['timestamp'], // Shows 2h
      };
    }).toList();
  }

  void markPostAsViewed(String postId) {
    final index = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (index != -1) {
      _posts[index][DatabaseHelper.colViews] = (_posts[index][DatabaseHelper.colViews] ?? 0) + 1;
      notifyListeners(); 
    }
    _firestore.collection('posts').doc(postId).update({'views': FieldValue.increment(1)});
  }

  void updateCommentCount(String postId, int newCount) {
    final index = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (index != -1) {
      _posts[index][DatabaseHelper.colCommentsCount] = newCount;
      notifyListeners();
    }
  }

  void toggleLikeStatus(String postId) {
    final index = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (index == -1 || currentUserId == null) return;
    final bool isLiked = _posts[index][DatabaseHelper.colIsLikedByMe] ?? false;
    _posts[index][DatabaseHelper.colIsLikedByMe] = !isLiked;
    _posts[index][DatabaseHelper.colLikes] = (_posts[index][DatabaseHelper.colLikes] ?? 0) + (isLiked ? -1 : 1);
    notifyListeners();
    _firestore.collection('posts').doc(postId).update({
      'likes': FieldValue.increment(isLiked ? -1 : 1), 
      'likedBy': isLiked ? FieldValue.arrayRemove([currentUserId]) : FieldValue.arrayUnion([currentUserId])
    });
  }

  String _formatCloudUrl(String url) {
    if (!url.startsWith('http')) return url;
    if (url.contains('auth=')) return url; 
    final path = Uri.parse(url).path;
    return "${R2Service.workerUrl}$path?auth=${R2Service.workerSecretKey}";
  }

  @override void dispose() { _disposeActiveController(); super.dispose(); }
}