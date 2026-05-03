// lib/network_video_player.dart
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:jembe_talk/widgets/tv_ticker_widget.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class NetworkVideoPlayerScreen extends StatefulWidget {
  final String? streamUrl; 
  final String? videoId;   
  final String title;
  final String channelId;
  final String type; 

  const NetworkVideoPlayerScreen({
    super.key,
    this.streamUrl,
    this.videoId,
    required this.title,
    required this.channelId,
    required this.type,
  });

  @override
  State<NetworkVideoPlayerScreen> createState() => _NetworkVideoPlayerScreenState();
}

class _NetworkVideoPlayerScreenState extends State<NetworkVideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  YoutubePlayerController? _youtubeController;
  
  bool _isError = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initializeCorrectPlayer();
    _addViewer();
  }

  void _initializeCorrectPlayer() async {
    if (widget.type == 'youtube' && widget.videoId != null) {
      _youtubeController = YoutubePlayerController(
        initialVideoId: widget.videoId!,
        // ✅ KOSORA: Hindura 'isLive' kibe false kugira ngo YouTube idashyiraho kariya kantu k'umutuku
        flags: const YoutubePlayerFlags(autoPlay: true, mute: false, isLive: false),
      );
      if (mounted) setState(() => _isInitialized = true);
    } else if (widget.type == 'tv' && widget.streamUrl != null) {
      try {
        _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl!));
        await _videoPlayerController!.initialize();
        _chewieController = ChewieController(
          videoPlayerController: _videoPlayerController!,
          autoPlay: true,
          // ✅ KOSORA: Hindura 'isLive' kibe false. Ibi bituma Chewie idandika ijambo "LIVE" imbere muri player
          isLive: false, 
          allowFullScreen: true,
          errorBuilder: (context, errorMessage) => Center(
            child: Text("Ikosa: $errorMessage", style: const TextStyle(color: Colors.white70)),
          ),
        );
        if (mounted) setState(() => _isInitialized = true);
      } catch (e) {
        if (mounted) setState(() => _isError = true);
      }
    }
  }

  // ... (Gukomeza na _addViewer na _removeViewer nka mbere)
  void _addViewer() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final ref = FirebaseDatabase.instance.ref('tv_viewers/${widget.channelId}/$uid');
      ref.set(true);
      ref.onDisconnect().remove();
    }
  }

  void _removeViewer() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final ref = FirebaseDatabase.instance.ref('tv_viewers/${widget.channelId}/$uid');
      ref.remove();
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _removeViewer();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _youtubeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ KOSORA: Icon iba ubururu aho kuba umutuku
                  const Icon(Icons.ondemand_video_rounded, color: Colors.blueAccent, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    widget.title, 
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            _isError 
                ? const Text("Iyi video ntabwo irimo kwaka.", style: TextStyle(color: Colors.white54))
                : !_isInitialized
                    ? const CircularProgressIndicator(color: Colors.blueAccent)
                    : widget.type == 'youtube'
                        ? YoutubePlayer(controller: _youtubeController!, showVideoProgressIndicator: true)
                        : AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Chewie(controller: _chewieController!),
                          ),
            const Padding(padding: EdgeInsets.only(top: 8.0), child: TvTickerWidget()),
          ],
        ),
      ),
    );
  }
}