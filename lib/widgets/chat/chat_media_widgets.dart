// lib/widgets/chat/chat_media_widgets.dart (VERSION 7.3 - ZERO FUNCTIONALITY LOSS - FIXED SYNC)

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:open_filex/open_filex.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../language_provider.dart';
import '../../services/audio_service.dart';
import '../../services/database_helper.dart';
import '../../services/file_storage_service.dart';
import '../../services/sync_service.dart';
import '../../full_photo_screen.dart';
import '../../contact_info_screen.dart';
import '../../chat_screen.dart';

// ===========================================================================
// 1. IMAGE BUBBLE
// ===========================================================================
class ImageBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final bool isUploadingOrFailed;
  const ImageBubble({super.key, required this.messageData, this.isUploadingOrFailed = false});
  @override State<ImageBubble> createState() => _ImageBubbleState();
}
class _ImageBubbleState extends State<ImageBubble> {
  bool _isD = false; double? _p; http.Client? _client;
  Future<void> _toggleD() async {
    if (_isD) { _client?.close(); setState(() { _isD = false; _p = null; }); return; }
    final url = widget.messageData['fileUrl']; if (url == null) return;
    setState(() { _isD = true; _p = 0.0; });
    try {
      _client = http.Client(); final res = await _client!.send(http.Request('GET', Uri.parse(url)));
      final f = File(path.join((await getTemporaryDirectory()).path, path.basename(url)));
      final sink = f.openWrite(); int rec = 0; int tot = res.contentLength ?? -1;
      await res.stream.listen((c) { rec += c.length; if (tot != -1 && mounted) setState(() => _p = rec / tot); sink.add(c); }).asFuture();
      await sink.close();
      final perm = await FileStorageService.instance.saveFileToPublicDirectory(tempFilePath: f.path, dirType: StorageDirectoryType.images, fileName: path.basename(url));
      if (perm != null && mounted) { await DatabaseHelper.instance.updateMessageLocalPath(widget.messageData['id'], perm); syncService.notifyUIMessageUpdate(widget.messageData['id']); setState(() => _isD = false); }
    } catch (_) { if (mounted) setState(() { _isD = false; _p = null; }); } finally { _client?.close(); }
  }
  @override Widget build(BuildContext context) {
    final local = widget.messageData['localPath']; final bool exists = local != null && File(local).existsSync();
    final thumbUrl = widget.messageData['thumbnailUrl'] ?? widget.messageData['fileUrl'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(height: 250, width: 250, color: Colors.black12, child: Stack(fit: StackFit.expand, children: [
        exists ? GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => FullPhotoScreen(imageUrl: local, isLocalFile: true, heroTag: widget.messageData['id']))), child: Image.file(File(local), fit: BoxFit.cover))
               : CachedNetworkImage(imageUrl: thumbUrl ?? "", fit: BoxFit.cover, placeholder: (c, u) => const Center(child: CircularProgressIndicator(strokeWidth: 1)), errorWidget: (c,u,e) => const Icon(Icons.image, color: Colors.white24)),
        if (!exists && !widget.isUploadingOrFailed) Positioned(bottom: 8, right: 8, child: GestureDetector(onTap: _toggleD, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: _isD ? Stack(alignment: Alignment.center, children: [CircularProgressIndicator(value: _p, color: Colors.white, strokeWidth: 2), const Icon(Icons.close, color: Colors.white, size: 18)]) : const Icon(Icons.download_for_offline, color: Colors.white, size: 28)))),
      ]))),
      if (widget.messageData['message'] != null && widget.messageData['message'].toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: Text(widget.messageData['message'])),
    ]);
  }
}

