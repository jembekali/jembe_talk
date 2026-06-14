import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_helper.dart';
import '../services/r2_service.dart';

// Isolate processing kugeza kuri JSON kugira ngo UI itigera ifreeze
List<Map<String, dynamic>> _processRawPostsStatic(List<dynamic> rawPosts) {
  return rawPosts.map<Map<String, dynamic>>((p) {
    final data = Map<String, dynamic>.from(p as Map);
    return {
      'postId': data['id'] ?? '',
      'title': data['title'] ?? '',
      'text': data['content'] ?? data['text'] ?? '',
      'userId': data['userId'] ?? '',
      'likes': data['likes'] ?? 0,
      'commentsCount': data['commentsCount'] ?? 0,
      'views': data['views'] ?? 0,
      'userName': data['authorName'] ?? 'Star',
      'userImageUrl': data['authorPhotoUrl'] ?? data['photoUrl'],
      'isLikedByMe': false,
      'imageUrl': data['imageUrl'],
      'thumbnailUrl': data['thumbnailUrl'],
      'networkVideoUrl': data['videoUrl'],
      'timestamp': data['timestamp'] is int
          ? data['timestamp']
          : ((data['timestamp'] is Map)
              ? (data['timestamp']['_seconds'] ?? 0) * 1000
              : DateTime.now().millisecondsSinceEpoch),
    };
  }).toList();
}

class FeedManager with ChangeNotifier {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

  static const int batchSize = 25;
  static const int triggerThreshold = 10;
  static const int maxPostsInList = 60; // Kurinda RAM Overflow

  List<Map<String, dynamic>> _posts = [];
  final Set<String> _seenPostIds = {};

  bool _isLoading = false;
  bool _isFetchingMore = false;

  final Map<String, CachedVideoPlayerPlusController> _controllers = {};
  final Set<String> _initializingIds = {};
  String? _activePostId;

  List<Map<String, dynamic>> _cachedStars = [];
  Timer? _scrollDelayTimer;
  int _currentIndex = 0;

  Duration _lastPosition = Duration.zero;
  int _stallCount = 0;

  // GETTERS
  List<Map<String, dynamic>> get posts => _posts;
  bool get isLoading => _isLoading;
  bool get isFetchingMore => _isFetchingMore;
  String? get activePostId => _activePostId;
  List<Map<String, dynamic>> get cachedStars => _cachedStars;
  CachedVideoPlayerPlusController? get activeController =>
      _controllers[_activePostId];

  void setCachedStars(List<Map<String, dynamic>> stars) {
    _cachedStars = stars;
    notifyListeners();
  }

  // 1. FRESHNESS LOGIC: Siba amakuru ashaje (24h) mu rutonde
  void _enforceLiveFreshness() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int twentyFourHours = 24 * 60 * 60 * 1000;

