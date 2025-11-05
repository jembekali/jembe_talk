// Code ya: JEMBE TALK APP
// Dosiye NSHASHA: lib/feedback_details_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FeedbackDetailsScreen extends StatefulWidget {
  final String feedbackId;
  const FeedbackDetailsScreen({super.key, required this.feedbackId});

  @override
  State<FeedbackDetailsScreen> createState() => _FeedbackDetailsScreenState();
}

class _FeedbackDetailsScreenState extends State<FeedbackDetailsScreen> {

  @override
  void initState() {
    super.initState();
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    try {
      final docRef = FirebaseFirestore.instance.collection('feedback').doc(widget.feedbackId);
      final doc = await docRef.get();
      if (doc.exists && (doc.data()?['hasUnreadReply'] ?? false)) {
        await docRef.update({'hasUnreadReply': false});
      }
    } catch (e) {
      // Nta kibazo n'iyo vyanka
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ikiganiro n'Ubuyobozi"),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('feedback').doc(widget.feedbackId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final originalMessage = data['message'] ?? '...';
          final timestamp = data['createdAt'] as Timestamp?;
          final date = timestamp != null ? DateFormat('d MMM y, HH:mm').format(timestamp.toDate()) : '';

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Ikibazo c'umukoresha
              _buildMessageBubble(
                message: originalMessage,
                date: date,
                isFromAdmin: false,
              ),
              const SizedBox(height: 16),
              
              // Inyishu z'umuyobozi
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('feedback')
                    .doc(widget.feedbackId)
                    .collection('admin_replies')
                    .orderBy('repliedAt', descending: false)
                    .snapshots(),
                builder: (context, replySnapshot) {
                  if (!replySnapshot.hasData) return const SizedBox.shrink();
                  if (replySnapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text("Ubuyobozi ntiburakwishura. Rindira gato."),
                      ),
                    );
                  }
                  
                  return Column(
                    children: replySnapshot.data!.docs.map((doc) {
                      final replyData = doc.data() as Map<String, dynamic>;
                      final replyMessage = replyData['message'] ?? '...';
                      final replyTimestamp = replyData['repliedAt'] as Timestamp?;
                      final replyDate = replyTimestamp != null ? DateFormat('d MMM y, HH:mm').format(replyTimestamp.toDate()) : '';

                      return _buildMessageBubble(
                        message: replyMessage,
                        date: replyDate,
                        isFromAdmin: true,
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // Akadirisha keza ko kwerekana ubutumwa
  Widget _buildMessageBubble({required String message, required String date, required bool isFromAdmin}) {
    final theme = Theme.of(context);
    return Align(
      alignment: isFromAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isFromAdmin ? theme.colorScheme.primaryContainer : theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 6),
            Text(date, style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}