// lib/widgets/chat/chat_app_bar.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// <--- TWONGEREYEMWO IZI DOSIYE --->
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
// <--- Ibindi bikurikira --->
import 'package:jembe_talk/services/database_helper.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String receiverEmail;
  final String receiverID;
  final Stream<DatabaseEvent>? presenceStream;
  final Stream<DatabaseEvent>? activityStream;
  final Stream<DocumentSnapshot<Object?>>? currentUserStream;
  final Stream<DocumentSnapshot<Object?>>? receiverUserStream;
  final VoidCallback onNavigateBack;
  final VoidCallback onNavigateToContactInfo;
  final Function(String, {bool isReceiverBlocked}) onMenuSelection;

  const ChatAppBar({
    super.key,
    required this.receiverEmail,
    required this.receiverID,
    required this.presenceStream,
    required this.activityStream,
    required this.currentUserStream,
    required this.receiverUserStream,
    required this.onNavigateBack,
    required this.onNavigateToContactInfo,
    required this.onMenuSelection,
  });

  @override
  Widget build(BuildContext context) {
    // <--- Duhamagara LanguageProvider --->
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), child: Container(color: theme.colorScheme.surface.withAlpha(180),),),),
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onNavigateBack),
      title: InkWell(
        onTap: onNavigateToContactInfo,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spacer(),
            _PresenceIndicator(presenceStream: presenceStream),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: currentUserStream,
                  builder: (context, currentUserSnapshot) {
                    return StreamBuilder<DocumentSnapshot>(
                      stream: receiverUserStream,
                      builder: (context, receiverSnapshot) {
                        
                        if (!currentUserSnapshot.hasData || !receiverSnapshot.hasData) {
                          return const CircleAvatar(radius: 20, child: Icon(Icons.person, size: 22));
                        }

                        final currentUserData = currentUserSnapshot.data?.data() as Map<String, dynamic>?;
                        final myBlockedUsers = currentUserData?['blockedUsers'] as List<dynamic>? ?? [];
                        final iHaveBlockedReceiver = myBlockedUsers.contains(receiverID);

                        final receiverData = receiverSnapshot.data?.data() as Map<String, dynamic>?;
                        final receiverBlockedUsers = receiverData?['blockedUsers'] as List<dynamic>? ?? [];
                        final amIBlockedByReceiver = receiverBlockedUsers.contains(currentUserSnapshot.data?.id);
                        
                        final isBlocked = iHaveBlockedReceiver || amIBlockedByReceiver;

                        return FutureBuilder<Map<String, dynamic>?>(
                          future: DatabaseHelper.instance.getJembeContactById(receiverID),
                          builder: (context, localDataSnapshot) {
                            ImageProvider? profileImageProvider;

                            if (!isBlocked) {
                              final localData = localDataSnapshot.data;
                              final localPhotoPath = localData?['localPhotoPath'] as String?;
                              final photoUrl = receiverData?['photoUrl'] as String?;

                              if (localPhotoPath != null && File(localPhotoPath).existsSync()) {
                                profileImageProvider = FileImage(File(localPhotoPath));
                              } else if (photoUrl != null) {
                                profileImageProvider = NetworkImage(photoUrl);
                              }
                            }
                            
                            return CircleAvatar(
                              radius: 20, 
                              backgroundImage: profileImageProvider, 
                              child: profileImageProvider == null ? const Icon(Icons.person, size: 22) : null,
                            );
                          },
                        );
                      },
                    );
                  }
                ),
                const SizedBox(height: 3),
                Text(receiverEmail, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal), overflow: TextOverflow.ellipsis,),
              ],
            ),
            const SizedBox(width: 8),
            _ActivityIndicator(activityStream: activityStream),
            const Spacer(),
          ],
        ),
      ),
      actions: [
        StreamBuilder<DocumentSnapshot>(
          stream: currentUserStream,
          builder: (context, snapshot) {
            bool isReceiverBlocked = false;
            if (snapshot.hasData && snapshot.data!.exists) {
              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              final blockedUsers = userData?['blockedUsers'] as List<dynamic>? ?? [];
              isReceiverBlocked = blockedUsers.contains(receiverID);
            }
            return PopupMenuButton<String>(
              onSelected: (value) => onMenuSelection(value, isReceiverBlocked: isReceiverBlocked),
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'view_contact', child: Text(lang.t('chat_app_bar_view_contact'))),
                PopupMenuItem<String>(value: 'wallpaper', child: Text(lang.t('chat_app_bar_wallpaper'))),
                PopupMenuItem<String>(value: 'clear_chat', child: Text(lang.t('chat_app_bar_clear_chat'))),
                PopupMenuItem<String>(value: 'block', child: Text(isReceiverBlocked ? lang.t('chat_app_bar_unblock') : lang.t('chat_app_bar_block'))),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}


class _PresenceIndicator extends StatefulWidget {
  final Stream<DatabaseEvent>? presenceStream;
  const _PresenceIndicator({required this.presenceStream});

  @override
  State<_PresenceIndicator> createState() => _PresenceIndicatorState();
}

class _PresenceIndicatorState extends State<_PresenceIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: widget.presenceStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          try {
            final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
            final state = data['state'];
            if (state == 'online') {
              return FadeTransition(
                opacity: _animation,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              );
            }
          } catch(e) { /* ignore */ }
        }
        return const SizedBox(width: 16);
      },
    );
  }
}

class _ActivityIndicator extends StatefulWidget {
  final Stream<DatabaseEvent>? activityStream;
  const _ActivityIndicator({required this.activityStream});

  @override
  State<_ActivityIndicator> createState() => _ActivityIndicatorState();
}

class _ActivityIndicatorState extends State<_ActivityIndicator> {
  late Timer _timer;
  late String _timeString;

  @override
  void initState() {
    super.initState();
    _timeString = _formatDateTime(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
  
  void _updateTime() {
    if (mounted) {
      setState(() {
        _timeString = _formatDateTime(DateTime.now());
      });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    String separator = dateTime.second.isEven ? ':' : ' ';
    return DateFormat('HH${separator}mm').format(dateTime);
  }
  
  @override
  Widget build(BuildContext context) {
    // <--- Duhamagara LanguageProvider --->
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    
    return StreamBuilder<DatabaseEvent>(
      stream: widget.activityStream,
      builder: (context, snapshot) {
        String activity = "idle";
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          activity = snapshot.data!.snapshot.value as String;
        }

        Widget content;
        
        switch(activity) {
          case 'typing':
            content = _buildActivityContent(
              key: 'typing',
              icon: Icons.edit,
              text: lang.t('chat_app_bar_typing'),
              theme: theme
            );
            break;
          case 'recording':
            content = _buildActivityContent(
              key: 'recording',
              icon: Icons.mic,
              text: lang.t('chat_app_bar_recording'),
              theme: theme
            );
            break;
          default: // idle
            content = _buildClockContent(
              key: 'idle',
              theme: theme
            );
            break;
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axis: Axis.horizontal,
                child: child,
              ),
            );
          },
          child: content,
        );
      },
    );
  }

  Widget _buildClockContent({required String key, required ThemeData theme}) {
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time, size: 14, color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
          const SizedBox(width: 6),
          Text(
            _timeString,
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActivityContent({required String key, required IconData icon, required String text, required ThemeData theme}) {
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSecondaryContainer,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}