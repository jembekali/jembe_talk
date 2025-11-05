// Code ya: JEMBE TALK APP
// Dosiye: lib/my_feedback_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jembe_talk/feedback_details_screen.dart'; 

class MyFeedbackScreen extends StatelessWidget {
  const MyFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Banza winjire.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ubutumwa Bwanje"),
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
            return const Center(child: Text("Nta butumwa urarungika."));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final message = data['message'] ?? '...';
              final timestamp = data['createdAt'] as Timestamp?;
              final date = timestamp != null
                  ? DateFormat('d MMM y').format(timestamp.toDate())
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