// ===========================================================================
// 2. VOICE BUBBLE (FIXED ARGUMENTS)
// ===========================================================================
class VoiceBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final bool isPlayed; 
  const VoiceBubble({super.key, required this.messageData, this.isPlayed = false});
  @override State<VoiceBubble> createState() => _VoiceBubbleState();
}
class _VoiceBubbleState extends State<VoiceBubble> {
  bool _isD = false; double? _p; http.Client? _client;

  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndAutoDownload()); }

  void _checkAndAutoDownload() {
    final local = widget.messageData['localPath'];
    final bool exists = local != null && File(local).existsSync();
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser?.uid;
    final status = widget.messageData['status'] ?? 'sent';
    if (!exists && !isMe && status == 'sent') {
      final msgTime = DateTime.fromMillisecondsSinceEpoch(widget.messageData['timestamp'] ?? 0);
      if (DateTime.now().difference(msgTime).inHours < 24 && !_isD) _toggleD();
    }
  }

  Future<ImageProvider?> _getSenderPhoto(String senderID, bool isMe) async {
    try {
      if (isMe) {
        final prefs = await SharedPreferences.getInstance();
        final String? myPhoto = prefs.getString('user_photoUrl');
        if (myPhoto != null && myPhoto.isNotEmpty) return myPhoto.startsWith('http') ? CachedNetworkImageProvider(myPhoto) : FileImage(File(myPhoto)) as ImageProvider;
      } else {
        final contact = await DatabaseHelper.instance.getJembeContactById(senderID);
        if (contact != null) {
          final String? lp = contact['localPhotoPath']; if (lp != null && File(lp).existsSync()) return FileImage(File(lp));
          final String? ou = contact['photoUrl']; if (ou != null && ou.isNotEmpty) return CachedNetworkImageProvider(ou);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _toggleD() async {
    if (_isD) { _client?.close(); if(mounted) setState(() { _isD = false; _p = null; }); return; }
    final url = widget.messageData['fileUrl']; if (url == null || url.isEmpty) return;
    if(mounted) setState(() { _isD = true; _p = 0.0; });
    try {
      _client = http.Client(); final res = await _client!.send(http.Request('GET', Uri.parse(url)));
      final f = File(path.join((await getTemporaryDirectory()).path, "v_${widget.messageData['id']}.mp3"));
      final sink = f.openWrite(); int rec = 0; int tot = res.contentLength ?? -1;
      await res.stream.listen((c) { rec += c.length; if (tot != -1 && mounted) setState(() => _p = rec / tot); sink.add(c); }).asFuture();
      await sink.close();
      final perm = await FileStorageService.instance.saveFileToPublicDirectory(tempFilePath: f.path, dirType: StorageDirectoryType.audio, fileName: "v_${widget.messageData['id']}.mp3");
      if (perm != null && mounted) { await DatabaseHelper.instance.updateMessageLocalPath(widget.messageData['id'], perm); syncService.notifyUIMessageUpdate(widget.messageData['id']); setState(() => _isD = false); }
    } catch (_) { if (mounted) setState(() { _isD = false; _p = null; }); } finally { _client?.close(); }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messageData['messageType'] == 'audio_file') return AudioFileBubble(messageData: widget.messageData);
    final playerSvc = context.watch<AudioPlayerService>();
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser?.uid;
    final bool isCur = playerSvc.currentMessageId == widget.messageData['id'], isPlaying = isCur && playerSvc.isPlaying;
    final bool isPlayed = widget.isPlayed;
    
    final duration = Duration(seconds: widget.messageData['duration'] ?? 0), position = isCur ? playerSvc.position : Duration.zero;
    final local = widget.messageData['localPath']; final bool exists = local != null && File(local).existsSync();
    
    Color activeWaveColor = isMe ? Colors.white : (isPlayed ? Colors.grey.shade600 : Colors.blue.shade700);
    Color micOverlayColor = isMe ? Colors.white : (isPlayed ? Colors.grey : Colors.blue);

    return Container(
      width: 280, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), 
      child: Row(children: [
        FutureBuilder<ImageProvider?>(future: _getSenderPhoto(widget.messageData['senderID'], isMe), builder: (c, snap) => Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(radius: 22, backgroundColor: Colors.grey.shade300, backgroundImage: snap.data, child: snap.data == null ? const Icon(Icons.person, color: Colors.white, size: 30) : null), 
          Positioned(bottom: -2, right: -2, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(Icons.mic, color: micOverlayColor, size: 14)))
        ])),
        const SizedBox(width: 5),
        
        SizedBox(
          width: 38, height: 38,
          child: exists 
                ? GestureDetector(onTap: () { 
                    // ✅ FIXED: Pass exactly 5 arguments: id, path, isLocal, roomId, senderId
                    playerSvc.loadAudio(
                      widget.messageData['id'], 
                      local!, 
                      true, 
                      widget.messageData['chatRoomID'], 
                      widget.messageData['senderID']
                    ); 
                  }, child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: isMe ? Colors.white : (isPlayed ? Colors.grey : Colors.blue), size: 36))
                : GestureDetector(onTap: _toggleD, child: _isD ? Stack(alignment: Alignment.center, children: [CircularProgressIndicator(value: _p, color: Colors.blue, strokeWidth: 2), const Icon(Icons.close, size: 14)]) : const Icon(Icons.download_for_offline, color: Colors.blue, size: 32)),
        ),
        
        Expanded(child: GestureDetector(onHorizontalDragUpdate: (d) { if (isCur && exists && duration.inMilliseconds > 0) playerSvc.seek(Duration(milliseconds: (d.localPosition.dx / 150 * duration.inMilliseconds).toInt().clamp(0, duration.inMilliseconds))); },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CustomPaint(size: const Size(double.infinity, 25), painter: WaveformPainter(progress: duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0.0, activeColor: activeWaveColor, inactiveColor: isMe ? Colors.white24 : Colors.grey.shade300)), 
              Padding(padding: const EdgeInsets.only(left: 4), child: Text("${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')} / ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 9, color: Colors.black54)))
            ]))),
        
        if (isCur && exists) IconButton(onPressed: playerSvc.toggleSpeed, icon: Text("${playerSvc.playbackSpeed}x", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isMe ? Colors.white : Colors.blue))),
    ]));
  }
}

