import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/database_helper.dart';
import '../services/r2_service.dart';
import '../services/file_storage_service.dart';
import 'feed_manager.dart';
import 'user_profile_screen.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/post_translations.dart';

class TiktokStylePost extends StatefulWidget {
  final Map<String, dynamic> postData;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onReport;
  final bool isVisible;

  const TiktokStylePost({
    super.key,
    required this.postData,
    required this.isLiked,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onDownload,
    required this.onReport,
    required this.isVisible,
  });

  @override
  State<TiktokStylePost> createState() => _TiktokStylePostState();
}

class _TiktokStylePostState extends State<TiktokStylePost>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  Timer? _viewTimer;
  bool _isViewCounted = false;

  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;
  late Animation<double> _likeOpacityAnimation;

  late AnimationController _playPauseController;
  IconData _playPauseIcon = Icons.play_arrow;
  double _playPauseOpacity = 0.0;

  late ImageProvider _cachedFullImageProvider;
  late ImageProvider _cachedThumbProvider;
  bool _isImageInitialized = false;

  bool _isVideoActuallyPlaying = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('en_short', timeago.EnShortMessages());

    _likeAnimationController = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);

    _likeScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.2)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 60),
    ]).animate(_likeAnimationController);

    _likeOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_likeAnimationController);

    _playPauseController = AnimationController(
        duration: const Duration(milliseconds: 400), vsync: this);

    _initImageProviders();
    if (widget.isVisible) {
      _startViewTimer();
    }
  }

  void _initImageProviders() {
    final String fullUrl =
        _formatUrl(widget.postData[DatabaseHelper.colImageUrl] ?? "");
    final String thumbUrl = _formatUrl(widget.postData['thumbnailUrl'] ??
        widget.postData[DatabaseHelper.colImageUrl] ??
        "");

    _cachedThumbProvider = ResizeImage(
      CachedNetworkImageProvider(thumbUrl,
          headers: {'X-Jembe-Auth': R2Service.workerSecretKey}),
      width: 250,
    );

    _cachedFullImageProvider = ResizeImage(
      CachedNetworkImageProvider(fullUrl,
          headers: {'X-Jembe-Auth': R2Service.workerSecretKey}),
      width: 800,
    );

    _isImageInitialized = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isImageInitialized) {
      precacheImage(_cachedThumbProvider, context);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) precacheImage(_cachedFullImageProvider, context);
      });
    }
  }

  @override
  void didUpdateWidget(covariant TiktokStylePost oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.isVisible && oldWidget.isVisible) {
      final feedManager = context.read<FeedManager>();
      if (feedManager.activePostId ==
          widget.postData[DatabaseHelper.colPostId]) {
        feedManager.activeController?.pause();
      }
    }

    if (widget.postData[DatabaseHelper.colPostId] !=
        oldWidget.postData[DatabaseHelper.colPostId]) {
      _isVideoActuallyPlaying = false;
      _isViewCounted = false;
      _initImageProviders();
    }

    if (widget.isVisible && !oldWidget.isVisible) {
      _startViewTimer();
    }
  }

  void _handleTap(FeedManager feedManager, bool isVideo) {
    if (!isVideo ||
        feedManager.activePostId != widget.postData[DatabaseHelper.colPostId]) {
      return;
    }

    final bool isCurrentlyPlaying =
        feedManager.activeController?.value.isPlaying ?? false;
    feedManager.togglePlayback();

    setState(() {
      _playPauseIcon =
          isCurrentlyPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
      _playPauseOpacity = 0.8;
    });

    _playPauseController.forward(from: 0.0).then((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _playPauseOpacity = 0.0);
      });
    });
  }

  String _formatUrl(String? url) {
    if (url == null || url.isEmpty) return "";
    if (url.contains('auth=')) return url;
    return "${R2Service.workerUrl}${Uri.parse(url).path}?auth=${R2Service.workerSecretKey}";
  }

  void _startViewTimer() {
    if (_isViewCounted || !mounted) return;
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && widget.isVisible && !_isViewCounted) {
        _isViewCounted = true;
        context
            .read<FeedManager>()
            .markPostAsViewed(widget.postData[DatabaseHelper.colPostId]);
      }
    });
  }

  void _triggerLike() {
    HapticFeedback.heavyImpact();
    if (!widget.isLiked) widget.onLike();
    _likeAnimationController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    _likeAnimationController.dispose();
    _playPauseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final feedManager = context.watch<FeedManager>();
    final String postId = widget.postData[DatabaseHelper.colPostId];
    final bool isVideo = widget.postData['networkVideoUrl'] != null;
    final bool isActivePost = (feedManager.activePostId == postId);
    final controller = feedManager.activeController;

    return Container(
      color: Colors.black,
      child: GestureDetector(
        onTap: () => _handleTap(feedManager, isVideo),
        onDoubleTap: _triggerLike,
        behavior: HitTestBehavior.opaque,
        child: Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
            child: _isImageInitialized
                ? Stack(fit: StackFit.expand, children: [
                    Image(
                        image: _cachedThumbProvider,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (c, e, s) =>
                            Container(color: Colors.black)),
                    Image(
                        image: _cachedFullImageProvider,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (c, e, s) => const SizedBox.shrink()),
                  ])
                : Container(color: Colors.black),
          ),

          if (isVideo && isActivePost && controller != null)
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, child) {
                  if (value.isInitialized &&
                      value.isPlaying &&
                      !_isVideoActuallyPlaying) {
                    Future.microtask(() {
                      if (mounted)
                        setState(() => _isVideoActuallyPlaying = true);
                    });
                  }

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (value.isInitialized)
                        AnimatedOpacity(
                          opacity: _isVideoActuallyPlaying ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInQuad,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: value.aspectRatio,
                              child: CachedVideoPlayerPlus(controller),
                            ),
                          ),
                        ),
                      if (value.isBuffering || !value.isInitialized)
                        const Center(
                            child: CupertinoActivityIndicator(
                                color: Colors.white, radius: 15)),
                    ],
                  );
                },
              ),
            ),

          Positioned.fill(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                Colors.black.withValues(alpha: 0.85),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.35)
              ],
                          stops: const [
                0.0,
                0.25,
                0.8,
                1.0
              ])))),

          _buildForeground(
              langCode: Provider.of<LanguageProvider>(context).currentLanguage),

          // KOSORA: Nizamuye umurongo wa progress bar ho 12 pixels kugira ngo wirinde system gestures
          if (isVideo &&
              isActivePost &&
              controller != null &&
              controller.value.isInitialized)
            Positioned(
                bottom: 12, // Nizamuye kure y'impera za screen
                left: 0,
                right: 0,
                child: GestureDetector(
                  onVerticalDragStart: (_) {},
                  child: Container(
                    height: 30, // Hit area nini cyane kurushaho (Easy touch)
                    alignment: Alignment.bottomCenter,
                    color: Colors.transparent, // Touch area itagaragara
                    child: VideoProgressIndicator(controller,
                        allowScrubbing: true,
                        padding: const EdgeInsets.only(top: 20),
                        colors: const VideoProgressColors(
                            playedColor: Colors.greenAccent,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.transparent)),
                  ),
                )),

          Center(
              child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _playPauseOpacity,
                  child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white10)),
                      child: Icon(_playPauseIcon,
                          color: Colors.white, size: 60)))),

          Center(
              child: AnimatedBuilder(
                  animation: _likeAnimationController,
                  builder: (context, child) {
                    return Opacity(
                        opacity: _likeOpacityAnimation.value,
                        child: ScaleTransition(
                            scale: _likeScaleAnimation,
                            child: const Icon(Icons.favorite,
                                color: Colors.white,
                                size: 110,
                                shadows: [
                                  Shadow(blurRadius: 30, color: Colors.black54)
                                ])));
                  })),

          if (_isDownloading)
            Center(
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 25, vertical: 20),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(
                          value: _downloadProgress,
                          color: Colors.greenAccent,
                          strokeWidth: 3),
                      const SizedBox(height: 12),
                      Text("${(_downloadProgress * 100).toInt()}%",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold))
                    ]))),
        ]),
      ),
    );
  }

  Widget _buildForeground({required String langCode}) {
    final String title = (widget.postData['title'] ?? "").toString().trim();
    final String content =
        (widget.postData[DatabaseHelper.colText] ?? "").toString().trim();
    final String livePhoto =
        _formatUrl(widget.postData[DatabaseHelper.colUserImageUrl]);
    final String timeStr = _getTimeAgo(widget.postData['timestamp'] ??
        widget.postData[DatabaseHelper.colTimestamp]);

    return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 10, 40),
        child: Stack(children: [
          Positioned(
              bottom: 15,
              left: 0,
              right: 75,
              child: RepaintBoundary(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.read<FeedManager>().pauseAll();
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (c) => UserProfileScreen(
                                        userId: widget.postData[
                                            DatabaseHelper.colUserId])));
                          },
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.white24,
                                backgroundImage: livePhoto.isNotEmpty
                                    ? CachedNetworkImageProvider(livePhoto)
                                    : null,
                                child: livePhoto.isEmpty
                                    ? const Icon(Icons.person,
                                        size: 16, color: Colors.white)
                                    : null),
                            const SizedBox(width: 10),
                            Flexible(
                                child: Text(
                                    "@${widget.postData[DatabaseHelper.colUserName] ?? 'Star'}",
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14))),
                            if (timeStr.isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text("• $timeStr",
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 11)))
                          ])),
                      const SizedBox(height: 12),
                      if (title.isNotEmpty)
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25)),
                              const SizedBox(height: 10),
                              if (content.isNotEmpty || title.length > 45)
                                GestureDetector(
                                    onTap: () => _showFullNewsModal(
                                        context, title, content, langCode),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                  PostTranslations.t(
                                                      'read_more', langCode),
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const Icon(
                                                  Icons
                                                      .keyboard_arrow_right_rounded,
                                                  color: Colors.white,
                                                  size: 14)
                                            ])))
                            ])
                    ]),
              )),
          Positioned(bottom: 50, right: 0, child: _buildSideActions(langCode)),
        ]));
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return "";
    try {
      DateTime date;
      if (timestamp is Timestamp)
        date = timestamp.toDate();
      else if (timestamp is int)
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      else
        return "";
      return timeago.format(date, locale: 'en_short');
    } catch (e) {
      return "";
    }
  }

  Widget _buildSideActions(String langCode) {
    return Column(children: [
      _actionButton(Icons.remove_red_eye_outlined,
          widget.postData[DatabaseHelper.colViews].toString(), () {}),
      const SizedBox(height: 18),
      _actionButton(
          widget.isLiked ? Icons.favorite : Icons.favorite_border_rounded,
          widget.postData[DatabaseHelper.colLikes].toString(), () {
        HapticFeedback.mediumImpact();
        widget.onLike();
      }, iconColor: widget.isLiked ? Colors.redAccent : Colors.white),
      const SizedBox(height: 18),
      _actionButton(Icons.chat_bubble_outline_rounded,
          widget.postData[DatabaseHelper.colCommentsCount].toString(), () {
        HapticFeedback.lightImpact();
        widget.onComment();
      }),
      const SizedBox(height: 18),
      _actionButton(
          Icons.share_outlined, PostTranslations.t('forward_button', langCode),
          () {
        HapticFeedback.lightImpact();
        widget.onShare();
      }),
      const SizedBox(height: 18),
      IconButton(
          onPressed: () => _showMoreOptions(context, langCode),
          icon: const Icon(Icons.more_horiz, color: Colors.white, size: 36)),
    ]);
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap,
      {Color iconColor = Colors.white}) {
    return GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Icon(icon,
              size: 32,
              color: iconColor,
              shadows: const [Shadow(blurRadius: 10, color: Colors.black45)]),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold))
        ]));
  }

  void _showFullNewsModal(
      BuildContext context, String title, String body, String langCode) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            padding: const EdgeInsets.all(25),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                  child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 25),
              Text(title,
                  style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              const Divider(color: Colors.white10),
              Expanded(
                  child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(body,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16, height: 1.7))))
            ])));
  }

  void _showMoreOptions(BuildContext context, String langCode) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => SafeArea(
              child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  padding: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(color: Colors.black54, blurRadius: 20)
                      ]),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 10),
                    ListTile(
                        leading: const Icon(Icons.file_download_outlined,
                            color: Colors.white),
                        title: Text(PostTranslations.t('save_button', langCode),
                            style: const TextStyle(color: Colors.white)),
                        onTap: () {
                          Navigator.pop(context);
                          _handleDownload(langCode);
                        }),
                    ListTile(
                        leading: const Icon(Icons.report_gmailerrorred_rounded,
                            color: Colors.redAccent),
                        title: Text(langCode == 'ki' ? "Rega" : "Report",
                            style: const TextStyle(color: Colors.redAccent)),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onReport();
                        }),
                    const SizedBox(height: 10)
                  ])),
            ));
  }

  Future<void> _handleDownload(String langCode) async {
    final String? videoUrl = widget.postData['networkVideoUrl'];
    final String? fileUrl =
        videoUrl ?? widget.postData[DatabaseHelper.colImageUrl];
    if (fileUrl == null || fileUrl.isEmpty || _isDownloading) return;
    try {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });
      final tempDir = await getTemporaryDirectory();
      final String fileName =
          "JembeTalk_${DateTime.now().millisecondsSinceEpoch}${videoUrl != null ? '.mp4' : '.jpg'}";
      final String tempPath = "${tempDir.path}/$fileName";
      await Dio().download(_formatUrl(fileUrl), tempPath,
          onReceiveProgress: (received, total) {
        if (total != -1) setState(() => _downloadProgress = received / total);
      });
      await FileStorageService.instance.saveFileToPublicDirectory(
          tempFilePath: tempPath,
          dirType: videoUrl != null
              ? StorageDirectoryType.video
              : StorageDirectoryType.images,
          fileName: fileName);
      setState(() => _isDownloading = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(PostTranslations.t('download_finished', langCode)),
            backgroundColor: Colors.green));
    } catch (_) {
      setState(() => _isDownloading = false);
    }
  }
}
