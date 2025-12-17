// lib/tangaza_star/tiktok_style_post.dart (VERSION IVUGURUYE)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/tangaza_star/user_profile_screen.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'feed_manager.dart';
import 'package:jembe_talk/language_provider.dart';

class TiktokStylePost extends StatefulWidget {
  final Map<String, dynamic> postData;
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

class _TiktokStylePostState extends State<TiktokStylePost> with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isPausedByUser = false;
  bool _showPauseIcon = false;
  
  late AnimationController _likeAnimationController;
  late Animation<double> _likeAnimation;
  double _likeAnimationOpacity = 0.0;

  late AnimationController _bottomSheetController;

  @override
  void initState() {
    super.initState();
    _likeAnimationController = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _likeAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _likeAnimationController, curve: Curves.elasticOut));
    
    _bottomSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), 
      reverseDuration: const Duration(milliseconds: 1000),
    );

    _setupController();
  }

  @override
  void didUpdateWidget(covariant TiktokStylePost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.postData[DatabaseHelper.colPostId] != oldWidget.postData[DatabaseHelper.colPostId]) {
      oldWidget.isPlaying ? _controller?.pause() : null;
      _setupController();
    } else {
      _updatePlayState();
    }
  }
  
  void _setupController() {
    final feedManager = context.read<FeedManager>();
    final postId = widget.postData[DatabaseHelper.colPostId] as String;
    _controller = feedManager.getPreloadedControllerFor(postId);
    _controller?.addListener(_updatePlayState);
    _updatePlayState();
  }

  void _updatePlayState() {
    if (!mounted) return;
    if (_controller != null && _controller!.value.isInitialized) {
      if (widget.isPlaying && !_isPausedByUser) {
        if (!_controller!.value.isPlaying) {
          _controller!.play();
        }
        _controller!.setVolume(1.0);
      } else {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        }
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_updatePlayState);
    if (_controller?.value.isPlaying ?? false) {
      _controller?.pause();
    }
    _likeAnimationController.dispose();
    _bottomSheetController.dispose(); 
    super.dispose();
  }
  
  String? _getOptimizedUrl(String? originalUrl, {required bool isImage}) {
    if (originalUrl == null || originalUrl.isEmpty) return null;
    try {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      final uri = Uri.parse(originalUrl);
      String path = uri.path;
      String encodedFileName = path.split('%2F').last;
      String originalFileName = Uri.decodeComponent(encodedFileName);
      if (originalFileName.startsWith('optimized_') || originalFileName.startsWith('thumb_')) {
        return originalUrl;
      }
      String baseName = originalFileName.contains('.') ? originalFileName.substring(0, originalFileName.lastIndexOf('.')) : originalFileName;
      
      String newPrefix = isImage ? 'optimized_' : 'thumb_';
      String newExtension = isImage ? 'webp' : 'jpg';
      
      String newFileName = '$newPrefix$baseName.$newExtension';
      String encodedNewFileName = Uri.encodeComponent(newFileName);
      
      return originalUrl.replaceAll(encodedFileName, encodedNewFileName);
    } catch (e) {
      debugPrint("${Provider.of<LanguageProvider>(context, listen: false).t('error_creating_optimized_url')} ($originalUrl): $e");
      return originalUrl;
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
  
  void _handleDoubleTap() {
    if (_likeAnimationController.isAnimating) return;
    if (!widget.isLiked) {
      widget.onLike();
    }
    setState(() => _likeAnimationOpacity = 1.0);
    _likeAnimationController.forward(from: 0.0).then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() => _likeAnimationOpacity = 0.0);
        }
      });
    });
  }

  void _showFullText(String fullText) {
    showModalBottomSheet(
      context: context,
      transitionAnimationController: _bottomSheetController,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75, 
        decoration: BoxDecoration(
          color: Colors.blueGrey[900]!.withOpacity(0.95), 
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 25),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(fullText, style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(30.0),
        ),
        clipBehavior: Clip.hardEdge,
        child: GestureDetector(
          onTap: _togglePlayPause,
          onDoubleTap: _handleDoubleTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildMediaBackground(),
              _buildForegroundContent(),
              if (_showPauseIcon)
                Center(child: Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.pause, color: Colors.white, size: 45))),
              Center(
                child: AnimatedOpacity(
                  opacity: _likeAnimationOpacity,
                  duration: const Duration(milliseconds: 300),
                  child: ScaleTransition(
                    scale: _likeAnimation,
                    child: const Icon(Icons.favorite, color: Colors.white, size: 90),
                  ),
                ),
              ),
              if (_controller != null && _controller!.value.isInitialized) _buildHorizontalProgressBar(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHorizontalProgressBar() {
    if (_controller == null || !_controller!.value.isInitialized) return const SizedBox.shrink();
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: VideoProgressIndicator(
        _controller!,
        allowScrubbing: true,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        colors: const VideoProgressColors(
          playedColor: Colors.white,
          bufferedColor: Colors.white30,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildMediaBackground() {
    final originalImageUrl = widget.postData[DatabaseHelper.colImageUrl] as String?;
    final imageUrl = _getOptimizedUrl(originalImageUrl, isImage: true);

    if (_controller != null) {
      if (_controller!.value.isInitialized) {
        return Center(child: AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!)));
      } else {
        if (imageUrl != null && imageUrl.isNotEmpty) {
          return CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain, placeholder: (context, url) => Container(color: Colors.black), errorWidget: (context, url, error) => _buildErrorWidget());
        }
        return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
      }
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain, placeholder: (context, url) => Container(color: Colors.black), errorWidget: (context, url, error) => _buildErrorWidget());
    }
    return _buildErrorWidget();
  }
  
  Widget _buildErrorWidget() {
    return const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.white24, size: 60));
  }

  Widget _buildForegroundContent() {
    final lang = Provider.of<LanguageProvider>(context);
    final userName = widget.postData[DatabaseHelper.colUserName] ?? lang.t('no_author_name');
    final userImageUrl = widget.postData[DatabaseHelper.colUserImageUrl] ?? '';
    final postText = widget.postData[DatabaseHelper.colText] as String?;
    final likes = widget.postData[DatabaseHelper.colLikes] ?? 0;
    final comments = widget.postData[DatabaseHelper.colCommentsCount] ?? 0;
    final views = widget.postData[DatabaseHelper.colViews] ?? 0;
    
    final displayTime = widget.postData['displayTime'] as String? ?? '';

    final TextStyle readableStyle = const TextStyle(
      color: Colors.white,
      fontSize: 16, 
      fontWeight: FontWeight.w600, 
      height: 1.4,
      shadows: [
        Shadow(
          offset: Offset(1.0, 1.0),
          blurRadius: 3.0,
          color: Colors.black, 
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ Colors.black.withAlpha(102), Colors.transparent, Colors.black.withAlpha(153) ],
          begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0.0, 0.4, 1.0],
        ),
      ),
      padding: const EdgeInsets.all(12.0).copyWith(bottom: 0),
      child: Stack(
        children: [
          Positioned(
            bottom: 30, left: 0, right: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (postText != null && postText.isNotEmpty)
                  Builder(
                    builder: (context) {
                      const int maxLength = 90;
                      final bool isLong = postText.length > maxLength;
                      
                      if (isLong) {
                         return Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(
                               '${postText.substring(0, maxLength)}...', 
                               style: readableStyle, 
                             ),
                             const SizedBox(height: 4),
                             GestureDetector(
                               onTap: () => _showFullText(postText),
                               child: Container(
                                 padding: const EdgeInsets.symmetric(vertical: 4.0),
                                 child: Text(
                                   lang.t('read_more_text'), 
                                   style: const TextStyle(
                                     color: Colors.lightBlueAccent, 
                                     fontWeight: FontWeight.w900,
                                     fontSize: 18, 
                                     shadows: [Shadow(color: Colors.black, offset: Offset(1,1), blurRadius: 2)]
                                   )
                                 ),
                               ),
                             ),
                           ],
                         );
                      } else {
                        return Text(postText, style: readableStyle);
                      }
                    }
                  ),
                
                const SizedBox(height: 10),

                GestureDetector(
                  onTap: () {
                    final authorId = widget.postData[DatabaseHelper.colUserId];
                    if (authorId != null) {
                        Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => UserProfileScreen(userId: authorId)),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20, backgroundColor: Colors.grey,
                        backgroundImage: userImageUrl.isNotEmpty ? CachedNetworkImageProvider(userImageUrl) : null,
                        child: userImageUrl.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(userName, style: const TextStyle(
                              color: Colors.white, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 16,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black)]
                            )),
                            
                            if (displayTime.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 3, height: 3, 
                                decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle)
                              ),
                              const SizedBox(width: 6),
                              Text(displayTime, style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black)]
                              )),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 85, right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(icon: Icons.remove_red_eye, text: views.toString(), color: Colors.white),
                const SizedBox(height: 20),
                _buildActionButton(icon: widget.isLiked ? Icons.favorite : Icons.favorite_border, text: likes.toString(), color: widget.isLiked ? Colors.red : Colors.white, onTap: widget.onLike),
                const SizedBox(height: 20),
                _buildActionButton(icon: Icons.comment_rounded, text: comments.toString(), color: Colors.white, onTap: widget.onComment),
                const SizedBox(height: 20),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'share') { widget.onShare(); } 
                    else if (value == 'save') { widget.onDownload(); } 
                    else if (value == 'report') { widget.onReport(); }
                  },
                  icon: const Icon(Icons.more_horiz, color: Colors.white, size: 30),
                  color: Colors.white,
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'share', child: Row(children: [ const Icon(Icons.share, color: Colors.black), const SizedBox(width: 10), Text(lang.t('share_menu_item')) ])),
                    PopupMenuItem<String>(value: 'save', child: Row(children: [ const Icon(Icons.download, color: Colors.black), const SizedBox(width: 10), Text(lang.t('save_menu_item')) ])),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(value: 'report', child: Row(children: [ const Icon(Icons.flag, color: Colors.black), const SizedBox(width: 10), Text(lang.t('report_menu_item')) ])),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String text, required Color color, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Icon(icon, size: 30, color: color, shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54)]),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black)]))
      ]),
    );
  }
}