// lib/tabs/chats_tab.dart (VERSION 32.28 - ACTIVITY REPAIRED - PERFORMANCE MASTER)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:jembe_talk/models/home_models.dart';
import 'package:jembe_talk/chat_screen.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/services/sync_service.dart';

class ChatsTab extends StatefulWidget {
  final ValueNotifier<List<ChatData>> chatsNotifier;
  final Future<void> Function() onRefresh;
  final List<dynamic> myBlockedUsers;

  const ChatsTab(
      {super.key,
      required this.chatsNotifier,
      required this.onRefresh,
      required this.myBlockedUsers});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab>
    with AutomaticKeepAliveClientMixin {
  bool _isSearchingLocal = false;
  final TextEditingController _localSearchController = TextEditingController();
  String _localQuery = "";

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _localSearchController.addListener(() {
      final q = _localSearchController.text.toLowerCase().trim();
      if (_localQuery != q) setState(() => _localQuery = q);
    });
  }

  @override
  void dispose() {
    _localSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);

    return ValueListenableBuilder<List<ChatData>>(
      valueListenable: widget.chatsNotifier,
      builder: (context, chats, child) {
        final filtered = chats.where((e) {
          if (_localQuery.isEmpty) return true;
          return e.displayName.toLowerCase().contains(_localQuery);
        }).toList();

        return Padding(
          padding: const EdgeInsets.only(top: 155),
          child: Column(
            children: [
              _buildHeader(theme, lang),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  color: theme.colorScheme.secondary,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 120),
                    physics: const BouncingScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      return ChatListItem(
                        key: ValueKey("chat_${filtered[i].userId}"),
                        chatData: filtered[i],
                        myBlockedUsers: widget.myBlockedUsers,
                        theme: theme,
                        lang: lang,
                        onTap: () => _openChat(context, filtered[i]),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openChat(BuildContext context, ChatData chat) {
    final currentUID = FirebaseAuth.instance.currentUser?.uid;
    if (currentUID == null) return;
    HapticFeedback.lightImpact();
    final List<String> ids = [currentUID, chat.userId]..sort();
    syncService.markChatAsSeen(ids.join('_'), chat.userId);
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (c) => ChatScreenWrapper(
                receiverEmail: chat.displayName, receiverID: chat.userId)));
  }

  Widget _buildHeader(ThemeData theme, LanguageProvider lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _isSearchingLocal
            ? _buildSearchField(theme)
            : Row(
                key: const ValueKey("default"),
                children: [
                  Text(lang.t('chats'),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color)),
                  const Spacer(),
                  IconButton(
                      onPressed: () => setState(() => _isSearchingLocal = true),
                      icon: Icon(Icons.search,
                          color: theme.colorScheme.secondary, size: 22)),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Container(
      key: const ValueKey("search"),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          color: theme.colorScheme.surface.withAlpha(120),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.secondary.withAlpha(30))),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: _localSearchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: "Shaka...",
                      border: InputBorder.none,
                      isDense: true),
                  style: const TextStyle(fontSize: 15))),
          IconButton(
              onPressed: () => setState(() => _isSearchingLocal = false),
              icon: const Icon(Icons.close, size: 18)),
        ],
      ),
    );
  }
}

class ChatListItem extends StatefulWidget {
  final ChatData chatData;
  final List<dynamic> myBlockedUsers;
  final ThemeData theme;
  final LanguageProvider lang;
  final VoidCallback onTap;

  const ChatListItem({
    super.key,
    required this.chatData,
    required this.myBlockedUsers,
    required this.theme,
    required this.lang,
    required this.onTap,
  });

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  StreamSubscription? _statusSub, _activitySub;
  bool _isOnline = false;
  String? _activity; // null, 'typing', or 'recording'

  @override
  void initState() {
    super.initState();
    _setupRealtimeListeners();
  }

