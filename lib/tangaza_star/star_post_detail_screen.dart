// lib/tangaza_star/star_post_detail_screen.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jembe_talk/tangaza_star/user_profile_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; 
import 'package:jembe_talk/post_translations.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/r2_service.dart';
import 'feed_manager.dart';

class StarPostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> postData;
  const StarPostDetailScreen({super.key, required this.postData});

  @override
  State<StarPostDetailScreen> createState() => _StarPostDetailScreenState();
}

class _StarPostDetailScreenState extends State<StarPostDetailScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  CachedVideoPlayerPlusController? _videoController;
  
  bool _isInitialized = false;
  bool _isViewCounted = false;
  Timer? _viewTimer;
  bool _isVideo = false; 
  
  bool _showCenterIcon = false;
  IconData _playPauseIcon = Icons.play_arrow_rounded;
  late AnimationController _tickerController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _tickerController = AnimationController(vsync: this, duration: const Duration(seconds: 25))..repeat();
    
    final String? videoUrl = widget.postData['videoUrl'] ?? widget.postData['video_url'] ?? widget.postData['networkVideoUrl'];
    _isVideo = videoUrl != null && videoUrl.isNotEmpty;

    if (_isVideo) {
      _setupVideo(); // 🔥 NON-BLOCKING INIT
    } else {
      _isInitialized = true; 
    }
    _startViewTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pauseVideo();
    }
  }

  void _pauseVideo() {
    if (_videoController != null && _videoController!.value.isPlaying) {
      _videoController!.pause();
      WakelockPlus.disable();
      if (mounted) setState(() => _playPauseIcon = Icons.pause_rounded);
    }
  }

  void _startViewTimer() {
    if (_isViewCounted) return;
    _viewTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isViewCounted) {
        _isViewCounted = true;
        context.read<FeedManager>().markPostAsViewed(widget.postData[DatabaseHelper.colPostId] ?? widget.postData['id']);
      }
    });
  }

  // 🔥 FIKISIYE: Non-blocking video setup nka TikTok
  void _setupVideo() {
    final String? rawVideoUrl = widget.postData['videoUrl'] ?? widget.postData['video_url'] ?? widget.postData['networkVideoUrl'];
    if (rawVideoUrl == null || rawVideoUrl.isEmpty) return;

    String finalUrl = rawVideoUrl;
    if (!rawVideoUrl.contains('auth=')) {
      final String path = Uri.parse(rawVideoUrl).path;
      finalUrl = "${R2Service.workerUrl}$path?auth=${R2Service.workerSecretKey}";
    }

    _videoController = CachedVideoPlayerPlusController.networkUrl(
      Uri.parse(finalUrl),
      httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey},
    );

    // 🔥 ANTI-FREEZE: Ireke yikine muri background
    _videoController!.initialize().then((_) {
      if (mounted) {
        setState(() { _isInitialized = true; });
        _videoController!.play();
        _videoController!.setLooping(true);
        WakelockPlus.enable();
      }
    }).catchError((e) => debugPrint("Video Star Error: $e"));
  }

  void _toggleVideoPlayback() {
    if (!_isVideo || _videoController == null || !_isInitialized) return;
    
    setState(() {
      if (_videoController!.value.isPlaying) { 
        _videoController!.pause(); 
        _playPauseIcon = Icons.play_arrow_rounded; // Fikisiye: play icon iyo upause-ije
        WakelockPlus.disable(); 
      } else { 
        _videoController!.play(); 
        _playPauseIcon = Icons.pause_rounded;
        WakelockPlus.enable(); 
      }
      _showCenterIcon = true;
    });
    Future.delayed(const Duration(milliseconds: 800), () { if (mounted) setState(() => _showCenterIcon = false); });
  }

  String _formatImgUrl(String? url) {
    if (url == null || url.isEmpty) return "";
    if (url.contains('auth=')) return url;
    return "${R2Service.workerUrl}${Uri.parse(url).path}?auth=${R2Service.workerSecretKey}";
  }

  @override
  void dispose() { 
    WidgetsBinding.instance.removeObserver(this);
    _viewTimer?.cancel(); 
    _videoController?.dispose(); 
    _tickerController.dispose(); 
    WakelockPlus.disable(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String postId = widget.postData[DatabaseHelper.colPostId] ?? widget.postData['id']?.toString() ?? "";

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
          _buildMediaLayer(),
          _buildGradientOverlay(),

          if (_isVideo)
            Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toggleVideoPlayback, child: Container(color: Colors.transparent))),

          // Indicator igaragara gusa niba video yatinze cyane
          if (_isVideo && !_isInitialized) 
            const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 20)),

          if (_isVideo && _showCenterIcon && _isInitialized) 
            Center(child: Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle), child: Icon(_playPauseIcon == Icons.pause_rounded ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white, size: 80))),

          if (postId.isNotEmpty) _buildFirebaseAdTicker(postId),

          _buildStaticContentOverlay(postId, lang),

          Positioned(top: 45, left: 15, child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 28), 
            onPressed: () {
              _pauseVideo();
              Navigator.pop(context);
            }
          )),
      ]),
    );
  }

  Widget _buildMediaLayer() {
    String rawImg = widget.postData[DatabaseHelper.colImageUrl] ?? widget.postData['imageUrl'] ?? widget.postData['thumbnailUrl'] ?? "";
    String finalUrl = _formatImgUrl(rawImg);

    if (!_isVideo) {
      return finalUrl.isNotEmpty 
        ? CachedNetworkImage(
            imageUrl: finalUrl, 
            httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey}, 
            fit: BoxFit.contain, 
            width: double.infinity,
            height: double.infinity,
            fadeInDuration: Duration.zero,
            placeholder: (c,u) => const SizedBox.shrink(),
          )
        : Container(color: Colors.black);
    }

    return Stack(fit: StackFit.expand, children: [
      // Thumbnail ifunguka vuba kurusha byose
      if (finalUrl.isNotEmpty) 
        CachedNetworkImage(
          imageUrl: finalUrl, 
          httpHeaders: {'X-Jembe-Auth': R2Service.workerSecretKey}, 
          fit: BoxFit.contain,
          fadeInDuration: Duration.zero,
        ),
      
      if (_isInitialized && _videoController != null) 
        Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: CachedVideoPlayerPlus(_videoController!),
          ),
        ),
    ]);
  }

  Widget _buildStaticContentOverlay(String postId, LanguageProvider lang) {
    return _buildUI(widget.postData, postId, lang);
  }

  Widget _buildUI(Map<String, dynamic> data, String postId, LanguageProvider lang) {
    final String langCode = lang.currentLanguage;
    final String title = (data['title'] ?? "").toString().trim();
    final String content = (data['content'] ?? data[DatabaseHelper.colText] ?? "").toString().trim();
    final String userId = data[DatabaseHelper.colUserId] ?? data['userId'] ?? "";

    final TextStyle customTitleStyle = TextStyle(
      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, 
      shadows: const [Shadow(blurRadius: 10, color: Colors.black)]
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 35),
      child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12), 
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(15)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: customTitleStyle),
                if (content.isNotEmpty || title.length > 25) Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: GestureDetector(
                    onTap: () { _pauseVideo(); _showFullContent(title, content); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), 
                      decoration: BoxDecoration(color: Colors.greenAccent, borderRadius: BorderRadius.circular(10)), 
                      child: Text(PostTranslations. t('read_more', langCode), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w900))
                    ),
                  ),
                ),
              ]),
            ),
          
          if (_isVideo && _isInitialized && _videoController != null)
            Padding(
              padding: const EdgeInsets.only(top: 15, bottom: 10, right: 10),
              child: SizedBox(
                height: 5, 
                child: VideoProgressIndicator(
                  _videoController!,
                  allowScrubbing: true, 
                  colors: const VideoProgressColors(
                    playedColor: Colors.greenAccent,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white10,
                  ),
                ),
              ),
            ),

          _buildUserPill(userId, data, postId),
          const SizedBox(height: 20),
          _buildStats(data),
      ]),
    );
  }

  Widget _buildUserPill(String userId, Map<String, dynamic> data, String postId) {
    return StreamBuilder<DocumentSnapshot>(stream: _firestore.collection('users').doc(userId).snapshots(), builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>?;
        final String name = userData?['displayName'] ?? data['authorName'] ?? data['userName'] ?? "Star";
        final String? img = _formatImgUrl(userData?['photoUrl'] ?? data['authorPhotoUrl'] ?? data['userImageUrl']);
        return Row(children: [
          Expanded(child: GestureDetector(
            onTap: () async { 
              _pauseVideo();
              await Navigator.push(context, MaterialPageRoute(builder: (c) => UserProfileScreen(userId: userId))); 
            }, 
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)), child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 12, backgroundColor: Colors.white10, backgroundImage: img != null && img.isNotEmpty ? CachedNetworkImageProvider(img) : null, child: img == null || img.isEmpty ? const Icon(Icons.person, size: 12, color: Colors.white) : null),
                const SizedBox(width: 8), Flexible(child: Text("@$name", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6), const Icon(Icons.stars_rounded, color: Color(0xFFFFD700), size: 18),
              ])))),
          const SizedBox(width: 10), if (postId.isNotEmpty) _buildAdButton(postId),
        ]);
      });
  }

  Widget _buildFirebaseAdTicker(String postId) {
    return Positioned(top: 100, left: 0, right: 0, child: StreamBuilder<DocumentSnapshot>(stream: _firestore.collection('star_ads').doc(postId).snapshots(), builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
          final ad = snapshot.data!.data() as Map<String, dynamic>;
          if (ad['is_active'] != true || ad['message'] == null) return const SizedBox.shrink();
          return Container(height: 35, color: Colors.amber.withValues(alpha: 0.85), child: AnimatedBuilder(animation: _tickerController, builder: (context, child) { return FractionalTranslation(translation: Offset(1.0 - (_tickerController.value * 2.0), 0.0), child: Center(child: Text(ad['message'], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)))); }));
        }));
  }

  Widget _buildAdButton(String postId) {
    return StreamBuilder<DocumentSnapshot>(stream: _firestore.collection('star_ads').doc(postId).snapshots(), builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
        final ad = snapshot.data!.data() as Map<String, dynamic>;
        if (ad['is_active'] != true || ad['link_url'] == null) return const SizedBox.shrink();
        return ElevatedButton(onPressed: () { _pauseVideo(); launchUrl(Uri.parse(ad['link_url']), mode: LaunchMode.externalApplication); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))), child: Text((ad['button_label'] ?? "SURA").toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)));
      });
  }

  Widget _buildStats(Map<String, dynamic> data) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _statItem(Icons.favorite, "${data['likes'] ?? 0}", Colors.redAccent),
          _statItem(Icons.chat_bubble_outline_rounded, "${data['commentsCount'] ?? 0}", Colors.white),
          _statItem(Icons.remove_red_eye_outlined, "${data['views'] ?? 0}", Colors.white),
    ]);
  }

  Widget _statItem(IconData icon, String val, Color col) => Column(children: [Icon(icon, color: col, size: 28), const SizedBox(height: 4), Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))]);
  
  Widget _buildGradientOverlay() => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent, Colors.black.withValues(alpha: 0.8)], begin: Alignment.topCenter, end: Alignment.bottomCenter)));
  
  void _showFullContent(String title, String content) { 
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.7, padding: const EdgeInsets.all(25), 
      decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.vertical(top: Radius.circular(35))), 
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 45, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 25),
          if (title.isNotEmpty) Text(title, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15), const Divider(color: Colors.white10), const SizedBox(height: 15),
          Expanded(child: SingleChildScrollView(child: Text(content.isEmpty ? title : content, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6)))),
      ]))); 
  }
}