// ===========================================================================
// 3. AUDIO FILE BUBBLE
// ===========================================================================
class AudioFileBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  const AudioFileBubble({super.key, required this.messageData});
  @override State<AudioFileBubble> createState() => _AudioFileBubbleState();
}
class _AudioFileBubbleState extends State<AudioFileBubble> {
  bool _isD = false; double? _p; http.Client? _client;
  double _dragValue = 0.0; bool _isDragging = false;
  Future<void> _toggleD() async {
    if (_isD) { _client?.close(); setState(() { _isD = false; _p = null; }); return; }
    final url = widget.messageData['fileUrl']; if (url == null) return;
    setState(() { _isD = true; _p = 0.0; });
    try {
      _client = http.Client(); final res = await _client!.send(http.Request('GET', Uri.parse(url)));
      final f = File(path.join((await getTemporaryDirectory()).path, "audio_${widget.messageData['id']}.mp3"));
      final sink = f.openWrite(); int rec = 0; int tot = res.contentLength ?? -1;
      await res.stream.listen((c) { rec += c.length; if (tot != -1 && mounted) setState(() => _p = rec / tot); sink.add(c); }).asFuture();
      await sink.close();
      final perm = await FileStorageService.instance.saveFileToPublicDirectory(tempFilePath: f.path, dirType: StorageDirectoryType.audio, fileName: widget.messageData['fileName']);
      if (perm != null && mounted) { await DatabaseHelper.instance.updateMessageLocalPath(widget.messageData['id'], perm); syncService.notifyUIMessageUpdate(widget.messageData['id']); setState(() => _isD = false); }
    } catch (_) { if (mounted) setState(() { _isD = false; _p = null; }); } finally { _client?.close(); }
  }
  @override Widget build(BuildContext context) {
    final playerSvc = context.watch<AudioPlayerService>();
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser?.uid;
    final bool isCur = playerSvc.currentMessageId == widget.messageData['id'], isPlaying = isCur && playerSvc.isPlaying;
    Duration totalDuration = Duration(seconds: widget.messageData['duration'] ?? 0);
    if (isCur && playerSvc.totalDuration != null && playerSvc.totalDuration!.inMilliseconds > 0) totalDuration = playerSvc.totalDuration!;
    final position = isCur ? playerSvc.position : Duration.zero;
    final local = widget.messageData['localPath']; final bool exists = local != null && File(local).existsSync();
    final cardColor = isMe ? Colors.orange.shade900 : Colors.grey.shade200;
    final accentColor = isMe ? Colors.white : Colors.orange.shade700;
    final textColor = isMe ? Colors.white : Colors.black87;
    return Container(width: 270, padding: const EdgeInsets.fromLTRB(8, 4, 8, 4), decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)), child: Row(children: [
        SizedBox(width: 36, height: 36, child: exists 
          ? GestureDetector(onTap: () {
              // ✅ FIXED: Pass exactly 5 arguments: id, path, isLocal, roomId, senderId
              playerSvc.loadAudio(
                widget.messageData['id'], 
                local!, 
                true, 
                widget.messageData['chatRoomID'],
                widget.messageData['senderID']
              );
            }, child: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: accentColor, size: 36)) 
          : GestureDetector(onTap: _toggleD, child: _isD ? Stack(alignment: Alignment.center, children: [CircularProgressIndicator(value: _p, color: Colors.white, strokeWidth: 2), const Icon(Icons.close, color: Colors.white, size: 14)]) : Icon(Icons.download_for_offline, color: accentColor, size: 36))),
        const SizedBox(width: 8),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Expanded(child: Text(widget.messageData['fileName'] ?? "Audio", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)), if (isCur && exists) GestureDetector(onTap: playerSvc.toggleSpeed, child: Text("${playerSvc.playbackSpeed}x", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 9)))]),
            SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4), activeTrackColor: accentColor, inactiveTrackColor: accentColor.withOpacity(0.2), thumbColor: accentColor, overlayShape: SliderComponentShape.noOverlay),
              child: Slider(value: _isDragging ? _dragValue : (isCur ? position.inMilliseconds.toDouble().clamp(0.0, totalDuration.inMilliseconds.toDouble()) : 0.0), max: totalDuration.inMilliseconds.toDouble() > 0 ? totalDuration.inMilliseconds.toDouble() : 1.0, onChangeStart: (v) => setState(() { _isDragging = true; _dragValue = v; }), onChanged: (v) => setState(() => _dragValue = v), onChangeEnd: (v) async { if (isCur && exists) await playerSvc.seek(Duration(milliseconds: v.toInt())); setState(() => _isDragging = false); })),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text("${position.inMinutes}:${(position.inSeconds%60).toString().padLeft(2,'0')}", style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 8)), Text("${totalDuration.inMinutes}:${(totalDuration.inSeconds%60).toString().padLeft(2,'0')}", style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 8))]),
        ])),
    ]));
  }
}

