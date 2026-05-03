import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; 
import 'package:timeago/timeago.dart' as timeago;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

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

class _TiktokStylePostState extends State<TiktokStylePost> with TickerProviderStateMixin {
  double _downloadProgress = 0.0; 
  bool _isDownloading = false;
  Timer? _viewTimer;
  bool _isViewCounted = false;
  late AnimationController _likeAnimationController;
  late Animation<double> _likeAnimation;
  double _likeAnimationOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    // Gushyiraho uburyo bw'igihe kigufi (e.g. 2h)
    timeago.setLocaleMessages('en_short', timeago.EnShortMessages());
    _likeAnimationController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _likeAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _likeAnimationController, curve: Curves.elasticOut));
    if (widget.isVisible) _startViewTimer();
  }

  @override
  void didUpdateWidget(covariant TiktokStylePost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _startViewTimer();
        // ✅ NO AUTOPLAY: Hano ntago tinitiyayizinga video, bituma yerekana thumbnail gusa.
      } else {
        _cancelViewTimer();
        // ✅ GHOST AUDIO PREVENTION: Niba umuntu arenzeho post, hagarika buri kantu kose (Hard kill)
        final fm = context.read<FeedManager>();
        if (fm.activePostId == widget.postData[DatabaseHelper.colPostId]) {
          fm.pauseAll(); 
        }
      }
    }
  }

  void _startViewTimer() {
    if (_isViewCounted || !mounted) return;
    _cancelViewTimer();
    _viewTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && widget.isVisible && !_isViewCounted) {
        _isViewCounted = true;
        context.read<FeedManager>().markPostAsViewed(widget.postData[DatabaseHelper.colPostId]);
      }
    });
  }

  void _cancelViewTimer() { _viewTimer?.cancel(); _viewTimer = null; }

  void _handleMainTap(FeedManager feedManager) {
    final String postId = widget.postData[DatabaseHelper.colPostId];
    final bool isVideo = widget.postData['networkVideoUrl'] != null;
    if (isVideo) {
      if (feedManager.activePostId == postId) {
        feedManager.togglePlayback();
      } else {
        // Video itangira gusa iyo umuntu ayikanzeho (Click to Play)
        feedManager.initializeAndPlayVideo(postId);
      }
    }
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return "";
    DateTime date;
    try {
      if (timestamp is Timestamp) date = timestamp.toDate();
      else if (timestamp is int) date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      else if (timestamp is Map) {
        final int seconds = timestamp['_seconds'] ?? (timestamp['seconds'] ?? 0);
        date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      } else if (timestamp is String) date = DateTime.parse(timestamp);
      else return "";
      return timeago.format(date, locale: 'en_short');
    } catch (e) { return ""; }
  }

  void _showFullNewsModal(BuildContext context, String title, String body, String langCode) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75, 
        decoration: BoxDecoration(color: const Color(0xFF0F172A).withValues(alpha: 0.95), borderRadius: const BorderRadius.vertical(top: Radius.circular(35))),
        padding: const EdgeInsets.fromLTRB(25, 20, 25, 25),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 45, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 25),
          if (title.isNotEmpty) Text(title, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15), const Divider(color: Colors.white10), const SizedBox(height: 15),
          Expanded(child: SingleChildScrollView(child: Text(body, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6)))),
        ])));
  }

  @override void dispose() { _cancelViewTimer(); _likeAnimationController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String langCode = lang.currentLanguage;
    final feedManager = context.watch<FeedManager>();
    final String postId = widget.postData[DatabaseHelper.colPostId];
    final bool isVideo = widget.postData['networkVideoUrl'] != null; 
    final bool isActiveVideo = (feedManager.activePostId == postId);
    final controller = feedManager.activeController;

    String rawImg = isVideo 
        ? (widget.postData['thumbnailUrl'] ?? widget.postData[DatabaseHelper.colImageUrl] ?? "") 
        : (widget.postData[DatabaseHelper.colImageUrl] ?? "");
    
    String finalImageUrl = "";
    if (rawImg.isNotEmpty) {
      if (rawImg.startsWith('http')) finalImageUrl = rawImg.contains('auth=') ? rawImg : "${R2Service.workerUrl}${Uri.parse(rawImg).path}?auth=${R2Service.workerSecretKey}";
      else finalImageUrl = rawImg;
    }

    return Container(
      color: Colors.black,
      child: GestureDetector(
        onTap: () => _handleMainTap(feedManager),
        onDoubleTap: () {
          if (!widget.isLiked) widget.onLike();
          setState(() => _likeAnimationOpacity = 1.0);
          _likeAnimationController.forward(from: 0.0).then((_) { Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _likeAnimationOpacity = 0.0); }); });
        },
        child: Stack(fit: StackFit.expand, children: [
            // IFOTO / THUMBNAIL (No Autoplay makes this stay visible)
            if (finalImageUrl.isNotEmpty) 
              CachedNetworkImage(
                imageUrl: finalImageUrl, 
                fit: BoxFit.contain, // ✅ NO ZOOM
                httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey}, 
                width: double.infinity, 
                height: double.infinity, 
                placeholder: (c, u) => const Center(child: CupertinoActivityIndicator(color: Colors.white24)), 
                errorWidget: (c, u, e) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white12, size: 50))
              ),
            
            // VIDEO PLAYER (Only shows when clicked/active)
            if (isVideo && isActiveVideo) 
              Center(child: (controller != null && controller.value.isInitialized) 
                ? Stack(alignment: Alignment.center, children: [ 
                    AspectRatio(aspectRatio: controller.value.aspectRatio, child: CachedVideoPlayerPlus(controller)), 
                    if (controller.value.isBuffering) const CupertinoActivityIndicator(color: Colors.white, radius: 25) 
                  ]) 
                : const CupertinoActivityIndicator(color: Colors.white, radius: 20)),
            
            // PLAY BUTTON OVERLAY (Shows when video is not playing)
            if (isVideo && (!isActiveVideo || (controller != null && !controller.value.isPlaying))) 
              Center(child: Container(
                padding: const EdgeInsets.all(15), 
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle, border: Border.all(color: Colors.white24)), 
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 50)
              )),
            
            _buildForeground(langCode, isVideo && isActiveVideo, isVideo ? controller : null),
            Center(child: AnimatedOpacity(opacity: _likeAnimationOpacity, duration: const Duration(milliseconds: 300), child: ScaleTransition(scale: _likeAnimation, child: const Icon(Icons.favorite, color: Colors.white, size: 110)))),
            if (_isDownloading) Center(child: Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ CircularProgressIndicator(value: _downloadProgress, color: Colors.greenAccent), const SizedBox(height: 10), Text("${(_downloadProgress * 100).toInt()}%", style: const TextStyle(color: Colors.white)) ]))),
        ]),
      ),
    );
  }

  Widget _buildForeground(String langCode, bool isActiveVideo, CachedVideoPlayerPlusController? controller) {
    final String title = (widget.postData['title'] ?? "").toString().trim();
    final String content = (widget.postData['content'] ?? widget.postData[DatabaseHelper.colText] ?? "").toString().trim();
    final String timeStr = _getTimeAgo(widget.postData['timestamp']); // ✅ 2h format
    String line1 = title; String line2 = "";
    bool showReadMore = content.isNotEmpty || title.length > 25;
    if (title.length > 20) {
      int splitTarget = (title.length * 0.6).toInt();
      int splitIndex = title.indexOf(' ', splitTarget);
      if (splitIndex == -1 || splitIndex > title.length - 5) splitIndex = splitTarget;
      line1 = title.substring(0, splitIndex).trim();
      line2 = title.substring(splitIndex).trim();
    }
    final TextStyle customTitleStyle = TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.0, shadows: const [Shadow(blurRadius: 10, color: Colors.black, offset: Offset(1, 1))]);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 35), 
      child: Stack(children: [
          Positioned(bottom: 10, left: 0, right: 85, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (title.isNotEmpty) Container(
                  padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(15)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(line1, style: customTitleStyle), const SizedBox(height: 5),
                      Text.rich(TextSpan(children: [
                          TextSpan(text: line2.isEmpty ? "" : "$line2  ", style: customTitleStyle),
                          if (showReadMore) WidgetSpan(alignment: PlaceholderAlignment.middle, child: GestureDetector(onTap: () => _showFullNewsModal(context, title, content, langCode), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3))]), child: Text(PostTranslations.t('read_more', langCode), style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5))))),
                      ])),
                  ]),
                ),
                const SizedBox(height: 10),
                _buildUserTag(timeStr),
                if (isActiveVideo && controller != null && controller.value.isInitialized)
                  Padding(padding: const EdgeInsets.only(top: 12, left: 5, right: 10), child: SizedBox(height: 15, child: VideoProgressIndicator(controller, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 6), colors: const VideoProgressColors(playedColor: Colors.greenAccent, bufferedColor: Colors.white24, backgroundColor: Colors.white10)))),
          ])),
          Positioned(bottom: 45, right: 0, child: _buildSideActions(langCode)),
      ]),
    );
  }

  Widget _buildUserTag(String timeStr) {
    String? rawPhoto = widget.postData[DatabaseHelper.colUserImageUrl];
    String livePhoto = (rawPhoto != null && rawPhoto.isNotEmpty) ? (rawPhoto.contains('auth=') ? rawPhoto : "${R2Service.workerUrl}${Uri.parse(rawPhoto).path}?auth=${R2Service.workerSecretKey}") : "";
    final String liveName = widget.postData[DatabaseHelper.colUserName] ?? "Star";
    return GestureDetector(
      onTap: () { context.read<FeedManager>().pauseAll(); Navigator.push(context, MaterialPageRoute(builder: (c) => UserProfileScreen(userId: widget.postData[DatabaseHelper.colUserId]))); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5), width: 1.2)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [ 
              ClipOval(child: SizedBox(width: 24, height: 24, child: (livePhoto.isNotEmpty) ? CachedNetworkImage(imageUrl: livePhoto, httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey}, fit: BoxFit.cover, errorWidget: (c,u,e) => const Icon(Icons.person, size: 14, color: Colors.white)) : const Icon(Icons.person, size: 14, color: Colors.white))), 
              const SizedBox(width: 8), Text("@$liveName", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, shadows: [Shadow(blurRadius: 5, color: Colors.black)])),
              const SizedBox(width: 6), Text("• $timeStr", style: const TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(blurRadius: 5, color: Colors.black)])),
        ]),
      ),
    );
  }

  Widget _buildSideActions(String langCode) {
    return Column(children: [
      _actionIcon(Icons.remove_red_eye_outlined, widget.postData[DatabaseHelper.colViews].toString()), const SizedBox(height: 18),
      _actionIcon(widget.isLiked ? Icons.favorite : Icons.favorite_border_rounded, widget.postData[DatabaseHelper.colLikes].toString(), color: widget.isLiked ? Colors.red : Colors.white), const SizedBox(height: 18),
      _actionIcon(Icons.chat_bubble_outline_rounded, widget.postData[DatabaseHelper.colCommentsCount].toString(), onTap: widget.onComment), const SizedBox(height: 18),
      _actionIcon(Icons.share_outlined, PostTranslations.t('forward_button', langCode), onTap: widget.onShare), const SizedBox(height: 18),
      GestureDetector(onTap: () => _showMoreOptions(context, langCode), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.3), shape: BoxShape.circle, border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6), width: 1.5), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)]), child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 22))),
    ]);
  }

  Widget _actionIcon(IconData icon, String label, {Color color = Colors.white, VoidCallback? onTap}) {
    return GestureDetector(onTap: onTap ?? widget.onLike, child: Column(children: [ 
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.35), shape: BoxShape.circle, border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6), width: 1.2), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2))]), child: Icon(icon, size: 26, color: color, shadows: const [Shadow(blurRadius: 10, color: Colors.black54)])),
          const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 10, color: Colors.black54)])),
    ]));
  }

  void _showMoreOptions(BuildContext context, String langCode) {
    String reportBtnLabel = "Report";
    if (langCode == 'ki') reportBtnLabel = "Rega"; else if (langCode == 'sw') reportBtnLabel = "Ripoti"; else if (langCode == 'fr') reportBtnLabel = "Signaler";
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (context) => Container(
        margin: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1E293B).withValues(alpha: 0.98), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 15),
            ListTile(leading: const Icon(Icons.file_download_outlined, color: Colors.white), title: Text(PostTranslations.t('save_button', langCode), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); _handleDownload(langCode); }),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(color: Colors.white10)),
            ListTile(leading: const CircleAvatar(backgroundColor: Colors.redAccent, radius: 15, child: Icon(Icons.report, color: Colors.white, size: 18)), title: Text(reportBtnLabel, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); widget.onReport(); }),
            const SizedBox(height: 15),
        ])));
  }

  Future<void> _handleDownload(String langCode) async {
    final String? videoUrl = widget.postData['networkVideoUrl'];
    final String? imageUrl = widget.postData[DatabaseHelper.colImageUrl];
    final String? fileUrl = (videoUrl != null && videoUrl.isNotEmpty) ? videoUrl : imageUrl;
    if (fileUrl == null || fileUrl.isEmpty || _isDownloading) return;
    try {
      setState(() { _isDownloading = true; _downloadProgress = 0.0; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PostTranslations.t('download_started', langCode))));
      final tempDir = await getTemporaryDirectory();
      final bool isVideoFile = (videoUrl != null && videoUrl.isNotEmpty);
      final String fileName = "JembeTalk_${DateTime.now().millisecondsSinceEpoch}${isVideoFile ? '.mp4' : '.jpg'}";
      final String tempPath = "${tempDir.path}/$fileName";
      String finalUrl = fileUrl.contains('auth=') ? fileUrl : "${R2Service.workerUrl}${Uri.parse(fileUrl).path}?auth=${R2Service.workerSecretKey}";
      await Dio().download(finalUrl, tempPath, onReceiveProgress: (received, total) { if (total != -1) { setState(() { _downloadProgress = (received / total); }); } });
      await FileStorageService.instance.saveFileToPublicDirectory(tempFilePath: tempPath, dirType: isVideoFile ? StorageDirectoryType.video : StorageDirectoryType.images, fileName: fileName);
      setState(() { _isDownloading = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PostTranslations.t('download_finished', langCode)), backgroundColor: Colors.green));
    } catch (_) { setState(() { _isDownloading = false; }); }
  }
}