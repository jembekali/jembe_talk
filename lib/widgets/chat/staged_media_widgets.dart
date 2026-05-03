// lib/widgets/chat/staged_media_widgets.dart (VERSION 3.10 - INFINITE CAPTION GROWTH)

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:video_editor/video_editor.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';

// --- SERVICES & PROVIDERS ---
import '../../language_provider.dart';

// ===========================================================================
// 1. PHOTO PREVIEW COMPOSER (Infinite Lines & Auto-Scroll)
// ===========================================================================
class PhotoPreviewComposer extends StatelessWidget {
  final Uint8List imageData;
  final TextEditingController captionController;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  final Function(Uint8List) onImageEdited;

  const PhotoPreviewComposer({
    super.key,
    required this.imageData,
    required this.captionController,
    required this.onCancel,
    required this.onSend,
    required this.onImageEdited,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      // Resizing UI bitewe na Keyboard
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        reverse: true, // ✅ Ituma ihita izamuka iyo wanditse umurongo mushya hasi
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image Preview
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.25),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(imageData, fit: BoxFit.contain),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                        onPressed: () async {
                          final edited = await Navigator.push<Uint8List?>(
                            context,
                            MaterialPageRoute(builder: (context) => ImageEditor(image: imageData)),
                          );
                          if (edited != null) onImageEdited(edited);
                        },
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: theme.scaffoldBackgroundColor, 
                            borderRadius: BorderRadius.circular(20)
                          ),
                          child: TextField(
                            controller: captionController,
                            // ✅ INFINITE GROWTH: Nta mupaka w'imirongo
                            maxLines: null, 
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences, 
                            style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: lang.t('chat_add_caption_hint'), 
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: onCancel),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: onSend,
                    icon: const Icon(Icons.send, color: Colors.white),
                    label: Text(lang.t('chat_send_button'), style: const TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 2. STAGED VIDEO PREVIEW (Infinite Lines & Auto-Scroll)
// ===========================================================================
class StagedVideoPreview extends StatelessWidget {
  final VideoPlayerController controller;
  final TextEditingController captionController;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const StagedVideoPreview({
    super.key,
    required this.controller,
    required this.captionController,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        reverse: true, // ✅ Ziboneka uko wandika
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 180, // Reduced to give more space for 100 lines
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: controller.value.isInitialized
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller)),
                          GestureDetector(
                            onTap: () => controller.value.isPlaying ? controller.pause() : controller.play(),
                            child: AnimatedBuilder(
                              animation: controller,
                              builder: (context, _) => Opacity(
                                opacity: controller.value.isPlaying ? 0 : 1,
                                child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 60)),
                              ),
                            ),
                          ),
                          Positioned(top: 10, left: 10, child: CircleAvatar(backgroundColor: Colors.black45, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 20), onPressed: onCancel))),
                        ],
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor, 
                        borderRadius: BorderRadius.circular(20), 
                        border: Border.all(color: Colors.black12)
                      ),
                      child: TextField(
                        controller: captionController,
                        // ✅ INFINITE GROWTH
                        maxLines: null,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences, 
                        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                        decoration: InputDecoration(
                          hintText: lang.t('chat_add_caption_hint'), 
                          border: InputBorder.none, 
                          contentPadding: const EdgeInsets.symmetric(vertical: 12)
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: onSend, 
                    backgroundColor: theme.colorScheme.primary, 
                    mini: true, 
                    child: const Icon(Icons.send, color: Colors.white, size: 20)
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NOTE: VideoEditorComposer has been kept simple as it's for trimming.
// ---------------------------------------------------------------------------
class VideoEditorComposer extends StatelessWidget {
  final VideoEditorController controller;
  final bool isProcessing;
  final double processingProgress;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const VideoEditorComposer({super.key, required this.controller, required this.isProcessing, required this.processingProgress, required this.onCancel, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.cardColor, borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 200, child: controller.initialized ? CropGridViewer.preview(controller: controller) : const Center(child: CircularProgressIndicator())),
          const SizedBox(height: 10),
          if (controller.initialized) TrimSlider(controller: controller, height: 45, child: TrimTimeline(controller: controller, padding: const EdgeInsets.all(2.0))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton.icon(onPressed: onCancel, icon: const Icon(Icons.close), label: Text(lang.t('chat_video_trim_cancel')), style: TextButton.styleFrom(foregroundColor: Colors.red)),
            isProcessing ? CircularProgressIndicator(value: processingProgress) : ElevatedButton.icon(onPressed: onSave, icon: const Icon(Icons.check), label: Text(lang.t('chat_video_trim_continue'))),
          ])
      ]),
    );
  }
}