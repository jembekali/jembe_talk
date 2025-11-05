// In lib/network_video_player.dart (YAHINDURIWEHO AMAGAMBO)

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class NetworkVideoPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;

  const NetworkVideoPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
  });

  @override
  State<NetworkVideoPlayerScreen> createState() => _NetworkVideoPlayerScreenState();
}

class _NetworkVideoPlayerScreenState extends State<NetworkVideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl));
    await _videoPlayerController.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      isLive: true,
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
            ? Chewie(controller: _chewieController!)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  // =============================================================
                  // >>>>> IMPINDUKA YABAYE HANO <<<<<
                  // =============================================================
                  Text(
                    'Raba ${widget.title}...', // IJAMBO RISHYA
                    style: const TextStyle(color: Colors.white, fontSize: 18), // TWONGEYE UKO RINGANA
                  ),
                ],
              ),
      ),
    );
  }
}