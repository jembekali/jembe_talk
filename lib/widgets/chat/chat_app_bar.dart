// lib/widgets/chat/chat_app_bar.dart (VERSION 2.30 - DYNAMIC ANIMATED ACTIVITY)

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:jembe_talk/language_provider.dart';
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
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: Colors.transparent, 
      elevation: 0, 
      centerTitle: true,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: Container(color: theme.colorScheme.surface.withAlpha(170)),
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), 
        onPressed: onNavigateBack
      ),
      title: InkWell(
        onTap: onNavigateToContactInfo,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min, // ✅ Ibi nibyo bituma iyo Row yagutse Profile yimuka
            children: [
              _PresenceIndicator(presenceStream: presenceStream),
              const SizedBox(width: 8),
              
              // PROFILE AND EMAIL SECTION
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
                            return const CircleAvatar(radius: 17, child: Icon(Icons.person, size: 18));
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
                                } else if (photoUrl != null && photoUrl.isNotEmpty) {
                                  profileImageProvider = NetworkImage(photoUrl);
                                }
                              }
                              
                              return CircleAvatar(
                                radius: 17, 
                                backgroundColor: theme.colorScheme.secondaryContainer,
                                backgroundImage: profileImageProvider, 
                                child: profileImageProvider == null 
                                  ? Icon(Icons.person, size: 18, color: theme.colorScheme.onSecondaryContainer) 
                                  : null,
                              );
                            },
                          );
                        },
                      );
                    }
                  ),
                  const SizedBox(height: 2),
                  Text(receiverEmail, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ],
              ),

              // ✅ DYNAMIC ACTIVITY INDICATOR (Pushing effect)
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: _ActivityIndicator(activityStream: activityStream),
              ),
            ],
          ),
        ),
      ),
      actions: [
        StreamBuilder<DocumentSnapshot>(
          stream: currentUserStream,
          builder: (context, snapshot) {
            bool isBlocked = false;
            if (snapshot.hasData && snapshot.data!.exists) {
              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              final blockedUsers = userData?['blockedUsers'] as List<dynamic>? ?? [];
              isBlocked = blockedUsers.contains(receiverID);
            }
            return PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) => onMenuSelection(value, isReceiverBlocked: isBlocked),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'view_contact', child: Row(children: [const Icon(Icons.person_outline, size: 18), const SizedBox(width: 10), Text(lang.t('chat_app_bar_view_contact'))])),
                PopupMenuItem<String>(value: 'wallpaper', child: Row(children: [const Icon(Icons.wallpaper, size: 18), const SizedBox(width: 10), Text(lang.t('chat_app_bar_wallpaper'))])),
                PopupMenuItem<String>(value: 'clear_chat', child: Row(children: [const Icon(Icons.delete_sweep_outlined, size: 18), const SizedBox(width: 10), Text(lang.t('chat_app_bar_clear_chat'))])),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'block', 
                  child: Row(children: [
                    Icon(isBlocked ? Icons.check_circle_outline : Icons.block, size: 18, color: isBlocked ? Colors.green : Colors.red),
                    const SizedBox(width: 10), 
                    Text(isBlocked ? lang.t('chat_app_bar_unblock') : lang.t('chat_app_bar_block'), style: TextStyle(color: isBlocked ? Colors.green : Colors.red))
                  ])
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 5);
}

// --- PRESENCE INDICATOR (Size 14px - GLOWING) ---
class _PresenceIndicator extends StatefulWidget {
  final Stream<DatabaseEvent>? presenceStream;
  const _PresenceIndicator({required this.presenceStream});
  @override
  State<_PresenceIndicator> createState() => _PresenceIndicatorState();
}

class _PresenceIndicatorState extends State<_PresenceIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: widget.presenceStream,
      builder: (context, snapshot) {
        bool isOnline = false;
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          try {
            final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
            isOnline = data['state'] == 'online';
          } catch(_) {}
        }
        
        return isOnline ? FadeTransition(
          opacity: _anim,
          child: Container(
            width: 14, height: 14, 
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.greenAccent, 
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.6), blurRadius: 6, spreadRadius: 1)]
            )
          ),
        ) : const SizedBox(width: 14);
      },
    );
  }
}

// --- ACTIVITY INDICATOR (MODERN ANIMATED PILL) ---
class _ActivityIndicator extends StatefulWidget {
  final Stream<DatabaseEvent>? activityStream;
  const _ActivityIndicator({required this.activityStream});
  @override
  State<_ActivityIndicator> createState() => _ActivityIndicatorState();
}

class _ActivityIndicatorState extends State<_ActivityIndicator> with TickerProviderStateMixin {
  late Timer _timer;
  late String _timeString;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _timeString = _formatTime(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (t) => _updateTime());
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }
  
  void _updateTime() { if (mounted) setState(() => _timeString = _formatTime(DateTime.now())); }
  String _formatTime(DateTime dt) => DateFormat(dt.second.isEven ? 'HH:mm' : 'HH mm').format(dt);
  
  @override
  void dispose() { _timer.cancel(); _pulseCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    return StreamBuilder<DatabaseEvent>(
      stream: widget.activityStream,
      builder: (context, snapshot) {
        String act = (snapshot.hasData && snapshot.data!.snapshot.value != null) ? snapshot.data!.snapshot.value as String : "idle";
        
        if (act == 'typing') {
          return _buildPill(Icons.edit_note_rounded, lang.t('chat_app_bar_typing'), Colors.blue, true);
        } else if (act == 'recording') {
          return _buildPill(Icons.mic_rounded, lang.t('chat_app_bar_recording'), Colors.red, true);
        } else {
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                const Icon(Icons.access_time_filled, size: 10, color: Colors.grey),
                const SizedBox(width: 3),
                Text(_timeString, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildPill(IconData icon, String txt, Color col, bool active) {
    return Container(
      margin: const EdgeInsets.only(left: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: col.withOpacity(0.2), width: 0.5)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.2).animate(_pulseCtrl),
            child: Icon(icon, size: 14, color: col),
          ),
          const SizedBox(width: 6),
          Text(txt, style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          _BouncingDots(color: col),
        ],
      ),
    );
  }
}

// --- BOUNCING DOTS ANIMATION ---
class _BouncingDots extends StatefulWidget {
  final Color color;
  const _BouncingDots({required this.color});
  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 400)));
    _animations = _controllers.map((c) => Tween<double>(begin: 0, end: -4).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();

    for (int i = 0; i < 3; i++) {
      Timer(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() { for (var c in _controllers) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _animations[i],
        builder: (context, child) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          transform: Matrix4.translationValues(0, _animations[i].value, 0),
          width: 3, height: 3, 
          decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
        ),
      )),
    );
  }
}