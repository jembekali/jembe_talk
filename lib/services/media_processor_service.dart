import 'dart:io';
import 'dart:typed_data'; // Ibi bishobora kuvaho niba ntaho ucyikoresha 'Uint8List'
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class MediaProcessorService {
  static Future<String?> createCompressedThumbnail(
      File sourceFile, String type) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final String thumbPath = "${tempDir.path}/thumb_${const Uuid().v4()}.jpg";

      if (type == 'video') {
        return await VideoThumbnail.thumbnailFile(
          video: sourceFile.path,
          thumbnailPath: tempDir.path,
          imageFormat: ImageFormat.JPEG,
          quality: 35,
          maxWidth: 320,
        );
      } else {
        final result = await FlutterImageCompress.compressAndGetFile(
          sourceFile.absolute.path,
          thumbPath,
          quality: 35,
          minWidth: 320,
          minHeight: 320,
        );
        return result?.path;
      }
    } catch (e) {
      debugPrint("Error creating thumbnail: $e");
    }
    return null;
  }

  static Future<Uint8List> processImage({
    required Uint8List bytes,
    required double brightness,
    required double saturation,
    required String filter,
  }) async {
    try {
      var compressedBytes = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1080,
        minHeight: 1080,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      return compressedBytes;
    } catch (e) {
      debugPrint("Error processing image: $e");
      return bytes;
    }
  }

  static Future<void> renderVideo({
    required String inputPath,
    required String outputPath,
    required String overlayPath,
    required double brightness,
    required double saturation,
    required String filter,
    required int rotation,
    required double zoom,
    required double? aspectRatio,
    required bool isMuted,
    required int startSec,
    required int duration,
    required Function(double) onProgress,
    required Function(bool, String?) onComplete,
  }) async {
    await FFmpegKit.cancel();

    String colorFilters = "eq=brightness=$brightness:saturation=$saturation";
    if (filter == "grayscale") colorFilters += ":saturation=0";

    String rotationFilter = rotation != 0 ? "rotate=$rotation*(PI/180)," : "";
    String cropFilter = aspectRatio != null
        ? "crop=w='min(iw,ih*$aspectRatio)':h='min(ih,iw/$aspectRatio)',"
        : "";
    String zoomFilter = zoom > 1.0 ? "crop=(iw/$zoom):(ih/$zoom)," : "";

    // Twakuyeho amaparenetize atari ngombwa (interpolation warning fix)
    String filterComplex =
        "[0:v]$rotationFilter$cropFilter$zoomFilter$colorFilters,scale=480:-2[vid];[vid][1:v]overlay=0:0";

    String audioCommand = isMuted ? "-an" : "-c:a aac -ac 1 -b:a 64k";

    String command = "-ss $startSec -t $duration -y "
        "-i '$inputPath' -i '$overlayPath' "
        "-filter_complex \"$filterComplex\" $audioCommand "
        "-c:v libx264 -crf 30 -maxrate 900k -bufsize 1800k "
        "-preset superfast -threads 1 "
        "-pix_fmt yuv420p -movflags +faststart '$outputPath'";

    FFmpegKit.executeAsync(
        command,
        (session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            onProgress(1.0);
            onComplete(true, outputPath);
          } else {
            onComplete(false, null);
          }
        },
        (log) => debugPrint(log.getMessage()),
        (stats) {
          // 🔥 Hano niho hari igisubizo:
          double currentMs = stats.getTime().toDouble();
          double totalMs = duration * 1000.0;

          if (totalMs > 0 && currentMs > 0) {
            double p = (currentMs / totalMs).clamp(0.0, 0.99);
            onProgress(p);
          }
        });
  }

  static Future<File?> moveFileToPermanent(
      File sourceFile, String postId, String type) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final String postsPath = "${appDir.path}/cached_posts";
      final postsDir = Directory(postsPath);
      if (!await postsDir.exists()) await postsDir.create(recursive: true);

      final String extension = type == 'video' ? '.mp4' : '.jpg';
      final String newPath = "$postsPath/post_$postId$extension";

      return await sourceFile.copy(newPath);
    } catch (e) {
      debugPrint("Error saving permanent file: $e");
      return null;
    }
  }

  static void clearFFmpegCache() {
    FFmpegKit.cancel();
    FFmpegKitConfig.clearSessions();
  }
}
