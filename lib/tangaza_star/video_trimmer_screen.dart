// Fayili ya: lib/tangaza_star/video_trimmer_screen.dart
// YAKOSOWEMO IKOSA RYA 'import' N'IBINDI BYOSE

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart'; // <<< IKOSA RYARI HANO, UBU RYARAKOSOWE
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_editor/video_editor.dart';

class TextOverlay {
  String text;
  Color color;
  Color? backgroundColor;
  double fontSize;
  Offset position;
  double scale;
  double rotation;

  TextOverlay({
    required this.text,
    required this.color,
    this.backgroundColor,
    required this.fontSize,
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
  });
}

class VideoTrimmerScreen extends StatefulWidget {
  final File videoFile;
  const VideoTrimmerScreen({super.key, required this.videoFile});
  @override
  State<VideoTrimmerScreen> createState() => _VideoTrimmerScreenState();
}

class _VideoTrimmerScreenState extends State<VideoTrimmerScreen> {
  late final VideoEditorController _controller;
  bool _isExporting = false;
  final List<TextOverlay> _addedTexts = [];
  int _selectedTextIndex = -1;
  Size _viewerSize = Size.zero;
  String _selectedFilter = 'Nta imwe';

  bool _isEditingText = false;
  late final TextEditingController _textEditingController;
  final List<Color> _colors = [
    Colors.white, Colors.black, Colors.red, Colors.orange,
    Colors.yellow, Colors.green, Colors.blue, Colors.indigo, Colors.purple,
  ];

  final Map<String, String> _filters = {
    'Nta imwe': '',
    'N&B': 'format=gray',
    'Sepia': 'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131',
    'Vignette': 'vignette',
    'B&W': 'lutyuv=y=maxval',
  };

  @override
  void initState() {
    super.initState();
    _controller = VideoEditorController.file(widget.videoFile, minDuration: const Duration(seconds: 1), maxDuration: const Duration(seconds: 60));
    _controller.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((error) {
      if (mounted) Navigator.pop(context);
    });
    _textEditingController = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _textEditingController.dispose();
    super.dispose();
  }
  
  Future<String> _getFontPath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final fontPath = '${documentsDir.path}/NotoColorEmoji-Regular.ttf';
    final fontFile = File(fontPath);
    if (!await fontFile.exists()) {
      final byteData = await rootBundle.load('assets/fonts/NotoColorEmoji-Regular.ttf');
      await fontFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return fontPath;
  }

  String _colorToFFmpegHex(Color color) {
    return '0x${color.value.toRadixString(16).substring(2)}';
  }