// ===========================================================================
// 4. VIDEO PLAYER BUBBLE
// ===========================================================================
class VideoPlayerBubble extends StatefulWidget {
  final Map<String, dynamic> messageData; final String? caption; final bool isUploadingOrFailed;
  const VideoPlayerBubble({super.key, required this.messageData, this.caption, this.isUploadingOrFailed = false});
  @override State<VideoPlayerBubble> createState() => _VideoPlayerBubbleState();
}
class _VideoPlayerBubbleState extends State<VideoPlayerBubble> {
  VideoPlayerController? _vCtrl; bool _isD = false; double? _p; http.Client? _client; bool _isInit = false;
  void _onPlay() async {
    final p = widget.messageData['localPath'];
    if (p != null && File(p).existsSync()) {
      if (_vCtrl == null) { _vCtrl = VideoPlayerController.file(File(p)); try { await _vCtrl!.initialize(); setState(() { _isInit = true; _vCtrl!.play(); }); } catch (_) {} }
      else { setState(() { if (_vCtrl!.value.isPlaying) _vCtrl!.pause(); else _vCtrl!.play(); }); }
    } else { _toggleD(); }
  }
  Future<void> _toggleD() async {
    if (_isD) { _client?.close(); setState(() { _isD = false; _p = null; }); return; }
    final url = widget.messageData['fileUrl']; if (url == null) return;
    setState(() { _isD = true; _p = 0.0; });
    try {
      _client = http.Client(); final res = await _client!.send(http.Request('GET', Uri.parse(url)));
      final f = File(path.join((await getTemporaryDirectory()).path, path.basename(url)));
      final sink = f.openWrite(); int rec = 0; int tot = res.contentLength ?? -1;
      await res.stream.listen((c) { rec += c.length; if (tot != -1 && mounted) setState(() => _p = rec / tot); sink.add(c); }).asFuture();
      await sink.close();
      final perm = await FileStorageService.instance.saveFileToPublicDirectory(tempFilePath: f.path, dirType: StorageDirectoryType.video, fileName: path.basename(url));
      if (perm != null && mounted) { await DatabaseHelper.instance.updateMessageLocalPath(widget.messageData['id'], perm); syncService.notifyUIMessageUpdate(widget.messageData['id']); setState(() => _isD = false); }
    } catch (_) { if (mounted) setState(() { _isD = false; _p = null; }); } finally { _client?.close(); }
  }
  @override void dispose() { _vCtrl?.dispose(); _client?.close(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final local = widget.messageData['localPath']; final bool exists = local != null && File(local).existsSync();
    final thumb = widget.messageData['thumbnailLocalPath'], thumbUrl = widget.messageData['thumbnailUrl'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(height: 200, width: 250, color: Colors.black, child: Stack(alignment: Alignment.center, children: [
        if (_vCtrl != null && _isInit) AspectRatio(aspectRatio: _vCtrl!.value.aspectRatio, child: VideoPlayer(_vCtrl!))
        else Positioned.fill(child: thumb != null && File(thumb).existsSync() ? Image.file(File(thumb), fit: BoxFit.cover) : (thumbUrl != null ? CachedNetworkImage(imageUrl: thumbUrl, fit: BoxFit.cover, errorWidget: (c,u,e) => Container(color: Colors.white10)) : Container(color: Colors.white10))),
        if (exists) IconButton(icon: Icon(_vCtrl?.value.isPlaying == true ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white, size: 50), onPressed: _onPlay)
        else if (!widget.isUploadingOrFailed) Positioned(bottom: 8, right: 8, child: GestureDetector(onTap: _toggleD, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: _isD ? Stack(alignment: Alignment.center, children: [CircularProgressIndicator(value: _p, color: Colors.white, strokeWidth: 2), const Icon(Icons.close, color: Colors.white, size: 18)]) : const Icon(Icons.download_for_offline, color: Colors.white, size: 28)))),
        if (_vCtrl != null && _isInit) Positioned(top: 5, right: 5, child: IconButton(icon: const Icon(Icons.fullscreen, color: Colors.white), onPressed: () async { final curPos = _vCtrl!.value.position; _vCtrl!.pause(); final Duration? newPos = await Navigator.push(context, MaterialPageRoute(builder: (c) => FullScreenVideoPlayer(videoUrl: local!, startAt: curPos))); if (newPos != null) _vCtrl!.seekTo(newPos); })),
        if (_vCtrl != null && _isInit) Positioned(bottom: 0, left: 0, right: 0, child: VideoProgressIndicator(_vCtrl!, allowScrubbing: true)),
      ]))),
      if (widget.caption != null && widget.caption!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5, left: 4), child: Text(widget.caption!)),
    ]);
  }
}

class FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl; final Duration startAt;
  const FullScreenVideoPlayer({super.key, required this.videoUrl, required this.startAt});
  @override State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}
class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late VideoPlayerController _v; ChewieController? _c;
  @override void initState() { super.initState(); _v = VideoPlayerController.file(File(widget.videoUrl)); _v.initialize().then((_) { _c = ChewieController(videoPlayerController: _v, autoPlay: true, looping: false, startAt: widget.startAt, fullScreenByDefault: true, allowFullScreen: true, aspectRatio: _v.value.aspectRatio, deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp]); setState(() {}); }); }
  @override void dispose() { _v.dispose(); _c?.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Stack(children: [Center(child: _c != null ? Chewie(controller: _c!) : const CircularProgressIndicator(color: Colors.white)), Positioned(top: 40, left: 20, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context, _v.value.position)))]));
}

class DocumentBubble extends StatefulWidget {
  final Map<String, dynamic> messageData; final Color textColor;
  const DocumentBubble({super.key, required this.messageData, required this.textColor});
  @override State<DocumentBubble> createState() => _DocumentBubbleState();
}
class _DocumentBubbleState extends State<DocumentBubble> {
  bool _isD = false; double? _p; http.Client? _client;
  Future<void> _toggleD() async {
    if (_isD) { _client?.close(); setState(() { _isD = false; _p = null; }); return; }
    final url = widget.messageData['fileUrl']; if (url == null) return;
    setState(() { _isD = true; _p = 0.0; });
    try {
      _client = http.Client(); final res = await _client!.send(http.Request('GET', Uri.parse(url)));
      final f = File(path.join((await getTemporaryDirectory()).path, "doc_${widget.messageData['id']}"));
      final sink = f.openWrite(); int rec = 0; int tot = res.contentLength ?? -1;
      await res.stream.listen((c) { rec += c.length; if (tot != -1 && mounted) setState(() => _p = rec / tot); sink.add(c); }).asFuture();
      await sink.close();
      final perm = await FileStorageService.instance.saveFileToPublicDirectory(tempFilePath: f.path, dirType: StorageDirectoryType.documents, fileName: widget.messageData['fileName']);
      if (perm != null && mounted) { await DatabaseHelper.instance.updateMessageLocalPath(widget.messageData['id'], perm); syncService.notifyUIMessageUpdate(widget.messageData['id']); setState(() => _isD = false); }
    } catch (_) { if (mounted) setState(() { _isD = false; _p = null; }); } finally { _client?.close(); }
  }
  @override Widget build(BuildContext context) {
    final local = widget.messageData['localPath']; final bool exists = local != null && File(local).existsSync();
    return InkWell(onTap: exists ? () => OpenFilex.open(local) : _toggleD, child: Container(width: 250, padding: const EdgeInsets.all(12), child: Row(children: [ _isD ? Stack(alignment: Alignment.center, children: [SizedBox(width: 35, height: 35, child: CircularProgressIndicator(value: _p, strokeWidth: 2)), const Icon(Icons.close, size: 16)]) : Icon(exists ? Icons.description_rounded : Icons.file_download_rounded, color: widget.textColor.withOpacity(0.7), size: 38), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(widget.messageData['fileName'] ?? "Document", style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis), if (exists) Text("Tap to open", style: TextStyle(color: widget.textColor.withOpacity(0.5), fontSize: 10)) ])) ])));
  }
}

