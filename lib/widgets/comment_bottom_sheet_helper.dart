// lib/widgets/comment_bottom_sheet_helper.dart (VERSION IKOSOYE)

import 'dart:ui'; // <<<--- TWAGARUYE IYI IMPORT
import 'package:flutter/material.dart';
import '../tangaza_star/comment_screen.dart'; // <<<--- TWAKOSOYE INZIRA IJA KURI COMMENT_SCREEN

Future<int?> showCommentBottomSheet(BuildContext context, Map<String, dynamic> postData, {AnimationController? controller}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.2),
    transitionAnimationController: controller,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          builder: (_, scrollController) {
            return Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: CommentScreen(
                postData: postData,
                scrollController: scrollController,
              ),
            );
          },
        ),
      );
    },
  );
}