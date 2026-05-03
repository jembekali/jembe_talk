// lib/widgets/comment_bottom_sheet_helper.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import '../tangaza_star/comment_screen.dart';

Future<int?> showCommentBottomSheet(BuildContext context, Map<String, dynamic> postData, {AnimationController? controller}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true, // IKI NI CYO CY'INGENZI CYANE
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    transitionAnimationController: controller,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: DraggableScrollableSheet(
          initialChildSize: 0.75, // Uburebure bwa mbere (75% bya screen)
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return CommentScreen(
              postData: postData,
              scrollController: scrollController,
            );
          },
        ),
      );
    },
  );
}