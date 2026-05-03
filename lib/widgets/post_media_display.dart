import 'dart:io';
import 'dart:developer';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:image/image.dart' as img_lib;
import 'package:jembe_talk/full_photo_screen.dart';

class PostMediaDisplay extends StatefulWidget {
  final String? imageUrl;
  final String? videoUrl;
  final String postId;
  final ValueNotifier<bool> isScreenActive;
  final String? thumbnailLocalPath;
  final String? thumbnailUrl;

  const PostMediaDisplay({
    super.key,
    this.imageUrl,
    this.videoUrl,
    required this.postId,
    required this.isScreenActive,
    this.thumbnailLocalPath,
    this.thumbnailUrl,
  });

  @override
  State<PostMediaDisplay> createState() => _PostMediaDisplayState();
}

class _PostMediaDisplayState extends State<PostMediaDisplay> {
  VideoPlayerController? _v;
  double _aspectRatio = 1.0;
  bool _isInitialized = false;
  String _durationText = '';
  bool _isWaitingToPlay = false;
  bool _userStartedPlay = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    if (widget.thumbnailLocalPath != null) {
      final File thumbFile = File(widget.thumbnailLocalPath!);
      if (await thumbFile.exists()) {
        try {
          final bytes = await thumbFile.readAsBytes();
          final img = img_lib.decodeImage(bytes);
          if (img != null && mounted) {
            setState(() => _aspectRatio = img.width / img.height);
          }
        } catch (e) {
          log("Error decoding local thumb: $e");
        }
      }
    }

    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      _v = (widget.videoUrl ?? '').startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!))
          : VideoPlayerController.file(File(widget.videoUrl!));
      try {
        await _v!.initialize();
        if (mounted) {
          setState(() {
            _aspectRatio = _v!.value.aspectRatio;
            _durationText =
                "${_v!.value.duration.inMinutes.toString().padLeft(2, '0')}:${(_v!.value.duration.inSeconds % 60).toString().padLeft(2, '0')}";
            _isInitialized = true;
          });
        }
        widget.isScreenActive.addListener(_onActive);
      } catch (e) {
        log("Video Init Failed: $e");
      }
    } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      final imgSource = (widget.imageUrl ?? '').startsWith('http')
          ? NetworkImage(widget.imageUrl!)
          : FileImage(File(widget.imageUrl!)) as ImageProvider;
      imgSource.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((info, _) {
          if (mounted) {
            setState(() {
              _aspectRatio = info.image.width / info.image.height;
              _isInitialized = true;
            });
          }
        }),
      );
    }
  }

  void _handleVideoTap() {
    if (!_isInitialized || _v == null) {
      setState(() => _isWaitingToPlay = true);
      return;
    }
    setState(() {
      if (_v!.value.isPlaying) {
        _v!.pause();
        WakelockPlus.disable();
      } else {
        _userStartedPlay = true;
        _v!.play();
        WakelockPlus.enable();
      }
    });
  }

  void _onActive() {
    if (!widget.isScreenActive.value) {
      _v?.pause();
      WakelockPlus.disable();
    }
  }

  @override
  void dispose() {
    widget.isScreenActive.removeListener(_onActive);
    _v?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool hasLocalThumb = widget.thumbnailLocalPath != null &&
        File(widget.thumbnailLocalPath!).existsSync();
    bool hasNetworkThumb =
        widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty;
    bool isPortrait = _aspectRatio < 1.0;

    if (widget.imageUrl == null && widget.videoUrl == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: isPortrait ? 0.65 : 1.0,
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: Stack(
            children: [
              if (!_userStartedPlay) ...[
                if (hasLocalThumb)
                  Positioned.fill(
                      child: Image.file(File(widget.thumbnailLocalPath!),
                          fit: BoxFit.cover))
                else if (hasNetworkThumb)
                  Positioned.fill(
                    child: Image.network(widget.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                            Container(color: Colors.black26)),
                  ),
              ],
              if (widget.videoUrl != null && _userStartedPlay)
                AnimatedOpacity(
                  opacity: _isInitialized ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      GestureDetector(
                          onTap: _handleVideoTap,
                          child: _v != null
                              ? VideoPlayer(_v!)
                              : const SizedBox()),
                      Positioned(
                        bottom: 25,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(_durationText,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (_v != null)
                        VideoProgressIndicator(
                          _v!,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.blueAccent,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.black26,
                          ),
                        )
                    ],
                  ),
                ),
              if (widget.videoUrl != null &&
                  (!_isInitialized || (_v != null && !_v!.value.isPlaying)))
                Center(
                  child: GestureDetector(
                    onTap: _handleVideoTap,
                    child: _isWaitingToPlay && !_isInitialized
                        ? const CupertinoActivityIndicator(
                            color: Colors.white, radius: 15)
                        : (const CircleAvatar(
                            backgroundColor: Colors.black45,
                            radius: 30,
                            child: Icon(Icons.play_arrow,
                                color: Colors.white, size: 40))),
                  ),
                ),
              if (widget.imageUrl != null && widget.videoUrl == null)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullPhotoScreen(
                          imageUrl: widget.imageUrl!,
                          heroTag: widget.postId,
                          isLocalFile:
                              !(widget.imageUrl ?? '').startsWith('http'),
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag: widget.postId,
                    child: (widget.imageUrl ?? '').startsWith('http')
                        ? Image.network(
                            widget.imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => hasLocalThumb
                                ? Image.file(File(widget.thumbnailLocalPath!))
                                : const Icon(Icons.broken_image),
                          )
                        : Image.file(File(widget.imageUrl!),
                            fit: BoxFit.contain),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}