class ContactBubble extends StatelessWidget {
  final Map<String, dynamic> contactData; const ContactBubble({super.key, required this.contactData});
  Future<void> _addContactToPhone(BuildContext context) async { if (await Permission.contacts.request().isGranted) await FlutterContacts.openExternalInsert(Contact()..name.first = contactData['name'] ?? ''..phones = [Phone(contactData['number'] ?? '')]); }
  Future<void> _findAndInteractWithUser(BuildContext context, {required bool openChat}) async {
    final phoneNumber = contactData['number']; if (phoneNumber == null) return;
    showDialog(context: context, builder: (c) => const Center(child: CircularProgressIndicator()));
    try {
      final query = await FirebaseFirestore.instance.collection('users').where('phoneNumber', isEqualTo: phoneNumber).limit(1).get();
      if (context.mounted) Navigator.pop(context);
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first, data = doc.data();
        if (context.mounted) { final route = MaterialPageRoute(builder: (c) => openChat ? ChatScreenWrapper(receiverID: doc.id, receiverEmail: data['displayName'] ?? 'User') : ContactInfoScreen(userID: doc.id, userEmail: data['displayName'] ?? 'User', photoUrl: data['photoUrl'])); if(openChat) Navigator.pushReplacement(context, route); else Navigator.push(context, route); }
      }
    } catch (e) { if (context.mounted) Navigator.pop(context); }
  }
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context), lang = Provider.of<LanguageProvider>(context);
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(width: 250, color: theme.cardColor, child: Column(mainAxisSize: MainAxisSize.min, children: [ InkWell(onTap: () => _findAndInteractWithUser(context, openChat: false), child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [const CircleAvatar(child: Icon(Icons.person)), const SizedBox(width: 12), Expanded(child: Text(contactData['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis)), IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () => Clipboard.setData(ClipboardData(text: contactData['number'] ?? '')))]))), const Divider(height: 1), Row(children: [Expanded(child: TextButton(onPressed: () => _findAndInteractWithUser(context, openChat: true), child: Text(lang.t('chat_message_button')))), Container(width: 1, height: 30, color: theme.dividerColor), Expanded(child: TextButton(onPressed: () => _addContactToPhone(context), child: Text(lang.t('chat_add_contact_button'))))]) ])));
  }
}

class WaveformPainter extends CustomPainter {
  final double progress; final Color activeColor, inactiveColor;
  WaveformPainter({required this.progress, required this.activeColor, required this.inactiveColor});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    const int barCount = 30;
    for (int i = 0; i < barCount; i++) {
      double x = i * (size.width / barCount); 
      double h = 6.0 + (i % 5 == 0 ? 12.0 : (i % 3 == 0 ? 8.0 : 4.0));
      p.color = (i / barCount) < progress ? activeColor : inactiveColor;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), p);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}