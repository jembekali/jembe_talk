// lib/tangaza_star/tiktok_style_post.dart (VERSION YANYUMA KANDI NZIMA 100%)

import 'package:flutter/material.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:jembe_talk/services/database_helper.dart';

class TiktokStylePost extends StatefulWidget {
  final Map<String, dynamic> postData;
  final List<Map<String, dynamic>> subsequentPosts;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onReport;
  final bool isPlaying;

  const TiktokStylePost({
    super.key,
    required this.postData,
    required this.subsequentPosts,
    required this.isLiked,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onDownload,
    required this.onReport,
    required this.isPlaying,
  });

  @override
  State<TiktokStylePost> createState() => _TiktokStylePostState();
}

class _TiktokStylePostState extends State<TiktokStylePost> {
  VideoPlayerController? _controller;
  Future<void>? _initializeVideoPlayerFuture;

  bool _isDisposed = false;
  final List<VideoPlayerController> _preloadedControllers = [];

  bool _isPausedByUser = false;
  bool _showPauseIcon = false;
  double _videoProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeCurrentVideo();
    _startSequentialPreloading();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller?.removeListener(_updateProgress);
    _controller?.dispose();
    for (var controller in _preloadedControllers) {
      controller.dispose();
    }
    _preloadedControllers.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TiktokStylePost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null && _controller!.value.isInitialized) {
      if (widget.isPlaying && !_isPausedByUser) {
        _controller!.play();
      } else {
        _controller!.pause();
      }
    }
  }

  void _initializeCurrentVideo() {
    final originalVideoUrl =
        widget.postData[DatabaseHelper.colVideoUrl] as String?;
    final videoUrl = _getOptimizedUrl(originalVideoUrl, isImage: false);

    if (videoUrl != null && videoUrl.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _initializeVideoPlayerFuture = _controller!.initialize().then((_) {
        if (mounted) {
          _controller!.setLooping(true);
          _controller!.setVolume(1.0);
          if (widget.isPlaying) {
            _controller!.play();
          }
          _controller!.addListener(_updateProgress);
          setState(() {});
        }
      });
    }
  }

  Future<void> _startSequentialPreloading() async {
    final postsToPreload = widget.subsequentPosts.take(5);

    for (final postData in postsToPreload) {
      if (_isDisposed) break;

      final originalVideoUrl = postData[DatabaseHelper.colVideoUrl] as String?;
      final videoUrl = _getOptimizedUrl(originalVideoUrl, isImage: false);

      if (videoUrl != null && videoUrl.isNotEmpty) {
        try {
          final preloadedController =
              VideoPlayerController.networkUrl(Uri.parse(videoUrl));

          _preloadedControllers.add(preloadedController);
          await preloadedController.initialize();

          debugPrint("Video yateguwe (pre-loaded): $videoUrl");
        } catch (e) {
          debugPrint("Ikosa ryo gutegura video: $e");
        }
      }
    }
  }

  String? _getOptimizedUrl(String? originalUrl, {required bool isImage}) {
    if (originalUrl == null || originalUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(originalUrl);
      String path = uri.path;
      String encodedFileName = path.split('%2F').last;
      String originalFileName = Uri.decodeComponent(encodedFileName);

      if (originalFileName.startsWith('optimized_')) {
        return originalUrl;
      }

      String baseName = originalFileName.contains('.')
          ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
          : originalFileName;

      String newExtension = isImage ? 'webp' : 'mp4';
      String newFileName = 'optimized_$baseName.$newExtension';
      String encodedNewFileName = Uri.encodeComponent(newFileName);
      String newUrl =
          originalUrl.replaceAll(encodedFileName, encodedNewFileName);
      return newUrl;
    } catch (e) {
      debugPrint("Ikosa ryo guhimba URL nshya ($originalUrl): $e");
      return originalUrl;
    }
  }

  void _updateProgress() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (mounted) {
      setState(() {
        final duration = _controller!.value.duration;
        final position = _controller!.value.position;
        _videoProgress = (duration.inMilliseconds > 0)
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPausedByUser = true;
        _showPauseIcon = true;
      } else {
        _controller!.play();
        _isPausedByUser = false;
      }
    });

    if (_showPauseIcon) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showPauseIcon = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildMediaBackground(),
          _buildForegroundContent(),
          if (_showPauseIcon)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    // <<<--- ICYAHINDUWE: Twakuyemo .withOpacity() ---<<<
                    color: Colors.black54,
                    shape: BoxShape.circle),
                child: const Icon(Icons.pause, color: Colors.white, size: 45),
              ),
            ),
          if (_controller != null && _controller!.value.isInitialized)
            _buildHorizontalProgressBar(),
        ],
      ),
    );
  }

  Widget _buildHorizontalProgressBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2.0,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
        ),
        child: Slider(
          value: _videoProgress,
          min: 0.0,
          max: 1.0,
          activeColor: Colors.white,
          // <<<--- ICYAHINDUWE: Twakuyemo .withOpacity() ---<<<
          inactiveColor: Colors.white30,
          onChanged: (newValue) {
            _controller?.seekTo(_controller!.value.duration * newValue);
          },
          onChangeStart: (value) {
            if (!_isPausedByUser) _controller?.pause();
          },
          onChangeEnd: (value) {
            if (!_isPausedByUser) _controller?.play();
          },
        ),
      ),
    );
  }

  Widget _buildMediaBackground() {
    final videoUrl = _getOptimizedUrl(
        widget.postData[DatabaseHelper.colVideoUrl],
        isImage: false);
    final imageUrl = _getOptimizedUrl(
        widget.postData[DatabaseHelper.colImageUrl],
        isImage: true);

    if (videoUrl != null && _controller != null) {
      return FutureBuilder(
        future: _initializeVideoPlayerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              _controller!.value.isInitialized) {
            return SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  // <<<--- ICYAHINDUWE: Twakoresheje 'VideoPlayer' aho kuba 'CachedVideoPlayerPlus' ---<<<
                  child: VideoPlayer(_controller!),
                ),
              ),
            );
          } else {
            if (imageUrl != null && imageUrl.isNotEmpty) {
              return Container(
                decoration: BoxDecoration(
                    image: DecorationImage(
                        image: NetworkImage(imageUrl), fit: BoxFit.cover)),
              );
            }
            return Container(color: Colors.black);
          }
        },
      );
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
              image: NetworkImage(imageUrl), fit: BoxFit.cover),
        ),
      );
    }
    return Container(color: Colors.grey.shade900);
  }

  Widget _buildForegroundContent() {
    final userName = widget.postData[DatabaseHelper.colUserName] ?? 'Ata zina';
    final userImageUrl =
        widget.postData[DatabaseHelper.colUserImageUrl] ?? '';
    final postText = widget.postData[DatabaseHelper.colText] as String?;
    final likes = widget.postData[DatabaseHelper.colLikes] ?? 0;
    final comments =
        widget.postData[DatabaseHelper.colCommentsCount] ?? 0;
    final views = widget.postData[DatabaseHelper.colViews] ?? 0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            // <<<--- ICYAHINDUWE: Twakuyemo .withOpacity() ---<<<
            Colors.black.withAlpha(102), // aribyo nka 0.4
            Colors.transparent,
            Colors.black.withAlpha(153), // aribyo nka 0.6
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      padding: const EdgeInsets.all(12.0).copyWith(bottom: 0),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey,
                  backgroundImage:
                      userImageUrl.isNotEmpty ? NetworkImage(userImageUrl) : null,
                  child: userImageUrl.isEmpty
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      const SizedBox(height: 4),
                      if (postText != null && postText.isNotEmpty)
                        Text(postText,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 85,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(
                    icon: Icons.remove_red_eye,
                    text: views.toString(),
                    color: Colors.white),
                const SizedBox(height: 20),
                _buildActionButton(
                    icon: widget.isLiked
                        ? Icons.favorite
                        : Icons.favorite_border,
                    text: likes.toString(),
                    color: widget.isLiked ? Colors.red : Colors.white,
                    onTap: widget.onLike),
                const SizedBox(height: 20),
                _buildActionButton(
                    icon: Icons.comment_rounded,
                    text: comments.toString(),
                    color: Colors.white,
                    onTap: widget.onComment),
                const SizedBox(height: 20),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'share') {
                      widget.onShare();
                    } else if (value == 'save') {
                      widget.onDownload();
                    } else if (value == 'report') {
                      widget.onReport();
                    }
                  },
                  icon: const Icon(Icons.more_horiz,
                      color: Colors.white, size: 30),
                  color: Colors.white,
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                        value: 'share',
                        child: Row(children: const [
                          Icon(Icons.share, color: Colors.black),
                          SizedBox(width: 10),
                          Text('Share')
                        ])),
                    PopupMenuItem<String>(
                        value: 'save',
                        child: Row(children: const [
                          Icon(Icons.download, color: Colors.black),
                          SizedBox(width: 10),
                          Text('Save')
                        ])),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                        value: 'report',
                        child: Row(children: const [
                          Icon(Icons.flag, color: Colors.black),
                          SizedBox(width: 10),
                          Text('Report')
                        ])),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
      required String text,
      required Color color,
      VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Icon(icon, size: 30, color: color),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 12))
      ]),
    );
  }
}