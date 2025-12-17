// Fayili: lib/tangaza_star/simple_video_editor_screen.dart
// IYI NI VERSION NSHASHA YAHUJWÉ NA LANGUAGE_PROVIDER

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:jembe_talk/language_provider.dart'; // << IMPINDUKA: Twongeyemwo import
import 'package:provider/provider.dart'; // << IMPINDUKA: Twongeyemwo import
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

class SimpleVideoEditorScreen extends StatefulWidget {
  final File videoFile;
  final Duration? initialStartTrim;
  final Duration? initialEndTrim;
  final List<TextOverlay>? initialTextOverlays;

  const SimpleVideoEditorScreen({
    super.key,
    required this.videoFile,
    this.initialStartTrim,
    this.initialEndTrim,
    this.initialTextOverlays,
  });

  @override
  State<SimpleVideoEditorScreen> createState() => _SimpleVideoEditorScreenState();
}

class _SimpleVideoEditorScreenState extends State<SimpleVideoEditorScreen> {
  late final VideoEditorController _controller;
  final List<TextOverlay> _addedTexts = [];
  int _selectedTextIndex = -1;
  Size _viewerSize = Size.zero;
  bool _isEditingText = false;
  late final TextEditingController _textEditingController;
  final List<Color> _colors = [
    Colors.white, Colors.black, Colors.red, Colors.orange,
    Colors.yellow, Colors.green, Colors.blue, Colors.indigo, Colors.purple,
  ];

  double _initialTextScale = 1.0;
  double _initialTextRotation = 0.0;
  
  bool _isDraggingText = false;
  bool _isTextOverTrash = false;
  final GlobalKey _trashKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = VideoEditorController.file(
      widget.videoFile,
      maxDuration: const Duration(minutes: 3),
    );

