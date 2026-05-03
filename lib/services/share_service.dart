// lib/services/share_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  // Singleton instance
  static final ShareService instance = ShareService._();
  ShareService._();

  // Iyi link ihuye neza na Firebase Project ID yawe 'jembe-talk-1'
  static const String _baseUrl = "https://jembe-talk-1.web.app/post";

  Future<void> sharePost({
    required String postId,
    required String content,
    String? mediaUrl,
    String? type,
    String? localThumbnailPath,
  }) async {
    try {
      // 🚀 HANO NAHAHINDURYE: Bishyira "TANGAZA STAR ⭐" imbere
      // Niba content irimo ubusa, hagenda gusa iryo jambo n'inyenyeri
      final String header = content.isEmpty ? "TANGAZA STAR ⭐" : "TANGAZA STAR ⭐\n$content";
      
      final String shareText = "$header\n\nView post here: $_baseUrl?id=$postId";

      if (localThumbnailPath != null && File(localThumbnailPath).existsSync()) {
        // Gusangiza ubutumwa hamwe n'ifoto (Thumbnail)
        await Share.shareXFiles(
          [XFile(localThumbnailPath)], 
          text: shareText
        );
      } else {
        // Gusangiza ubutumwa bw'inyandiko na Link gusa
        await Share.share(shareText);
      }
    } catch (e) {
      debugPrint("Share Error: $e");
    }
  }
}