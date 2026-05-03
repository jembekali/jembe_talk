import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/post_translations.dart';
import 'package:image_picker/image_picker.dart';

class MediaTextOverlay {
  String text;
  Offset position;
  Color color;
  Color? backgroundColor;
  double fontSize;
  double scale;
  bool isEmoji;

  MediaTextOverlay({
    required this.text,
    required this.position,
    this.color = Colors.white,
    this.backgroundColor,
    this.fontSize = 28,
    this.scale = 1.0,
    this.isEmoji = false,
  });

  MediaTextOverlay copy() => MediaTextOverlay(
        text: text,
        position: position,
        color: color,
        backgroundColor: backgroundColor,
        fontSize: fontSize,
        scale: scale,
        isEmoji: isEmoji,
      );
}

class MediaEditorView extends StatefulWidget {
  final File file;
  final String type;
  final List? initialOverlays;
  final double? initialBrightness;
  final double? initialSaturation;
  final int? initialRotation;
  final double? initialZoom;
  final Offset? initialOffset;
  final String? initialFilter;
  final bool? initialMute;
  final double? initialStart;
  final double? initialEnd;

  const MediaEditorView({
    super.key,
    required this.file,
    required this.type,
    this.initialOverlays,
    this.initialBrightness,
    this.initialSaturation,
    this.initialRotation,
    this.initialZoom,
    this.initialOffset,
    this.initialFilter,
    this.initialMute,
    this.initialStart,
    this.initialEnd,
  });

  @override
  State<MediaEditorView> createState() => _MediaEditorViewState();
}

class _MediaEditorViewState extends State<MediaEditorView> {
  VideoPlayerController? _videoController;
  double _startValue = 0.0;
  double _endValue = 1.0;
  bool _isMuted = false;
  String _currentFilter = "none";
  bool _isPlayingPreview = false;

  double _zoomScale = 1.0;
  Offset _videoOffset = Offset.zero;
  int _rotation = 0;
  double _brightness = 0.0;
  double _saturation = 1.0;
  double? _selectedAspectRatio;

  List<MediaTextOverlay> _textOverlays = [];
  MediaTextOverlay? _selectedOverlay;
  bool _isDraggingForDelete = false;
  bool _isOverDeleteZone = false;
  final List<String> _thumbnails = [];
  String? _selectedThumbnailPath;
  final ImagePicker _picker = ImagePicker();