    _posts.removeWhere((p) {
      final ts = p['timestamp'];
      if (ts is int && (now - ts) > twentyFourHours) {
        final id = p['postId'];
        if (_controllers.containsKey(id)) {
          _controllers[id]?.dispose();
          _controllers.remove(id);
        }
        return true; // Post ihita isibwa kuko imaze amasaha 24
      }
      return false;
    });
  }

  // 2. DATA FLOW (APPEND LOGIC)
  Future<void> refreshFeed() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    await _loadSeenHistory();

    try {
      if (_posts.isEmpty) {
        final cachedPosts = await DatabaseHelper.instance.getCachedFivePosts();
        if (cachedPosts.isNotEmpty) {
          _posts = List.from(cachedPosts);
          _enforceLiveFreshness(); // Isuku rya cache
          if (_posts.isNotEmpty) {
            _activePostId = _posts[0][DatabaseHelper.colPostId];
            _currentIndex = 0;
            notifyListeners();
            Future.delayed(const Duration(milliseconds: 300), () {
              if (_activePostId != null)
                _initController(_activePostId!,
                    shouldPlay: true, priority: true);
            });
          }
        }
      }

      final result = await _functions
          .httpsCallable('getForYouFeed')
          .call({'seenIds': _seenPostIds.toList(), 'limit': batchSize});

      if (result.data != null) {
        final List<Map<String, dynamic>> onlinePosts =
            await compute(_processRawPostsStatic, result.data as List);
        for (var p in onlinePosts) {
          p['isLikedByMe'] = (p['likedBy'] ?? []).contains(currentUserId);
        }

        if (onlinePosts.isNotEmpty) {
          if (_posts.isEmpty) {
            _posts = onlinePosts;
            _activePostId = _posts[0]['postId'];
            _currentIndex = 0;
            _initController(_activePostId!, shouldPlay: true, priority: true);
          } else {
            // APPEND: Zishyire inyuma (Munsi ya post ya 5 cyangwa aho ari)
            final currentIds = _posts.map((p) => p['postId']).toSet();
            final List<Map<String, dynamic>> uniqueNewPosts = onlinePosts
                .where((p) => !currentIds.contains(p['postId']))
                .toList();
            if (uniqueNewPosts.isNotEmpty) {
              _posts.addAll(uniqueNewPosts);
            }
          }
          _prefetchStarterMedia(onlinePosts.take(3).toList());
        }
      }
    } catch (e) {
      debugPrint("Feed Error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _prefetchStarterMedia(List<Map<String, dynamic>> topPosts) {
    for (var post in topPosts) {
      final String? imageUrl = post['imageUrl'];
      if (imageUrl != null && imageUrl.isNotEmpty) {
        DefaultCacheManager().downloadFile(_formatCloudUrl(imageUrl));
      }
    }
  }

  // 3. PIPELINE & RAM MANAGEMENT
  void setCurrentPage(int index) {
    if (index < 0 || index >= _posts.length) return;

    // Isuku ya buri gihe umukoresha ascrollye
    _enforceLiveFreshness();
    if (index >= _posts.length) index = _posts.length - 1;

    _currentIndex = index;
    final String newPostId = _posts[index][DatabaseHelper.colPostId];
    if (_activePostId == newPostId) return;

    _activePostId = newPostId;
    _controllers.forEach((id, c) {
      if (id != newPostId && c.value.isPlaying) c.pause();
    });

    _updateOfflineStarterPack(index);

    // RAM Pruning: Siba izo wasize inyuma cyane niba posts zarenze 60
    if (_posts.length > maxPostsInList && index > 20) {
      _posts.removeRange(0, 10);
      _currentIndex -= 10;
    }

    _scrollDelayTimer?.cancel();
    _scrollDelayTimer = Timer(const Duration(milliseconds: 200),
        () => _managePipeline(_currentIndex));

    if (_currentIndex >= _posts.length - triggerThreshold) _fetchBatch();
    notifyListeners();
  }

  void _managePipeline(int index) async {
    if (_activePostId == null) return;
    await _initController(_activePostId!, shouldPlay: true, priority: true);

    Future.delayed(const Duration(milliseconds: 400), () {
      final Set<String> activeWindow = {_activePostId!};
      for (int i = index + 1; i < _posts.length && i <= index + 2; i++) {
        final String nextId = _posts[i][DatabaseHelper.colPostId];
        activeWindow.add(nextId);
        _initController(nextId, shouldPlay: false, priority: false);
      }
      if (index > 0) {
        final String prevId = _posts[index - 1][DatabaseHelper.colPostId];
        activeWindow.add(prevId);
        _initController(prevId, shouldPlay: false, priority: false);
      }
      _controllers.removeWhere((id, controller) {
        if (!activeWindow.contains(id)) {
          controller.dispose();
          return true;
        }
        return false;
      });
    });
  }

  Future<void> _initController(String postId,
      {required bool shouldPlay, required bool priority}) async {
    if (_controllers.containsKey(postId)) {
      final c = _controllers[postId]!;
      if (shouldPlay && _activePostId == postId && !c.value.isPlaying) {
        await c.play();
        WakelockPlus.enable();
      }
      return;
    }
    if (_initializingIds.contains(postId)) return;
    final post =
        _posts.firstWhere((p) => p['postId'] == postId, orElse: () => {});
    if (post['networkVideoUrl'] == null) return;

    _initializingIds.add(postId);
    try {
      final controller = CachedVideoPlayerPlusController.networkUrl(
        Uri.parse(_formatCloudUrl(post['networkVideoUrl'])),
        httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey},
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      if (!priority) await Future.delayed(const Duration(milliseconds: 250));
      await controller.initialize();

      if (_activePostId == postId) {
        controller.setLooping(true);
        controller.addListener(_videoListener);
        _controllers[postId] = controller;
        if (shouldPlay) {
          await controller.play();
          WakelockPlus.enable();
        }
      } else {
        final int pIndex = _posts.indexWhere((p) => p['postId'] == postId);
        if ([_currentIndex - 1, _currentIndex + 1, _currentIndex + 2]
            .contains(pIndex)) {
          controller.setLooping(true);
          controller.addListener(_videoListener);
          _controllers[postId] = controller;
        } else {
          await controller.dispose();
        }
      }
      _initializingIds.remove(postId);
      notifyListeners();
    } catch (e) {
      _initializingIds.remove(postId);
      debugPrint("Init Error (Dead link likely): $e");
    }
  }

  void _videoListener() {
    final c = activeController;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      if (c.value.position == _lastPosition && !c.value.isBuffering) {
        _stallCount++;
        if (_stallCount > 15) {
          c.play();
          _stallCount = 0;
        }
      } else {
        _stallCount = 0;
        _lastPosition = c.value.position;
      }
    }
  }

  // 4. USER ACTIONS & RTDB SYNC
  void togglePlayback() {
    final c = activeController;
    if (c != null && c.value.isInitialized) {
      if (c.value.isPlaying) {
        c.pause();
        WakelockPlus.disable();
      } else {
        c.play();
        WakelockPlus.enable();
      }
      notifyListeners();
    }
  }

  void pauseAll() {
    _controllers.forEach((_, c) {
      if (c.value.isPlaying) c.pause();
    });
    WakelockPlus.disable();
    notifyListeners();
  }

  void resumeActive() {
    if (_activePostId != null && _controllers.containsKey(_activePostId)) {
      if (!_controllers[_activePostId]!.value.isPlaying) {
        _controllers[_activePostId]!.play();
        WakelockPlus.enable();
      }
    }
    notifyListeners();
  }

  void toggleLikeStatus(String postId) {
    final i = _posts.indexWhere((p) => p['postId'] == postId);
    if (i == -1 || currentUserId == null) return;
    final bool isLiked = _posts[i]['isLikedByMe'] ?? false;
    final int diff = isLiked ? -1 : 1;
    final String authorId = _posts[i]['userId'] ?? "";

    _posts[i]['isLikedByMe'] = !isLiked;
    _posts[i]['likes'] = (_posts[i]['likes'] ?? 0) + diff;
    notifyListeners();

    _rtdb.ref("counters/$postId/likes").set(ServerValue.increment(diff));
    if (isLiked)
      _rtdb.ref("user_likes/$currentUserId/$postId").remove();
    else
      _rtdb.ref("user_likes/$currentUserId/$postId").set(true);

    if (authorId.isNotEmpty) {
      _rtdb
          .ref("user_stats/$authorId/totalLikes")
          .set(ServerValue.increment(diff));
    }
  }

  void markPostAsViewed(String postId) {
    final i = _posts.indexWhere((p) => p['postId'] == postId);
    if (i != -1) {
      _posts[i]['views'] = (_posts[i]['views'] ?? 0) + 1;
      notifyListeners();
    }
    _rtdb.ref("counters/$postId/views").set(ServerValue.increment(1));
    _saveSeenId(postId);
  }

  Future<void> _fetchBatch() async {
    if (_isFetchingMore) return;
    _isFetchingMore = true;
    notifyListeners();
    try {
      final result = await _functions
          .httpsCallable('getForYouFeed')
          .call({'seenIds': _seenPostIds.toList(), 'limit': batchSize});
      if (result.data != null) {
        final onlinePosts =
            await compute(_processRawPostsStatic, result.data as List);
        final currentIds = _posts.map((p) => p['postId']).toSet();
        for (var p in onlinePosts) {
          if (!currentIds.contains(p['postId'])) _posts.add(p);
        }
        notifyListeners();
      }
    } catch (_) {
    } finally {
      _isFetchingMore = false;
      notifyListeners();
    }
  }

  String _formatCloudUrl(String url) {
    if (url.isEmpty || !url.startsWith('http') || url.contains('auth='))
      return url;
    return "${R2Service.workerUrl}${Uri.parse(url).path}?auth=${R2Service.workerSecretKey}";
  }

  void _updateOfflineStarterPack(int index) async {
    final List<Map<String, dynamic>> pack = [];
    for (int i = index; i < _posts.length && pack.length < 5; i++)
      pack.add(_posts[i]);
    if (pack.isNotEmpty) await DatabaseHelper.instance.saveTopFivePosts(pack);
  }

  Future<void> _loadSeenHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? saved = prefs.getStringList('seen_posts_v4');
    if (saved != null) _seenPostIds.addAll(saved);
  }

  Future<void> _saveSeenId(String postId) async {
    if (_seenPostIds.contains(postId)) return;
    _seenPostIds.add(postId);
    if (_seenPostIds.length > 1000) _seenPostIds.remove(_seenPostIds.first);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('seen_posts_v4', _seenPostIds.toList());
  }

  void updateCommentCount(String postId, int newCount) {
    final i = _posts.indexWhere((p) => p['postId'] == postId);
    if (i != -1) {
      _posts[i]['commentsCount'] = newCount;
      notifyListeners();
    }
  }

  void forceCleanup() {
    _controllers.removeWhere((id, c) {
      if (id != _activePostId) {
        c.dispose();
        return true;
      }
      return false;
    });
    _initializingIds.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _scrollDelayTimer?.cancel();
    _controllers.forEach((_, c) => c.dispose());
    super.dispose();
  }
}
