// Code ya: JEMBE TALK APP
// Dosiye: lib/my_feedback_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jembe_talk/feedback_details_screen.dart';
// <--- TWONGEREYEMWO IZI DOSIYE --->
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';

class MyFeedbackScreen extends StatelessWidget {
  const MyFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // <--- Duhamagara LanguageProvider --->
    final lang = Provider.of<LanguageProvider>(context);
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(body: Center(child: Text(lang.t('my_feedback_login_prompt'))));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.t('my_feedback_title')),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('feedback')
            .where('uid', isEqualTo: currentUser.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text(lang.t('my_feedback_no_messages')));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final message = data['message'] ?? '...';
              final timestamp = data['createdAt'] as Timestamp?;
              final date = timestamp != null
                  ? DateFormat('d MMM y', lang.currentLanguage).format(timestamp.toDate())
                  : '';
              final bool isResolved = data['isResolved'] ?? false;
              final bool hasReply = data['hasAdminReply'] ?? false;

              return ListTile(
                leading: Icon(
                  isResolved ? Icons.check_circle : Icons.help_outline,
                  color: isResolved ? Colors.green : Colors.orange,
                ),
                title: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(date),
                trailing: hasReply
                    ? const Icon(Icons.mark_chat_read, color: Colors.blue)
                    : null,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FeedbackDetailsScreen(feedbackId: doc.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}