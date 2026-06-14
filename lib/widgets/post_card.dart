import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/post_translations.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/share_service.dart';
import 'package:jembe_talk/widgets/post_media_display.dart';

class PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final String? currentUserId;
  final double? uploadProgress;
  final bool isSharing;
  final Function(Map<String, dynamic>) onLike;
  final Function(Map<String, dynamic>) onOpenComments;
  final Function(Map<String, dynamic>) onShowOptions;
  final Function(BuildContext, String, String, String) onShowFullNews;
  final VoidCallback onShareStart;
  final Function(bool) onShareEnd;
  final ValueNotifier<bool> isScreenActive;
  final Function(Map<String, dynamic>)? onRetry; // 🔥 Twongeyeho iyi callback

  const PostCard({
    super.key,
    required this.post,
    this.currentUserId,
    this.uploadProgress,
    required this.isSharing,
    required this.onLike,
    required this.onOpenComments,
    required this.onShowOptions,
    required this.onShowFullNews,
    required this.onShareStart,
    required this.onShareEnd,
    required this.isScreenActive,
    this.onRetry, // 🔥
  });

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final String l = lang.currentLanguage;
    final String postId = post[DatabaseHelper.colPostId] ?? "temp";
    final int likeCount = post[DatabaseHelper.colLikes] ?? 0;
    final int commentCount = post[DatabaseHelper.colCommentsCount] ?? 0;
    final bool isLiked = (post[DatabaseHelper.colIsLikedByMe] == 1);
    final String title = post[DatabaseHelper.colTitle] ?? "";
    final String body = post[DatabaseHelper.colText] ?? "";
    final int ts = post[DatabaseHelper.colTimestamp] ??
        DateTime.now().millisecondsSinceEpoch;

    // 🔥 Reba niba upload yarageze kure cyangwa niba yarapfuye
    final bool isFailed = post[DatabaseHelper.colSyncStatus] == 'failed';
    final bool isUploading = post[DatabaseHelper.colSyncStatus] == 'uploading';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header (User Info)
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white10,
                backgroundImage: post[DatabaseHelper.colUserImageUrl] != null
                    ? NetworkImage(post[DatabaseHelper.colUserImageUrl])
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post[DatabaseHelper.colUserName] ?? "User",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    Text(
                        DateFormat('MMM d, HH:mm')
                            .format(DateTime.fromMillisecondsSinceEpoch(ts)),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11))
                  ],
                ),
              ),
              if (post[DatabaseHelper.colUserId] == currentUserId)
                IconButton(
                  icon: const Icon(Icons.more_horiz, color: Colors.white70),
                  onPressed: () => onShowOptions(post),
                )
            ],
          ),

          // 2. Uploading Progress Bar
          if (isUploading && uploadProgress != null && uploadProgress! < 1.0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                        value: uploadProgress,
                        minHeight: 4,
                        color: Colors.lightBlueAccent,
                        backgroundColor: Colors.white10),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(PostTranslations.t('uploading', l),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 10)),
                      Text("${(uploadProgress! * 100).toInt()}%",
                          style: const TextStyle(
                              color: Colors.lightBlueAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
            ),

          // 3. Title & Read More
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 0.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: () => onShowFullNews(context, title, body, l),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(PostTranslations.t('read_more', l),
                      style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),

          // 4. Media Section with RETRY Overlay
          if (post[DatabaseHelper.colImageUrl] != null ||
              post[DatabaseHelper.colVideoUrl] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ahashyirwa Media (Video cyangwa Ifoto)
                    PostMediaDisplay(
                      imageUrl: post[DatabaseHelper.colImageUrl],
                      videoUrl: post[DatabaseHelper.colVideoUrl],
                      postId: postId,
                      isScreenActive: isScreenActive,
                      thumbnailLocalPath:
                          post[DatabaseHelper.colPostThumbnailLocalPath],
                      thumbnailUrl: post['thumbnailUrl'],
                    ),

                    // 🔥 RETRY OVERLAY (Iyo upload yanze)
                    if (isFailed)
                      GestureDetector(
                        onTap: () => onRetry?.call(post),
                        child: Container(
                          width: double.infinity,
                          height: 200, // Matching media height
                          color: Colors.black54,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_off_rounded,
                                  color: Colors.redAccent, size: 40),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 15, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        color: Colors.black, size: 18),
                                    SizedBox(width: 8),
                                    Text("RETRY UPLOAD",
                                        style: TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text("Internet Connection Failed",
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          const Divider(color: Colors.white10, height: 25),

          // 5. Action Buttons (Like, Comment, Share)
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  label: "$likeCount",
                  color: isLiked ? Colors.redAccent : Colors.white70,
                  onPressed: () => onLike(post),
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: "$commentCount",
                  color: Colors.white70,
                  onPressed: () => onOpenComments(post),
                ),
              ),
              Expanded(
                child: isSharing
                    ? const Center(
                        child: CupertinoActivityIndicator(
                            color: Colors.white, radius: 10))
                    : IconButton(
                        icon: const Icon(Icons.share_rounded,
                            color: Colors.white70, size: 22),
                        onPressed: () async {
                          onShareStart();
                          HapticFeedback.mediumImpact();
                          try {
                            await ShareService.instance.sharePost(
                              postId: postId,
                              content: post[DatabaseHelper.colText] ??
                                  "TANGAZA STAR",
                              mediaUrl: post[DatabaseHelper.colImageUrl] ??
                                  post[DatabaseHelper.colVideoUrl],
                              type: post[DatabaseHelper.colVideoUrl] != null
                                  ? 'video'
                                  : 'image',
                              localThumbnailPath: post[
                                  DatabaseHelper.colPostThumbnailLocalPath],
                            );
                            onShareEnd(true);
                          } catch (e) {
                            onShareEnd(false);
                          }
                        },
                      ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color color = Colors.white,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13),
            )
          ],
        ),
      ),
    );
  }
}
