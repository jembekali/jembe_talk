import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jembe_talk/tangaza_star/media_editor_view.dart';

class PostMediaPreview extends StatelessWidget {
  final String mediaType;
  final XFile? mediaFile;
  final String? thumbnailPath;
  final VideoPlayerController? videoController;
  final bool isRendered;
  final bool
      isRendering; // Iyi iba true niba ari Picking cyangwa Rendering (FFmpeg)
  final double renderingProgress;
  final int activeRotation;
  final Offset activeOffset;
  final double activeZoom;
  final List<MediaTextOverlay> activeTextOverlays;
  final double? activeAspectRatio;
  final ColorFilter previewFilter;
  final VoidCallback onClear;
  final VoidCallback onEdit;
  final String renderingText;

  const PostMediaPreview({
    super.key,
    required this.mediaType,
    required this.mediaFile,
    this.thumbnailPath,
    this.videoController,
    required this.isRendered,
    required this.isRendering,
    required this.renderingProgress,
    required this.activeRotation,
    required this.activeOffset,
    required this.activeZoom,
    required this.activeTextOverlays,
    this.activeAspectRatio,
    required this.previewFilter,
    required this.onClear,
    required this.onEdit,
    required this.renderingText,
  });

  @override
  Widget build(BuildContext context) {
    if (mediaFile == null) return const SizedBox.shrink();

    // Kubara uburebure bw'agace ka Preview bitewe n'uko keyboard ifunguye
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    double containerHeight = keyboardH > 0 ? 170 : 270;

    // 🔥 KOSORA HANO: Buto ya Edit igaragara niba ari video yaka CYANGWA niba ari ifoto
    bool canEdit = (mediaType == 'video' &&
            videoController != null &&
            videoController!.value.isInitialized) ||
        (mediaType == 'image');

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // 1. Agace k'amashusho (Media Area)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                height: containerHeight,
                color: Colors.black,
                alignment: Alignment.center,
                child: _buildMediaContent(context),
              ),
            ),

            // 2. Buto yo gukuraho (X)
            if (!isRendering)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: onClear,
                  child: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),

            // 3. BUTO YA EDIT: Izahita igaragara n'iyo yaba ari ifoto (Image)
            if (!isRendered && !isRendering && canEdit)
              Positioned(
                bottom: 12,
                right: 12,
                child: ElevatedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.auto_awesome,
                      size: 14, color: Colors.white),
                  label: const Text("Edit",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
          ],
        ),

        // 4. Progress bar niba FFmpeg irimo gu-rendera video (Submit)
        if (isRendering && renderingProgress > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: renderingProgress,
                minHeight: 6,
                color: Colors.amberAccent,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMediaContent(BuildContext context) {
    // --- STATUS A: VIDEO IRIMO GUSOMWA (PICKING) CYANGWA GU-RENDERA ---
    if (mediaType == 'video' &&
        (isRendering ||
            videoController == null ||
            !videoController!.value.isInitialized)) {
      return Stack(
        alignment: Alignment.center,
        children: [
          // Niba Thumbnail yamaze kuboneka, yerekane background yayo
          if (thumbnailPath != null)
            Image.file(
              File(thumbnailPath!),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              cacheWidth: 480, // 🔥 RAM Optimization
              filterQuality: FilterQuality.low,
            ),

          // Overlay y'umukara n'izina rya Loading
          Container(
            color: Colors.black45,
            width: double.infinity,
            height: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CupertinoActivityIndicator(
                    color: Colors.amberAccent, radius: 20),
                const SizedBox(height: 15),
                Text(
                  renderingText.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w900),
                ),
                if (renderingProgress > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "${(renderingProgress * 100).toInt()}%",
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // --- STATUS B: VIDEO PREVIEW (READY) ---
    if (mediaType == 'video' &&
        videoController != null &&
        videoController!.value.isInitialized) {
      return RepaintBoundary(
        // 🔥 RAM Optimization
        child: GestureDetector(
          onTap: () {
            videoController!.value.isPlaying
                ? videoController!.pause()
                : videoController!.play();
          },
          child: AspectRatio(
            aspectRatio:
                activeAspectRatio ?? videoController!.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: isRendered ? 0 : (activeRotation * 3.14159 / 180),
                  child: Transform.translate(
                    offset: isRendered ? Offset.zero : activeOffset,
                    child: Transform.scale(
                      scale: isRendered ? 1.0 : activeZoom,
                      child: ColorFiltered(
                        colorFilter: previewFilter,
                        child: VideoPlayer(videoController!),
                      ),
                    ),
                  ),
                ),
                if (!isRendered) _buildOverlays(),
                if (!videoController!.value.isPlaying &&
                    MediaQuery.of(context).viewInsets.bottom == 0)
                  const CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.black45,
                    child: Icon(Icons.play_arrow_rounded,
                        size: 40, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // --- STATUS C: IMAGE PREVIEW (IFOTO) ---
    return Stack(
      alignment: Alignment.center,
      children: [
        ColorFiltered(
          colorFilter: previewFilter,
          child: Image.file(
            File(mediaFile!.path),
            fit: BoxFit.contain,
            width: double.infinity,
            cacheWidth:
                800, // 🔥 RAM Optimization bituma amafoto nini adakrasha telefone
          ),
        ),
        if (!isRendered) _buildOverlays(),
      ],
    );
  }

  // Method yo gushyira amagambo hejuru ya media
  Widget _buildOverlays() {
    return LayoutBuilder(
      builder: (context, constraints) {
        double scaleFactor = constraints.maxWidth / 720;
        return Stack(
          children: activeTextOverlays.map((o) {
            return Positioned(
              left: o.position.dx * scaleFactor * 1.8,
              top: o.position.dy * scaleFactor * 4.5,
              child: Transform.scale(
                scale: o.scale * scaleFactor * 2.0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: o.backgroundColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    o.text,
                    style: TextStyle(
                      color: o.color,
                      fontSize: o.fontSize,
                      fontWeight: FontWeight.bold,
                      shadows: o.backgroundColor == null
                          ? [const Shadow(blurRadius: 8, color: Colors.black)]
                          : null,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
