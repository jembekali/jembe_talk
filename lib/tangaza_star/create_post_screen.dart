// lib/tangaza_star/create_post_screen.dart (CODE YANYUMA KANDI IKOSOYE BURUNDU)

import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <<<--- TWONGEREYEMWO IYI KUGIRA DUKORESHE HTTPCLIENT
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/tangaza_star/comment_screen.dart';
import 'package:jembe_talk/tangaza_star/video_trimmer_screen.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';


class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _postController = TextEditingController();
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  XFile? _mediaFile;
  String? _mediaType;
  VideoPlayerController? _videoController;
  List<Map<String, dynamic>> _posts = [];
  bool _isLoadingPosts = true;
  final _mediaStorePlugin = MediaStore();

  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadPosts();
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

  @override
  void dispose() {
    _postController.dispose();
    _videoController?.dispose();
    super.dispose();
  }
  
  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    if (!isVideo) {
      final XFile? file = await _picker.pickImage(source: source, imageQuality: 90);
      if (file == null) return;
      
      final Uint8List imageBytes = await file.readAsBytes();
      
      if (!mounted) return;
      final Uint8List? editedImageBytes = await Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => ImageEditor(image: imageBytes))
      );

      if (editedImageBytes != null) {
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final tempFile = await File(tempPath).writeAsBytes(editedImageBytes);
        setState(() {
          _mediaFile = XFile(tempFile.path); _mediaType = 'image'; _videoController?.dispose(); _videoController = null;
        });
      }
      return;
    }

    final XFile? videoFile = await _picker.pickVideo(source: source);
    if (videoFile == null) return;

    if (!mounted) return; 
    final File? editedVideo = await Navigator.push<File>(
      context,
      MaterialPageRoute<File>(builder: (context) => VideoTrimmerScreen(videoFile: File(videoFile.path))),
    );

    if (editedVideo == null) return;
    
    await _videoController?.dispose();
    final newController = VideoPlayerController.file(editedVideo);
    await newController.initialize();

    if (!mounted) {
      await newController.dispose();
      return;
    }

    setState(() {
      _mediaFile = XFile(editedVideo.path);
      _mediaType = 'video';
      _videoController = newController;
      _videoController!.play();
      _videoController!.setLooping(true);
    });
  }
  
  Future<void> _submitPost() async {
    if (_isLoading || _currentUserId == null) return;
    final content = _postController.text.trim();
    if (content.isEmpty && _mediaFile == null) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ugomba kwandika ikintu canke ugashirako ifoto/video.")));
      return;
    }
    
    setState(() { _isLoading = true; });

    final postId = const Uuid().v4();
    String? imageUrl;
    String? videoUrl;

    try {
      if (_mediaFile != null) {
        final file = File(_mediaFile!.path);
        final ref = _storage.ref().child('posts').child(_currentUserId!).child('$postId.${_mediaType == 'image' ? 'jpg' : 'mp4'}');
        final uploadTask = ref.putFile(file);
        final snapshot = await uploadTask.whenComplete(() {});
        final downloadUrl = await snapshot.ref.getDownloadURL();
        
        if (_mediaType == 'image') {
          imageUrl = downloadUrl;
        } else {
          videoUrl = downloadUrl;
        }
      }

      final postDataForFirebase = {
        'content': content,
        'userId': _currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0, 'views': 0, 'isStar': false, 'likedBy': [],
        'imageUrl': imageUrl,
        'videoUrl': videoUrl,
      };
      await _firestore.collection('posts').doc(postId).set(postDataForFirebase);
      
      final currentUser = FirebaseAuth.instance.currentUser;
      final postDataForDB = {
        DatabaseHelper.colPostId: postId, 
        DatabaseHelper.colUserId: _currentUserId, 
        DatabaseHelper.colUserName: currentUser?.displayName ?? 'Ata Zina', 
        DatabaseHelper.colUserImageUrl: currentUser?.photoURL, 
        DatabaseHelper.colText: content, 
        DatabaseHelper.colImageUrl: imageUrl,
        DatabaseHelper.colVideoUrl: videoUrl,
        DatabaseHelper.colTimestamp: DateTime.now().millisecondsSinceEpoch, 
        DatabaseHelper.colSyncStatus: 'synced',
        DatabaseHelper.colLikes: 0, 
        DatabaseHelper.colCommentsCount: 0, 
        DatabaseHelper.colViews: 0, 
        DatabaseHelper.colIsLikedByMe: 0,
      };

      await DatabaseHelper.instance.savePost(postDataForDB);

      if (mounted) {
        Navigator.of(context).pop();
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Habaye ikibazo: $e")));
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }
  
  void _clearMedia() {
    setState(() {
      _mediaFile = null; _mediaType = null; _videoController?.dispose(); _videoController = null;
    });
  }
  
  // <<<--- IKOSORWA: Iyi function yose yarasubiwemwo kugira ikure dosiye kuri internet imbere yo kuyisangiza ---<<<
  Future<void> _sharePost(Map<String, dynamic> post) async {
    final text = post[DatabaseHelper.colText] as String? ?? '';
    final imageUrl = post[DatabaseHelper.colImageUrl] as String?;
    final videoUrl = post[DatabaseHelper.colVideoUrl] as String?;

    try {
      final List<XFile> filesToShare = [];
      final tempDir = await getTemporaryDirectory();

      // Function yo gukurura dosiye
      Future<XFile?> downloadFile(String url, String fileName) async {
        try {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(url));
          final response = await request.close();
          final bytes = await consolidateHttpClientResponseBytes(response);
          final filePath = '${tempDir.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(bytes);
          return XFile(filePath);
        } catch (e) {
          return null;
        }
      }

      if (imageUrl != null && imageUrl.isNotEmpty) {
        final file = await downloadFile(imageUrl, 'image.jpg');
        if (file != null) filesToShare.add(file);
      }
      if (videoUrl != null && videoUrl.isNotEmpty) {
         final file = await downloadFile(videoUrl, 'video.mp4');
        if (file != null) filesToShare.add(file);
      }

      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(filesToShare, text: text);
      } else {
        await Share.share(text);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gusangiza byanze: $e")));
    }
  }

  Future<void> _downloadMedia(Map<String, dynamic> post) async {
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ugomba kwemera uburenganzira bwo kubika.")));
      return;
    }
    final imageUrl = post[DatabaseHelper.colImageUrl] as String?;
    final videoUrl = post[DatabaseHelper.colVideoUrl] as String?;
    if (imageUrl == null && videoUrl == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nta media yo gukurura kuri iyi post.")));
      return;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Urikurura...")));

    try {
      final url = imageUrl ?? videoUrl!;
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      final downloadedBytes = await consolidateHttpClientResponseBytes(response);
      
      final tempDir = await getTemporaryDirectory();
      final tempFile = await File('${tempDir.path}/temp_media').writeAsBytes(downloadedBytes);

      await _mediaStorePlugin.saveFile(tempFilePath: tempFile.path, dirType: imageUrl != null ? DirType.photo : DirType.video, dirName: DirName.download);
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Byabitswe neza muri Downloads!"), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gukurura byanze: $e"), backgroundColor: Colors.red));
    }
  }
  
  Future<void> _deletePost(String postId) async {
    await DatabaseHelper.instance.deletePost(postId);
    if (mounted) {
      setState(() { _posts.removeWhere((post) => post[DatabaseHelper.colPostId] == postId); });
    }
  }

  Future<void> _showDeletePostConfirmation(String postId) async {
    showDialog(context: context, builder: (BuildContext context) => AlertDialog(
      title: const Text("Gufuta Iposita"), content: const Text("Vyukuri urashaka gufuta iyi posita burundu?"),
      actions: [
        TextButton(child: const Text("Oya"), onPressed: () => Navigator.of(context).pop()),
        TextButton(
          child: const Text("Ego, futa", style: TextStyle(color: Colors.red)),
          onPressed: () { Navigator.of(context).pop(); _deletePost(postId); },
        ),
      ],
    ));
  }

  void _showPostOptions(Map<String, dynamic> post) {
    showModalBottomSheet(context: context, builder: (context) => Wrap(
      children: <Widget>[
        ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Gukosora Iposita'), onTap: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Igikorwa co gukosora iposita ntikirashirwamo.'))); }),
        ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Gufuta Iposita', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _showDeletePostConfirmation(post[DatabaseHelper.colPostId]); }),
      ],
    ));
  }

  void _openComments(Map<String, dynamic> postData) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => CommentScreen(postData: postData)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ibishasha kuri Tangaza Star", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white,
        actions: [
          if (_postController.text.trim().isNotEmpty || _mediaFile != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                onPressed: !_isLoading ? _submitPost : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Tangaza", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
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
                          child: const Center(child: Text("Nta posita yawe iraboneka.\nKora iya mbere!", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero, 
                          itemCount: _posts.length, 
                          itemBuilder: (context, index) => _buildPostCard(_posts[index])
                        ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                decoration: BoxDecoration( color: const Color.fromRGBO(255, 255, 255, 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Center( child: Text("KORA POST NSHASHA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
              ),
              _buildCreatePostArea(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPostCard(Map<String, dynamic> post) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(post[DatabaseHelper.colTimestamp] ?? DateTime.now().millisecondsSinceEpoch);
    final formattedTime = DateFormat('MMM d, yyyy  HH:mm').format(timestamp);
    final syncStatus = post[DatabaseHelper.colSyncStatus];

    Icon syncIcon; String syncTooltip;
    switch (syncStatus) {
      case 'synced': syncIcon = const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16); syncTooltip = 'Yageze kuri serveri'; break;
      case 'failed': syncIcon = const Icon(Icons.error, color: Colors.redAccent, size: 16); syncTooltip = 'Kwohereza byaranze'; break;
      default: syncIcon = const Icon(Icons.sync, color: Colors.orangeAccent, size: 16); syncTooltip = 'Itegereje interineti';
    }
    
    final imageUrl = post[DatabaseHelper.colImageUrl] as String?;
    final videoUrl = post[DatabaseHelper.colVideoUrl] as String?;

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
              CircleAvatar(
                radius: 20, 
                // <<<--- IKOSORWA: Gukuraho '!' itari ngombwa ---<<<
                backgroundImage: post[DatabaseHelper.colUserImageUrl] != null ? NetworkImage(post[DatabaseHelper.colUserImageUrl]) : null, 
                child: post[DatabaseHelper.colUserImageUrl] == null ? const Icon(Icons.person, size: 20, color: Colors.white) : null
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post[DatabaseHelper.colUserName] ?? 'Amazina atazwi', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    Row(children: [Text(formattedTime, style: TextStyle(color: Colors.white.withAlpha(178), fontSize: 12)), const SizedBox(width: 5), Tooltip(message: syncTooltip, child: syncIcon)]),
                  ],
                ),
              ),
              IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.more_horiz, color: Colors.white70), onPressed: () => _showPostOptions(post)),
            ],
          ),
          // <<<--- IKOSORWA: Gukuraho '!' itari ngombwa ---<<<
          if (post[DatabaseHelper.colText] != null && post[DatabaseHelper.colText].isNotEmpty) ...[
            const SizedBox(height: 12), 
            Text(post[DatabaseHelper.colText], style: TextStyle(fontSize: 16, color: Colors.white.withAlpha(230)))
          ],
          if (imageUrl != null || videoUrl != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, 
                          loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                          errorBuilder: (context, error, stack) => const Icon(Icons.error, color: Colors.red),
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
              _buildActionPostButton(icon: Icons.thumb_up_alt_outlined, label: "${post[DatabaseHelper.colLikes]} Likes", onPressed: () {}),
              _buildActionPostButton(icon: Icons.comment_outlined, label: "${post[DatabaseHelper.colCommentsCount]} Ivyiyumviro", onPressed: () => _openComments(post)),
              _buildActionPostButton(icon: Icons.share_outlined, label: "Share", onPressed: () => _sharePost(post)),
              _buildActionPostButton(icon: Icons.download_outlined, label: "Download", onPressed: () => _downloadMedia(post)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionPostButton({required IconData icon, required String label, required VoidCallback onPressed}) {
    return TextButton.icon(
      onPressed: onPressed, icon: Icon(icon, size: 18, color: Colors.white.withAlpha(204)), label: Text(label, style: TextStyle(color: Colors.white.withAlpha(230))),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }

  Widget _buildCreatePostArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(77),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(51)))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _postController, 
              onChanged: (text) => setState(() {}), 
              maxLines: 3, 
              minLines: 1,
              style: const TextStyle(color: Colors.white), 
              keyboardType: TextInputType.multiline, 
              textCapitalization: TextCapitalization.sentences, 
              decoration: const InputDecoration(
                hintText: 'Uvyiyumvirako iki uno musi?', 
                hintStyle: TextStyle(color: Colors.white54), 
                border: InputBorder.none
              )
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
                                setState(() {
                                  if (_videoController!.value.isPlaying) {
                                    _videoController!.pause();
                                  } else {
                                    _videoController!.play();
                                  }
                                });
                              },
                              child: AspectRatio(
                                aspectRatio: _videoController!.value.aspectRatio,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(_videoController!),
                                    if (!_videoController!.value.isPlaying)
                                      Icon(Icons.play_circle_outline, color: Colors.white.withAlpha(204), size: 60),
                                  ],
                                ),
                              ),
                            )
                          : Image.file(File(_mediaFile!.path), fit: BoxFit.cover, width: double.infinity),
                    ),
                  ),
                  Positioned(top: 8, right: 8, child: InkWell(onTap: _clearMedia, child: const CircleAvatar(radius: 14, backgroundColor: Colors.black54, child: Icon(Icons.close, color: Colors.white, size: 18)))),
                ],
              ),
            ),
          
          Divider(height: 1, color: Colors.white.withAlpha(51)),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMediaButton(icon: Icons.photo_library, label: "Ifoto", color: Colors.lightBlueAccent, onPressed: () => _pickMedia(ImageSource.gallery)),
                _buildMediaButton(icon: Icons.video_library, label: "Video", color: Colors.redAccent, onPressed: () => _pickMedia(ImageSource.gallery, isVideo: true)),
                _buildMediaButton(icon: Icons.camera_alt, label: "Camera", color: Colors.greenAccent, onPressed: () => _pickMedia(ImageSource.camera)),
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

class _VideoPostdiplayState extends State<_VideoPostDisplay> {
  VideoPlayerController? _controller;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoPath.isEmpty) return;

    bool isNetworkUrl = widget.videoPath.startsWith('http');
    
    _controller = isNetworkUrl
        ? VideoPlayerController.networkUrl(Uri.parse(widget.videoPath))
        : VideoPlayerController.file(File(widget.videoPath));

    _controller?.initialize().then((_) {
      if (mounted) {
        setState(() { _isVideoInitialized = true; });
        _controller?.setLooping(true);
        _controller?.play();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isVideoInitialized && _controller != null) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _controller?.value.isPlaying ?? false ? _controller?.pause() : _controller?.play();
          });
        },
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
    return Container(
      height: 200,
      color: Colors.black,
      child: const Center(child: CupertinoActivityIndicator(color: Colors.white)),
    );
  }
}