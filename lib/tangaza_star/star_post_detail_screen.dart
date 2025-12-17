// lib/star_post_detail_screen.dart (VERSION IKOSOYE)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/tangaza_star/user_profile_screen.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';
import 'package:video_player/video_player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';

class StarPostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> postData;
  const StarPostDetailScreen({super.key, required this.postData});

  @override
  State<StarPostDetailScreen> createState() => _StarPostDetailScreenState();
}

class _StarPostDetailScreenState extends State<StarPostDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  VideoPlayerController? _videoController;
  Future<void>? _initializeVideoPlayerFuture;

  String? _getOptimizedUrl(String? originalUrl, {required bool isImage}) {
    if (originalUrl == null || originalUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(originalUrl);
      String path = uri.path;
      String encodedFileName = path.split('%2F').last;
      String originalFileName = Uri.decodeComponent(encodedFileName);

      if (originalFileName.startsWith('optimized_') || originalFileName.startsWith('thumb_')) {
        return originalUrl;
      }

      String baseName = originalFileName.contains('.')
          ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
          : originalFileName;
      
      String newPrefix = isImage ? 'optimized_' : 'thumb_';
      String newExtension = isImage ? 'webp' : 'jpg';
      
      String newFileName = '$newPrefix$baseName.$newExtension';
      String encodedNewFileName = Uri.encodeComponent(newFileName);
      
      return originalUrl.replaceAll(encodedFileName, encodedNewFileName);
    } catch (e) {
      return originalUrl;
    }
  }

  @override
  void initState() {
    super.initState();
    final originalVideoUrl = widget.postData[DatabaseHelper.colVideoUrl] as String?;
    final videoUrl = _getOptimizedUrl(originalVideoUrl, isImage: false);

    if (videoUrl != null && videoUrl.isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _initializeVideoPlayerFuture = _videoController!.initialize().then((_) {
        if (mounted) {
          setState(() {
            _videoController!.play();
            _videoController!.setLooping(true);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String postId = widget.postData[DatabaseHelper.colPostId];

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('posts').doc(postId).snapshots(),
        builder: (context, snapshot) {
          final Map<String, dynamic> initialData = widget.postData;
          Map<String, dynamic> liveData = {};

          if (snapshot.hasData && snapshot.data!.exists) {
            liveData = snapshot.data!.data() as Map<String, dynamic>;
          }

          final Map<String, dynamic> currentPostData = {...initialData, ...liveData};

          return Stack(
            fit: StackFit.expand,
            children: [
              _buildMediaBackground(currentPostData),
              _buildGradientOverlay(),
              _buildContentOverlay(currentPostData),
              _buildAppBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMediaBackground(Map<String, dynamic> postData) {
    final originalImageUrl = postData[DatabaseHelper.colImageUrl] as String?;
    final imageUrl = _getOptimizedUrl(originalImageUrl, isImage: true);

    if (_videoController != null && _initializeVideoPlayerFuture != null) {
      return FutureBuilder(
        future: _initializeVideoPlayerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && _videoController!.value.isInitialized) {
            return Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            );
          }
          else if (imageUrl != null && imageUrl.isNotEmpty) {
             return CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              );
          }
          return const Center(child: CircularProgressIndicator());
        },
      );
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return Container(color: Colors.black);
  }

  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.6),
            Colors.transparent,
            Colors.black.withOpacity(0.8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildContentOverlay(Map<String, dynamic> postData) {
    final lang = Provider.of<LanguageProvider>(context);
    final userId = postData[DatabaseHelper.colUserId] as String?;
    final userName = postData[DatabaseHelper.colUserName] as String? ?? lang.t('no_author_name');
    final userImageUrl = postData[DatabaseHelper.colUserImageUrl] as String?;
    final content = postData[DatabaseHelper.colText] as String?;
    final likes = postData[DatabaseHelper.colLikes] as int? ?? 0;
    final comments = postData[DatabaseHelper.colCommentsCount] as int? ?? 0;
    final views = postData[DatabaseHelper.colViews] as int? ?? 0;

    dynamic timestampValue = postData['timestamp_server'];
    Timestamp? timestamp;
    if (timestampValue is Timestamp) {
      timestamp = timestampValue;
    } else if (timestampValue is int) {
      timestamp = Timestamp.fromMillisecondsSinceEpoch(timestampValue);
    }

    final formattedTime = timestamp != null
        ? DateFormat('MMM d, yyyy  HH:mm').format(timestamp.toDate())
        : lang.t('unknown_time');

    final heroTag = 'user-profile-photo-$userId';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                if (userId != null) {
                  Navigator.push(
                    context,
                    CustomPageRoute(
                      child: UserProfileScreen(userId: userId),
                    ),
                  );
                }
              },
              child: Container(
                color: Colors.transparent,
                child: Row(
                  children: [
                    Hero(
                      tag: heroTag,
                      child: CircleAvatar(
                        radius: 25,
                        backgroundImage: userImageUrl != null && userImageUrl.isNotEmpty
                            ? CachedNetworkImageProvider(userImageUrl)
                            : null,
                        child: userImageUrl == null || userImageUrl.isEmpty
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
                          ),
                          Text(
                            formattedTime,
                            style: TextStyle(color: Colors.grey[300], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (content != null && content.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                content,
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 16, 
                  height: 1.5,
                  shadows: [Shadow(blurRadius: 2, color: Colors.black)]
                ),
              ),
            ],
            Divider(color: Colors.grey[700], height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatIcon(Icons.thumb_up_alt_outlined, likes.toString(), lang.t('likes_label')),
                _buildStatIcon(Icons.comment_outlined, comments.toString(), lang.t('comments_label')),
                _buildStatIcon(Icons.visibility_outlined, views.toString(), lang.t('views_label')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final lang = Provider.of<LanguageProvider>(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          lang.t('star_post_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
        ),
      ),
    );
  }

  Widget _buildStatIcon(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}