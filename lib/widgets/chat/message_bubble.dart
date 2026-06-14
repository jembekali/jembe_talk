// lib/widgets/chat/message_bubble.dart (VERSION 4.38 - DEEP LINK & REPLY JUMP FIXED)

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../language_provider.dart';
import '../../services/database_helper.dart';
import '../../services/chat_message_service.dart';
import '../../services/sync_service.dart';
import '../../tangaza_star/tangaza_star_screen.dart'; // ✅ Menya ko iyi import ihari
import 'chat_media_widgets.dart';

class MessageBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final bool isMe;
  final bool isSelected;
  final double? uploadProgress;
  final VoidCallback? onAcceptInvitation;
  final Function(Map<String, dynamic>)? onDeclineInvitation;
  final VoidCallback? onRetryUpload;
  final Function(String messageId)? onReplyTap;
  final Function(String messageId)? onLongPress;
  final Function(String messageId)? onTap;
  final String receiverDisplayName;
  final bool isHighlighted; 
  final Function(Map<String, dynamic>) onSwipeReply;
  final VoidCallback onDelete; 
  final VoidCallback onEdit; 
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const MessageBubble({
    super.key,
    required this.messageData,
    required this.isMe,
    required this.isSelected,
    this.uploadProgress,
    this.onAcceptInvitation,
    this.onDeclineInvitation,
    this.onRetryUpload,
    this.onReplyTap,
    this.onLongPress,
    this.onTap,
    required this.receiverDisplayName,
    this.isHighlighted = false,
    required this.onSwipeReply,
    required this.onDelete,
    required this.onEdit, 
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; 

  bool _actionTaken = false;
  Map<String, dynamic>? _decodedReply;
  Map<String, dynamic>? _decodedContact;
  late final DateFormat _timeFormatter;
  Timer? _gameExpiryTimer;

  @override
  void initState() {
    super.initState();
    _timeFormatter = DateFormat.Hm();
    _decodeData(); 
    _startInvitationExpiryCheck();
  }

  void _startInvitationExpiryCheck() {
    if (widget.messageData['messageType'] == 'dame_invitation') {
      final int ts = widget.messageData['timestamp'] ?? 0;
      final expiryTime = ts + (5 * 60 * 1000);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= expiryTime) {
        _autoDeleteExpiredInvitation();
      } else {
        _gameExpiryTimer = Timer(Duration(milliseconds: expiryTime - now), () => _autoDeleteExpiredInvitation());
      }
    }
  }

  Future<void> _autoDeleteExpiredInvitation() async {
    if (!mounted) return;
    try {
      await FirebaseFirestore.instance.collection('chat_rooms').doc(widget.messageData['chatRoomID']).collection('messages').doc(widget.messageData['id']).delete();
      await chatMessageService.deleteMessage(widget.messageData['id']);
      syncService.notifyUIMessageUpdate("refresh_ui");
    } catch (e) { log("Error: $e"); }
  }

  @override
  void dispose() { 
    _gameExpiryTimer?.cancel(); 
    super.dispose(); 
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messageData['replyingTo'] != oldWidget.messageData['replyingTo'] ||
        widget.messageData['message'] != oldWidget.messageData['message']) {
      _decodeData();
    }
  }

  void _decodeData() {
    try {
      final replyStr = widget.messageData['replyingTo'];
      if (replyStr != null && replyStr is String && replyStr.isNotEmpty) {
        _decodedReply = jsonDecode(replyStr);
      } else {
        _decodedReply = null;
      }
      if (widget.messageData['messageType'] == 'contact') {
        _decodedContact = jsonDecode(widget.messageData['message'] ?? '{}');
      }
    } catch (e) { log("Error decode: $e"); }
  }

  BorderRadius _getBorderRadius() {
    const double r = 18.0; const double s = 4.0;
    if (widget.isMe) {
      return BorderRadius.only(
        topLeft: const Radius.circular(r), bottomLeft: const Radius.circular(r),
        topRight: Radius.circular(widget.isFirstInGroup ? r : s),
        bottomRight: Radius.circular(widget.isLastInGroup ? r : s),
      );
    } else {
      return BorderRadius.only(
        topRight: const Radius.circular(r), bottomRight: const Radius.circular(r),
        topLeft: Radius.circular(widget.isFirstInGroup ? r : s),
        bottomLeft: Radius.circular(widget.isLastInGroup ? r : s),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 
    final theme = Theme.of(context);
    final String type = widget.messageData['messageType'] ?? 'text';
    final bool isMe = widget.isMe;

    return RepaintBoundary( 
      child: Slidable(
        key: ValueKey(widget.messageData['id']),
        startActionPane: ActionPane(
          motion: const DrawerMotion(), 
          extentRatio: 0.15,
          children: [
            CustomSlidableAction(
              onPressed: (_) => widget.onSwipeReply(widget.messageData),
              backgroundColor: Colors.transparent,
              child: Icon(Icons.reply_rounded, color: theme.colorScheme.primary, size: 24),
            ),
          ],
        ),
        endActionPane: _buildEndActionPane(theme, type),
        child: _buildBubbleContent(theme, type, isMe),
      ),
    );
  }

  ActionPane? _buildEndActionPane(ThemeData theme, String type) {
    final isEdited = (widget.messageData['isEdited'] ?? 0) == 1;
    final msgTime = DateTime.fromMillisecondsSinceEpoch(widget.messageData['timestamp'] ?? 0);
    final bool canEdit = widget.isMe && type == 'text' && DateTime.now().difference(msgTime).inMinutes < 15 && !isEdited;

    return ActionPane(
      motion: const DrawerMotion(),
      extentRatio: canEdit ? 0.35 : 0.15,
      children: [
        if (canEdit)
          SlidableAction(onPressed: (_) => widget.onEdit(), backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, icon: Icons.edit_rounded),
        SlidableAction(onPressed: (_) => widget.onDelete(), backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, icon: Icons.delete_outline_rounded),
      ],
    );
  }

  Widget _buildBubbleContent(ThemeData theme, String type, bool isMe) {
    final status = widget.messageData['status'] ?? 'sent';
    final isUploading = status == 'uploading' || status == 'pending';
    final isFailed = status == 'failed' || status == 'canceled';
    final bool isMedia = ['image', 'video', 'voice_note', 'audio_file', 'document'].contains(type);
    final bool isVisual = type == 'video' || type == 'image';
    final bool isPlayed = (widget.messageData['isPlayed'] ?? 0) == 1;

    final Color bubbleColor = isMe ? theme.colorScheme.primary : theme.colorScheme.surface;

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.heavyImpact();
        if (type == 'text') Clipboard.setData(ClipboardData(text: widget.messageData['message'] ?? ""));
        widget.onLongPress?.call(widget.messageData['id']);
      },
      onTap: () => widget.onTap?.call(widget.messageData['id']),
      child: Container(
        color: widget.isHighlighted ? theme.colorScheme.primary.withOpacity(0.12) : Colors.transparent,
        padding: EdgeInsets.only(bottom: widget.isLastInGroup ? 8 : 1, top: widget.isFirstInGroup ? 4 : 0),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: (type == 'large_emoji' || type == 'contact' || type == 'voice_note' || isVisual) 
                ? EdgeInsets.zero 
                : const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              color: widget.isSelected ? theme.colorScheme.primary.withOpacity(0.3) : bubbleColor,
              borderRadius: _getBorderRadius(),
              border: isMe ? null : Border.all(color: Colors.black12, width: 0.5),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_decodedReply != null) 
                      GestureDetector(
                        onTap: () { if (_decodedReply!['id'] != null) widget.onReplyTap?.call(_decodedReply!['id']); },
                        child: _buildReplyPreview(theme, isMe),
                      ),
                    _buildMessageContent(type, isMe, theme, isUploading || isFailed, isPlayed),
                    if (type != 'deleted') _buildFooter(isMe, theme, isPlayed),
                  ],
                ),
                if (isMe && isMedia && (isUploading || isFailed)) 
                   _buildUploadOverlay(isVisual, type, isUploading, isFailed),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent(String type, bool isMe, ThemeData theme, bool isUploadingOrFailed, bool isPlayed) {
    final Color textColor = isMe ? Colors.white : theme.colorScheme.onSurface;
    final String text = widget.messageData['message'] ?? '';
    final lang = Provider.of<LanguageProvider>(context);

    switch (type) {
      case 'text':
        return Linkify(
          onOpen: (link) async { 
            final String url = link.url;
            // 🔥 TANGAZA STAR DEEP LINK: Intercept URL for In-App Navigation
            if (url.contains('jembe-talk-1.web.app/post') && url.contains('id=')) {
              try {
                final uri = Uri.parse(url);
                final postId = uri.queryParameters['id'];
                if (postId != null) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => TangazaStarScreen(targetPostId: postId)));
                  return; 
                }
              } catch (_) {}
            }
            // STANDARD BROWSER OPEN
            if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
          text: text, style: TextStyle(color: textColor, fontSize: 15.5, height: 1.3),
          linkStyle: TextStyle(color: isMe ? Colors.cyanAccent : Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
        );
      case 'image': return ImageBubble(messageData: widget.messageData, isUploadingOrFailed: isUploadingOrFailed);
      case 'video': return VideoPlayerBubble(messageData: widget.messageData, caption: text, isUploadingOrFailed: isUploadingOrFailed);
      case 'voice_note':
      case 'audio_file': return VoiceBubble(messageData: widget.messageData, isPlayed: isPlayed);
      case 'document': return DocumentBubble(messageData: widget.messageData, textColor: textColor);
      case 'contact': return ContactBubble(contactData: _decodedContact ?? {});
      case 'large_emoji': return Text(text, style: const TextStyle(fontSize: 55));
      case 'dame_invitation':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.all(8.0), child: Text(text, style: TextStyle(color: textColor, fontStyle: FontStyle.italic))),
          if (!widget.isMe && !_actionTaken) 
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: () { setState(() => _actionTaken = true); widget.onDeclineInvitation?.call(widget.messageData); }, child: Text(lang.t('dialog_no'), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: () { setState(() => _actionTaken = true); widget.onAcceptInvitation?.call(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(lang.t('dialog_yes'))),
            ]))
        ]);
      case 'deleted': return const Padding(padding: EdgeInsets.all(8.0), child: Text("Message deleted", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)));
      default: return Text(text, style: TextStyle(color: textColor));
    }
  }

  Widget _buildFooter(bool isMe, ThemeData theme, bool voicePlayed) {
    final status = widget.messageData['status'] ?? 'sent';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_timeFormatter.format(DateTime.fromMillisecondsSinceEpoch(widget.messageData['timestamp'] ?? 0)), 
               style: TextStyle(fontSize: 9, color: isMe ? Colors.white70 : Colors.grey[600], fontWeight: FontWeight.w500)),
          if (isMe) ...[ const SizedBox(width: 4), _getStatusIcon(status) ],
        ],
      ),
    );
  }

  Widget _getStatusIcon(String status) {
    IconData icon; Color color;
    if (status == 'seen') { icon = Icons.visibility_rounded; color = Colors.cyanAccent; }
    else if (status == 'delivered') { icon = Icons.done_all_rounded; color = Colors.white70; }
    else if (status == 'sent') { icon = Icons.done_rounded; color = Colors.white70; }
    else { icon = Icons.schedule_rounded; color = Colors.white60; }
    return Icon(icon, size: 13, color: color);
  }

  Widget _buildReplyPreview(ThemeData theme, bool isMe) {
    if (_decodedReply == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 6), padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: isMe ? Colors.white54 : theme.colorScheme.primary, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_decodedReply!['senderID'] == FirebaseAuth.instance.currentUser?.uid ? "You" : widget.receiverDisplayName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: isMe ? Colors.white : theme.colorScheme.primary)),
        Text(_decodedReply!['message'] ?? "", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ]),
    );
  }

  Widget _buildUploadOverlay(bool isVisual, String type, bool isUploading, bool isFailed) {
    return Positioned(
      bottom: isVisual ? (type == 'video' ? 45 : 8) : 5, right: isVisual ? 8 : 5,
      child: GestureDetector(
        onTap: () { if (isFailed) widget.onRetryUpload?.call(); else syncService.cancelUpload(widget.messageData['id']); },
        child: Container(
          width: 32, height: 32, decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), shape: BoxShape.circle),
          child: isUploading
              ? Stack(alignment: Alignment.center, children: [ CircularProgressIndicator(value: widget.uploadProgress ?? 0.1, strokeWidth: 2.5, color: Colors.white, backgroundColor: Colors.white10), const Icon(Icons.close, color: Colors.white, size: 14) ])
              : const Icon(Icons.refresh, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}