  void _setupRealtimeListeners() {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    // 1. Precise Room ID calculation
    final List<String> ids = [myUid, widget.chatData.userId]..sort();
    String roomId = ids.join('_');

    // 2. Online Presence (Realtime Database)
    _statusSub = FirebaseDatabase.instance
        .ref('status/${widget.chatData.userId}/state')
        .onValue
        .listen((event) {
      if (mounted)
        setState(
            () => _isOnline = (event.snapshot.value?.toString() == 'online'));
    });

    // 3. Activity Tracking (Typing/Recording) - FIXED PATH
    _activitySub = FirebaseDatabase.instance
        .ref('activity/$roomId/${widget.chatData.userId}')
        .onValue
        .listen((event) {
      if (mounted) {
        final val = event.snapshot.value?.toString();
        // Niba ari 'idle' cyangwa ntacyo arimo gukora, dushyiraho null kugira ngo subtitle igaruke kuri message
        setState(() =>
            _activity = (val == 'typing' || val == 'recording') ? val : null);
      }
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _activitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final isBlocked = widget.myBlockedUsers.contains(widget.chatData.userId) ||
        widget.chatData.blockedUsers.contains(currentUid);
    final isAdmin = widget.chatData.userId == 'jembe_talk_official_admin';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
          color: widget.theme.colorScheme.surface.withAlpha(220),
          borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        onTap: widget.onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Stack(
          children: [
            _buildAvatar(isAdmin, isBlocked),
            if (_isOnline && !isBlocked)
              Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: widget.theme.colorScheme.surface,
                              width: 2)))),
          ],
        ),
        title: Row(
          children: [
            Flexible(
                child: Text(widget.chatData.displayName,
                    style: TextStyle(
                        fontWeight: isAdmin ? FontWeight.w900 : FontWeight.bold,
                        fontSize: 15,
                        color: isAdmin
                            ? Colors.amber
                            : widget.theme.textTheme.bodyLarge?.color))),
            if (isAdmin)
              const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child:
                      Icon(Icons.stars_rounded, color: Colors.amber, size: 18)),
          ],
        ),
        subtitle: _buildSubtitle(currentUid),
        trailing: _buildTrailing(),
      ),
    );
  }

  Widget _buildAvatar(bool isAdmin, bool isBlocked) {
    if (isBlocked)
      return const CircleAvatar(radius: 25, child: Icon(Icons.block, size: 20));
    if (isAdmin)
      return const CircleAvatar(
          radius: 25,
          backgroundImage: AssetImage('assets/images/jeme_talk_icon.png'));

    ImageProvider? provider;
    if (widget.chatData.localPhotoPath != null &&
        File(widget.chatData.localPhotoPath!).existsSync()) {
      provider = ResizeImage(FileImage(File(widget.chatData.localPhotoPath!)),
          width: 100, height: 100);
    } else if (widget.chatData.photoUrl != null &&
        widget.chatData.photoUrl!.isNotEmpty) {
      provider = CachedNetworkImageProvider(widget.chatData.photoUrl!,
          maxWidth: 100, maxHeight: 100);
    }

    return CircleAvatar(
        radius: 25,
        backgroundColor: widget.theme.colorScheme.surface,
        backgroundImage: provider,
        child: provider == null
            ? const Icon(Icons.person, color: Colors.grey)
            : null);
  }

  Widget _buildSubtitle(String myUid) {
    // 🔥 PRIORITY 1: ACTIVITY (TYPING/RECORDING)
    if (_activity == 'typing') {
      return Text("${widget.lang.t('chat_app_bar_typing')}...",
          style: const TextStyle(
              color: Colors.blueAccent,
              fontWeight: FontWeight.bold,
              fontSize: 12.5));
    }
    if (_activity == 'recording') {
      return Row(children: [
        const Icon(Icons.mic, size: 13, color: Colors.redAccent),
        const SizedBox(width: 4),
        Text("${widget.lang.t('chat_app_bar_recording')}...",
            style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12.5)),
      ]);
    }

    // PRIORITY 2: LAST MESSAGE CONTENT
    final isMe = widget.chatData.lastMessageSenderId == myUid;
    String content = widget.chatData.lastMessageContent ?? "";
    if (widget.chatData.lastMessageType == 'image')
      content = "📷 ${widget.lang.t('chat_reply_photo')}";
    if (widget.chatData.lastMessageType == 'voice_note')
      content = "🎤 ${widget.lang.t('chat_reply_voice_note')}";

    return Row(
      children: [
        if (isMe) _buildStatusIcon(),
        Expanded(
            child: Text(content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: widget.theme.textTheme.bodySmall?.color))),
      ],
    );
  }

  Widget _buildStatusIcon() {
    IconData icon = Icons.done;
    Color color = Colors.grey.withAlpha(180);
    final status = widget.chatData.lastMessageStatus;
    if (status == 'seen') {
      icon = Icons.visibility;
      color = Colors.cyan.shade300;
    } else if (status == 'delivered') {
      icon = Icons.done_all;
    } else if (status == 'failed') {
      icon = Icons.error_outline;
      color = Colors.red;
    }
    return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(icon, size: 14, color: color));
  }

  Widget _buildTrailing() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.chatData.lastMessageTimestamp > 0)
          Text(_formatTs(widget.chatData.lastMessageTimestamp),
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 5),
        if (widget.chatData.unreadCount > 0)
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(widget.chatData.unreadCount.toString(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold))),
      ],
    );
  }

  String _formatTs(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    return dt.day == now.day
        ? DateFormat('HH:mm').format(dt)
        : DateFormat('dd/MM').format(dt);
  }
}
