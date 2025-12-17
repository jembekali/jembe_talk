// Fayili: lib/tangaza_star/create_post_screen.dart
// IYI NI VERSION YANYUMA KANDI YAKOSOWE NEZA 100% - VIDEO POSTING YAHAWE PAUSE (HIDDEN)

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/post_service.dart';
import 'package:jembe_talk/tangaza_star/comment_screen.dart';
import 'package:jembe_talk/tangaza_star/simple_video_editor_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:jembe_talk/full_photo_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jembe_talk/chat_screen.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
import 'package:jembe_talk/tangaza_star/user_profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:path/path.dart' as p;

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> with TickerProviderStateMixin {
  final TextEditingController _postController = TextEditingController();
  final FocusNode _postFocusNode = FocusNode();

  bool _isLoading = false;
  double _uploadProgress = 0.0;

  final ImagePicker _picker = ImagePicker();
  
  XFile? _originalMediaFile; 
  
  XFile? _mediaFile;
  String? _mediaType;
  VideoPlayerController? _videoController;
  List<Map<String, dynamic>> _posts = [];
  bool _isLoadingPosts = true;

  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  final PostService _postService = PostService();

  late AnimationController _bottomSheetController;

  final ValueNotifier<List<DocumentSnapshot>> _friendRequestsNotifier = ValueNotifier([]);
  StreamSubscription<QuerySnapshot>? _friendRequestsSubscription;
  bool _hasInitialDataLoaded = false;

  bool _isProcessingVideo = false;

  List<TextOverlay> _activeTextOverlays = [];
  Duration _activeStartTrim = Duration.zero;
  Duration _activeEndTrim = Duration.zero;
  Size _editorViewerSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _bottomSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      reverseDuration: const Duration(milliseconds: 1000),
    );
    _loadPosts();
    _startListeningToFriendRequests();
  }

  void _startListeningToFriendRequests() {
    if (_currentUserId == null) return;

    _friendRequestsSubscription = _firestore.collection('friendships')
        .where('users', arrayContains: _currentUserId)
        .snapshots(includeMetadataChanges: true) 
        .listen((snapshot) {
          
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        final status = data['status'];
        final requestedBy = data['requestedBy'];
        final hasChatted = data['hasChatted'] ?? false;
        
        if (status == 'pending' && requestedBy != _currentUserId) return true;
        if (status == 'accepted' && hasChatted == false) return true;
        return false;
      }).toList();

      if (mounted) _friendRequestsNotifier.value = filteredDocs;
      
      if (!_hasInitialDataLoaded && mounted) {
        setState(() => _hasInitialDataLoaded = true);
      }
    });
  }

  Future<void> _loadPosts() async {
    if (_currentUserId == null) {
      if (mounted) setState(() => _isLoadingPosts = false);
      return;
    }
    final postsFromDb = await DatabaseHelper.instance.getPostsByUserId(_currentUserId!);
    if (mounted) {
      setState(() {
        _posts = postsFromDb;
        _isLoadingPosts = false;
      });
    }
  }

  Future<void> _refreshPostStats(String postId) async {
    try {
      final docSnapshot = await _firestore.collection('posts').doc(postId).get();
      if (!docSnapshot.exists) return;

      final data = docSnapshot.data()!;
      final likes = data['likes'] ?? 0;
      final commentsCount = data['commentsCount'] ?? 0; 
      final likedByList = List<String>.from(data['likedBy'] ?? []);
      final bool isLikedByMe = _currentUserId != null && likedByList.contains(_currentUserId);

      final index = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
      if (index != -1 && mounted) {
        setState(() {
          final updatedPost = Map<String, dynamic>.from(_posts[index]);
          updatedPost[DatabaseHelper.colLikes] = likes;
          updatedPost[DatabaseHelper.colCommentsCount] = commentsCount;
          updatedPost[DatabaseHelper.colIsLikedByMe] = isLikedByMe ? 1 : 0;
          _posts[index] = updatedPost;
        });
        await DatabaseHelper.instance.savePost(_posts[index]);
      }
    } catch (e) {
      // silent fail
    }
  }

  Future<void> _handleLike(Map<String, dynamic> post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_currentUserId == null) return;

    final postId = post[DatabaseHelper.colPostId];
    final isCurrentlyLiked = (post[DatabaseHelper.colIsLikedByMe] == 1) || (post[DatabaseHelper.colIsLikedByMe] == true);
    final currentLikes = post[DatabaseHelper.colLikes] as int? ?? 0;

    final index = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
    if (index != -1 && mounted) {
      setState(() {
        final updatedPost = Map<String, dynamic>.from(_posts[index]);
        updatedPost[DatabaseHelper.colIsLikedByMe] = isCurrentlyLiked ? 0 : 1;
        updatedPost[DatabaseHelper.colLikes] = isCurrentlyLiked ? (currentLikes - 1) : (currentLikes + 1);
        _posts[index] = updatedPost;
      });
    }

    try {
      await _postService.togglePostLike(postId, isCurrentlyLiked);
    } catch (e) {
      if (!mounted) return;
      if (index != -1) {
        setState(() => _posts[index] = post);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('like_failed_snackbar'))));
      }
    }
  }

  @override
  void dispose() {
    _friendRequestsSubscription?.cancel();
    _friendRequestsNotifier.dispose();
    _postController.dispose();
    _postFocusNode.dispose();

    _videoController?.pause();
    _videoController?.removeListener(_videoPlaybackListener);
    _videoController?.dispose();

    _bottomSheetController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    _postFocusNode.unfocus();

    if (!isVideo) {
      final XFile? file = await _picker.pickImage(source: source, imageQuality: 90);
      if (file == null) return;
      
      _clearMedia();
      if (mounted) setState(() {
        _originalMediaFile = file;
        _mediaFile = file; 
        _mediaType = 'image'; 
      });
      return;
    }

    final XFile? videoFile = await _picker.pickVideo(source: source);
    if (videoFile == null) return;

    File videoToProcess = File(videoFile.path);

    final tempController = VideoPlayerController.file(videoToProcess);
    await tempController.initialize();
    final int durationInSeconds = tempController.value.duration.inSeconds;
    await tempController.dispose();

    if (durationInSeconds > 180) { // Iminota 3
      if (!mounted) return;
      final choice = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: false,
        barrierLabel: "Video Limit",
        transitionDuration: const Duration(milliseconds: 1200),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 25),
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[900], 
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15, spreadRadius: 5)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_off_outlined, size: 50, color: Colors.orangeAccent),
                    const SizedBox(height: 15),
                    Text(
                      lang.t('long_video_title'), 
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: 15),
                    Text(
                      lang.t('long_video_body'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 30),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.cut, color: Colors.white),
                          label: Text(lang.t('long_video_trim_manual'), style: const TextStyle(color: Colors.white, fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent, 
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                          onPressed: () => Navigator.of(context).pop('trim'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.auto_fix_high, color: Colors.greenAccent),
                          label: Text(lang.t('long_video_trim_auto'), style: const TextStyle(color: Colors.greenAccent, fontSize: 16)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.greenAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                          onPressed: () => Navigator.of(context).pop('auto_cut'),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      );

      if (choice == 'trim') {
        _navigateToSimpleEditor(videoToProcess, isReEdit: false);
        return;
      } else if (choice == 'auto_cut') {
        final tempDir = await getTemporaryDirectory();
        final outputPath = '${tempDir.path}/cut_${const Uuid().v4()}.mp4';
        final command = '-i "${videoToProcess.path}" -ss 0 -t 180 -c copy "$outputPath"';

        final ValueNotifier<double> trimProgress = ValueNotifier(0.0);
        FFmpegKitConfig.enableStatisticsCallback((Statistics stats) {
          final progress = stats.getTime() / (180 * 1000);
          trimProgress.value = progress.clamp(0.0, 1.0);
        });

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.blueGrey[900],
              title: const Text('Uririko uragabanya video...', style: TextStyle(color: Colors.white)),
              content: ValueListenableBuilder<double>(
                valueListenable: trimProgress,
                builder: (context, value, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: value, color: Colors.blueAccent, backgroundColor: Colors.white24),
                      const SizedBox(height: 16),
                      Text('${(value * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white70)),
                    ],
                  );
                },
              ),
            ),
          );
        }

        final session = await FFmpegKit.execute(command);
        FFmpegKitConfig.enableStatisticsCallback(null);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();

        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          videoToProcess = File(outputPath);
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('video_trim_failed'))));
          return;
        }
      } else {
        return; 
      }
    }

    _clearMedia();
    final newController = VideoPlayerController.file(videoToProcess);
    await newController.initialize();

    if (!mounted) {
      await newController.dispose();
      return;
    }

    setState(() {
      _originalMediaFile = XFile(videoToProcess.path); 
      _mediaFile = XFile(videoToProcess.path);
      _mediaType = 'video';
      _videoController = newController;
      _videoController!.play();
      _videoController!.setLooping(true);
    });
  }
  
  Future<void> _editMedia() async {
    if (_mediaFile == null || _isLoading || _originalMediaFile == null) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);

    if (_mediaType == 'video') {
      if (!mounted) return;
      
      final bool hasBeenEdited = _activeEndTrim > Duration.zero || _activeTextOverlays.isNotEmpty;
      
      if (hasBeenEdited) {
        final bool? wantsToProceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.blueGrey[900],
            title: Text(lang.t('re_edit_video_title'), style: const TextStyle(color: Colors.white)),
            content: Text(lang.t('re_edit_video_body'), style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                child: Text(lang.t('dialog_cancel'), style: const TextStyle(color: Colors.white)),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: Text(lang.t('re_edit_video_confirm'), style: const TextStyle(color: Colors.white)),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        );
        
        if (wantsToProceed != true) {
          return; 
        }

        await _navigateToSimpleEditor(File(_originalMediaFile!.path), isReEdit: false);

      } else {
        await _navigateToSimpleEditor(File(_originalMediaFile!.path), isReEdit: false);
      }

    } else { 
      final Uint8List imageBytes = await _mediaFile!.readAsBytes();
      if (!mounted) return;
      
      final Uint8List? editedImageBytes = await Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => ImageEditor(image: imageBytes))
      );
      
      if (editedImageBytes != null) {
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final tempFile = await File(tempPath).writeAsBytes(editedImageBytes);
        if(mounted) setState(() {
          _mediaFile = XFile(tempFile.path);
          _originalMediaFile = XFile(tempFile.path); 
        });
      }
    }
  }

  // <<<< IMPINDUKA Y'INGENZI HANO: Guhagarika video >>>>
  Future<void> _navigateToSimpleEditor(File videoFile, {required bool isReEdit}) async {
    if (!mounted) return;

    // Turabanje guhagarika video iriko irakina imbere yo kuja kuyindi page
    await _videoController?.pause();
    
    if(mounted) setState(() {
       _originalMediaFile = XFile(videoFile.path);
    });

    final Map<String, dynamic>? result = await Navigator.push<Map<String, dynamic>>(
      context, 
      MaterialPageRoute(builder: (context) => SimpleVideoEditorScreen(
        videoFile: videoFile,
        initialStartTrim: isReEdit ? _activeStartTrim : null,
        initialEndTrim: isReEdit ? _activeEndTrim : null,
        initialTextOverlays: isReEdit ? _activeTextOverlays : null,
      ))
    );

    if (result == null) {
      // Umukoresha asubiye inyuma atagize ico akoze, reka dusubire dukinishe ya video
      if(mounted && _videoController?.value.isInitialized == true) {
        await _videoController?.play();
      }
      return;
    }

    _clearMedia(keepOriginal: true); 

    final newController = VideoPlayerController.file(videoFile);
    await newController.initialize();

    if (!mounted) {
      newController.dispose();
      return;
    }

    setState(() {
      _mediaFile = XFile(videoFile.path); 
      _mediaType = 'video';
      _videoController = newController;
      
      _activeStartTrim = result['startTrim'];
      _activeEndTrim = result['endTrim'];
      _activeTextOverlays = result['textOverlays'];
      _editorViewerSize = result['viewerSize'];

      _videoController?.seekTo(_activeStartTrim);
      _videoController?.play();
      _videoController?.setLooping(false);
      _videoController?.addListener(_videoPlaybackListener);

      final bool hasEdits = _activeEndTrim > _activeStartTrim || _activeTextOverlays.isNotEmpty;

      if(hasEdits){
         _isProcessingVideo = true; 
         _processVideoInBackground(videoFile, result);
      } else {
         _isProcessingVideo = false;
      }
    });
  }

  void _videoPlaybackListener() {
    if (_videoController == null || !_videoController!.value.isInitialized) return;

    final position = _videoController!.value.position;
    if (_activeEndTrim > Duration.zero && (position >= _activeEndTrim || position < _activeStartTrim)) {
      _videoController!.seekTo(_activeStartTrim);
    }
  }

  void _processVideoInBackground(File originalVideo, Map<String, dynamic> editParams) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = p.join(tempDir.path, 'processed_${const Uuid().v4()}.mp4');

      final Duration start = editParams['startTrim'];
      final Duration end = editParams['endTrim'];
      final Duration duration = end - start;
      final List<TextOverlay> texts = editParams['textOverlays'];
      final Size viewerSize = editParams['viewerSize'];
      final double rotation = editParams['rotation'];

      final tempController = VideoPlayerController.file(originalVideo);
      await tempController.initialize();
      final videoWidth = tempController.value.size.width;
      final videoHeight = tempController.value.size.height;
      await tempController.dispose();

      final fontPath = await _getFontPath();

      List<String> videoFilters = [];
      if (rotation == 90) videoFilters.add('transpose=1');
      else if (rotation == 180) videoFilters.add('transpose=2,transpose=2');
      else if (rotation == 270) videoFilters.add('transpose=2');

      String colorToFFmpegHex(Color color) => '0x${color.value.toRadixString(16).substring(2)}';

      for (var text in texts) {
        final ffFontSize = (text.fontSize * text.scale) * (videoHeight / viewerSize.height);
        final ffX = (text.position.dx / viewerSize.width) * videoWidth;
        final ffY = (text.position.dy / viewerSize.height) * videoHeight;
        final colorHex = colorToFFmpegHex(text.color);
        
        String drawtext = "drawtext=fontfile='$fontPath':text='${text.text.replaceAll("'", "’")}':fontcolor='$colorHex':fontsize=$ffFontSize:x=$ffX:y=$ffY";
        if (text.backgroundColor != null) {
          final bgColorHex = colorToFFmpegHex(text.backgroundColor!);
          drawtext += ":box=1:boxcolor=$bgColorHex:boxborderw=10";
        }
        videoFilters.add(drawtext);
      }

      final String filterCommand = videoFilters.isNotEmpty ? '-vf "${videoFilters.join(',')}"' : '';

      final command =
          '-i "${originalVideo.path}" -ss ${start.inSeconds} -t ${duration.inSeconds} '
          '$filterCommand '
          '-c:v libx264 -preset veryfast -crf 23 '
          '-c:a aac -b:a 128k '
          '"$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (!mounted) return;

      if (ReturnCode.isSuccess(returnCode)) {
        final processedFile = File(outputPath);
        
        _videoController?.removeListener(_videoPlaybackListener);
        await _videoController?.dispose();

        final newController = VideoPlayerController.file(processedFile);
        await newController.initialize();

        if (!mounted) {
          newController.dispose();
          return;
        }
        
        setState(() {
          _mediaFile = XFile(processedFile.path); 
          _videoController = newController..play()..setLooping(true);
          _isProcessingVideo = false;
          _activeTextOverlays.clear(); 
          _activeStartTrim = Duration.zero;
          _activeEndTrim = Duration.zero;

        });
      } else {
         setState(() => _isProcessingVideo = false);
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('video_processing_failed'))));
      }
    } catch(e) {
      if (!mounted) return;
      setState(() => _isProcessingVideo = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('video_processing_failed'))));
    }
  }

  Future<String> _getFontPath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final fontPath = p.join(documentsDir.path, 'NotoColorEmoji-Regular.ttf');
    final fontFile = File(fontPath);
    if (!await fontFile.exists()) {
      final byteData = await rootBundle.load('assets/fonts/NotoColorEmoji-Regular.ttf');
      await fontFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return fontPath;
  }

  Future<void> _submitPost() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_isLoading || _currentUserId == null) return;
    if (_isProcessingVideo) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('wait_for_video_processing'))));
      return;
    }
    final content = _postController.text.trim();
    if (content.isEmpty && _mediaFile == null) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('post_empty_error'))));
      return;
    }

    _postFocusNode.unfocus();
    if(mounted) setState(() { 
      _isLoading = true; 
      _uploadProgress = 0.0;
    });

    final postId = const Uuid().v4();
    String? firebaseImageUrl;
    String? firebaseVideoUrl;

    try {
      String userName = lang.t('no_author_name');
      String? userPhotoUrl;
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null && currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
           userName = currentUser.displayName!;
           userPhotoUrl = currentUser.photoURL;
        } else {
           final userDoc = await _firestore.collection('users').doc(_currentUserId).get();
           if (userDoc.exists) {
             userName = userDoc.data()?['displayName'] ?? lang.t('no_author_name');
             userPhotoUrl = userDoc.data()?['photoUrl'];
           }
        }
      } catch (e) {
        // silent fail
      }

      if (_mediaFile != null) {
        final file = File(_mediaFile!.path);
        final ref = _storage.ref().child('posts').child(_currentUserId!).child('$postId.${_mediaType == 'image' ? 'jpg' : 'mp4'}');
        final uploadTask = ref.putFile(file);

        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          if (snapshot.totalBytes > 0) {
            double progress = snapshot.bytesTransferred / snapshot.totalBytes;
            if (mounted) setState(() => _uploadProgress = progress);
          }
        });

        await uploadTask;
        final downloadUrl = await ref.getDownloadURL();
        
        if (_mediaType == 'image') {
          firebaseImageUrl = downloadUrl;
        } else {
          firebaseVideoUrl = downloadUrl;
        }
      }

      final postDataForFirebase = {
        'content': content,
        'userId': _currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0, 'views': 0, 'isStar': false, 'likedBy': [],
        'imageUrl': firebaseImageUrl,
        'videoUrl': firebaseVideoUrl,
      };
      await _firestore.collection('posts').doc(postId).set(postDataForFirebase);
      
      final postDataForDB = {
        DatabaseHelper.colPostId: postId, 
        DatabaseHelper.colUserId: _currentUserId, 
        DatabaseHelper.colUserName: userName, 
        DatabaseHelper.colUserImageUrl: userPhotoUrl, 
        DatabaseHelper.colText: content, 
        DatabaseHelper.colImageUrl: (_mediaType == 'image' && _mediaFile != null) ? _mediaFile!.path : firebaseImageUrl,
        DatabaseHelper.colVideoUrl: (_mediaType == 'video' && _mediaFile != null) ? _mediaFile!.path : firebaseVideoUrl,
        DatabaseHelper.colTimestamp: DateTime.now().millisecondsSinceEpoch, 
        DatabaseHelper.colSyncStatus: 'synced',
        DatabaseHelper.colLikes: 0, 
        DatabaseHelper.colCommentsCount: 0, 
        DatabaseHelper.colViews: 0, 
        DatabaseHelper.colIsLikedByMe: 0,
      };

      await DatabaseHelper.instance.savePost(postDataForDB);

      if (!mounted) return;

      setState(() {
        _posts.insert(0, postDataForDB);
        _postController.clear();
        _clearMedia();
        _isLoading = false;
        _uploadProgress = 0.0;
      });
      Navigator.of(context).pop(); 

    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('post_creation_failed')}$e")));
      }
    }
  }

  void _clearMedia({bool keepOriginal = false}) {
    if(mounted) setState(() {
      if(!keepOriginal){
         _originalMediaFile = null;
      }
      _mediaFile = null;
      _mediaType = null;
      _videoController?.removeListener(_videoPlaybackListener);
      _videoController?.dispose();
      _videoController = null;
      _activeTextOverlays.clear();
      _activeStartTrim = Duration.zero;
      _activeEndTrim = Duration.zero;
      _editorViewerSize = Size.zero;
    });
  }

  Future<void> _updatePost(String postId, String newText) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    try {
      await _firestore.collection('posts').doc(postId).update({'content': newText});

      final postIndex = _posts.indexWhere((p) => p[DatabaseHelper.colPostId] == postId);
      if (postIndex != -1) {
        final updatedPost = Map<String, dynamic>.from(_posts[postIndex]);
        updatedPost[DatabaseHelper.colText] = newText;
        
        await DatabaseHelper.instance.savePost(updatedPost);

        if (mounted) {
          setState(() {
            _posts[postIndex] = updatedPost;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('post_edit_success')), backgroundColor: Colors.green));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('post_edit_failed')}$e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final postId = post[DatabaseHelper.colPostId];
    final imageUrl = post[DatabaseHelper.colImageUrl] as String?;
    final videoUrl = post[DatabaseHelper.colVideoUrl] as String?;

    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      await _firestore.collection('posts').doc(postId).delete();

      Future<void> deleteFromStorage(String? url) async {
        if (url != null && url.startsWith('http')) {
          try {
            await _storage.refFromURL(url).delete();
          } catch (e) {
            // silent fail
          }
        }
      }
      await deleteFromStorage(imageUrl);
      await deleteFromStorage(videoUrl);

      await DatabaseHelper.instance.deletePost(postId);

      if (!mounted) return;
      Navigator.pop(context); // Remove loading
      setState(() {
        _posts.removeWhere((p) => p[DatabaseHelper.colPostId] == postId);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('post_delete_success')), backgroundColor: Colors.green));
      
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('post_delete_failed')}$e"), backgroundColor: Colors.red));
    }
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

    try {
      final List<XFile> filesToShare = [];
      final tempDir = await getTemporaryDirectory();

      Future<XFile?> getFileForShare(String url) async {
        try {
          if (!url.startsWith('http')) {
             final file = File(url);
             if (await file.exists()) return XFile(url);
             return null;
          }
          
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(url));
          final response = await request.close();
          final bytes = await consolidateHttpClientResponseBytes(response);
          final fileName = 'share_temp_${DateTime.now().millisecondsSinceEpoch}.${url.endsWith('mp4') ? 'mp4' : 'jpg'}';
          final filePath = '${tempDir.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(bytes);
          return XFile(filePath);
        } catch (e) {
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
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('share_failed_generic')}$e")));
    }
  }

  void _openComments(Map<String, dynamic> postData) async {
    _videoController?.pause();
    await Navigator.of(context).push(MaterialPageRoute(builder: (context) => CommentScreen(postData: postData)));
    _refreshPostStats(postData[DatabaseHelper.colPostId]);
  }

  void _showFullText(String fullText) {
    showModalBottomSheet(
      context: context,
      transitionAnimationController: _bottomSheetController,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(color: Colors.blueGrey[900]!.withOpacity(0.95), borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 25),
            Expanded(child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: Text(fullText, style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.6)))),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditPostDialog(Map<String, dynamic> post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final TextEditingController editController = TextEditingController(text: post[DatabaseHelper.colText]);

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Edit",
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blueGrey[900], borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2)],),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(lang.t('edit_post_title'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(controller: editController, maxLines: 5, style: const TextStyle(color: Colors.white), decoration: InputDecoration(filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), hintText: "...", hintStyle: const TextStyle(color: Colors.white54)),),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text(lang.t('dialog_cancel'), style: const TextStyle(color: Colors.white70))),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () async {
                          final newText = editController.text.trim();
                          if (newText.isNotEmpty) {
                            Navigator.pop(context);
                            await _updatePost(post[DatabaseHelper.colPostId], newText);
                          }
                        },
                        child: Text(lang.t('btn_save'), style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack), 
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  Future<void> _showDeletePostConfirmation(Map<String, dynamic> post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Delete",
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 30),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blueGrey[900], borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2)],),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 50, color: Colors.amber),
                  const SizedBox(height: 10),
                  Text(lang.t('delete_post_title'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(lang.t('delete_post_confirm'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(onPressed: () => Navigator.of(context).pop(), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white30), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text(lang.t('dialog_no'), style: const TextStyle(color: Colors.white)),),
                      ElevatedButton(onPressed: () { Navigator.of(context).pop(); _deletePost(post); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text(lang.t('dialog_yes_delete'), style: const TextStyle(color: Colors.white)),),
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  void _showPostOptions(Map<String, dynamic> post) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showModalBottomSheet(context: context, builder: (context) => Wrap(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: Text(lang.t('edit_post_title')),
          onTap: () { Navigator.pop(context); _showEditPostDialog(post); }
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: Text(lang.t('delete_post_title'), style: const TextStyle(color: Colors.red)),
          onTap: () { Navigator.pop(context); _showDeletePostConfirmation(post); }
        ),
      ],
    ));
  }

  void _showFriendRequestsBottomSheet() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.blueGrey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        if (_currentUserId == null) return const SizedBox.shrink();

        return ValueListenableBuilder<List<DocumentSnapshot>>(
          valueListenable: _friendRequestsNotifier,
          builder: (context, requests, child) {
            
            if (!_hasInitialDataLoaded) {
              return Container(padding: const EdgeInsets.all(20), height: 200, child: const Center(child: CircularProgressIndicator(color: Colors.white)));
            }

            if (requests.isEmpty) {
              return Container(padding: const EdgeInsets.all(20), height: 200, child: Center(child: Text(lang.t('no_friend_requests'), style: const TextStyle(color: Colors.white70))));
            }

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(lang.t('friend_requests_title'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final reqDoc = requests[index];
                        final reqData = reqDoc.data() as Map<String, dynamic>;
                        final List<dynamic> users = reqData['users'];
                        final senderId = users.firstWhere((id) => id != _currentUserId, orElse: () => reqData['requestedBy']);
                        final isPending = reqData['status'] == 'pending';

                        return StreamBuilder<DocumentSnapshot>(
                          stream: _firestore.collection('users').doc(senderId).snapshots(),
                          builder: (context, userSnap) {
                            if (!userSnap.hasData) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Row(children: [ const CircleAvatar(radius: 25, backgroundColor: Colors.white12), const SizedBox(width: 12), Expanded(child: Container(height: 16, width: 100, color: Colors.white12)) ] ),
                              );
                            }

                            final userData = userSnap.data!.data() as Map<String, dynamic>;
                            final userName = userData['displayName'] ?? 'Umuntu';
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(context, CustomPageRoute(child: UserProfileScreen(userId: senderId))),
                                      child: Row(
                                        children: [
                                          CircleAvatar(radius: 25, backgroundImage: (userData['photoUrl'] != null) ? CachedNetworkImageProvider(userData['photoUrl']) : null, child: (userData['photoUrl'] == null) ? const Icon(Icons.person) : null),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                                                Text(lang.t('view_profile_prompt'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isPending) ...[
                                    OutlinedButton(onPressed: () => _firestore.collection('friendships').doc(reqDoc.id).delete(), style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 36)), child: Text(lang.t('friend_req_decline')),),
                                    const SizedBox(width: 8),
                                  ],
                                  ElevatedButton(
                                    onPressed: () async {
                                      if (!mounted) return;
                                      if (isPending) {
                                        await _firestore.collection('friendships').doc(reqDoc.id).update({'status': 'accepted', 'hasChatted': false});
                                      } else {
                                        Navigator.of(sheetContext).pop(); 
                                        Navigator.of(this.context).push(CustomPageRoute(child: ChatScreen(receiverID: senderId, receiverEmail: userName)));
                                        _firestore.collection('friendships').doc(reqDoc.id).update({'hasChatted': true});
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 36)),
                                    child: Text(isPending ? lang.t('friend_req_accept') : lang.t('friend_req_message')),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

// WIDGET BUILDERS
  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(lang.t('create_post_title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: 1.5)),
            const SizedBox(width: 8),
            const Icon(Icons.star_rounded, size: 36, color: Colors.amberAccent),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          if (_currentUserId != null)
            ValueListenableBuilder<List<DocumentSnapshot>>(
              valueListenable: _friendRequestsNotifier,
              builder: (context, requests, child) {
                final requestCount = requests.length;
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(icon: const Icon(Icons.notifications_outlined, size: 32), onPressed: _showFriendRequestsBottomSheet),
                      if (requestCount > 0)
                        Positioned(
                          right: 8, top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Center(child: Text('$requestCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          ),
                        )
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.black87], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: AppBar().preferredSize.height + MediaQuery.of(context).padding.top),
              _isLoadingPosts
                  ? const Center(child: CupertinoActivityIndicator(color: Colors.white))
                  : _posts.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 50.0),
                          child: Center(child: Text(lang.t('create_post_no_posts'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: _posts.length,
                          itemBuilder: (context, index) => _buildPostCard(_posts[index])
                        ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                decoration: BoxDecoration(color: const Color.fromRGBO(255, 255, 255, 0.1), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(lang.t('create_post_new_post_header'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    if (_postController.text.trim().isNotEmpty || _mediaFile != null)
                      SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          onPressed: !_isLoading ? _submitPost : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlueAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 16)
                          ),
                          child: _isLoading 
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24, 
                                    child: CircularProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null, color: Colors.white, strokeWidth: 3, backgroundColor: Colors.white12)
                                  ),
                                  if (_uploadProgress > 0) ...[
                                    const SizedBox(width: 8),
                                    Text('${(_uploadProgress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ]
                                ],
                              )
                            : Text(lang.t('create_post_publish_button'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
              _buildCreatePostArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final lang = Provider.of<LanguageProvider>(context);
    final timestamp = DateTime.fromMillisecondsSinceEpoch(post[DatabaseHelper.colTimestamp] ?? DateTime.now().millisecondsSinceEpoch);
    final formattedTime = DateFormat('MMM d, yyyy  HH:mm').format(timestamp);
    final syncStatus = post[DatabaseHelper.colSyncStatus];
    final postText = post[DatabaseHelper.colText] as String?;

    final likes = post[DatabaseHelper.colLikes] ?? 0;
    final commentsCount = post[DatabaseHelper.colCommentsCount] ?? 0;
    final isLikedByMe = (post[DatabaseHelper.colIsLikedByMe] == 1) || (post[DatabaseHelper.colIsLikedByMe] == true);

    Icon syncIcon;
    switch (syncStatus) {
      case 'synced': syncIcon = const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16); break;
      case 'failed': syncIcon = const Icon(Icons.error, color: Colors.redAccent, size: 16); break;
      default: syncIcon = const Icon(Icons.sync, color: Colors.orangeAccent, size: 16);
    }

    final imageUrl = post[DatabaseHelper.colImageUrl] as String?;
    final videoUrl = post[DatabaseHelper.colVideoUrl] as String?;
    final heroTag = 'create_post_img_${post[DatabaseHelper.colPostId]}';

    String displayName = post[DatabaseHelper.colUserName] ?? lang.t('unknown_username');
    String? displayPhotoUrl = post[DatabaseHelper.colUserImageUrl];

    final bool isMyPost = post[DatabaseHelper.colUserId] == _currentUserId;
    if (isMyPost) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
        displayName = currentUser.displayName!;
      }
      if (currentUser != null && currentUser.photoURL != null) {
        displayPhotoUrl = currentUser.photoURL!;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 6), 
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(color: const Color.fromRGBO(255, 255, 255, 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 20, backgroundImage: displayPhotoUrl != null ? NetworkImage(displayPhotoUrl) : null, child: displayPhotoUrl == null ? const Icon(Icons.person, size: 20, color: Colors.white) : null),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    Row(children: [Text(formattedTime, style: TextStyle(color: Colors.white.withAlpha(178), fontSize: 12)), const SizedBox(width: 5), syncIcon]),
                  ],
                ),
              ),
              if (isMyPost)
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.more_horiz, color: Colors.white70), onPressed: () => _showPostOptions(post)),
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
                       Text('${postText.substring(0, maxLength)}...', style: TextStyle(fontSize: 16, color: Colors.white.withAlpha(230))),
                       const SizedBox(height: 4),
                       GestureDetector(
                         onTap: () => _showFullText(postText),
                         child: Container(
                           padding: const EdgeInsets.symmetric(vertical: 4.0),
                           child: Text(lang.t('read_more_text'), style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w900, fontSize: 18)),
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

          if (imageUrl != null || videoUrl != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullPhotoScreen(imageUrl: imageUrl, heroTag: heroTag, isLocalFile: !imageUrl.startsWith('http')))),
                          child: Hero(
                            tag: heroTag,
                            child: (imageUrl.startsWith('http') 
                                ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, 
                                    loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                                    errorBuilder: (context, error, stack) => const Icon(Icons.error, color: Colors.red),
                                  )
                                : Image.file(File(imageUrl), fit: BoxFit.cover, width: double.infinity)
                              ),
                          ),
                        )
                      : videoUrl != null && videoUrl.isNotEmpty 
                          ? _VideoPostDisplay(videoPath: videoUrl)
                          : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
          Divider(height: 20, color: Colors.white.withAlpha(51)),
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 8.0, 
            runSpacing: 4.0,
            children: [
              _buildActionPostButton(icon: isLikedByMe ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined, label: "$likes ${lang.t('likes_label')}", color: isLikedByMe ? Colors.blueAccent : Colors.white.withAlpha(204), onPressed: () => _handleLike(post)),
              _buildActionPostButton(icon: Icons.comment_outlined, label: "$commentsCount ${lang.t('comments_label')}", onPressed: () => _openComments(post)),
              _buildActionPostButton(icon: Icons.share_outlined, label: lang.t('share_menu_item'), onPressed: () => _sharePost(post)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionPostButton({required IconData icon, required String label, required VoidCallback onPressed, Color? color}) {
    return TextButton.icon(
      onPressed: onPressed, icon: Icon(icon, size: 18, color: color ?? Colors.white.withAlpha(204)), label: Text(label, style: TextStyle(color: color ?? Colors.white.withAlpha(230))),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }

  Widget _buildCreatePostArea() {
    final lang = Provider.of<LanguageProvider>(context);
    return Container(
      decoration: BoxDecoration(color: Colors.black.withAlpha(77), border: Border(top: BorderSide(color: Colors.white.withAlpha(51)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _postController,
              focusNode: _postFocusNode,
              autofocus: false,
              onChanged: (text) => setState(() {}),
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: lang.t('create_post_placeholder'), hintStyle: const TextStyle(color: Colors.white54), border: InputBorder.none)
            ),
          ),
          if (_mediaFile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 350),
                      child: _mediaType == 'video' && _videoController != null && _videoController!.value.isInitialized
                          ? GestureDetector(
                              onTap: () {
                                if (_videoController != null) {
                                  setState(() => _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play());
                                }
                              },
                              child: AspectRatio(
                                aspectRatio: _videoController!.value.aspectRatio,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(_videoController!),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        return Stack(
                                          children: _activeTextOverlays.map((text) {
                                            if (_editorViewerSize.width == 0) return const SizedBox.shrink();

                                            final scaleX = constraints.maxWidth / _editorViewerSize.width;
                                            final scaleY = constraints.maxHeight / _editorViewerSize.height;

                                            return Positioned(
                                              left: text.position.dx * scaleX,
                                              top: text.position.dy * scaleY,
                                              child: Transform.rotate(
                                                angle: text.rotation,
                                                child: Transform.scale(
                                                  scale: text.scale,
                                                  child: Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: text.backgroundColor,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      text.text,
                                                      style: TextStyle(
                                                        fontFamily: 'EmojiFont',
                                                        color: text.color,
                                                        fontSize: text.fontSize,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                    if (!_videoController!.value.isPlaying)
                                      Icon(Icons.play_circle_outline, color: Colors.white.withAlpha(204), size: 60),
                                    
                                    if (_isProcessingVideo)
                                      Container(
                                        color: Colors.black.withOpacity(0.5),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const CircularProgressIndicator(color: Colors.white),
                                              const SizedBox(height: 8),
                                              Text(lang.t('video_processing_in_background'), style: const TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            )
                          : Image.file(File(_mediaFile!.path), fit: BoxFit.cover, width: double.infinity),
                    ),
                  ),
                  Positioned(top: 8, right: 8, child: InkWell(onTap: () => _clearMedia(), child: const CircleAvatar(radius: 14, backgroundColor: Colors.black54, child: Icon(Icons.close, color: Colors.white, size: 18)))),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: _editMedia,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                          child: Row(
                            children: [
                              const Icon(Icons.edit, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(lang.t('edit_option'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          Divider(height: 1, color: Colors.white.withAlpha(51)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMediaButton(icon: Icons.photo_library, label: lang.t('post_media_photo'), color: Colors.lightBlueAccent, onPressed: () => _pickMedia(ImageSource.gallery)),
                
                // HANO NIHO DUFUNGIYE VIDEO POSTING KUGIRA BIZOZE MURI VERSION 2
                // _buildMediaButton(icon: Icons.video_library, label: lang.t('post_media_video'), color: Colors.redAccent, onPressed: () => _pickMedia(ImageSource.gallery, isVideo: true)),
                
                _buildMediaButton(icon: Icons.camera_alt, label: lang.t('post_media_camera'), color: Colors.greenAccent, onPressed: () => _pickMedia(ImageSource.camera)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaButton({required IconData icon, required String label, required Color color, required VoidCallback onPressed}) {
    return Material(
      color: color.withAlpha(38),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPostDisplay extends StatefulWidget {
  final String videoPath;
  const _VideoPostDisplay({required this.videoPath});

  @override
  State<_VideoPostDisplay> createState() => _VideoPostdiplayState();
}

class _VideoPostdiplayState extends State<_VideoPostDisplay> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.videoPath.isEmpty) return;

    bool isNetworkUrl = widget.videoPath.startsWith('http');

    _controller = isNetworkUrl
        ? VideoPlayerController.networkUrl(Uri.parse(widget.videoPath))
        : VideoPlayerController.file(File(widget.videoPath));

    _controller?.initialize().then((_) {
      if (mounted) {
        setState(() => _isVideoInitialized = true);
        _controller?.setLooping(true);
        _controller?.play();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _controller?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _controller?.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isVideoInitialized && _controller != null) {
      return GestureDetector(
        onTap: () => setState(() => _controller?.value.isPlaying ?? false ? _controller?.pause() : _controller?.play()),
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller!),
              if (!(_controller?.value.isPlaying ?? false))
                Icon(Icons.play_circle_outline, color: Colors.white.withAlpha(204), size: 60),
            ],
          ),
        ),
      );
    }
    return Container(height: 200, color: Colors.black, child: const Center(child: CupertinoActivityIndicator(color: Colors.white)));
  }
}