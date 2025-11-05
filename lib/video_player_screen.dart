// In lib/video_player_screen.dart (YAHINDUTSEHO GATO)

import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final bool autoPlay; // <<< AKANTU GASHASHA

  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
    this.autoPlay = true, // <<< Ubusanzwe bizajya bihora ari 'true'
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: YoutubePlayerFlags(
        autoPlay: widget.autoPlay, // <<< TWAKORESHEJE YA VARIABULU NSHYA
        mute: false,
      ),
    );
  }
  
  // Ibindi byose biguma uko byari biri
  // ...
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Colors.amber,
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(widget.title),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: player,
            ),
          ),
        );
      },
    );
  }
}