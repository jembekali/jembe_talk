// Code ya: JEMBE TALK APP
// Dosiye: lib/unified_notifications_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jembe_talk/feedback_details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UnifiedNotificationsScreen extends StatefulWidget {
  const UnifiedNotificationsScreen({super.key});
  @override State<UnifiedNotificationsScreen> createState() => _UnifiedNotificationsScreenState();
}

class _UnifiedNotificationsScreenState extends State<UnifiedNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    _markAnnouncementsAsRead();
  }

  Future<void> _markAnnouncementsAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastReadAnnouncementTimestamp', DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Scaffold(body: Center(child: Text("Banza winjire.")));

    return Scaffold(
      // <<--- IMPINDUKA: TWAKUYE GRADIENT, DUSHIRAMWO IBARA RYA THEME --->>
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("    AMATANGAZO"),
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: ListView(
        children: [
          _buildFeedbackRepliesSection(context, currentUser.uid),
          _buildAnnouncementsSection(context),
        ],
      ),
    );
  }

  Widget _buildFeedbackRepliesSection(BuildContext context, String currentUserId) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('feedback').where('uid', isEqualTo: currentUserId).where('hasAdminReply', isEqualTo: true).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
              child: Text("Inyishu z'Ubufasha", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
            ),
            ...snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final message = data['message'] ?? '...';
              final bool hasUnread = data['hasUnreadReply'] ?? false;
              return Card(
                color: theme.colorScheme.surface,
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: ListTile(
                  leading: Icon(Icons.reply_all, color: hasUnread ? theme.colorScheme.secondary : theme.textTheme.bodyMedium?.color),
                  title: Text("Inyishu ku kibazo cawe", style: TextStyle(fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal, color: theme.textTheme.bodyLarge?.color)),
                  subtitle: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                  onTap: () {
                    if (hasUnread) {
                      FirebaseFirestore.instance.collection('feedback').doc(doc.id).update({'hasUnreadReply': false});
                    }
                    Navigator.push(context, MaterialPageRoute(builder: (context) => FeedbackDetailsScreen(feedbackId: doc.id)));
                  },
                ),
              );
            }).toList(),
            Divider(color: theme.dividerColor, indent: 16, endIndent: 16, height: 32),
          ],
        );
      },
    );
  }

  Widget _buildAnnouncementsSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
          child: Text("      Amatangazo Rusangi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('announcements').orderBy('createdAt', descending: true).limit(20).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: theme.colorScheme.secondary));
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Nta tangazo riraboneka.")));
            return Column(
              children: snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final title = data['title'] ?? 'Umutwe ntuboneka';
                final message = data['message'] ?? 'Ubutumwa ntibuboneka';
                final timestamp = data['createdAt'] as Timestamp?;
                final date = timestamp != null ? DateFormat('d MMM y, HH:mm').format(timestamp.toDate()) : '';
                return Card(
                  color: theme.colorScheme.surface,
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: ListTile(
                    leading: Icon(Icons.campaign_outlined, color: theme.colorScheme.secondary),
                    title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
                    subtitle: Text('$message\n- $date', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                    isThreeLine: true,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}