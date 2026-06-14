// lib/services/share_service.dart (VERSION 2.0 - UNIFIED LINKS)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  // Singleton instance
  static final ShareService instance = ShareService._();
  ShareService._();

  // Iyi link niyo App izajya igenderaho isuzuma niba ubutumwa ari Post ya Tangaza Star
  static const String _baseUrl = "https://jembe-talk-1.web.app/post";

  Future<void> sharePost({
    required String postId,
    required String content,
    String? mediaUrl,
    String? type,
    String? localThumbnailPath,
  }) async {
    try {
      // Shaka umutwe w'ubutumwa: "TANGAZA STAR ⭐"
      final String header = content.isEmpty ? "TANGAZA STAR ⭐" : "TANGAZA STAR ⭐\n$content";
      
      // Remeranya link ihoraho: .../post?id=POST_ID
      final String shareText = "$header\n\nView post here: $_baseUrl?id=$postId";

      if (localThumbnailPath != null && File(localThumbnailPath).existsSync()) {
        // Share hamwe n'ifoto (Thumbnail)
        await Share.shareXFiles(
          [XFile(localThumbnailPath)], 
          text: shareText
        );
      } else {
        // Share inyandiko na Link gusa
        await Share.share(shareText);
      }
    } catch (e) {
      debugPrint("Share Error: $e");
    }
  }
}