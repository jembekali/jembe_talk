// lib/tangaza_star/comment_bubble.dart

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class CommentBubble extends StatefulWidget {
  final String userName;
  final String? text;
  final String? audioUrl;
  final int timestamp;
  final int likesCount;
  final bool isLikedByMe;
  final VoidCallback onLike;
  final bool isMyComment;
  final VoidCallback onShowOptions;
  final String? syncStatus;
  
  const CommentBubble({
    super.key, 
    required this.userName, 
    this.text,
    this.audioUrl,
    required this.timestamp,
    required this.likesCount,
    required this.isLikedByMe,
    required this.onLike,
    required this.isMyComment,
    required this.onShowOptions,
    this.syncStatus,
  });

  @override
  State<CommentBubble> createState() => _CommentBubbleState();
}

class _CommentBubbleState extends State<CommentBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration? _duration;
  Duration _currentPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.audioUrl != null) {
      _initAudioPlayer();
    }
  }

  Future<void> _initAudioPlayer() async {
    try {
      _duration = await _audioPlayer.setFilePath(widget.audioUrl!);
      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            if (state.processingState == ProcessingState.completed) {
               _audioPlayer.seek(Duration.zero);
               _audioPlayer.pause();
            }
          });
        }
      });
      _audioPlayer.positionStream.listen((position) {
         if (mounted) {
           setState(() {
             _currentPosition = position;
           });
         }
      });
    } catch(e) {
      debugPrint("Ikosa ryo gutangiza audio: $e");
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  String _formatDuration(Duration d) {
    return d.toString().split('.').first.padLeft(8, "0").substring(3);
  }

  String _formatTimestamp() {
    final now = DateTime.now();
    final messageTime = DateTime.fromMillisecondsSinceEpoch(widget.timestamp);
    final difference = now.difference(messageTime);

    if (difference.inSeconds < 60) {
      return "${difference.inSeconds}s";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes}m";
    } else if (difference.inHours < 24) {
      return "${difference.inHours}h";
    } else if (difference.inDays == 1) {
      return "ejo";
    } else {
      return "${difference.inDays}d";
    }
  }

  Widget _buildSyncIcon() {
    switch (widget.syncStatus) {
      case 'synced':
        return const SizedBox.shrink();
      case 'failed':
        return Tooltip(
          message: 'Kwohereza byaranze',
          child: Icon(Icons.error_outline, color: Colors.red.shade400, size: 14),
        );
      case 'pending':
      default:
        return const Tooltip(
          message: 'Itegereje interineti',
          child: Icon(Icons.sync, color: Colors.grey, size: 14),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isAudioComment = widget.audioUrl != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
      decoration: BoxDecoration(
        color: isAudioComment ? Colors.teal.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.userName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                            fontSize: 15)),
                    const SizedBox(height: 6),
                    if (isAudioComment)
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                                _isPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_arrow_rounded,
                                color: Colors.teal,
                                size: 36),
                            onPressed: _togglePlayPause,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_duration != null)
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.0,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6.0),
                                      overlayShape: const RoundSliderOverlayShape(
                                          overlayRadius: 12.0),
                                    ),
                                    child: Slider(
                                      value:
                                          _currentPosition.inMilliseconds.toDouble(),
                                      min: 0.0,
                                      max: _duration!.inMilliseconds.toDouble(),
                                      onChanged: (value) {
                                        _audioPlayer.seek(Duration(
                                            milliseconds: value.toInt()));
                                      },
                                      activeColor: Colors.teal,
                                      inactiveColor:
                                          Colors.teal.withOpacity(0.3),
                                    ),
                                  ),
                                Text(
                                    "${_formatDuration(_currentPosition)} / ${_formatDuration(_duration ?? Duration.zero)}",
                                    style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      Text(widget.text ?? '',
                          style:
                              const TextStyle(fontSize: 15, color: Colors.black87)),
                  ],
                ),
              ),
              if (widget.isMyComment)
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: widget.onShowOptions,
                  iconSize: 20,
                  padding:
                      const EdgeInsets.only(left: 16, top: 0, right: 0, bottom: 0),
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _formatTimestamp(),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(width: 8),
              if (widget.isMyComment) _buildSyncIcon(),
              const Spacer(),
              InkWell(
                onTap: widget.onLike,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                  child: Row(
                    children: [
                      Icon(
                        widget.isLikedByMe
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: widget.isLikedByMe
                            ? Colors.red
                            : Colors.grey.shade600,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.likesCount.toString(),
                        style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      )
                    ],
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}