  Future<void> _exportVideo() async {
    if (mounted) setState(() { _isExporting = true; });
    try {
      final String fontPath = await _getFontPath();
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String outputPath = '${appDocDir.path}/edited_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final Duration start = _controller.startTrim;
      final Duration end = _controller.endTrim;
      final Duration duration = end - start;
      List<String> videoFilters = [];
      
      if (_selectedFilter != 'Nta imwe' && _filters.containsKey(_selectedFilter)) {
        videoFilters.add(_filters[_selectedFilter]!);
      }

      final rotation = _controller.rotation;
      if (rotation == 90) videoFilters.add('transpose=1');
      else if (rotation == 180) videoFilters.add('transpose=2,transpose=2');
      else if (rotation == 270) videoFilters.add('transpose=2');
      
      final videoWidth = _controller.video.value.size.width;
      final videoHeight = _controller.video.value.size.height;
      
      for (var textOverlay in _addedTexts) {
        final colorHex = _colorToFFmpegHex(textOverlay.color);
        final ffFontSize = (textOverlay.fontSize * textOverlay.scale) * (videoHeight / _viewerSize.height);
        final ffX = (textOverlay.position.dx / _viewerSize.width) * videoWidth;
        final ffY = (textOverlay.position.dy / _viewerSize.height) * videoHeight;
        
        String drawtext = "drawtext=fontfile='$fontPath':text='${textOverlay.text.replaceAll("'", "’")}':fontcolor='$colorHex':fontsize=$ffFontSize:x=$ffX:y=$ffY";
        if (textOverlay.backgroundColor != null) {
          final bgColorHex = _colorToFFmpegHex(textOverlay.backgroundColor!);
          drawtext += ":box=1:boxcolor=$bgColorHex:boxborderw=10";
        }
        videoFilters.add(drawtext);
      }

      final String filterCommand = videoFilters.isNotEmpty ? '-vf "${videoFilters.join(',')}"' : '';
      
      final String command =
          '-i "${widget.videoFile.path}" -ss ${start.inSeconds} -t ${duration.inSeconds} '
          '$filterCommand '
          '-c:v libx264 -preset medium -crf 23 '
          '-c:a aac -b:a 128k '
          '"$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        if (mounted) Navigator.pop(context, File(outputPath));
      } else { /* Handle error */ }
    } catch (e) { /* Handle error */ } finally {
      if (mounted) setState(() { _isExporting = false; });
    }
  }

  String _formatter(Duration duration) => [
        duration.inMinutes.remainder(60).toString().padLeft(2, '0'),
        duration.inSeconds.remainder(60).toString().padLeft(2, '0')
      ].join(":");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tunganya Video'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(onPressed: (_isExporting || _isEditingText) ? null : _exportVideo, icon: const Icon(Icons.check, color: Colors.blueAccent))
        ],
      ),
      backgroundColor: Colors.black,
      body: _controller.initialized
          ? SafeArea(
              child: Stack(alignment: Alignment.center, children: [
                Column(children: [
                  _viewer(),
                  if (!_isEditingText) ...[
                    _buildFilterSelection(),
                    _trimmer(),
                    _editingTools()
                  ]
                ]),

                if (_isEditingText) _buildTextEditingUI(),

                if (_isExporting)
                  Container(
                    color: Colors.black.withAlpha(128),
                    child: const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(), SizedBox(height: 10),
                        Text("Bika videwo...", style: TextStyle(color: Colors.white))
                      ]),
                    ),
                  )
              ]),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _viewer() {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewerSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              CropGridViewer.preview(controller: _controller),
              
              if (_selectedFilter != 'Nta imwe')
                Container(color: _getFilterOverlayColor()),

              for (int i = 0; i < _addedTexts.length; i++)
                if (!_isEditingText || _selectedTextIndex == i)
                  _buildInteractiveText(index: i),
            ],
          );
        },
      ),
    );
  }

  Color _getFilterOverlayColor() {
    switch (_selectedFilter) {
      case 'N&B': return Colors.grey.withOpacity(0.4);
      case 'Sepia': return Colors.brown.withOpacity(0.3);
      case 'B&W': return Colors.white.withOpacity(0.2);
      default: return Colors.transparent;
    }
  }

  Widget _buildFilterSelection() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.keys.length,
        itemBuilder: (context, index) {
          final filterName = _filters.keys.elementAt(index);
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = filterName),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _selectedFilter == filterName ? Colors.orange : Colors.black54,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white54),
              ),
              child: Text(filterName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInteractiveText({required int index}) {
    final textOverlay = _addedTexts[index];
    return Positioned(
      left: textOverlay.position.dx,
      top: textOverlay.position.dy,
      child: GestureDetector(
        onDoubleTap: () => _startTextEditing(existingTextIndex: index),
        onScaleStart: (details) => setState(() => _selectedTextIndex = index),
        onScaleUpdate: (details) {
          if (_isEditingText) return;
          setState(() {
            _addedTexts[index].scale = details.scale;
            _addedTexts[index].rotation = details.rotation;
            _addedTexts[index].position += details.focalPointDelta;
          });
        },
        child: Transform.rotate(
          angle: textOverlay.rotation,
          child: Transform.scale(
            scale: textOverlay.scale,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: textOverlay.backgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: _selectedTextIndex == index ? Border.all(color: Colors.orange, width: 2) : null,
              ),
              child: Text(
                textOverlay.text,
                style: TextStyle(
                  fontFamily: 'EmojiFont',
                  color: textOverlay.color,
                  fontSize: textOverlay.fontSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trimmer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_formatter(_controller.startTrim), style: const TextStyle(color: Colors.white)),
            const Text(" - ", style: TextStyle(color: Colors.white)),
            Text(_formatter(_controller.endTrim), style: const TextStyle(color: Colors.white)),
          ]),
        ),
        TrimSlider(controller: _controller, height: 40, horizontalMargin: 0)
      ]),
    );
  }

  Widget _editingTools() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildToolButton(icon: Icons.rotate_90_degrees_ccw, label: 'HINDURUKIZA', onPressed: () => _controller.rotate90Degrees(RotateDirection.left)),
          _buildToolButton(icon: Icons.text_fields, label: 'INYANDIKO', onPressed: () => _startTextEditing()),
        ],
      ),
    );
  }
  
  void _startTextEditing({int? existingTextIndex}) {
    setState(() {
      _isEditingText = true;
      if (existingTextIndex != null) {
        _selectedTextIndex = existingTextIndex;
        _textEditingController.text = _addedTexts[existingTextIndex].text;
      } else {
        final newText = TextOverlay(
          text: "",
          color: Colors.white,
          backgroundColor: Colors.black.withOpacity(0.5),
          fontSize: 32,
          position: Offset(_viewerSize.width / 4, _viewerSize.height / 3),
        );
        _addedTexts.add(newText);
        _selectedTextIndex = _addedTexts.length - 1;
        _textEditingController.clear();
      }
    });
  }

  void _stopTextEditing() {
    setState(() {
      if (_selectedTextIndex != -1 && _textEditingController.text.trim().isEmpty) {
        _addedTexts.removeAt(_selectedTextIndex);
      }
      _isEditingText = false;
      _selectedTextIndex = -1;
      _textEditingController.clear();
      // Kuraho focus kuri textfield
      FocusScope.of(context).unfocus();
    });
  }
  
  Widget _buildTextEditingUI() {
    if (_selectedTextIndex == -1 || _selectedTextIndex >= _addedTexts.length) return const SizedBox.shrink();
    final currentText = _addedTexts[_selectedTextIndex];

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.7),
      body: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 48),
                const Text("Andika", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                TextButton(
                  onPressed: _stopTextEditing,
                  child: const Text("BIKORA", style: TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: _textEditingController,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    maxLines: null,
                    style: TextStyle(
                      fontFamily: 'EmojiFont',
                      color: currentText.color,
                      fontSize: currentText.fontSize,
                      backgroundColor: currentText.backgroundColor,
                    ),
                    onChanged: (text) => setState(() => currentText.text = text),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Andika hano...",
                      hintStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ),
            ),
            const Text("Ingene Inyandiko Ingana", style: TextStyle(color: Colors.white70)),
            Slider(
              value: currentText.fontSize, min: 14.0, max: 72.0,
              activeColor: Colors.white,
              onChanged: (value) => setState(() => currentText.fontSize = value),
            ),
            const Text("Ibara ry'Inyandiko", style: TextStyle(color: Colors.white70)),
            _buildColorPaletteForText(isForText: true),
            const Text("Ibara ry'inyuma", style: TextStyle(color: Colors.white70)),
            _buildColorPaletteForText(isForText: false),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPaletteForText({required bool isForText}) {
    final currentText = _addedTexts[_selectedTextIndex];
    
    return Container(
      padding: const EdgeInsets.all(8.0), height: 60,
      child: Center(
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: isForText ? _colors.length : _colors.length + 1,
          itemBuilder: (context, index) {
            if (!isForText && index == 0) {
              return GestureDetector(
                onTap: () => setState(() => currentText.backgroundColor = null),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6), width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                  child: const Icon(Icons.format_color_reset, color: Colors.white),
                ),
              );
            }
            final color = isForText ? _colors[index] : _colors[index - 1];
            final Color selectedColor = (isForText ? currentText.color : currentText.backgroundColor) ?? Colors.transparent;
            
            bool isSelected = false;
            if(isForText) {
                isSelected = selectedColor.value == color.value;
            } else {
                isSelected = selectedColor.value == color.withOpacity(0.7).value;
            }

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isForText) {
                    currentText.color = color;
                  } else {
                    currentText.backgroundColor = color.withOpacity(0.7);
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6), width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.orange : Colors.white, 
                    width: isSelected ? 3 : 1
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildToolButton({required IconData icon, required String label, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: Colors.white),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
        ]),
      ),
    );
  }
}