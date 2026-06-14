// lib/network_video_player.dart (VERSION 3.0 - BRANDED & OPTIMIZED)

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
  State<NetworkVideoPlayerScreen> createState() =>
      _NetworkVideoPlayerScreenState();
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
        flags: const YoutubePlayerFlags(
            autoPlay: true, mute: false, isLive: false),
      );
      if (mounted) setState(() => _isInitialized = true);
    } else if (widget.type == 'tv' && widget.streamUrl != null) {
      try {
        _videoPlayerController =
            VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl!));
        await _videoPlayerController!.initialize();
        _chewieController = ChewieController(
          videoPlayerController: _videoPlayerController!,
          autoPlay: true,
          isLive: false,
          allowFullScreen: true,
          errorBuilder: (context, errorMessage) => Center(
            child: Text("Ikosa: $errorMessage",
                style: const TextStyle(color: Colors.white70)),
          ),
        );
        if (mounted) setState(() => _isInitialized = true);
      } catch (e) {
        if (mounted) setState(() => _isError = true);
      }
    }
  }

  void _addViewer() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final ref =
          FirebaseDatabase.instance.ref('tv_viewers/${widget.channelId}/$uid');
      ref.set(true);
      ref.onDisconnect().remove();
    }
  }

  void _removeViewer() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final ref =
          FirebaseDatabase.instance.ref('tv_viewers/${widget.channelId}/$uid');
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
            // 🔥 BRANDING HEADER: JEMBE TV
            const Text(
              "JEMBE TV",
              style: TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 3,
                  shadows: [Shadow(color: Colors.blueAccent, blurRadius: 10)]),
            ),
            const SizedBox(height: 8),

            // CHANNEL TITLE BOX
            Container(
              margin: const EdgeInsets.only(bottom: 15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.ondemand_video_rounded,
                      color: Colors.blueAccent, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            // VIDEO PLAYER AREA
            _isError
                ? const Text("Iyi video ntabwo irimo kwaka.",
                    style: TextStyle(color: Colors.white54))
                : !_isInitialized
                    ? const CircularProgressIndicator(color: Colors.blueAccent)
                    : widget.type == 'youtube'
                        ? YoutubePlayer(
                            controller: _youtubeController!,
                            showVideoProgressIndicator: true)
                        : AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Chewie(controller: _chewieController!),
                          ),

            // TICKER WIDGET
            const Padding(
                padding: EdgeInsets.only(top: 10.0), child: TvTickerWidget()),
          ],
        ),
      ),
    );
  }
}
