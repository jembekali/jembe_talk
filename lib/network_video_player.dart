// lib/network_video_player.dart (YAKOSOWE: WAKELOCK YONGEWEMO)

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:jembe_talk/widgets/tv_ticker_widget.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // <<< IYI NI NSHYA

class NetworkVideoPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String channelId;

  const NetworkVideoPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.channelId,
  });

  @override
  State<NetworkVideoPlayerScreen> createState() => _NetworkVideoPlayerScreenState();
}

class _NetworkVideoPlayerScreenState extends State<NetworkVideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    
    // 1. TEGEKA SCREEN KUTARYAMA (KEEP SCREEN ON)
    WakelockPlus.enable(); 

    initializePlayer();
    _addViewer(); 
  }

  // --- LOGIC YO KUBARA ---
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
  // -----------------------

  Future<void> initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl));
      await _videoPlayerController.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        isLive: true,
        allowFullScreen: true,
        allowedScreenSleep: false, // Dushyizemo n'iyi nka backup
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Ntabwo bikunze gufungura iyi TV.\n$errorMessage",
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if(mounted) setState(() => _isError = true);
    }
  }

  @override
  void dispose() {
    // 2. REKURA SCREEN ISINZIRE IYO TUVUYEMO
    WakelockPlus.disable();
    
    _removeViewer(); 
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 1. VIDEO PLAYER
            _isError 
                ? const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text("Habaye ikosa.", style: TextStyle(color: Colors.white)),
                  )
                : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Chewie(controller: _chewieController!),
                      )
                    : Column(
                        children: [
                          const CircularProgressIndicator(color: Colors.red),
                          const SizedBox(height: 20),
                          Text(
                            'Raba ${widget.title}...', 
                            style: const TextStyle(color: Colors.white, fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
            
            // 2. TICKER WIDGET
            const TvTickerWidget(),
          ],
        ),
      ),
    );
  }
}