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
    final int ts = post[DatabaseHelper.colTimestamp] ?? DateTime.now().millisecondsSinceEpoch;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
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
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                        DateFormat('MMM d, HH:mm')
                            .format(DateTime.fromMillisecondsSinceEpoch(ts)),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12))
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
          if (uploadProgress != null && uploadProgress! < 1.0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  LinearProgressIndicator(
                      value: uploadProgress,
                      color: Colors.blueAccent,
                      backgroundColor: Colors.white12),
                  const SizedBox(height: 4),
                  Text(
                    "${(uploadProgress! * 100).toInt()}% ${PostTranslations.t('uploading', l)}",
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  )
                ],
              ),
            ),
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                title,
                style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: () => onShowFullNews(context, title, body, l),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(5)),
                  child: Text(
                    PostTranslations.t('read_more', l),
                    style: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          if (post[DatabaseHelper.colImageUrl] != null ||
              post[DatabaseHelper.colVideoUrl] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15.0),
                child: PostMediaDisplay(
                  imageUrl: post[DatabaseHelper.colImageUrl],
                  videoUrl: post[DatabaseHelper.colVideoUrl],
                  postId: postId,
                  isScreenActive: isScreenActive,
                  thumbnailLocalPath: post[DatabaseHelper.colPostThumbnailLocalPath],
                  thumbnailUrl: post['thumbnailUrl'],
                ),
              ),
            ),
          const Divider(color: Colors.white24, height: 20),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  label: "$likeCount",
                  color: isLiked ? Colors.redAccent : Colors.white,
                  onPressed: () => onLike(post),
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.comment_outlined,
                  label: "$commentCount",
                  color: Colors.white,
                  onPressed: () => onOpenComments(post),
                ),
              ),
              Expanded(
                child: isSharing
                    ? const CupertinoActivityIndicator(
                        color: Colors.white, radius: 10)
                    : IconButton(
                        icon: const Icon(Icons.share_outlined, color: Colors.white),
                        onPressed: () async {
                          onShareStart();
                          HapticFeedback.mediumImpact();
                          try {
                            await ShareService.instance.sharePost(
                              postId: postId,
                              content: post[DatabaseHelper.colText] ?? "TANGAZA",
                              mediaUrl: post[DatabaseHelper.colImageUrl] ??
                                  post[DatabaseHelper.colVideoUrl],
                              type: post[DatabaseHelper.colVideoUrl] != null
                                  ? 'video'
                                  : 'image',
                              localThumbnailPath:
                                  post[DatabaseHelper.colPostThumbnailLocalPath],
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 14),
          )
        ],
      ),
    );
  }
}