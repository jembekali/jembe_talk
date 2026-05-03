import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui; 
import 'dart:developer'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/post_service.dart';
import 'package:jembe_talk/services/r2_service.dart'; 
import 'package:jembe_talk/services/share_service.dart'; 
import 'package:jembe_talk/tangaza_star/comment_screen.dart';
import 'package:jembe_talk/tangaza_star/media_editor_view.dart'; 
import 'package:jembe_talk/tangaza_star/user_profile_screen.dart'; // 🔥 Import nshya
import 'package:jembe_talk/post_translations.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:jembe_talk/chat_screen.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:path/path.dart' as p; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img_lib; 
import 'package:video_thumbnail/video_thumbnail.dart'; 
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/foundation.dart';

// Widgets
import 'package:jembe_talk/widgets/post_card.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> with TickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController(); 
  final TextEditingController _postController = TextEditingController();
  final FocusNode _postFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool _isLoadingPosts = true;
  bool _isRendering = false; 
  double _renderingProgress = 0.0; 
  bool _isRendered = false;  
  File? _finalVideoFile;     
  File? _finalImageFile; 
  bool _isPostAreaExpanded = false; 

  final Map<String, double> _individualUploadProgress = {};
  final Set<String> _sharingPostIds = {}; 
  final ImagePicker _picker = ImagePicker();
  XFile? _originalMediaFile; 
  XFile? _mediaFile;
  String? _mediaType;
  VideoPlayerController? _videoController;
  List<Map<String, dynamic>> _posts = [];

  final _firestore = FirebaseFirestore.instance;
  final R2Service _r2Service = R2Service(); 
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final PostService _postService = PostService();

  late AnimationController _bottomSheetController;
  final ValueNotifier<List<DocumentSnapshot>> _friendRequestsNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _isScreenActive = ValueNotifier(true);
  StreamSubscription<QuerySnapshot>? _friendRequestsSubscription;

  final List<String> _categories = ["General", "Gospel", "Music", "Comedy", "News", "Sports", "Health", "Entertainment", "Tech", "Lifestyle"];
  String _selectedCategory = "General";

  // MEDIA STATE
  List<MediaTextOverlay> _activeTextOverlays = [];
  double _activeBrightness = 0.0; double _activeSaturation = 1.0;
  int _activeRotation = 0; double _activeZoom = 1.0;
  Offset _activeOffset = Offset.zero; String _activeFilter = "none";
  bool _isMuted = false; double _activeStartTrim = 0.0; double _activeEndTrim = 1.0;
  String? _activeThumbnailPath; 
  double? _activeAspectRatio;

  @override
  void initState() {
    super.initState();
    _bottomSheetController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _loadPosts();
    _startListeningToFriendRequests();
    _loadLastUsedCategory();
  }

  Future<void> _loadPosts() async {
    if (_currentUserId == null) return;
    try {
      await DatabaseHelper.instance.cleanupOldPosts();
      final postsFromDb = await DatabaseHelper.instance.getPostsByUserId(_currentUserId!);
      if (mounted) {
        setState(() { 
          _posts = postsFromDb.map((p) => Map<String, dynamic>.from(p)).toList(); 
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

  Future<void> _refreshPostStats(String postId) async {
    try {
      final docSnapshot = await _firestore.collection('posts').doc(postId).get();
      if (!docSnapshot.exists) return;
      final data = docSnapshot.data();
      if (data == null) return;
      final index = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
      if (index != -1 && mounted) {
        setState(() {
          _posts[index][DatabaseHelper.colLikes] = data['likes'] ?? 0;
          _posts[index][DatabaseHelper.colCommentsCount] = data['commentsCount'] ?? 0;
          _posts[index][DatabaseHelper.colIsLikedByMe] = (data['likedBy'] ?? []).contains(_currentUserId) ? 1 : 0;
          _posts[index]['thumbnailUrl'] = data['thumbnailUrl'];
        });
        await DatabaseHelper.instance.savePost(_posts[index]);
      }
    } catch (e) {}
  }

  Future<void> _handleLike(Map<String, dynamic> post) async {
    if (_currentUserId == null) return;
    HapticFeedback.lightImpact();
    final postId = post[DatabaseHelper.colPostId];
    if (postId == null) return;
    final bool isLiked = (post[DatabaseHelper.colIsLikedByMe] == 1);
    setState(() {
      if (isLiked) { post[DatabaseHelper.colIsLikedByMe] = 0; post[DatabaseHelper.colLikes] = (post[DatabaseHelper.colLikes] ?? 1) - 1; }
      else { post[DatabaseHelper.colIsLikedByMe] = 1; post[DatabaseHelper.colLikes] = (post[DatabaseHelper.colLikes] ?? 0) + 1; }
    });
    await _postService.togglePostLike(postId, isLiked); 
    _refreshPostStats(postId);
  }

  Future<void> _loadLastUsedCategory() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCat = prefs.getString('last_category');
    if (lastCat != null && _categories.contains(lastCat)) {
      setState(() { _selectedCategory = lastCat; _categories.remove(lastCat); _categories.insert(0, lastCat); });
    }
  }

  Future<void> _saveLastUsedCategory(String category) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_category', category);
  }

  void _startListeningToFriendRequests() {
    if (_currentUserId == null) return;
    _friendRequestsSubscription = _firestore.collection('friendships')
        .where('users', arrayContains: _currentUserId)
        .snapshots().listen((snapshot) {
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        return data['status'] == 'pending' && data['requestedBy'] != _currentUserId;
      }).toList();
      if (mounted) _friendRequestsNotifier.value = filteredDocs;
    });
  }

  String _formatDur(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

  @override
  void dispose() { 
    _friendRequestsSubscription?.cancel(); _friendRequestsNotifier.dispose(); _isScreenActive.dispose(); 
    _titleController.dispose(); _postController.dispose(); _postFocusNode.dispose(); 
    _videoController?.dispose(); _bottomSheetController.dispose(); _scrollController.dispose(); super.dispose(); 
  }

  Future<void> _safeNavigate(Widget destination) async { _videoController?.pause(); _isScreenActive.value = false; await Navigator.push(context, CustomPageRoute(child: destination)); _isScreenActive.value = true; }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    _postFocusNode.unfocus();
    if (!isVideo) {
      final XFile? file = await _picker.pickImage(source: source);
      if (file != null) { _clearMedia(); setState(() { _originalMediaFile = file; _mediaFile = file; _mediaType = 'image'; _isRendered = false; }); }
      return;
    }
    final XFile? videoFile = await _picker.pickVideo(source: source);
    if (videoFile == null) return;
    File videoToProcess = File(videoFile.path);
    final nc = VideoPlayerController.file(videoToProcess);
    await nc.initialize();
    _videoController = nc;
    _videoController!.addListener(_videoLoopListener);
    _activeStartTrim = 0.0;
    _activeEndTrim = nc.value.duration.inSeconds > 120 ? 120 / nc.value.duration.inSeconds : 1.0;
    setState(() { _originalMediaFile = XFile(videoToProcess.path); _mediaFile = XFile(videoToProcess.path); _mediaType = 'video'; _isRendered = false; _videoController!.play(); });
  }

  void _videoLoopListener() {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    final duration = _videoController!.value.duration;
    if (_videoController!.value.position >= duration * _activeEndTrim) { 
      _videoController!.seekTo(duration * _activeStartTrim); 
    }
    if(mounted) setState(() {}); 
  }

  Future<void> _editMedia() async {
    if (_mediaFile == null || _originalMediaFile == null) return;
    if (_mediaType == 'video') { _editMediaFromVideo(File(_originalMediaFile!.path)); }
    else {
      final Uint8List imageBytes = await File(_originalMediaFile!.path).readAsBytes();
      final Uint8List? editedImageBytes = await Navigator.push(context, MaterialPageRoute(builder: (context) => ImageEditor(image: imageBytes)));
      if (editedImageBytes != null) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = await File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg').writeAsBytes(editedImageBytes);
        setState(() { _mediaFile = XFile(tempFile.path); _originalMediaFile = XFile(tempFile.path); _isRendered = false; });
      }
    }
  }

  Future<void> _editMediaFromVideo(File videoFile) async {
    _videoController?.pause();
    final dynamic result = await Navigator.push(context, MaterialPageRoute(builder: (context) => MediaEditorView(
      file: videoFile, type: 'video', 
      initialOverlays: _activeTextOverlays, initialBrightness: _activeBrightness, initialSaturation: _activeSaturation, 
      initialRotation: _activeRotation, initialZoom: _activeZoom, initialOffset: _activeOffset, 
      initialFilter: _activeFilter, initialMute: _isMuted, initialStart: _activeStartTrim, initialEnd: _activeEndTrim,
    ), fullscreenDialog: true));
    
    if (result != null && result is Map && mounted) {
      setState(() { 
        _activeTextOverlays = List<MediaTextOverlay>.from(result['overlays'] ?? []); 
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
        _activeThumbnailPath = result['thumbnail']; 
        _isRendered = false; 
        _videoController?.setVolume(_isMuted ? 0.0 : 1.0); 
        _videoController?.seekTo(_videoController!.value.duration * _activeStartTrim); 
        _videoController?.play(); 
      });
    } else { _videoController?.play(); }
  }

  ColorFilter _getPreviewFilter() {
    if (_isRendered) return const ColorFilter.matrix([1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0]);
    double s = _activeSaturation; double b = _activeBrightness * 255;
    if (_activeFilter == "grayscale") s = 0.0;
    double invS = 1.0 - s; double lumR = 0.2126 * invS; double lumG = 0.7152 * invS; double lumB = 0.0722 * invS;
    if (_activeFilter == "sepia") return ColorFilter.matrix([0.393*s, 0.769*s, 0.189*s, 0, b, 0.349*s, 0.686*s, 0.168*s, 0, b, 0.272*s, 0.534*s, 0.131*s, 0, b, 0, 0, 0, 1, 0]);
    if (_activeFilter == "green") return ColorFilter.matrix([lumR + s*0.5, lumG, lumB, 0, b, lumR, lumG + s*1.5, lumB, 0, b, lumR, lumG, lumB + s*0.5, 0, b, 0, 0, 0, 1, 0]);
    if (_activeFilter == "blue") return ColorFilter.matrix([lumR + s*0.5, lumG, lumB, 0, b, lumR, lumG, lumB, 0, b, lumR, lumG, lumB + s*2.0, 0, b, 0, 0, 0, 1, 0]);
    return ColorFilter.matrix([lumR + s, lumG, lumB, 0, b, lumR, lumG + s, lumB, 0, b, lumR, lumG, lumB + s, 0, b, 0, 0, 0, 1, 0]);
  }

  static Future<Uint8List> _processImageInIsolate(Map<String, dynamic> params) async {
    return await compute(_handleImageMath, params);
  }

  static Uint8List _handleImageMath(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final double brightness = params['brightness'];
    final double saturation = params['saturation'];
    final String filter = params['filter'];

    img_lib.Image? image = img_lib.decodeImage(bytes);
    if (image == null) return Uint8List(0);

    if (brightness != 0) image = img_lib.adjustColor(image, brightness: 1.0 + brightness);
    if (saturation != 1.0 || filter == "grayscale") {
      double s = filter == "grayscale" ? 0.0 : saturation;
      image = img_lib.adjustColor(image, saturation: s);
    }
    if (image.width > 1080) image = img_lib.copyResize(image, width: 1080);
    return img_lib.encodeJpg(image, quality: 85);
  }

  Future<void> _renderAndSaveImage() async {
    if (_mediaType != 'image' || _originalMediaFile == null) return;
    setState(() { _isRendering = true; _renderingProgress = 0.5; });
    WakelockPlus.enable(); 
    try {
      final bytes = await File(_originalMediaFile!.path).readAsBytes();
      final processedBytes = await _processImageInIsolate({
        'bytes': bytes, 'brightness': _activeBrightness, 
        'saturation': _activeSaturation, 'filter': _activeFilter
      });
      
      final processedPath = p.join((await getTemporaryDirectory()).path, 'processed_${const Uuid().v4()}.jpg');
      _finalImageFile = await File(processedPath).writeAsBytes(processedBytes);
      if (mounted) setState(() { _isRendering = false; _isRendered = true; });
    } catch (e) { 
      if (mounted) setState(() { _isRendering = false; }); 
    } finally { WakelockPlus.disable(); }
  }

  Future<void> _renderAndSaveVideo() async {
    if (_mediaType != 'video' || _originalMediaFile == null) return;
    setState(() { _isRendering = true; _renderingProgress = 0.0; });
    WakelockPlus.enable(); 
    try {
      final tempDir = await getTemporaryDirectory();
      final renderedPath = p.join(tempDir.path, 'final_rendered_${const Uuid().v4()}.mp4');
      
      double renderWidth = 720.0;
      double renderHeight = 1280.0; 
      if (_activeAspectRatio != null) {
        renderHeight = renderWidth / _activeAspectRatio!;
      } else {
        renderHeight = (_videoController!.value.size.height * renderWidth) / _videoController!.value.size.width;
      }

      final File overlayFile = await _generateOverlayImage(Size(renderWidth, renderHeight));
      final int durSec = ((_videoController?.value.duration.inSeconds ?? 0) * (_activeEndTrim - _activeStartTrim)).toInt();
      final int startSec = ((_videoController?.value.duration.inSeconds ?? 0) * _activeStartTrim).toInt();

      String colorFilters = "eq=brightness=$_activeBrightness:saturation=$_activeSaturation";
      String specialFilter = "";
      if (_activeFilter == "grayscale") {
        specialFilter = ",hue=s=0";
      } else if (_activeFilter == "sepia") {
        specialFilter = ",colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131";
      } else if (_activeFilter == "green") {
        specialFilter = ",colorbalance=gh=0.5:bh=-0.2";
      } else if (_activeFilter == "blue") {
        specialFilter = ",colorbalance=bh=0.5:gh=-0.2";
      }

      String rotationFilter = _activeRotation != 0 ? "rotate=${_activeRotation}*(PI/180)," : "";
      String cropFilter = _activeAspectRatio != null ? "crop=w='min(iw,ih*$_activeAspectRatio)':h='min(ih,iw/$_activeAspectRatio)'," : "";
      String zoomFilter = _activeZoom > 1.0 ? "crop=(iw/$_activeZoom):(ih/$_activeZoom),scale=720:-2," : "scale=720:-2,";
      
      String filterComplex = "[0:v]${rotationFilter}${cropFilter}${zoomFilter}${colorFilters}${specialFilter}[vid];[vid][1:v]overlay=0:0";
      String audioCommand = _isMuted ? "-an" : "-c:a aac -b:a 128k";

      await FFmpegKit.executeAsync("-ss $startSec -t $durSec -i '${_originalMediaFile!.path}' -i '${overlayFile.path}' -filter_complex \"$filterComplex\" $audioCommand -c:v libx264 -crf 28 -preset superfast '$renderedPath'", (session) async {
        if (ReturnCode.isSuccess(await session.getReturnCode())) {
          _finalVideoFile = File(renderedPath);
          await _videoController?.dispose();
          final nc = VideoPlayerController.file(_finalVideoFile!);
          await nc.initialize(); _videoController = nc;
          if (mounted) setState(() { _isRendering = false; _isRendered = true; _videoController!.play(); });
        } else if (mounted) setState(() { _isRendering = false; });
        WakelockPlus.disable();
      }, null, (stats) { if (durSec > 0 && mounted) setState(() => _renderingProgress = (stats.getTime() / (durSec * 1000)).clamp(0.0, 1.0)); });
    } catch (e) { 
      if (mounted) setState(() { _isRendering = false; }); 
      WakelockPlus.disable();
    }
  }

  Future<File> _generateOverlayImage(Size renderSize) async {
    final recorder = ui.PictureRecorder(); 
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, renderSize.width, renderSize.height));
    final double previewWidth = MediaQuery.of(context).size.width;
    final double previewHeight = 250; 
    for (var o in _activeTextOverlays) {
      final double ratioX = renderSize.width / previewWidth;
      final double ratioY = renderSize.height / previewHeight;
      final textPainter = TextPainter(text: TextSpan(text: o.text, style: TextStyle(color: o.color, fontSize: o.fontSize * ratioX * o.scale, fontWeight: FontWeight.bold, fontFamily: o.isEmoji ? 'EmojiFont' : 'Roboto', shadows: [ui.Shadow(blurRadius: 15, color: Colors.black.withAlpha(200), offset: const Offset(2, 2))])), textDirection: ui.TextDirection.ltr, textAlign: TextAlign.center);
      textPainter.layout(); 
      double x = o.position.dx * ratioX; double y = o.position.dy * ratioY;
      if (o.backgroundColor != null) { canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 10, y - 5, textPainter.width + 20, textPainter.height + 10), const Radius.circular(10)), Paint()..color = o.backgroundColor!); }
      textPainter.paint(canvas, Offset(x, y));
    }
    final img = await (recorder.endRecording()).toImage(renderSize.width.toInt(), renderSize.height.toInt());
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${(await getTemporaryDirectory()).path}/overlay_${const Uuid().v4()}.png');
    await file.writeAsBytes(pngBytes!.buffer.asUint8List()); return file;
  }

  Future<String?> _createCompressedThumbnail(File sourceFile, String type) async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (type == 'video') { 
        return await VideoThumbnail.thumbnailFile(video: sourceFile.path, thumbnailPath: tempDir.path, imageFormat: ImageFormat.JPEG, quality: 60); 
      } else { 
        final bytes = await sourceFile.readAsBytes(); 
        img_lib.Image? image = img_lib.decodeImage(bytes); 
        if (image != null) { 
          img_lib.Image thumbnail = img_lib.copyResize(image, width: 400); 
          final String thumbPath = p.join(tempDir.path, "thumb_${const Uuid().v4()}.jpg");
          await File(thumbPath).writeAsBytes(img_lib.encodeJpg(thumbnail, quality: 60)); 
          return thumbPath; 
        } 
      }
    } catch (e) {} return null;
  }

  Future<File?> _moveFileToPermanent(File sourceFile, String postId, String type) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final postsDir = Directory(p.join(appDir.path, 'cached_posts'));
      if (!await postsDir.exists()) await postsDir.create(recursive: true);
      final String extension = type == 'video' ? '.mp4' : '.jpg';
      final String newPath = p.join(postsDir.path, 'post_$postId$extension');
      return await sourceFile.copy(newPath);
    } catch (e) { return null; }
  }

  Future<void> _submitPost() async {
    final title = _titleController.text.trim().toUpperCase(); 
    final content = _postController.text.trim();
    if (title.isEmpty && content.isEmpty && _mediaFile == null) return;
    
    if (!_isRendered && _mediaFile != null) {
      bool needsRender = _activeBrightness != 0 || _activeSaturation != 1.0 || 
                         _activeRotation != 0 || _activeZoom != 1.0 || 
                         _activeTextOverlays.isNotEmpty || _isMuted || 
                         _activeStartTrim != 0.0 || _activeAspectRatio != null ||
                         _activeFilter != "none";

      if (needsRender) {
         if (_mediaType == 'video') { 
            await _renderAndSaveVideo(); 
            while(_isRendering) { await Future.delayed(const Duration(milliseconds: 500)); }
         } else { 
            await _renderAndSaveImage(); 
         }
      }
    }

    final tempPostId = const Uuid().v4(); 
    _postFocusNode.unfocus();
    final currentCategory = _selectedCategory; final currentType = _mediaType ?? 'none'; 
    File? fileToSubmit;
    if (currentType == 'video') fileToSubmit = _isRendered && _finalVideoFile != null ? _finalVideoFile : (_originalMediaFile != null ? File(_originalMediaFile!.path) : null);
    else if (currentType == 'image') fileToSubmit = _isRendered && _finalImageFile != null ? _finalImageFile : (_originalMediaFile != null ? File(_originalMediaFile!.path) : null);
    
    String? localThumbPath = _activeThumbnailPath; 
    if (localThumbPath != null) {
       localThumbPath = await _createCompressedThumbnail(File(localThumbPath), 'image');
    } else if (fileToSubmit != null) { 
       localThumbPath = await _createCompressedThumbnail(fileToSubmit, currentType); 
    }
    
    File? permanentFile;
    if (fileToSubmit != null) { 
      permanentFile = await _moveFileToPermanent(fileToSubmit, tempPostId, currentType); 
    }

    final userSnap = await _firestore.collection('users').doc(_currentUserId).get();
    final userData = userSnap.data();

    final postDataUI = {
      DatabaseHelper.colPostId: tempPostId, DatabaseHelper.colUserId: _currentUserId,
      DatabaseHelper.colUserName: userData?['displayName'] ?? "Star", DatabaseHelper.colUserImageUrl: userData?['photoUrl'], 
      DatabaseHelper.colTitle: title, DatabaseHelper.colText: content, 
      DatabaseHelper.colImageUrl: currentType == 'image' ? (permanentFile?.path ?? fileToSubmit?.path) : null, 
      DatabaseHelper.colVideoUrl: currentType == 'video' ? (permanentFile?.path ?? fileToSubmit?.path) : null, 
      DatabaseHelper.colSyncStatus: 'uploading', DatabaseHelper.colTimestamp: DateTime.now().millisecondsSinceEpoch, DatabaseHelper.colLikes: 0, DatabaseHelper.colCommentsCount: 0, DatabaseHelper.colIsLikedByMe: 0, DatabaseHelper.colCategory: currentCategory,
      DatabaseHelper.colPostThumbnailLocalPath: localThumbPath, DatabaseHelper.colIsStar: 0,
    };

    if(mounted) {
      setState(() { _posts.insert(0, Map<String, dynamic>.from(postDataUI)); _individualUploadProgress[tempPostId] = 0.01; _titleController.clear(); _postController.clear(); _categories.remove(currentCategory); _categories.insert(0, currentCategory); _isPostAreaExpanded = false; });
    }
    _clearMedia(); _saveLastUsedCategory(currentCategory);
    await DatabaseHelper.instance.savePost(postDataUI);
    if (fileToSubmit != null) { _uploadRenderedFile(tempPostId, title, content, _currentUserId!, fileToSubmit, currentType, currentCategory, localThumbPath, permanentFile?.path); }
  }

  Future<void> _uploadRenderedFile(String postId, String title, String content, String uid, File fileToUpload, String type, String category, String? localThumb, String? localPermPath) async {
    if (_videoController != null) {
      try { await _videoController!.pause(); await _videoController!.dispose(); _videoController = null; if (mounted) setState(() {}); } catch (e) {}
    }
    await Future.delayed(const Duration(milliseconds: 500));
    Timer? simulationTimer; double currentP = 0.05;
    simulationTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) { if (currentP < 0.90 && mounted) { currentP += 0.03; setState(() => _individualUploadProgress[postId] = currentP); } });
    try {
      final String downloadUrl = await _r2Service.uploadFile(fileToUpload, 'posts/$uid/$postId.${type == 'image' ? 'jpg' : 'mp4'}', type == 'image' ? 'image/jpeg' : 'video/mp4');
      String? cloudThumbUrl;
      if (localThumb != null) { cloudThumbUrl = await _r2Service.uploadFile(File(localThumb), 'thumbnails/$uid/$postId.jpg', 'image/jpeg'); }
      simulationTimer.cancel();
      if(mounted) { setState(() => _individualUploadProgress[postId] = 1.0); await Future.delayed(const Duration(milliseconds: 500)); final idx = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId); if (idx != -1) setState(() { _posts[idx][DatabaseHelper.colSyncStatus] = 'synced'; _individualUploadProgress.remove(postId); }); }
      final userSnap = await _firestore.collection('users').doc(uid).get();
      final userData = userSnap.data();
      await _firestore.collection('posts').doc(postId).set({ 'id': postId, 'title': title, 'content': content, 'userId': uid, 'authorName': userData?['displayName'] ?? "Star", 'authorPhotoUrl': userData?['photoUrl'], 'timestamp': FieldValue.serverTimestamp(), 'imageUrl': type == 'image' ? downloadUrl : null, 'videoUrl': type == 'video' ? downloadUrl : null, 'thumbnailUrl': cloudThumbUrl, 'likes': 0, 'commentsCount': 0, 'views': 0, 'likedBy': [], 'category': category, 'isStar': false });
      final lIdx = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId); if (lIdx != -1) await DatabaseHelper.instance.savePost(_posts[lIdx]);
      HapticFeedback.mediumImpact();
    } catch (e) { simulationTimer.cancel(); final idx = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId); if (idx != -1 && mounted) setState(() => _posts[idx][DatabaseHelper.colSyncStatus] = 'failed'); }
  }

  void _clearMedia() { if(mounted) setState(() { _originalMediaFile = null; _mediaFile = null; _mediaType = null; _isRendered = false; _isRendering = false; _finalVideoFile = null; _finalImageFile = null; _activeTextOverlays = []; _activeBrightness = 0; _activeSaturation = 1; _activeFilter = "none"; _activeRotation = 0; _activeZoom = 1.0; _activeOffset = Offset.zero; _activeThumbnailPath = null; _activeAspectRatio = null; _videoController?.dispose(); _videoController = null; }); }
  void _openComments(Map<String, dynamic> postData) async { _videoController?.pause(); _isScreenActive.value = false; await Navigator.of(context).push(MaterialPageRoute(builder: (context) => CommentScreen(postData: postData))); _isScreenActive.value = true; _refreshPostStats(postData[DatabaseHelper.colPostId]); }
  void _showPostOptions(Map<String, dynamic> post) { final lang = Provider.of<LanguageProvider>(context, listen: false); final String l = lang.currentLanguage; showModalBottomSheet(context: context, builder: (context) => Wrap(children: [ ListTile(leading: const Icon(Icons.edit, color: Colors.blueAccent), title: Text(PostTranslations.t('edit_post_text', l)), onTap: () { Navigator.pop(context); _editPostContent(post); }), ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: Text(PostTranslations.t('delete_post', l), style: const TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _confirmDeletePost(post); }) ])); }
  void _editPostContent(Map<String, dynamic> post) { final lang = Provider.of<LanguageProvider>(context, listen: false); final String l = lang.currentLanguage; final TextEditingController editController = TextEditingController(text: post[DatabaseHelper.colText]); showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: Colors.blueGrey[900], title: Text(PostTranslations.t('edit_content_title', l)), content: TextField(controller: editController, style: const TextStyle(color: Colors.white), maxLines: null, decoration: InputDecoration(hintText: PostTranslations.t('edit_content_hint', l), hintStyle: const TextStyle(color: Colors.white54))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(PostTranslations.t('cancel', l))), ElevatedButton(onPressed: () async { final newContent = editController.text.trim(); final postId = post[DatabaseHelper.colPostId]; Navigator.pop(context); await _firestore.collection('posts').doc(postId).update({'content': newContent}); final idx = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId); if (idx != -1 && mounted) { setState(() => _posts[idx][DatabaseHelper.colText] = newContent); await DatabaseHelper.instance.savePost(_posts[idx]); } }, child: Text(PostTranslations.t('confirm', l)))])); }
  void _confirmDeletePost(Map<String, dynamic> post) { final lang = Provider.of<LanguageProvider>(context, listen: false); final String l = lang.currentLanguage; showCupertinoDialog(context: context, builder: (context) => CupertinoAlertDialog(title: Text(PostTranslations.t('delete_confirm_title', l)), content: Text(PostTranslations.t('delete_confirm_body', l)), actions: [CupertinoDialogAction(child: Text(PostTranslations.t('cancel', l)), onPressed: () => Navigator.pop(context)), CupertinoDialogAction(isDestructiveAction: true, child: Text(PostTranslations.t('confirm', l)), onPressed: () async { final postId = post[DatabaseHelper.colPostId]; Navigator.pop(context); await _firestore.collection('posts').doc(postId).delete(); await DatabaseHelper.instance.deletePost(postId); setState(() => _posts.removeWhere((p) => p[DatabaseHelper.colPostId] == postId)); })])); }

  // 🔥 UPDATED FRIENDS PAGE WITH NAVIGATION TO USER PROFILE
  void _showFriendRequestsBottomSheet() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final String l = lang.currentLanguage;
    String searchQuery = '';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.blueGrey[900],
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: PostTranslations.t('search_friend', l),
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onChanged: (val) => setSheetState(() => searchQuery = val.toLowerCase()),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('friendships').where('users', arrayContains: _currentUserId).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CupertinoActivityIndicator());
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) return Center(child: Text(PostTranslations.t('no_friend_requests', l), style: const TextStyle(color: Colors.white)));

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final reqData = docs[index].data() as Map<String, dynamic>;
                        final senderId = reqData['users'].firstWhere((id) => id != _currentUserId);
                        final status = reqData['status'];

                        return StreamBuilder<DocumentSnapshot>(
                          stream: _firestore.collection('users').doc(senderId).snapshots(),
                          builder: (context, userSnap) {
                            if (!userSnap.hasData) return const SizedBox.shrink();
                            final userData = userSnap.data!.data() as Map<String, dynamic>?;
                            if (userData == null) return const SizedBox.shrink();
                            if (searchQuery.isNotEmpty && !(userData['displayName'] as String).toLowerCase().contains(searchQuery)) return const SizedBox.shrink();

                            return ListTile(
                              // 🔥 KOSORA HANO: Navigate to Profile when clicking Avatar or Name
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _safeNavigate(UserProfileScreen(userId: senderId));
                              },
                              leading: CircleAvatar(backgroundImage: userData['photoUrl'] != null ? NetworkImage(userData['photoUrl']) : null),
                              title: Text(userData['displayName'] ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text(status == 'pending' ? 'Pending Request' : 'Friend', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (status == 'pending' && reqData['requestedBy'] != _currentUserId) 
                                    ElevatedButton(
                                      onPressed: () => _firestore.collection('friendships').doc(docs[index].id).update({'status': 'accepted'}),
                                      child: Text(PostTranslations.t('confirm', l)),
                                    ),
                                  
                                  if (status == 'accepted')
                                    IconButton(
                                      icon: const Icon(Icons.chat_bubble, color: Colors.blueAccent),
                                      onPressed: () {
                                        Navigator.pop(sheetContext);
                                        _safeNavigate(ChatScreenWrapper(receiverID: senderId, receiverEmail: userData['displayName']));
                                      },
                                    ),

                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.person_remove_alt_1, color: Colors.redAccent),
                                    onPressed: () {
                                      showCupertinoDialog(
                                        context: context,
                                        builder: (c) => CupertinoAlertDialog(
                                          title: Text(PostTranslations.t('unfriend_confirm_title', l)),
                                          content: Text(PostTranslations.t('unfriend_confirm_body', l)),
                                          actions: [
                                            CupertinoDialogAction(child: Text(PostTranslations.t('cancel', l)), onPressed: () => Navigator.pop(c)),
                                            CupertinoDialogAction(isDestructiveAction: true, child: Text(PostTranslations.t('unfriend_confirm_button', l)), onPressed: () {
                                              _firestore.collection('friendships').doc(docs[index].id).delete();
                                              Navigator.pop(c);
                                            }),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullNewsModal(BuildContext context, String title, String body, String langCode) { showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => Container(height: MediaQuery.of(context).size.height * 0.75, decoration: BoxDecoration(color: const Color(0xFF1C2935), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))), padding: const EdgeInsets.all(25), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))), const SizedBox(height: 25), if (title.isNotEmpty) Text(title, style: const TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 15), const Divider(color: Colors.white10), const SizedBox(height: 15), Expanded(child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: Text(body, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6))))]))); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true, 
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [ ShaderMask(shaderCallback: (bounds) => const LinearGradient(colors: [Colors.amberAccent, Colors.white, Colors.orangeAccent]).createShader(bounds), child: const Text("TANGAZA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 2.0, color: Colors.white, shadows: [Shadow(color: Colors.black45, blurRadius: 10)]))), const SizedBox(width: 10), const Icon(Icons.star_rounded, size: 40, color: Colors.amberAccent) ]), 
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        actions: [ 
          if (_currentUserId != null) ValueListenableBuilder<List<DocumentSnapshot>>(
            valueListenable: _friendRequestsNotifier, 
            builder: (context, requests, child) { 
              final pendingCount = requests.length; 
              return Padding(padding: const EdgeInsets.only(right: 12.0), child: Stack(alignment: Alignment.center, children: [ IconButton(icon: const Icon(Icons.people_alt_rounded, size: 34, color: Colors.white), onPressed: _showFriendRequestsBottomSheet), if (pendingCount > 0) Positioned(right: 4, top: 8, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), child: Text('$pendingCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))) ])); 
            }
          ) 
        ], 
      ), 
      extendBodyBehindAppBar: true, 
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.black], begin: Alignment.topLeft, end: Alignment.bottomRight)), 
        child: Column(children: [ 
          Expanded(child: _isLoadingPosts ? const Center(child: CupertinoActivityIndicator(color: Colors.white)) : ListView.builder(controller: _scrollController, reverse: true, padding: const EdgeInsets.only(bottom: 10, top: 120), itemCount: _posts.length, itemBuilder: (context, index) {
            final post = _posts[index];
            final String pid = post[DatabaseHelper.colPostId] ?? "temp";
            return PostCard(
              post: post,
              currentUserId: _currentUserId,
              uploadProgress: _individualUploadProgress[pid],
              isSharing: _sharingPostIds.contains(pid),
              onLike: _handleLike,
              onOpenComments: _openComments,
              onShowOptions: _showPostOptions,
              onShowFullNews: _showFullNewsModal,
              onShareStart: () => setState(() => _sharingPostIds.add(pid)),
              onShareEnd: (s) => setState(() => _sharingPostIds.remove(pid)),
              isScreenActive: _isScreenActive,
            );
          })), 
          _buildCreatePostArea() 
        ])
      )
    );
  } 

  Widget _buildCreatePostArea() {
    final lang = Provider.of<LanguageProvider>(context); final String l = lang.currentLanguage; final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedSize(duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic, child: AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: !_isPostAreaExpanded ? _buildCollapsedButton(l) : _buildExpandedForm(l, keyboardH)));
  }

  Widget _buildCollapsedButton(String l) => Container(key: const ValueKey(1), padding: const EdgeInsets.all(16), color: Colors.black87, child: InkWell(onTap: () => setState(() => _isPostAreaExpanded = true), child: Container(height: 50, decoration: BoxDecoration(color: Colors.amberAccent, borderRadius: BorderRadius.circular(25), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))]), child: Center(child: Text(PostTranslations.t('publish_button', l), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18))))));

  Widget _buildExpandedForm(String l, double keyboardH) {
    return Container(
      key: const ValueKey(2), padding: const EdgeInsets.all(16), color: Colors.black87, 
      constraints: BoxConstraints(maxHeight: keyboardH > 0 ? 350 : MediaQuery.of(context).size.height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [ const Spacer(), IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => setState(() => _isPostAreaExpanded = false)) ]),
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                if(_mediaFile != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Stack(alignment: Alignment.center, children: [ ClipRRect(borderRadius: BorderRadius.circular(15), child: Container(color: Colors.black26, alignment: Alignment.centerLeft, constraints: BoxConstraints(maxHeight: keyboardH > 0 ? 120 : 250), child: _mediaType == 'video' && _videoController != null && _videoController!.value.isInitialized ? GestureDetector(onTap: () => setState(() => _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play()), child: Container(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: _videoController!.value.aspectRatio < 1.0 ? 0.65 : 1.0, child: AspectRatio(aspectRatio: _activeAspectRatio ?? _videoController!.value.aspectRatio, child: Stack(alignment: Alignment.center, children: [
                        Transform.rotate(angle: _isRendered ? 0 : (_activeRotation * 3.14 / 180), child: Transform.translate(offset: _isRendered ? Offset.zero : _activeOffset, child: Transform.scale(scale: _isRendered ? 1.0 : _activeZoom, child: ColorFiltered(colorFilter: _getPreviewFilter(), child: VideoPlayer(_videoController!))))),
                        if (!_isRendered) ..._activeTextOverlays.map((o) => Positioned(left: o.position.dx * 0.4, top: o.position.dy * 0.4, child: Transform.scale(scale: o.scale * 0.6, child: Text(o.text, textAlign: TextAlign.center, style: TextStyle(color: o.color, fontSize: o.fontSize, fontWeight: FontWeight.bold, backgroundColor: o.backgroundColor, shadows: const [Shadow(blurRadius: 10, color: Colors.black)]))))),
                        Positioned(bottom: 5, right: 5, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text(_formatDur(_videoController!.value.duration), style: const TextStyle(color: Colors.white, fontSize: 9)))),
                        if (!_videoController!.value.isPlaying) const CircleAvatar(radius: 30, backgroundColor: Colors.black45, child: Icon(Icons.play_arrow, size: 40, color: Colors.white70))
                    ]))))) : Stack(alignment: Alignment.center, children: [ Image.file(File(_mediaFile!.path), fit: BoxFit.contain), if (!_isRendered) ..._activeTextOverlays.map((o) => Positioned(left: o.position.dx * 0.4, top: o.position.dy * 0.4, child: Transform.scale(scale: o.scale * 0.6, child: Text(o.text, textAlign: TextAlign.center, style: TextStyle(color: o.color, fontSize: o.fontSize, fontWeight: FontWeight.bold, backgroundColor: o.backgroundColor, shadows: const [Shadow(blurRadius: 10, color: Colors.black)]))))) ]))), Positioned(top: 0, right: 0, child: IconButton(icon: const CircleAvatar(backgroundColor: Colors.black54, child: Icon(Icons.close, color: Colors.white, size: 18)), onPressed: () => _clearMedia())), if(!_isRendered) Positioned(bottom: 8, right: 8, child: ElevatedButton.icon(onPressed: _editMedia, icon: const Icon(Icons.edit, size: 14), label: Text(PostTranslations.t('edit_label', l)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent))), ])),
                if (_isRendering) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [ LinearProgressIndicator(value: _renderingProgress, color: Colors.orangeAccent), const SizedBox(height: 5), Text("${(_renderingProgress * 100).toInt()}% ${PostTranslations.t(_mediaType == 'video' ? 'rendering_video' : 'rendering_image', l)}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)) ])),
                SizedBox(height: 45, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _categories.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(right: 10.0), child: ChoiceChip(label: Text(PostTranslations.t('cat_${_categories[index]}', l), style: TextStyle(color: _selectedCategory == _categories[index] ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), selected: _selectedCategory == _categories[index], selectedColor: Colors.amberAccent, backgroundColor: const Color(0xFF263238), side: BorderSide(color: _selectedCategory == _categories[index] ? Colors.amberAccent : Colors.white38), shape: const StadiumBorder(), showCheckmark: false, onSelected: (selected) { if (selected) setState(() => _selectedCategory = _categories[index]); } )))),
                TextField(controller: _titleController, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 18), maxLength: 30, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(hintText: PostTranslations.t('title_placeholder', l), hintStyle: const TextStyle(color: Colors.white24, fontSize: 12), border: InputBorder.none, counterStyle: const TextStyle(color: Colors.white54, fontSize: 10))),
                TextField(controller: _postController, focusNode: _postFocusNode, style: const TextStyle(color: Colors.white), maxLines: null, keyboardType: TextInputType.multiline, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: PostTranslations.t('placeholder_text', l), border: InputBorder.none, hintStyle: const TextStyle(color: Colors.white54))),
              ])
            ),
          ),
          Row(children: [ 
            IconButton(icon: const Icon(Icons.camera_alt, color: Colors.greenAccent), onPressed: () => _pickMedia(ImageSource.camera)), 
            IconButton(icon: const Icon(Icons.photo_library, color: Colors.blueAccent), onPressed: () => _pickMedia(ImageSource.gallery)), 
            IconButton(icon: const Icon(Icons.video_library, color: Colors.redAccent), onPressed: () => _pickMedia(ImageSource.gallery, isVideo: true)), 
            const Spacer(), 
            if (!_isRendered && _mediaFile != null) 
              ElevatedButton(onPressed: _isRendering ? null : (_mediaType == 'video' ? _renderAndSaveVideo : _renderAndSaveImage), style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: Text(PostTranslations.t('save_button', l), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))) 
            else 
              ElevatedButton(onPressed: _submitPost, style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: _isLoadingPosts ? const CupertinoActivityIndicator() : Text(PostTranslations.t('publish_button', l), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))) 
          ])
        ],
      )
    );
  }
}