  final ScrollController _timelineScrollController = ScrollController();
  double _timelineZoom = 5.0;
  final List<Color> _availableColors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.orange,
    Colors.pink,
    Colors.purple,
    Colors.cyan
  ];

  @override
  void initState() {
    super.initState();
    _textOverlays = widget.initialOverlays?.map((e) => (e as MediaTextOverlay).copy()).toList() ?? [];
    _brightness = widget.initialBrightness ?? 0.0;
    _saturation = widget.initialSaturation ?? 1.0;
    _rotation = widget.initialRotation ?? 0;
    _zoomScale = widget.initialZoom ?? 1.0;
    _videoOffset = widget.initialOffset ?? Offset.zero;
    _currentFilter = widget.initialFilter ?? "none";
    _isMuted = widget.initialMute ?? false;
    _startValue = widget.initialStart ?? 0.0;
    _endValue = widget.initialEnd ?? 1.0;

    if (widget.type == 'video') {
      _videoController = VideoPlayerController.file(widget.file)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isPlayingPreview = _videoController!.value.isPlaying;
              double videoDur = _videoController!.value.duration.inSeconds.toDouble();
              if (widget.initialEnd == null) _endValue = videoDur > 120 ? 120 / videoDur : 1.0;
            });
            _generateThumbnails();
            _jumpToHandle(_startValue);
          }
          _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
          _videoController!.addListener(_videoListener);
        });
    }
  }

  String _formatDur(Duration d) =>
      "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

  void _jumpToHandle(double percentage) {
    final vc = _videoController;
    if (vc == null || !vc.value.isInitialized) return;
    double duration = vc.value.duration.inSeconds.toDouble();
    double screenWidth = MediaQuery.of(context).size.width;
    double currentPPS = ((screenWidth - 40) / duration) * (_timelineZoom / 5.0);
    double totalWidth = duration * currentPPS;
    double offset = (percentage * totalWidth) - (screenWidth / 2);
    if (_timelineScrollController.hasClients) {
      _timelineScrollController.animateTo(
        offset.clamp(0.0, _timelineScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _videoListener() {
    final vc = _videoController;
    if (vc == null || !vc.value.isInitialized) return;
    if (vc.value.position >= vc.value.duration * _endValue) {
      vc.seekTo(vc.value.duration * _startValue);
    }
    if (mounted) setState(() => _isPlayingPreview = vc.value.isPlaying);
  }

  Future<void> _pickThumbnailFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _selectedThumbnailPath = image.path);
  }

  Future<void> _generateThumbnails() async {
    final tempDir = await getTemporaryDirectory();
    if (_videoController == null) return;
    final duration = _videoController!.value.duration.inSeconds;
    if (duration < 1) return;
    for (int i = 0; i < 15; i++) {
      final time = (duration / 15 * i).toInt();
      final thumbPath = p.join(tempDir.path, 'thumb${const Uuid().v4()}.jpg');
      await FFmpegKit.execute("-ss $time -i '${widget.file.path}' -vframes 1 -q:v 8 '$thumbPath'");
      if (mounted) {
        setState(() {
          _thumbnails.add(thumbPath);
          if (_selectedThumbnailPath == null) _selectedThumbnailPath = thumbPath;
        });
      }
    }
  }

  void _confirmEdits() {
    Navigator.pop(context, {
      'file': widget.file,
      'overlays': _textOverlays,
      'brightness': _brightness,
      'saturation': _saturation,
      'rotation': _rotation,
      'zoom': _zoomScale,
      'offset': _videoOffset,
      'filter': _currentFilter,
      'isMuted': _isMuted,
      'startTrim': _startValue,
      'endTrim': _endValue,
      'thumbnail': _selectedThumbnailPath,
      'aspectRatio': _selectedAspectRatio,
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _timelineScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final lang = Provider.of<LanguageProvider>(context);
    final String l = lang.currentLanguage;
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        ),
        flexibleSpace: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.only(top: 15),
          child: Opacity(
            opacity: 0.2,
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(colors: [Colors.blueAccent, Colors.amberAccent, Colors.orangeAccent]).createShader(bounds),
              child: const Text("JEMBE TALK", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 4)),
            ),
          ),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.undo, color: Colors.white70),
              onPressed: () {
                if (_textOverlays.isNotEmpty) {
                  setState(() {
                    _textOverlays.removeLast();
                    _selectedOverlay = null;
                  });
                }
              }),
          IconButton(icon: const Icon(Icons.rotate_right), onPressed: () => setState(() => _rotation = (_rotation + 90) % 360)),
          IconButton(
              icon: const Icon(Icons.title),
              onPressed: () {
                String it = "";
                showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                        backgroundColor: Colors.grey[900],
                        title: Text(PostTranslations.t('add_text', l), style: const TextStyle(color: Colors.white)),
                        content: TextField(
                            autofocus: true,
                            style: const TextStyle(color: Colors.white),
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (v) => it = v),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: Text(PostTranslations.t('cancel', l))),
                          ElevatedButton(
                              onPressed: () {
                                if (it.trim().isNotEmpty) {
                                  setState(() {
                                    _selectedOverlay = MediaTextOverlay(text: it.trim(), position: Offset(size.width / 2 - 80, size.height * 0.08));
                                    _textOverlays.add(_selectedOverlay!);
                                  });
                                }
                                Navigator.pop(c);
                              },
                              child: Text(PostTranslations.t('confirm', l)))
                        ]));
              }),
          TextButton(onPressed: _confirmEdits, child: Text(PostTranslations.t('save_button', l), style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16))),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        return Column(children: [
          Expanded(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedOverlay = null;
                    if (_videoController!.value.isPlaying) {
                      _videoController!.pause();
                    } else {
                      _videoController!.play();
                    }
                  }),
                  onDoubleTap: () => setState(() {
                    _zoomScale = 1.0;
                    _videoOffset = Offset.zero;
                  }),
                  onScaleUpdate: (details) {
                    if (_selectedOverlay == null) {
                      setState(() {
                        _zoomScale = (_zoomScale * details.scale).clamp(1.0, 5.0);
                        _videoOffset += details.focalPointDelta;
                      });
                    }
                  },
                  child: Container(
                      color: Colors.black,
                      child: Center(
                          child: (_videoController != null && _videoController!.value.isInitialized)
                              ? ClipRect(
                                  child: AspectRatio(
                                      aspectRatio: _selectedAspectRatio ?? _videoController!.value.aspectRatio,
                                      child: Transform.rotate(
                                          angle: _rotation * 3.14 / 180,
                                          child: Transform.translate(
                                              offset: _videoOffset,
                                              child: Transform.scale(scale: _zoomScale, child: ColorFiltered(colorFilter: _getVideoFilter(), child: VideoPlayer(_videoController!)))))))
                              : const CircularProgressIndicator())),
                ),
                if (_selectedThumbnailPath != null && !isKeyboardVisible)
                  Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent, width: 2), borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black54)]),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(alignment: Alignment.bottomCenter, children: [
                                Image.file(File(_selectedThumbnailPath!), width: 60, height: 85, fit: BoxFit.cover),
                                Container(
                                    width: 60,
                                    color: Colors.blueAccent.withOpacity(0.7),
                                    child: const Text("COVER", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))
                              ])))),
                ..._textOverlays
                    .map((o) => Positioned(
                          left: o.position.dx,
                          top: o.position.dy,
                          child: GestureDetector(
                            onScaleUpdate: (d) => setState(() {
                              _selectedOverlay = o;
                              o.position += d.focalPointDelta;
                              o.scale = (o.scale * d.scale).clamp(0.5, 5.0);
                              _isOverDeleteZone = (o.position.dy > constraints.maxHeight - 150);
                            }),
                            onScaleStart: (_) => setState(() {
                              _selectedOverlay = o;
                              _isDraggingForDelete = true;
                            }),
                            onScaleEnd: (_) {
                              if (_isOverDeleteZone) {
                                setState(() {
                                  _textOverlays.remove(o);
                                  _selectedOverlay = null;
                                });
                              }
                              setState(() {
                                _isDraggingForDelete = false;
                                _isOverDeleteZone = false;
                              });
                            },
                            onTap: () => setState(() => _selectedOverlay = o),
                            child: Material(
                                color: Colors.transparent,
                                child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: o.backgroundColor, border: _selectedOverlay == o ? Border.all(color: Colors.blueAccent, width: 2) : null, borderRadius: BorderRadius.circular(8)),
                                    child: Transform.scale(
                                        scale: o.scale,
                                        child: Text(o.text, style: TextStyle(color: o.color, fontSize: o.fontSize, fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 10, color: Colors.black)]))))),
                          ),
                        ))
                    .toList(),
                if (_isDraggingForDelete)
                  Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Center(
                          child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(shape: BoxShape.circle, color: _isOverDeleteZone ? Colors.red : Colors.black87),
                              child: Icon(_isOverDeleteZone ? Icons.delete : Icons.delete_outline, color: Colors.white, size: _isOverDeleteZone ? 50 : 35)))),
              ],
            ),
          ),
          if (!isKeyboardVisible) _buildTimelineAndControls(l, size),
        ]);
      }),
    );
  }

  Widget _buildTimelineAndControls(String l, Size size) {
    final vc = _videoController;
    if (vc == null || !vc.value.isInitialized) return const SizedBox();
    double duration = vc.value.duration.inSeconds.toDouble();
    double totalWidth = (size.width - 40) * _timelineZoom;
    double playheadX = (vc.value.position.inMilliseconds / (duration * 1000)) * totalWidth;

    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1A1A1A),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [_ratioBtn("Original", null), _ratioBtn("TikTok", 9 / 16), _ratioBtn("YouTube", 16 / 9), _ratioBtn("Instagram", 1 / 1)])),
        const Divider(color: Colors.white10),
        Row(children: [
          IconButton(icon: const Icon(Icons.start, color: Colors.greenAccent, size: 18), onPressed: () => _jumpToHandle(_startValue)),
          Expanded(child: Slider(value: _timelineZoom, min: 1.0, max: 15.0, divisions: 28, activeColor: Colors.blueAccent, onChanged: (v) => setState(() => _timelineZoom = v))),
          IconButton(icon: const Icon(Icons.not_started, color: Colors.redAccent, size: 18), onPressed: () => _jumpToHandle(_endValue)),
        ]),
        GestureDetector(
          onTapUp: (details) {
            double tapX = details.localPosition.dx + _timelineScrollController.offset - (size.width / 2);
            double seekRatio = (tapX / totalWidth).clamp(0.0, 1.0);
            vc.seekTo(Duration(milliseconds: (duration * seekRatio * 1000).toInt()));
          },
          child: SizedBox(
              height: 60,
              child: SingleChildScrollView(
                  controller: _timelineScrollController,
                  scrollDirection: Axis.horizontal,
                  child: Container(
                      width: totalWidth + size.width,
                      padding: EdgeInsets.symmetric(horizontal: size.width / 2),
                      child: Stack(alignment: Alignment.centerLeft, children: [
                        Row(children: _thumbnails.map((t) => Image.file(File(t), width: totalWidth / _thumbnails.length, height: 45, fit: BoxFit.cover)).toList()),
                        Positioned(left: _startValue * totalWidth, width: (_endValue - _startValue) * totalWidth, child: Container(height: 48, decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.2), border: const Border.symmetric(horizontal: BorderSide(color: Colors.amberAccent, width: 2))))),
                        Positioned(left: playheadX, child: Container(width: 2, height: 55, decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black45)]))),
                        Positioned(
                            left: _startValue * totalWidth - 10,
                            child: GestureDetector(
                                onHorizontalDragUpdate: (d) {
                                  setState(() => _startValue = ((_startValue * totalWidth + d.delta.dx) / totalWidth).clamp(0.0, _endValue - 0.001));
                                  vc.seekTo(Duration(milliseconds: (duration * _startValue * 1000).toInt()));
                                },
                                child: _handleWidget(Colors.greenAccent, Icons.arrow_right))),
                        Positioned(
                            left: _endValue * totalWidth - 10,
                            child: GestureDetector(
                                onHorizontalDragUpdate: (d) {
                                  double maxEnd = _startValue + (120 / duration);
                                  setState(() => _endValue = ((_endValue * totalWidth + d.delta.dx) / totalWidth).clamp(_startValue + 0.001, maxEnd.clamp(0.0, 1.0)));
                                  vc.seekTo(Duration(milliseconds: (duration * _endValue * 1000).toInt()));
                                },
                                child: _handleWidget(Colors.redAccent, Icons.arrow_left))),
                      ])))),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_formatDur(Duration(seconds: (duration * _startValue).toInt())), style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
          IconButton(icon: Icon(vc.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.blueAccent, size: 24), onPressed: () => setState(() => vc.value.isPlaying ? vc.pause() : vc.play())),
          Text(_formatDur(Duration(seconds: (duration * _endValue).toInt())), style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Cover", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          GestureDetector(onTap: _pickThumbnailFromGallery, child: const Row(children: [Icon(Icons.photo_library, size: 14, color: Colors.blueAccent), Text(" Gallery", style: TextStyle(color: Colors.blueAccent, fontSize: 10))])),
        ]),
        SizedBox(
            height: 40,
            child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _thumbnails.length,
                itemBuilder: (context, index) {
                  bool isSel = _selectedThumbnailPath == _thumbnails[index];
                  return GestureDetector(
                      onTap: () => setState(() => _selectedThumbnailPath = _thumbnails[index]),
                      child: Container(margin: const EdgeInsets.only(right: 5), decoration: BoxDecoration(border: Border.all(color: isSel ? Colors.blueAccent : Colors.transparent, width: 2), borderRadius: BorderRadius.circular(4)), child: Image.file(File(_thumbnails[index]), width: 40, height: 40, fit: BoxFit.cover)));
                })),
        if (_selectedOverlay != null)
          Container(
              height: 40,
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _availableColors.length,
                  itemBuilder: (c, i) => GestureDetector(onTap: () => setState(() => _selectedOverlay!.color = _availableColors[i]), child: Container(width: 30, height: 30, margin: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: _availableColors[i], shape: BoxShape.circle, border: Border.all(color: Colors.white)))))),
        Row(children: [
          const Icon(Icons.wb_sunny_outlined, color: Colors.amberAccent, size: 14),
          Expanded(child: Slider(value: _brightness, min: -0.5, max: 0.5, activeColor: Colors.amberAccent, onChanged: (v) => setState(() => _brightness = v))),
          const Icon(Icons.palette_outlined, color: Colors.blueAccent, size: 14),
          Expanded(child: Slider(value: _saturation, min: 0.0, max: 2.0, activeColor: Colors.blueAccent, onChanged: (v) => setState(() => _saturation = v)))
        ]),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterBtn("None", "none"),
              _filterBtn("B&W", "grayscale"),
              _filterBtn("Sepia", "sepia"),
              _filterBtn("Green", "green"),
              _filterBtn("Blue", "blue"),
              const SizedBox(width: 15),
              IconButton(icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20), onPressed: () => setState(() { _isMuted = !_isMuted; vc.setVolume(_isMuted ? 0.0 : 1.0); }))
            ])),
      ]),
    );
  }

  Widget _ratioBtn(String label, double? ratio) => GestureDetector(
      onTap: () => setState(() => _selectedAspectRatio = ratio),
      child: Container(margin: const EdgeInsets.only(right: 10), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: _selectedAspectRatio == ratio ? Colors.amberAccent : Colors.white10, borderRadius: BorderRadius.circular(15)), child: Text(label, style: TextStyle(color: _selectedAspectRatio == ratio ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold))));

  Widget _handleWidget(Color color, IconData icon) => Container(width: 20, height: 55, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black45)]), child: Icon(icon, size: 18, color: Colors.black));

  Widget _filterBtn(String label, String filterType) => GestureDetector(onTap: () => setState(() => _currentFilter = filterType), child: Container(margin: const EdgeInsets.only(right: 10), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: _currentFilter == filterType ? Colors.blueAccent : Colors.white10, borderRadius: BorderRadius.circular(20)), child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11))));

  ColorFilter _getVideoFilter() {
    double b = _brightness * 255;
    double s = _saturation;
    double invS = 1.0 - s;
    double lumR = 0.2126 * invS;
    double lumG = 0.7152 * invS;
    double lumB = 0.0722 * invS;

    if (_currentFilter == "grayscale") {
      return ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, b,
        0.2126, 0.7152, 0.0722, 0, b,
        0.2126, 0.7152, 0.0722, 0, b,
        0, 0, 0, 1, 0
      ]);
    }
    if (_currentFilter == "sepia") {
      return ColorFilter.matrix([
        0.393 * s, 0.769 * s, 0.189 * s, 0, b,
        0.349 * s, 0.686 * s, 0.168 * s, 0, b,
        0.272 * s, 0.534 * s, 0.131 * s, 0, b,
        0, 0, 0, 1, 0
      ]);
    }
    if (_currentFilter == "green") {
      return ColorFilter.matrix([
        lumR + s * 0.5, lumG, lumB, 0, b,
        lumR, lumG + s * 1.5, lumB, 0, b,
        lumR, lumG, lumB + s * 0.5, 0, b,
        0, 0, 0, 1, 0
      ]);
    }
    if (_currentFilter == "blue") {
      return ColorFilter.matrix([
        lumR + s * 0.5, lumG, lumB, 0, b,
        lumR, lumG, lumB, 0, b,
        lumR, lumG, lumB + s * 2.0, 0, b,
        0, 0, 0, 1, 0
      ]);
    }
    return ColorFilter.matrix([
      lumR + s, lumG, lumB, 0, b,
      lumR, lumG + s, lumB, 0, b,
      lumR, lumG, lumB + s, 0, b,
      0, 0, 0, 1, 0
    ]);
  }
}