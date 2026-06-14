// lib/tangaza_star/post_card.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jembe_talk/tangaza_star/comment_screen.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:video_player/video_player.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post; // Koresha Map yose kugira ngo tubone byose
  final String? currentUserId;
  final double? uploadProgress;
  final bool isSharing;
  final ValueNotifier<bool> isScreenActive;
  final Function(Map<String, dynamic>) onLike;
  final Function(Map<String, dynamic>) onOpenComments;
  final Function(Map<String, dynamic>) onShowOptions;
  final Function(BuildContext, String, String, String) onShowFullNews;
  final VoidCallback onShareStart;
  final Function(bool) onShareEnd;

  const PostCard({
    super.key,
    required this.post,
    this.currentUserId,
    this.uploadProgress,
    this.isSharing = false,
    required this.isScreenActive,
    required this.onLike,
    required this.onOpenComments,
    required this.onShowOptions,
    required this.onShowFullNews,
    required this.onShareStart,
    required this.onShareEnd,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isMuted = true;

  @override
  void initState() {
    super.initState();
    if (widget.post[DatabaseHelper.colVideoUrl] != null) {
      _initializeVideo();
    }
  }

  // LOGIC Y'INGEZI: Local vs Network
  void _initializeVideo() {
    final String videoPath = widget.post[DatabaseHelper.colVideoUrl] ?? "";
    if (videoPath.isEmpty) return;

    // 1. Reba niba ari file yo muri terefone (Local Path)
    if (videoPath.startsWith('/') || videoPath.contains('com.jembe.talk')) {
      File localFile = File(videoPath);
      if (localFile.existsSync()) {
        // Koresha video yo muri terefone (High Quality)
        _videoController = VideoPlayerController.file(localFile);
      } else {
        // Niba file itagihari, shakira kuri internet (niba URL ihari)
        // Icyitonderwa: Hano turatunganya niba 'videoUrl' yarahindutse cloud link
        _videoController = VideoPlayerController.networkUrl(Uri.parse(videoPath));
      }
    } else {
      // 2. Niba ari URL isanzwe (Network)
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoPath));
    }

    _videoController?.initialize().then((_) {
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _videoController!.setLooping(true);
          _videoController!.setVolume(_isMuted ? 0 : 1);
        });
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final String type = post[DatabaseHelper.colVideoUrl] != null ? 'video' : (post[DatabaseHelper.colImageUrl] != null ? 'image' : 'text');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF15202B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildContent(),
          if (type != 'text') _buildMediaSection(type),
          _buildFooter(),
          if (widget.uploadProgress != null && widget.uploadProgress! < 1.0)
            LinearProgressIndicator(value: widget.uploadProgress, backgroundColor: Colors.white10, color: Colors.amberAccent),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: widget.post[DatabaseHelper.colUserImageUrl] != null 
          ? CachedNetworkImageProvider(widget.post[DatabaseHelper.colUserImageUrl]) 
          : null,
        child: widget.post[DatabaseHelper.colUserImageUrl] == null ? const Icon(Icons.person) : null,
      ),
      title: Text(widget.post[DatabaseHelper.colUserName] ?? "User", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(widget.post[DatabaseHelper.colCategory] ?? "General", style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: IconButton(icon: const Icon(Icons.more_vert, color: Colors.white54), onPressed: () => widget.onShowOptions(widget.post)),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.post[DatabaseHelper.colTitle] != null)
            Text(widget.post[DatabaseHelper.colTitle], style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 5),
          Text(widget.post[DatabaseHelper.colText] ?? "", style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildMediaSection(String type) {
    if (type == 'video') {
      return AspectRatio(
        aspectRatio: _isVideoInitialized ? _videoController!.value.aspectRatio : 16 / 9,
        child: Container(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_isVideoInitialized) VideoPlayer(_videoController!),
              if (!_isVideoInitialized) const CircularProgressIndicator(color: Colors.amberAccent),
              Positioned(
                bottom: 10, right: 10,
                child: IconButton(
                  icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white70),
                  onPressed: () => setState(() { _isMuted = !_isMuted; _videoController?.setVolume(_isMuted ? 0 : 1); }),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play();
                  });
                },
                child: Center(child: Icon(_videoController?.value.isPlaying == true ? null : Icons.play_arrow, size: 60, color: Colors.white54)),
              )
            ],
          ),
        ),
      );
    } else {
      // Logic y'ifoto (Local vs Network)
      final String imgPath = widget.post[DatabaseHelper.colImageUrl] ?? "";
      final bool isLocal = imgPath.startsWith('/');
      return isLocal 
        ? Image.file(File(imgPath), fit: BoxFit.cover, width: double.infinity)
        : CachedNetworkImage(imageUrl: imgPath, fit: BoxFit.cover, width: double.infinity, placeholder: (context, url) => Container(height: 200, color: Colors.white10));
    }
  }

  Widget _buildFooter() {
    bool isLiked = widget.post[DatabaseHelper.colIsLikedByMe] == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            IconButton(icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : Colors.white54), onPressed: () => widget.onLike(widget.post)),
            Text('${widget.post[DatabaseHelper.colLikes] ?? 0}', style: const TextStyle(color: Colors.white70)),
          ]),
          Row(children: [
            IconButton(icon: const Icon(Icons.comment_outlined, color: Colors.white54), onPressed: () => widget.onOpenComments(widget.post)),
            Text('${widget.post[DatabaseHelper.colCommentsCount] ?? 0}', style: const TextStyle(color: Colors.white70)),
          ]),
          Row(children: [
            const Icon(Icons.remove_red_eye_outlined, color: Colors.white54, size: 20),
            const SizedBox(width: 5),
            Text('${widget.post[DatabaseHelper.colViews] ?? 0}', style: const TextStyle(color: Colors.white70)),
          ]),
          IconButton(icon: const Icon(Icons.share_outlined, color: Colors.white54), onPressed: widget.onShareStart),
        ],
      ),
    );
  }
}