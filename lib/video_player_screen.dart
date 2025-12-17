// lib/video_player_screen.dart (YAKOSOWE: TICKER IRI MUNSI YA VIDEO NEZA)

import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:jembe_talk/widgets/tv_ticker_widget.dart'; 

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final String channelId;
  final bool autoPlay;

  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
    required this.channelId,
    this.autoPlay = true,
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
        autoPlay: widget.autoPlay,
        mute: false,
        enableCaption: false,
        isLive: false, 
        forceHD: false,
      ),
    );
    // TANGIRA KUBARA UMUKORESHA
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
  
  @override
  void dispose() {
    _removeViewer(); 
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
        onEnded: (meta) {},
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(widget.title, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          
          // HANO NIHO TWAHINDUYE: 
          // Twabishize muri Column iri hagati (Center) kugira ngo Ticker yegere Video
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min, // Fata umwanya ukeneye gusa (Hagati)
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. YOUTUBE PLAYER
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: player,
                ),
                
                // 2. TICKER WIDGET (Ije munsi ya Video neza neza)
                const TvTickerWidget(),
              ],
            ),
          ),
        );
      },
    );
  }
}