    _controller.initialize().then((_) {
      if (widget.initialStartTrim != null && widget.initialEndTrim != null) {
        _controller.updateTrim(
          widget.initialStartTrim!.inSeconds.toDouble(),
          widget.initialEndTrim!.inSeconds.toDouble()
        );
      }
      if (widget.initialTextOverlays != null) {
        _addedTexts.addAll(widget.initialTextOverlays!);
      }

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

  void _confirmAndReturn() {
    Navigator.pop(context, {
      'startTrim': _controller.startTrim,
      'endTrim': _controller.endTrim,
      'textOverlays': _addedTexts,
      'viewerSize': _viewerSize,
      'rotation': _controller.rotation,
    });
  }

  String _formatter(Duration duration) => [
    duration.inMinutes.remainder(60).toString().padLeft(2, '0'),
    duration.inSeconds.remainder(60).toString().padLeft(2, '0')
  ].join(":");

  @override
  Widget build(BuildContext context) {
    // << IMPINDUKA: Twongeyemwo Language Provider kugira dukure amajambo yose hano >>
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.t('video_editor_title')), // << IMPINDUKA
        backgroundColor: Colors.black,
        actions: [
          if (_selectedTextIndex != -1 && !_isEditingText)
            IconButton(
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              onPressed: () => setState(() => _selectedTextIndex = -1),
            )
          else
            IconButton(
              onPressed: _isEditingText ? null : _confirmAndReturn,
              icon: const Icon(Icons.check, color: Colors.blueAccent),
            ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _controller.initialized
          ? SafeArea(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(children: [
                    _viewer(),
                    if (!_isEditingText) ...[
                      _trimmer(),
                      _editingTools(),
                    ]
                  ]),
                  
                  if (_isDraggingText)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedOpacity(
                        opacity: _isDraggingText ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: _buildTrashArea(),
                      ),
                    ),
                  
                  if (_isEditingText) _buildTextEditingUI(),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _viewer() {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTextIndex = -1),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewerSize = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                CropGridViewer.preview(controller: _controller),
                for (int i = 0; i < _addedTexts.length; i++)
                  if (!_isEditingText || _selectedTextIndex != i)
                    _buildInteractiveText(index: i),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInteractiveText({required int index}) {
    final textOverlay = _addedTexts[index];
    
    if (textOverlay.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: textOverlay.position.dx,
      top: textOverlay.position.dy,
      child: GestureDetector(
        onTap: () => setState(() => _selectedTextIndex = index),
        onDoubleTap: () => _startTextEditing(existingTextIndex: index),
        
        onScaleStart: (details) {
          setState(() {
            _selectedTextIndex = index;
            _initialTextScale = _addedTexts[index].scale;
            _initialTextRotation = _addedTexts[index].rotation;
            _isDraggingText = true;
            _isTextOverTrash = false;
          });
        },
        onScaleUpdate: (details) {
          if (_isEditingText) return;

          final fingerPosition = details.focalPoint;
          final trashRenderBox = _trashKey.currentContext?.findRenderObject() as RenderBox?;
          if (trashRenderBox != null) {
            final trashPosition = trashRenderBox.localToGlobal(Offset.zero);
            final trashArea = Rect.fromLTWH(trashPosition.dx, trashPosition.dy, trashRenderBox.size.width, trashRenderBox.size.height);
            _isTextOverTrash = trashArea.contains(fingerPosition);
          }

          setState(() {
            _addedTexts[index].scale = _initialTextScale * details.scale;
            _addedTexts[index].rotation = _initialTextRotation + details.rotation;
            _addedTexts[index].position += details.focalPointDelta;
          });
        },
        onScaleEnd: (details) {
          if (_isTextOverTrash) {
            _addedTexts.removeAt(index);
            _selectedTextIndex = -1;
          }
          setState(() {
            _isDraggingText = false;
            _isTextOverTrash = false;
          });
        },
        child: Transform.rotate(
          angle: textOverlay.rotation,
          child: Transform.scale(
            scale: _isTextOverTrash && _selectedTextIndex == index ? 0.5 : textOverlay.scale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: textOverlay.backgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: _selectedTextIndex == index ? Border.all(color: Colors.orange, width: 2) : null,
              ),
              child: Text(
                textOverlay.text,
                style: TextStyle(
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
            const Text(" - ", style: const TextStyle(color: Colors.white)),
            Text(_formatter(_controller.endTrim), style: const TextStyle(color: Colors.white)),
          ]),
        ),
        TrimSlider(controller: _controller, height: 40, horizontalMargin: 0)
      ]),
    );
  }

  Widget _editingTools() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildToolButton(icon: Icons.rotate_90_degrees_ccw, label: lang.t('rotate_tool_label'), onPressed: () => _controller.rotate90Degrees(RotateDirection.left)), // << IMPINDUKA
          _buildToolButton(icon: Icons.text_fields, label: lang.t('text_tool_label'), onPressed: () => _startTextEditing()), // << IMPINDUKA
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
          backgroundColor: null,
          fontSize: 32,
          position: Offset(_viewerSize.width / 4, _viewerSize.height / 3),
        );
        _addedTexts.add(newText);
        _selectedTextIndex = _addedTexts.length - 1;
        _textEditingController.clear();
      }
    });
  }
  
  void _exitTextEditing() {
    setState(() {
      if (_selectedTextIndex != -1 && _textEditingController.text.trim().isEmpty) {
        _addedTexts.removeAt(_selectedTextIndex);
      }
      _isEditingText = false;
      _selectedTextIndex = -1;
      _textEditingController.clear();
      FocusScope.of(context).unfocus();
    });
  }

  Widget _buildTextEditingUI() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);

    if (_selectedTextIndex == -1 || _selectedTextIndex >= _addedTexts.length) return const SizedBox.shrink();
    final currentText = _addedTexts[_selectedTextIndex];

    return Scaffold(
      backgroundColor: Colors.black.withAlpha(178),
      body: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.blueAccent, size: 30),
                  onPressed: _exitTextEditing,
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
                      color: currentText.color,
                      fontSize: currentText.fontSize,
                      backgroundColor: currentText.backgroundColor,
                      shadows: const [
                        Shadow(offset: Offset(1.0, 1.0), blurRadius: 3.0, color: Colors.black)
                      ]
                    ),
                    onChanged: (text) => setState(() => currentText.text = text),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: lang.t('text_editor_hint'), // << IMPINDUKA
                      hintStyle: const TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  Text(lang.t('font_size_label'), style: const TextStyle(color: Colors.white70)), // << IMPINDUKA
                  Slider(
                    value: currentText.fontSize, min: 14.0, max: 72.0,
                    activeColor: Colors.white,
                    onChanged: (value) => setState(() => currentText.fontSize = value),
                  ),
                  Text(lang.t('text_color_label'), style: const TextStyle(color: Colors.white70)), // << IMPINDUKA
                  _buildColorPaletteForText(isForText: true),
                  Text(lang.t('background_color_label'), style: const TextStyle(color: Colors.white70)), // << IMPINDUKA
                  _buildColorPaletteForText(isForText: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPaletteForText({required bool isForText}) {
    if (_selectedTextIndex == -1 || _selectedTextIndex >= _addedTexts.length) return const SizedBox.shrink();
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: currentText.backgroundColor == null ? 3 : 1),
                    color: currentText.backgroundColor == null ? Colors.orange.withOpacity(0.5) : Colors.transparent
                  ),
                  child: const Icon(Icons.format_color_reset, color: Colors.white),
                ),
              );
            }
            final color = isForText ? _colors[index] : _colors[index - 1];
            final Color selectedColor = (isForText ? currentText.color : currentText.backgroundColor) ?? Colors.transparent;
            
            bool isSelected = false;
            final backgroundColorWithAlpha = color.withAlpha(178);
            if(isForText) {
                isSelected = selectedColor == color;
            } else {
                isSelected = selectedColor == backgroundColorWithAlpha;
            }

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isForText) {
                    currentText.color = color;
                  } else {
                    currentText.backgroundColor = backgroundColorWithAlpha;
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
  
  Widget _buildTrashArea() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: AnimatedContainer(
        key: _trashKey,
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isTextOverTrash ? Colors.red.withOpacity(0.8) : Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: _isTextOverTrash ? 40 : 28,
        ),
      ),
    );
  }
}