import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

// Services
import 'package:jembe_talk/services/media_processor_service.dart';
import 'package:jembe_talk/widgets/post_media_preview.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/post_service.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'package:jembe_talk/tangaza_star/comment_screen.dart';
import 'package:jembe_talk/tangaza_star/media_editor_view.dart';
import 'package:jembe_talk/tangaza_star/user_profile_screen.dart';
import 'package:jembe_talk/post_translations.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/widgets/post_card.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
import 'package:jembe_talk/chat_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen>
    with TickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _postController = TextEditingController();
  final FocusNode _postFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final ValueNotifier<double> _renderingProgressNotifier = ValueNotifier(0.0);

  bool _isLoadingPosts = true;
  bool _isRendering = false;
  bool _isPickingMedia = false;
  bool _isRendered = false;
  File? _finalMediaFile;
  bool _isPostAreaExpanded = false;

  final Map<String, double> _individualUploadProgress = {};
  final Set<String> _sharingPostIds = {};
  final ImagePicker _picker = ImagePicker();
  XFile? _originalMediaFile;
  String? _mediaType;
  VideoPlayerController? _videoController;
  List<Map<String, dynamic>> _posts = [];

  final _firestore = FirebaseFirestore.instance;
  final _rtdb = FirebaseDatabase.instance;
  final R2Service _r2Service = R2Service();
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final PostService _postService = PostService();

  // MEDIA STATE
  List<MediaTextOverlay> _activeTextOverlays = [];
  double _activeBrightness = 0.0;
  double _activeSaturation = 1.0;
  int _activeRotation = 0;
  double _activeZoom = 1.0;
  Offset _activeOffset = Offset.zero;
  String _activeFilter = "none";
  bool _isMuted = false;
  double _activeStartTrim = 0.0;
  double _activeEndTrim = 1.0;
  double? _activeAspectRatio;
  String? _selectedThumbnailPath;

  final ValueNotifier<List<DocumentSnapshot>> _friendRequestsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> _isScreenActive = ValueNotifier(true);
  StreamSubscription<QuerySnapshot>? _friendRequestsSubscription;

  final List<String> _categories = [
    "General",
    "Gospel",
    "Music",
    "Comedy",
    "News",
    "Sports",
    "Health",
    "Entertainment",
    "Tech",
    "Lifestyle"
  ];
  String _selectedCategory = "General";

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _startListeningToFriendRequests();
    _loadLastUsedCategory();
    _syncFriendsWithLocal();
    _postFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_postFocusNode.hasFocus && _videoController != null) {
      _videoController?.pause();
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _friendRequestsSubscription?.cancel();
    _friendRequestsNotifier.dispose();
    _renderingProgressNotifier.dispose();
    _isScreenActive.dispose();
    _titleController.dispose();
    _postController.dispose();
    _postFocusNode.removeListener(_onFocusChange);
    _postFocusNode.dispose();
    _videoController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- LOGIC METHODS ---

  Future<void> _loadPosts() async {
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      await DatabaseHelper.instance.cleanupOldPosts();
      final postsFromDb = await DatabaseHelper.instance.getPostsByUserId(uid);
      if (mounted) {
        setState(() {
          _posts =
              postsFromDb.map((p) => Map<String, dynamic>.from(p)).toList();
          _isLoadingPosts = false;
        });
        for (var post in _posts) {
          String? pid = post[DatabaseHelper.colPostId];
          if (pid != null) _refreshPostStats(pid);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  // 🔥 UPDATED: STATS ZIKURWA MURI RTDB GUSA
  Future<void> _refreshPostStats(String postId) async {
    try {
      final docSnapshot =
          await _firestore.collection('posts').doc(postId).get();
      if (!docSnapshot.exists) return;
      final fData = docSnapshot.data() ?? {};

      // Soma Likes na Views muri RTDB
      final rtdbSnap = await _rtdb.ref("counters/$postId").get();
      final rData = rtdbSnap.value as Map? ?? {};

      // Soma niba uyu muntu yarayikunze muri RTDB
      final userLikeSnap =
          await _rtdb.ref("user_likes/$_currentUserId/$postId").get();
      final bool isLikedByMe = userLikeSnap.exists;

      final index =
          _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
      if (index != -1 && mounted) {
        setState(() {
          _posts[index][DatabaseHelper.colLikes] = rData['likes'] ?? 0;
          _posts[index][DatabaseHelper.colViews] = rData['views'] ?? 0;
          _posts[index][DatabaseHelper.colCommentsCount] =
              fData['commentsCount'] ?? 0;
          _posts[index][DatabaseHelper.colIsLikedByMe] = isLikedByMe ? 1 : 0;
          _posts[index]['thumbnailUrl'] = fData['thumbnailUrl'];
        });
        await DatabaseHelper.instance.savePost(_posts[index]);
      }
    } catch (e) {}
  }

  Future<void> _syncFriendsWithLocal() async {
    if (_currentUserId == null) return;
    try {
      final snapshot = await _firestore
          .collection('friendships')
          .where('users', arrayContains: _currentUserId)
          .get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final otherId =
            (data['users'] as List).firstWhere((id) => id != _currentUserId);
        final uSnap = await _firestore.collection('users').doc(otherId).get();
        if (uSnap.exists) {
          final uData = uSnap.data()!;
          await DatabaseHelper.instance.saveJembeContact({
            'id': otherId,
            'displayName': uData['displayName'],
            'photoUrl': uData['photoUrl'],
            'status': data['status'],
            'requestedBy': data['requestedBy'],
            'friendshipId': doc.id
          });
        }
      }
    } catch (e) {}
  }

  void _startListeningToFriendRequests() {
    if (_currentUserId == null) return;
    _friendRequestsSubscription = _firestore
        .collection('friendships')
        .where('users', arrayContains: _currentUserId)
        .snapshots()
        .listen((snapshot) {
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        return data['status'] == 'pending' &&
            data['requestedBy'] != _currentUserId;
      }).toList();
      if (mounted) _friendRequestsNotifier.value = filteredDocs;
    });
  }

  // --- ACTIONS ---

  // 🔥 UPDATED: LIKE ZIKANDIKWA MURI RTDB GUSA (EXCLUSIVE)
  Future<void> _handleLike(Map<String, dynamic> post) async {
    if (_currentUserId == null) return;
    HapticFeedback.lightImpact();

    final postId = post[DatabaseHelper.colPostId];
    final authorId = post[DatabaseHelper.colUserId];
    final bool isLiked = (post[DatabaseHelper.colIsLikedByMe] == 1);
    final int diff = isLiked ? -1 : 1;

    setState(() {
      post[DatabaseHelper.colIsLikedByMe] = isLiked ? 0 : 1;
      post[DatabaseHelper.colLikes] =
          (post[DatabaseHelper.colLikes] ?? 0) + diff;
    });

    try {
      // 1. RTDB: Update Like Counter ya post
      _rtdb.ref("counters/$postId/likes").set(ServerValue.increment(diff));

      // 2. RTDB: Update Author Total Stats
      if (authorId != null && authorId.isNotEmpty) {
        _rtdb
            .ref("user_stats/$authorId/totalLikes")
            .set(ServerValue.increment(diff));
      }

      // 3. RTDB: Relationship Tracking
      if (isLiked) {
        await _rtdb.ref("user_likes/$_currentUserId/$postId").remove();
      } else {
        await _rtdb.ref("user_likes/$_currentUserId/$postId").set(true);
      }
    } catch (e) {
      debugPrint("RTDB Like error: $e");
    }
  }

  Future<void> _handleRetryUpload(Map<String, dynamic> post) async {
    final String postId = post[DatabaseHelper.colPostId];
    final String? videoPath = post[DatabaseHelper.colVideoUrl];
    final String? imagePath = post[DatabaseHelper.colImageUrl];
    final String? thumbPath = post[DatabaseHelper.colPostThumbnailLocalPath];
    final String type = videoPath != null ? 'video' : 'image';
    final String? filePath = videoPath ?? imagePath;

    if (filePath == null) return;

    setState(() {
      post[DatabaseHelper.colSyncStatus] = 'uploading';
      _individualUploadProgress[postId] = 0.05;
    });
    await DatabaseHelper.instance.savePost(post);

    _startBackgroundUpload(
        postId,
        File(filePath),
        thumbPath,
        post[DatabaseHelper.colTitle] ?? "",
        post[DatabaseHelper.colText] ?? "",
        {
          'displayName': post[DatabaseHelper.colUserName],
          'photoUrl': post[DatabaseHelper.colUserImageUrl]
        },
        type);
  }

  Future<void> _safeNavigate(Widget destination) async {
    _videoController?.pause();
    WakelockPlus.disable();
    _isScreenActive.value = false;
    await Navigator.push(context, CustomPageRoute(child: destination));
    _isScreenActive.value = true;
    if (_videoController != null &&
        _originalMediaFile != null &&
        !_isRendering) {
      _videoController?.play();
      WakelockPlus.enable();
    }
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    _postFocusNode.unfocus();
    final XFile? file = isVideo
        ? await _picker.pickVideo(source: source)
        : await _picker.pickImage(source: source);

    if (file != null) {
      _clearMedia();
      setState(() {
        _isPickingMedia = true;
        _originalMediaFile = file;
        _mediaType = isVideo ? 'video' : 'image';
        _isPostAreaExpanded = true;
      });

      await Future.delayed(const Duration(milliseconds: 50));

      if (isVideo) {
        try {
          final thumb = await MediaProcessorService.createCompressedThumbnail(
              File(file.path), 'video');
          if (mounted) setState(() => _selectedThumbnailPath = thumb);

          _videoController = VideoPlayerController.file(File(file.path));
          await _videoController!.initialize();
          _videoController!.setLooping(true);

          if (!_postFocusNode.hasFocus) {
            _videoController!.play();
            WakelockPlus.enable();
          }

          if (mounted) setState(() => _isPickingMedia = false);
        } catch (e) {
          if (mounted) setState(() => _isPickingMedia = false);
        }
      } else {
        setState(() => _isPickingMedia = false);
      }
    }
  }

  void _clearMedia() {
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    WakelockPlus.disable();
    MediaProcessorService.clearFFmpegCache();

    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    setState(() {
      _originalMediaFile = null;
      _mediaType = null;
      _isRendered = false;
      _isRendering = false;
      _isPickingMedia = false;
      _finalMediaFile = null;
      _activeTextOverlays = [];
      _selectedThumbnailPath = null;
      _activeBrightness = 0.0;
      _activeSaturation = 1.0;
      _activeFilter = "none";
      _activeRotation = 0;
      _activeZoom = 1.0;
      _activeOffset = Offset.zero;
      _activeStartTrim = 0.0;
      _activeEndTrim = 1.0;
      _activeAspectRatio = null;
    });
    _renderingProgressNotifier.value = 0.0;
  }

  Future<void> _editMedia() async {
    if (_originalMediaFile == null) return;

    if (_mediaType == 'video') {
      _videoController?.pause();
      WakelockPlus.disable();
      final dynamic result = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => MediaEditorView(
                    file: File(_originalMediaFile!.path),
                    type: 'video',
                    initialOverlays: _activeTextOverlays,
                    initialBrightness: _activeBrightness,
                    initialSaturation: _activeSaturation,
                    initialRotation: _activeRotation,
                    initialZoom: _activeZoom,
                    initialOffset: _activeOffset,
                    initialFilter: _activeFilter,
                    initialMute: _isMuted,
                    initialStart: _activeStartTrim,
                    initialEnd: _activeEndTrim,
                  ),
              fullscreenDialog: true));
      if (result != null && result is Map && mounted) {
        setState(() {
          _activeTextOverlays =
              List<MediaTextOverlay>.from(result['overlays'] ?? []);
          _activeBrightness = result['brightness'] ?? 0.0;
          _activeSaturation = result['saturation'] ?? 1.0;
          _activeRotation = result['rotation'] ?? 0;
          _activeZoom = result['zoom'] ?? 1.0;
          _activeOffset = result['offset'] ?? Offset.zero;
          _activeFilter = result['filter'] ?? "none";
          _isMuted = result['isMuted'] ?? false;
          _activeStartTrim = result['startTrim'] ?? 0.0;
          _activeEndTrim = result['endTrim'] ?? 1.0;
          _activeAspectRatio = result['aspectRatio'];
          _selectedThumbnailPath = result['thumbnail'];
          _isRendered = false;
        });
        _videoController?.setVolume(_isMuted ? 0.0 : 1.0);
        _videoController
            ?.seekTo(_videoController!.value.duration * _activeStartTrim);
        if (!_postFocusNode.hasFocus) _videoController?.play();
        WakelockPlus.enable();
      } else {
        if (!_postFocusNode.hasFocus) _videoController?.play();
        WakelockPlus.enable();
      }
    } else {
      final bytes = await File(_originalMediaFile!.path).readAsBytes();
      final edited = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageEditor(
              image: bytes,
            ),
          ));

      if (edited != null && mounted) {
        final tempDir = await getTemporaryDirectory();
        final file = await File(
                '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg')
            .writeAsBytes(edited);
        setState(() {
          _originalMediaFile = XFile(file.path);
          _isRendered = false;
        });
        PaintingBinding.instance.imageCache.clear();
      }
    }
  }

  Future<void> _renderMedia() async {
    if (_originalMediaFile == null) return;
    if (_videoController != null) {
      await _videoController!.pause();
      await _videoController!.dispose();
      _videoController = null;
    }
    setState(() {
      _isRendering = true;
    });
    _renderingProgressNotifier.value = 0.01;
    WakelockPlus.enable();
    try {
      if (_mediaType == 'image') {
        final bytes = await File(_originalMediaFile!.path).readAsBytes();
        final processed = await MediaProcessorService.processImage(
            bytes: bytes,
            brightness: _activeBrightness,
            saturation: _activeSaturation,
            filter: _activeFilter);
        final tempDir = await getTemporaryDirectory();
        _finalMediaFile =
            await File('${tempDir.path}/rendered_${const Uuid().v4()}.jpg')
                .writeAsBytes(processed);
        if (mounted)
          setState(() {
            _isRendered = true;
            _isRendering = false;
          });
      } else {
        final tempDir = await getTemporaryDirectory();
        final outPath = '${tempDir.path}/out_${const Uuid().v4()}.mp4';
        final overlayFile = await _generateOverlayImage();
        final tempVC =
            VideoPlayerController.file(File(_originalMediaFile!.path));
        await tempVC.initialize();
        final int totalSec = tempVC.value.duration.inSeconds;
        await tempVC.dispose();
        int renderDur =
            (totalSec * (_activeEndTrim - _activeStartTrim)).toInt();
        if (renderDur <= 0) renderDur = totalSec;

        await MediaProcessorService.renderVideo(
            inputPath: _originalMediaFile!.path,
            outputPath: outPath,
            overlayPath: overlayFile.path,
            brightness: _activeBrightness,
            saturation: _activeSaturation,
            filter: _activeFilter,
            rotation: _activeRotation,
            zoom: _activeZoom,
            aspectRatio: _activeAspectRatio,
            isMuted: _isMuted,
            startSec: (totalSec * _activeStartTrim).toInt(),
            duration: renderDur,
            onProgress: (p) => _renderingProgressNotifier.value = p,
            onComplete: (success, path) async {
              if (success && path != null && mounted) {
                _finalMediaFile = File(path);
                _videoController = VideoPlayerController.file(_finalMediaFile!);
                await _videoController!.initialize();
                _videoController!.setLooping(true);
                setState(() {
                  _isRendered = true;
                  _isRendering = false;
                });
              } else {
                if (mounted) setState(() => _isRendering = false);
              }
            });
      }
    } catch (e) {
      if (mounted) setState(() => _isRendering = false);
    } finally {
      WakelockPlus.disable();
    }
  }

  Future<File> _generateOverlayImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 720, 1280));
    for (var o in _activeTextOverlays) {
      final tp = TextPainter(
          text: TextSpan(
              text: o.text,
              style: TextStyle(
                  color: o.color,
                  fontSize: o.fontSize * 1.8 * o.scale,
                  fontWeight: FontWeight.bold)),
          textDirection: ui.TextDirection.ltr)
        ..layout();
      if (o.backgroundColor != null) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(o.position.dx * 1.8 - 10, o.position.dy * 4.5 - 5,
                    tp.width + 20, tp.height + 10),
                const Radius.circular(10)),
            Paint()..color = o.backgroundColor!);
      }
      tp.paint(canvas, Offset(o.position.dx * 1.8, o.position.dy * 4.5));
    }
    final img = await (recorder.endRecording()).toImage(720, 1280);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    return File('${(await getTemporaryDirectory()).path}/ovl.png')
      ..writeAsBytesSync(png!.buffer.asUint8List());
  }

  Future<void> _submitPost() async {
    final title = _titleController.text.trim().toUpperCase();
    final content = _postController.text.trim();
    if (title.isEmpty && content.isEmpty && _originalMediaFile == null) return;
    if (!_isRendered && _originalMediaFile != null) {
      await _renderMedia();
      while (_isRendering) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    final postId = const Uuid().v4();
    File? fileToSubmit = _finalMediaFile ??
        (_originalMediaFile != null ? File(_originalMediaFile!.path) : null);
    final String type = _mediaType ?? 'none';
    String? localThumb = _selectedThumbnailPath;
    if (localThumb == null && fileToSubmit != null)
      localThumb = await MediaProcessorService.createCompressedThumbnail(
          fileToSubmit, type);
    File? permanentFile;
    if (fileToSubmit != null)
      permanentFile = await MediaProcessorService.moveFileToPermanent(
          fileToSubmit, postId, type);
    final userSnap =
        await _firestore.collection('users').doc(_currentUserId).get();
    final userData = userSnap.data();
    final postData = {
      DatabaseHelper.colPostId: postId,
      DatabaseHelper.colUserId: _currentUserId,
      DatabaseHelper.colUserName: userData?['displayName'] ?? "Star",
      DatabaseHelper.colUserImageUrl: userData?['photoUrl'],
      DatabaseHelper.colTitle: title,
      DatabaseHelper.colText: content,
      DatabaseHelper.colSyncStatus: 'uploading',
      DatabaseHelper.colTimestamp: DateTime.now().millisecondsSinceEpoch,
      DatabaseHelper.colCategory: _selectedCategory,
      DatabaseHelper.colVideoUrl:
          type == 'video' ? (permanentFile?.path ?? fileToSubmit?.path) : null,
      DatabaseHelper.colImageUrl:
          type == 'image' ? (permanentFile?.path ?? fileToSubmit?.path) : null,
      DatabaseHelper.colLikes: 0,
      DatabaseHelper.colCommentsCount: 0,
      DatabaseHelper.colViews: 0,
      DatabaseHelper.colIsLikedByMe: 0,
      DatabaseHelper.colPostThumbnailLocalPath: localThumb,
    };
    setState(() {
      _posts.insert(0, postData);
      _isPostAreaExpanded = false;
      _individualUploadProgress[postId] = 0.01;
    });
    _clearMedia();
    _titleController.clear();
    _postController.clear();
    _saveLastUsedCategory(_selectedCategory);
    await DatabaseHelper.instance.savePost(postData);
    _startBackgroundUpload(postId, permanentFile ?? fileToSubmit, localThumb,
        title, content, userData, type);
  }

  Future<void> _startBackgroundUpload(
      String postId,
      File? file,
      String? thumb,
      String title,
      String content,
      Map<String, dynamic>? userData,
      String type) async {
    try {
      String? cloudUrl;
      String? cloudThumb;
      if (thumb != null) {
        cloudThumb = await _r2Service.uploadFile(File(thumb),
            'thumbnails/$_currentUserId/$postId.jpg', 'image/jpeg');
      }
      if (file != null) {
        final String ext = type == 'video' ? 'mp4' : 'jpg';
        final String mime = type == 'video' ? 'video/mp4' : 'image/jpeg';
        cloudUrl = await _r2Service.uploadFile(
            file, 'posts/$_currentUserId/$postId.$ext', mime, onProgress: (p) {
          if (mounted) setState(() => _individualUploadProgress[postId] = p);
        });
      }
      if (mounted) setState(() => _individualUploadProgress[postId] = 1.0);
      await Future.delayed(const Duration(milliseconds: 500));

      // 🔥 INITIALIZE RTDB COUNTERS
      await _rtdb.ref("counters/$postId").set({'likes': 0, 'views': 0});

      await _firestore.collection('posts').doc(postId).set({
        'id': postId,
        'title': title,
        'content': content,
        'userId': _currentUserId,
        'videoUrl': type == 'video' ? cloudUrl : null,
        'imageUrl': type == 'image' ? cloudUrl : null,
        'thumbnailUrl': cloudThumb,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0, // Firestore version for general query
        'category': _selectedCategory,
        'authorName': userData?['displayName'],
        'authorPhotoUrl': userData?['photoUrl'],
        'isStar': false
      });
      if (mounted) {
        setState(() {
          _individualUploadProgress.remove(postId);
          final idx =
              _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
          if (idx != -1) {
            _posts[idx][DatabaseHelper.colSyncStatus] = 'synced';
            _posts[idx]['thumbnailUrl'] = cloudThumb;
            DatabaseHelper.instance.savePost(_posts[idx]);
          }
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx =
              _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
          if (idx != -1) {
            _posts[idx][DatabaseHelper.colSyncStatus] = 'failed';
            DatabaseHelper.instance.savePost(_posts[idx]);
          }
          _individualUploadProgress.remove(postId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(colors: [
                    Colors.amberAccent,
                    Colors.white,
                    Colors.orangeAccent
                  ]).createShader(bounds),
              child: const Text("TANGAZA",
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      letterSpacing: 2.0,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: Colors.black45, blurRadius: 10)
                      ]))),
          const SizedBox(width: 10),
          const Icon(Icons.star_rounded, size: 40, color: Colors.amberAccent)
        ]),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          ValueListenableBuilder<List<DocumentSnapshot>>(
            valueListenable: _friendRequestsNotifier,
            builder: (context, requests, _) => Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Stack(alignment: Alignment.center, children: [
                IconButton(
                    icon: const Icon(Icons.people_alt_rounded,
                        size: 34, color: Colors.white),
                    onPressed: _showFriendRequestsBottomSheet),
                if (requests.isNotEmpty)
                  Positioned(
                      right: 4,
                      top: 8,
                      child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.redAccent, shape: BoxShape.circle),
                          child: Text('${requests.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold))))
              ]),
            ),
          )
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [Colors.blue.shade900, Colors.black],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: Column(children: [
          Expanded(
            child: _isLoadingPosts
                ? const Center(
                    child: CupertinoActivityIndicator(color: Colors.white))
                : IgnorePointer(
                    ignoring: _isPostAreaExpanded,
                    child: ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.only(bottom: 10, top: 120),
                      itemCount: _posts.length,
                      itemBuilder: (context, index) {
                        final post = _posts[index];
                        final pid = post[DatabaseHelper.colPostId] ?? "temp";
                        return PostCard(
                          post: post,
                          currentUserId: _currentUserId,
                          uploadProgress: _individualUploadProgress[pid],
                          isSharing: _sharingPostIds.contains(pid),
                          isScreenActive: _isScreenActive,
                          onLike: _handleLike,
                          onOpenComments: (p) =>
                              _safeNavigate(CommentScreen(postData: p)),
                          onShowOptions: _showPostOptions,
                          onShowFullNews: _showFullNewsModal,
                          onShareStart: () =>
                              setState(() => _sharingPostIds.add(pid)),
                          onShareEnd: (s) =>
                              setState(() => _sharingPostIds.remove(pid)),
                          onRetry: (p) => _handleRetryUpload(p),
                        );
                      },
                    ),
                  ),
          ),
          _buildCreatePostArea()
        ]),
      ),
    );
  }

  Widget _buildCreatePostArea() {
    final lang = Provider.of<LanguageProvider>(context).currentLanguage;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedSize(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: !_isPostAreaExpanded
            ? _buildCollapsedButton(lang)
            : _buildExpandedForm(lang, keyboardH),
      ),
    );
  }

  Widget _buildCollapsedButton(String l) => Container(
      key: const ValueKey(1),
      padding: const EdgeInsets.all(16),
      color: Colors.black87,
      child: InkWell(
          onTap: () => setState(() => _isPostAreaExpanded = true),
          child: Container(
              height: 50,
              decoration: BoxDecoration(
                  color: Colors.amberAccent,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black45,
                        blurRadius: 10,
                        offset: Offset(0, 4))
                  ]),
              child: Center(
                  child: Text(PostTranslations.t('publish_button', l),
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 18))))));

  Widget _buildExpandedForm(String l, double keyboardH) {
    bool needsRender = !_isRendered && _originalMediaFile != null;
    return Container(
      key: const ValueKey(2),
      padding: const EdgeInsets.all(16),
      color: Colors.black87,
      constraints: BoxConstraints(
          maxHeight:
              keyboardH > 0 ? 350 : MediaQuery.of(context).size.height * 0.75),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () => setState(() => _isPostAreaExpanded = false))
        ]),
        Expanded(
            child: SingleChildScrollView(
                child: Column(children: [
          if (_originalMediaFile != null)
            ValueListenableBuilder<double>(
              valueListenable: _renderingProgressNotifier,
              builder: (context, prog, _) => PostMediaPreview(
                mediaType: _mediaType!,
                mediaFile: _originalMediaFile,
                thumbnailPath: _selectedThumbnailPath,
                videoController: _videoController,
                isRendered: _isRendered,
                isRendering: _isRendering || _isPickingMedia,
                renderingProgress: prog,
                activeRotation: _activeRotation,
                activeOffset: _activeOffset,
                activeZoom: _activeZoom,
                activeTextOverlays: _activeTextOverlays,
                activeAspectRatio: _activeAspectRatio,
                previewFilter: _getPreviewFilter(),
                onClear: _clearMedia,
                onEdit: _editMedia,
                renderingText: PostTranslations.t(
                    _isPickingMedia
                        ? 'loading_video'
                        : (_mediaType == 'video'
                            ? 'rendering_video'
                            : 'rendering_image'),
                    l),
              ),
            ),
          SizedBox(
              height: 45,
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: 10.0),
                      child: ChoiceChip(
                          label: Text(
                              PostTranslations.t(
                                  'cat_${_categories[index]}', l),
                              style: TextStyle(
                                  color: _selectedCategory == _categories[index]
                                      ? Colors.black
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          selected: _selectedCategory == _categories[index],
                          selectedColor: Colors.amberAccent,
                          backgroundColor: const Color(0xFF263238),
                          side: BorderSide(
                              color: _selectedCategory == _categories[index]
                                  ? Colors.amberAccent
                                  : Colors.white38),
                          shape: const StadiumBorder(),
                          showCheckmark: false,
                          onSelected: (val) {
                            if (val)
                              setState(
                                  () => _selectedCategory = _categories[index]);
                          })))),
          TextField(
              controller: _titleController,
              style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
              maxLength: 30,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                  hintText: PostTranslations.t('title_placeholder', l),
                  hintStyle:
                      const TextStyle(color: Colors.white24, fontSize: 12),
                  border: InputBorder.none,
                  counterStyle:
                      const TextStyle(color: Colors.white54, fontSize: 10))),
          TextField(
              controller: _postController,
              focusNode: _postFocusNode,
              maxLines: null,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  hintText: PostTranslations.t('placeholder_text', l),
                  border: InputBorder.none,
                  hintStyle: const TextStyle(color: Colors.white54))),
        ]))),
        Row(children: [
          IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.greenAccent),
              onPressed: () => _pickMedia(ImageSource.camera)),
          IconButton(
              icon: const Icon(Icons.photo_library, color: Colors.blueAccent),
              onPressed: () => _pickMedia(ImageSource.gallery)),
          IconButton(
              icon: const Icon(Icons.video_library, color: Colors.redAccent),
              onPressed: () => _pickMedia(ImageSource.gallery, isVideo: true)),
          const Spacer(),
          ElevatedButton(
              onPressed: (_isRendering || _isPickingMedia)
                  ? null
                  : (needsRender ? _renderMedia : _submitPost),
              style: ElevatedButton.styleFrom(
                  backgroundColor: needsRender
                      ? Colors.orangeAccent
                      : Colors.lightBlueAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20))),
              child: (_isRendering || _isPickingMedia)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      PostTranslations.t(
                          needsRender ? 'save_button' : 'publish_button', l),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)))
        ])
      ]),
    );
  }

  ColorFilter _getPreviewFilter() {
    if (_isRendered)
      return const ColorFilter.matrix(
          [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);
    double b = _activeBrightness * 255;
    double s = _activeSaturation;
    double invS = 1.0 - s;
    double lumR = 0.2126 * invS;
    double lumG = 0.7152 * invS;
    double lumB = 0.0722 * invS;
    if (_activeFilter == "grayscale")
      return const ColorFilter.matrix([
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]);
    if (_activeFilter == "sepia")
      return ColorFilter.matrix([
        0.393 * s,
        0.769 * s,
        0.189 * s,
        0,
        b,
        0.349 * s,
        0.686 * s,
        0.168 * s,
        0,
        b,
        0.272 * s,
        0.534 * s,
        0.131 * s,
        0,
        b,
        0,
        0,
        0,
        1,
        0
      ]);
    return ColorFilter.matrix([
      lumR + s,
      lumG,
      lumB,
      0,
      b,
      lumR,
      lumG + s,
      lumB,
      0,
      b,
      lumR,
      lumG,
      lumB + s,
      0,
      b,
      0,
      0,
      0,
      1,
      0
    ]);
  }

  void _showFriendRequestsBottomSheet() {
    final lang =
        Provider.of<LanguageProvider>(context, listen: false).currentLanguage;
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.blueGrey[900],
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Container(
                height: MediaQuery.of(context).size.height * 0.85,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(children: [
                  const SizedBox(height: 12),
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                              hintText:
                                  PostTranslations.t('search_friend', lang),
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.amberAccent),
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide.none)),
                          onChanged: (val) => setSheetState(
                              () => searchQuery = val.toLowerCase()))),
                  const SizedBox(height: 15),
                  Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: DatabaseHelper.instance.getJembeContacts(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(
                            child: CupertinoActivityIndicator());
                      final allPeople = snapshot.data!;
                      List<Map<String, dynamic>> pendingRec = [];
                      List<Map<String, dynamic>> accepted = [];
                      List<Map<String, dynamic>> pendingSent = [];
                      for (var p in allPeople) {
                        final st = p[DatabaseHelper.colFriendStatus];
                        final req = p[DatabaseHelper.colRequestedBy];
                        if (st == 'pending') {
                          if (req != _currentUserId)
                            pendingRec.add(p);
                          else
                            pendingSent.add(p);
                        } else if (st == 'accepted') accepted.add(p);
                      }
                      final sorted = [
                        ...pendingRec,
                        ...accepted,
                        ...pendingSent
                      ];
                      final filtered = sorted
                          .where((p) => p[DatabaseHelper.colDisplayName]
                              .toString()
                              .toLowerCase()
                              .contains(searchQuery))
                          .toList();
                      return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final p = filtered[index];
                            final isRec = p[DatabaseHelper.colFriendStatus] ==
                                    'pending' &&
                                p[DatabaseHelper.colRequestedBy] !=
                                    _currentUserId;
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (index == 0 && isRec)
                                    _buildSectionHeader(
                                        "NEW REQUESTS", Colors.orangeAccent),
                                  if (p[DatabaseHelper.colFriendStatus] ==
                                          'accepted' &&
                                      (index == 0 ||
                                          filtered[index - 1][DatabaseHelper
                                                  .colFriendStatus] !=
                                              'accepted'))
                                    _buildSectionHeader(
                                        "MY FRIENDS", Colors.greenAccent),
                                  ListTile(
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      _safeNavigate(UserProfileScreen(
                                          userId: p[DatabaseHelper.colUserId]));
                                    },
                                    leading: CircleAvatar(
                                        backgroundImage: p[DatabaseHelper
                                                    .colPhotoUrl] !=
                                                null
                                            ? NetworkImage(
                                                p[DatabaseHelper.colPhotoUrl])
                                            : null,
                                        backgroundColor: Colors.white10),
                                    title: Text(
                                        p[DatabaseHelper.colDisplayName] ??
                                            'User',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isRec)
                                            ElevatedButton(
                                                onPressed: () async {
                                                  await _firestore
                                                      .collection('friendships')
                                                      .doc(p[DatabaseHelper
                                                          .colFriendshipId])
                                                      .update({
                                                    'status': 'accepted'
                                                  });
                                                  _syncFriendsWithLocal().then(
                                                      (_) =>
                                                          setSheetState(() {}));
                                                },
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.amberAccent,
                                                    foregroundColor:
                                                        Colors.black),
                                                child: Text(PostTranslations.t(
                                                    'confirm', lang))),
                                          if (p[DatabaseHelper
                                                  .colFriendStatus] ==
                                              'accepted')
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.chat_bubble,
                                                    color: Colors.blueAccent),
                                                onPressed: () {
                                                  Navigator.pop(sheetContext);
                                                  _safeNavigate(ChatScreenWrapper(
                                                      receiverID: p[
                                                          DatabaseHelper
                                                              .colUserId],
                                                      receiverEmail: p[
                                                          DatabaseHelper
                                                              .colDisplayName]));
                                                }),
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.person_remove_alt_1,
                                                  color: Colors.redAccent,
                                                  size: 20),
                                              onPressed: () => _confirmUnfriend(
                                                  p[DatabaseHelper
                                                      .colFriendshipId],
                                                  lang)),
                                        ]),
                                  ),
                                ]);
                          });
                    },
                  )),
                ]),
              )),
    );
  }

  Widget _buildSectionHeader(String title, Color color) => Padding(
      padding: const EdgeInsets.only(left: 15, top: 20, bottom: 8),
      child: Text(title,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2)));

  void _confirmUnfriend(String id, String lang) {
    showCupertinoDialog(
        context: context,
        builder: (c) => CupertinoAlertDialog(
                title: Text(PostTranslations.t('unfriend_confirm_title', lang)),
                actions: [
                  CupertinoDialogAction(
                      child: Text(PostTranslations.t('cancel', lang)),
                      onPressed: () => Navigator.pop(c)),
                  CupertinoDialogAction(
                      isDestructiveAction: true,
                      child: Text(
                          PostTranslations.t('unfriend_confirm_button', lang)),
                      onPressed: () {
                        _firestore.collection('friendships').doc(id).delete();
                        Navigator.pop(c);
                        _syncFriendsWithLocal();
                      })
                ]));
  }

  void _showFullNewsModal(
      BuildContext context, String title, String body, String lang) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
                color: Color(0xFF1C2935),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            padding: const EdgeInsets.all(25),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 25),
              Text(title,
                  style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white10),
              Expanded(
                  child: SingleChildScrollView(
                      child: Text(body,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16, height: 1.6))))
            ])));
  }

  void _showPostOptions(Map<String, dynamic> post) {
    final lang =
        Provider.of<LanguageProvider>(context, listen: false).currentLanguage;
    showModalBottomSheet(
        context: context,
        builder: (context) => Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blueAccent),
                  title: Text(PostTranslations.t('edit_post_text', lang)),
                  onTap: () {
                    Navigator.pop(context);
                    _editPostContent(post);
                  }),
              ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(PostTranslations.t('delete_post', lang),
                      style: const TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeletePost(post);
                  })
            ]));
  }

  void _editPostContent(Map<String, dynamic> post) {
    final lang =
        Provider.of<LanguageProvider>(context, listen: false).currentLanguage;
    final ctrl = TextEditingController(text: post[DatabaseHelper.colText]);
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
                backgroundColor: Colors.blueGrey[900],
                title: Text(PostTranslations.t('edit_content_title', lang)),
                content: TextField(
                    controller: ctrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: null),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(PostTranslations.t('cancel', lang))),
                  ElevatedButton(
                      onPressed: () async {
                        final txt = ctrl.text.trim();
                        final pid = post[DatabaseHelper.colPostId];
                        Navigator.pop(context);
                        await _firestore
                            .collection('posts')
                            .doc(pid)
                            .update({'content': txt});
                        setState(() {
                          final idx = _posts.indexWhere(
                              (p) => p[DatabaseHelper.colPostId] == pid);
                          if (idx != -1)
                            _posts[idx][DatabaseHelper.colText] = txt;
                          DatabaseHelper.instance.savePost(_posts[idx]);
                        });
                      },
                      child: Text(PostTranslations.t('confirm', lang)))
                ]));
  }

  void _confirmDeletePost(Map<String, dynamic> post) {
    final lang =
        Provider.of<LanguageProvider>(context, listen: false).currentLanguage;
    showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
                title: Text(PostTranslations.t('delete_confirm_title', lang)),
                actions: [
                  CupertinoDialogAction(
                      child: Text(PostTranslations.t('cancel', lang)),
                      onPressed: () => Navigator.pop(context)),
                  CupertinoDialogAction(
                      isDestructiveAction: true,
                      child: Text(PostTranslations.t('confirm', lang)),
                      onPressed: () async {
                        final pid = post[DatabaseHelper.colPostId];
                        Navigator.pop(context);
                        await _firestore.collection('posts').doc(pid).delete();
                        await DatabaseHelper.instance.deletePost(pid);
                        setState(() => _posts.removeWhere(
                            (p) => p[DatabaseHelper.colPostId] == pid));
                      })
                ]));
  }

  Future<void> _loadLastUsedCategory() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCat = prefs.getString('last_category');
    if (lastCat != null && _categories.contains(lastCat)) {
      setState(() {
        _selectedCategory = lastCat;
        _categories.remove(lastCat);
        _categories.insert(0, lastCat);
      });
    }
  }

  Future<void> _saveLastUsedCategory(String category) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_category', category);
  }
}
