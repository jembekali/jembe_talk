// lib/tabs/chats_tab.dart (VERSION 31.0 - REAL-TIME TYPING & RECORDING STATUS)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:liquid_pull_to_refresh/liquid_pull_to_refresh.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart'; 

import 'package:jembe_talk/models/home_models.dart';
import 'package:jembe_talk/chat_screen.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/services/sync_service.dart';

class ChatsTab extends StatefulWidget {
  final String searchQuery;
  final ValueNotifier<List<ChatData>> chatsNotifier;
  final Future<void> Function() onRefresh;
  final List<dynamic> myBlockedUsers;

  const ChatsTab({
    super.key, 
    required this.searchQuery, 
    required this.chatsNotifier, 
    required this.onRefresh, 
    required this.myBlockedUsers
  });

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; 

  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    super.build(context); 
    final theme = Theme.of(context);

    return ValueListenableBuilder<List<ChatData>>(
      valueListenable: widget.chatsNotifier,
      builder: (context, chats, child) {
        final filtered = widget.searchQuery.isEmpty 
            ? chats 
            : chats.where((e) => e.displayName.toLowerCase().contains(widget.searchQuery.toLowerCase())).toList();

        return Padding(
          padding: const EdgeInsets.only(top: 145), 
          child: LiquidPullToRefresh(
            onRefresh: widget.onRefresh,
            color: theme.scaffoldBackgroundColor, 
            backgroundColor: theme.colorScheme.secondary, 
            height: 60, 
            animSpeedFactor: 2.5,
            showChildOpacityTransition: false,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 15, 10, 120), 
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final chat = filtered[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withAlpha(190),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.colorScheme.onSurface.withAlpha(25)),
                    ),
                    child: ChatListItem(
                      chatData: chat, 
                      myBlockedUsers: widget.myBlockedUsers,
                      isNavigating: _isNavigating,
                      onNavigate: (val) { if (mounted) setState(() => _isNavigating = val); },
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class ChatListItem extends StatelessWidget {
  final ChatData chatData;
  final List<dynamic> myBlockedUsers;
  final bool isNavigating;
  final Function(bool) onNavigate;

  const ChatListItem({
    super.key, 
    required this.chatData, 
    required this.myBlockedUsers,
    required this.isNavigating,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    final List<String> ids = [currentUser.uid, chatData.userId]..sort();
    final String chatRoomID = ids.join('_');
    final isBlocked = myBlockedUsers.contains(chatData.userId) || chatData.blockedUsers.contains(currentUser.uid);
    final bool isAdmin = chatData.userId == 'jembe_talk_official_admin';

    ImageProvider? profilePic;
    if (!isBlocked) {
      if (isAdmin) {
        profilePic = const AssetImage('assets/images/jeme_talk_icon.png');
      } else if (chatData.localPhotoPath != null && File(chatData.localPhotoPath!).existsSync()) {
        profilePic = FileImage(File(chatData.localPhotoPath!));
      } else if (chatData.photoUrl != null && chatData.photoUrl!.isNotEmpty) {
        profilePic = CachedNetworkImageProvider(chatData.photoUrl!);
      }
    }

    return ListTile(
      onTap: () {
        if (isNavigating) return;
        onNavigate(true);
        HapticFeedback.lightImpact(); 
        syncService.markChatAsSeen(chatRoomID, chatData.userId);
        Navigator.push(context, MaterialPageRoute(builder: (c) => ChatScreenWrapper(receiverEmail: chatData.displayName, receiverID: chatData.userId))).then((_) => onNavigate(false));
      },
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28, 
            backgroundImage: profilePic, 
            backgroundColor: theme.colorScheme.secondary.withAlpha(30),
            child: (profilePic == null && !isAdmin) ? Icon(Icons.person, color: theme.colorScheme.secondary) : null
          ),
          if (!isAdmin)
            StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance.ref('status/${chatData.userId}').onValue,
              builder: (c, pSnap) {
                bool isOnline = false;
                if (pSnap.hasData && pSnap.data!.snapshot.value != null) {
                  try { final data = pSnap.data!.snapshot.value as Map?; isOnline = data?['state'] == 'online'; } catch (_) {}
                }
                return isOnline 
                  ? Positioned(bottom: 2, right: 2, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.surface, width: 2.5))))
                  : const SizedBox.shrink();
              },
            )
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              chatData.displayName, 
              style: TextStyle(
                fontWeight: isAdmin ? FontWeight.w900 : FontWeight.w600, 
                fontSize: 16,
                color: isAdmin ? theme.colorScheme.secondary : theme.textTheme.bodyLarge?.color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          ),
          if (isAdmin) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.stars_rounded, color: Colors.amber, size: 22)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: StreamBuilder<DatabaseEvent>(
          // ✅ KOSORA HANO: Reba niba mugenzi wawe arimo kwandika cyangwa gufata ijwi
          stream: FirebaseDatabase.instance.ref('activity/$chatRoomID/${chatData.userId}').onValue,
          builder: (context, activitySnapshot) {
            String act = "idle";
            if (activitySnapshot.hasData && activitySnapshot.data!.snapshot.value != null) {
              act = activitySnapshot.data!.snapshot.value.toString();
            }

            // 1. NIBA ARIMO KWANDIKA (TYPING)
            if (act == 'typing') {
              return Text(
                "${lang.t('chat_app_bar_typing')}...", 
                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)
              );
            } 
            
            // 2. NIBA ARIMO GUFATA IJWI (RECORDING)
            else if (act == 'recording') {
              return Row(
                children: [
                  const Icon(Icons.mic, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Text(
                    "${lang.t('chat_app_bar_recording')}...", 
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)
                  ),
                ],
              );
            }

            // 3. NIBA NTACYO ARIMO GUKORA (IDLE) - EREKANA UBUTUMWA BWA NYUMA BUSANZWE
            return Row(
              children: [
                Expanded(
                  child: LastMessagePreview(
                    messageContent: chatData.lastMessageContent,
                    messageType: chatData.lastMessageStatus == 'deleted' ? 'deleted' : chatData.lastMessageType,
                    messageStatus: chatData.lastMessageStatus,
                    senderId: chatData.lastMessageSenderId,
                    currentUserID: currentUser.uid,
                  ),
                ),
                if (chatData.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: theme.colorScheme.secondary, borderRadius: BorderRadius.circular(10)),
                    child: Text(chatData.unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                if (chatData.lastMessageTimestamp > 0) 
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(_formatTimestamp(chatData.lastMessageTimestamp), style: TextStyle(fontSize: 10, color: theme.textTheme.bodySmall?.color?.withAlpha(120))),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatTimestamp(int ts) {
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(ts);
    if (now.day == date.day && now.month == date.month && now.year == date.year) return DateFormat('HH:mm').format(date);
    return DateFormat('dd/MM').format(date);
  }
}

class LastMessagePreview extends StatelessWidget {
  final String? messageContent, messageType, messageStatus, senderId;
  final String currentUserID;

  const LastMessagePreview({
    super.key,
    this.messageContent,
    this.messageType,
    this.messageStatus,
    this.senderId,
    required this.currentUserID,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);

    if (messageType == null || messageType == 'deleted') {
      return Text(
        messageType == 'deleted' ? lang.t('chat_deleted_message_placeholder') : "",
        style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withAlpha(178), fontStyle: FontStyle.italic),
      );
    }

    final isMe = senderId == currentUserID;
    IconData? messageIcon;
    String messageText;

    switch (messageType) {
      case 'text': messageText = messageContent ?? ''; break;
      case 'image': messageIcon = Icons.photo_camera; messageText = lang.t('chat_reply_photo'); break; 
      case 'video': messageIcon = Icons.videocam; messageText = lang.t('chat_reply_video'); break;
      case 'voice_note': messageIcon = Icons.mic; messageText = lang.t('chat_reply_voice_note'); break; 
      case 'audio_file': messageIcon = Icons.headset; messageText = lang.t('chat_reply_audio_file'); break;
      case 'document': messageIcon = Icons.insert_drive_file; messageText = lang.t('chat_reply_document'); break;
      case 'large_emoji': messageText = messageContent ?? 'Emoji'; break;
      default: messageText = lang.t('chat_reply_generic_message');
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMe) _buildStatusIcon(messageStatus, theme),
        if (messageIcon != null) ...[
          Icon(messageIcon, color: theme.textTheme.bodyMedium?.color?.withAlpha(128), size: 14),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            messageText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withAlpha(178)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(String? status, ThemeData theme) {
    IconData icon;
    Color color = theme.textTheme.bodyMedium?.color ?? Colors.grey;

    switch (status) {
      case 'seen': icon = Icons.visibility; color = Colors.cyan.shade300; break;
      case 'delivered': icon = Icons.done_all; color = theme.textTheme.bodyMedium?.color?.withAlpha(150) ?? Colors.grey; break;
      case 'sent': icon = Icons.done; color = theme.textTheme.bodyMedium?.color?.withAlpha(150) ?? Colors.grey; break;
      case 'failed': icon = Icons.error_outline; color = Colors.red.shade400; break;
      default: icon = Icons.watch_later_outlined; color = theme.textTheme.bodyMedium?.color?.withAlpha(150) ?? Colors.grey;
    }
    return Padding(padding: const EdgeInsets.only(right: 6.0), child: Icon(icon, size: 16, color: color));
  }
}