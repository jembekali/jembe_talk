// lib/widgets/chat/chat_attachment_panel.dart (VERSION 3.75 - KEYBOARD-ADAPTIVE FLOATING ICONS)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../language_provider.dart';

class ChatAttachmentPanel extends StatelessWidget {
  final VoidCallback onCameraTap, onPhotoTap, onVideoTap, onAudioTap, onDocumentTap, onContactTap, onDameTap, onLudoTap, onClose;

  const ChatAttachmentPanel({
    super.key,
    required this.onCameraTap, required this.onPhotoTap, required this.onVideoTap, required this.onAudioTap,
    required this.onDocumentTap, required this.onContactTap, required this.onDameTap, required this.onLudoTap, required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    // ✅ Reba niba keyboard izamuye
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;

    final List<Map<String, dynamic>> menuItems = [
      {'icon': Icons.camera_alt_rounded, 'label': lang.t('chat_attachment_camera'), 'color': Colors.purple, 'onTap': onCameraTap},
      {'icon': Icons.photo_library_rounded, 'label': lang.t('chat_attachment_photo'), 'color': Colors.pink, 'onTap': onPhotoTap},
      {'icon': Icons.videocam_rounded, 'label': lang.t('chat_attachment_video'), 'color': Colors.orange, 'onTap': onVideoTap},
      {'icon': Icons.headset_rounded, 'label': lang.t('chat_attachment_audio'), 'color': Colors.lightBlue, 'onTap': onAudioTap},
      {'icon': Icons.insert_drive_file_rounded, 'label': lang.t('chat_attachment_document'), 'color': Colors.green, 'onTap': onDocumentTap},
      {'icon': Icons.contact_page_rounded, 'label': lang.t('chat_attachment_contact'), 'color': Colors.teal, 'onTap': onContactTap},
      {'icon': Icons.casino_rounded, 'label': lang.t('chat_attachment_dame'), 'color': Colors.brown, 'onTap': onDameTap},
      {'icon': Icons.grid_view_rounded, 'label': "Ludo", 'color': Colors.indigo, 'onTap': onLudoTap},
    ];

    return Material(
      color: Colors.transparent, 
      child: SafeArea(
        child: Container(
          // ✅ Niba keyboard ihari, izamura icons hejuru yayo gato, niba idahari ikaza hasi
          padding: EdgeInsets.fromLTRB(20, 10, 20, isKeyboardOpen ? 10 : 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // ✅ Twarinze ko icons zirenga screen niba keyboard ihari (Scrollable niba space ari nto)
              Flexible(
                child: AnimationLimiter(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: menuItems.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, 
                      mainAxisSpacing: isKeyboardOpen ? 10 : 20, // ✅ spacing ihinduka bitewe na keyboard
                      crossAxisSpacing: 10, 
                      childAspectRatio: 0.78 
                    ),
                    itemBuilder: (context, index) {
                      final item = menuItems[index];
                      return AnimationConfiguration.staggeredGrid(
                        position: index,
                        duration: const Duration(milliseconds: 500),
                        columnCount: 4,
                        child: ScaleAnimation(
                          scale: 0.4,
                          child: FadeInAnimation(
                            child: _buildFloatingItem(
                              theme: theme,
                              icon: item['icon'], 
                              label: item['label'], 
                              color: item['color'], 
                              onTap: item['onTap'],
                              isCompact: isKeyboardOpen // ✅ Menya niba igomba kuba ntoya gato
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (!isKeyboardOpen) const SizedBox(height: 30),
              // ✅ CLOSE BUTTON
              GestureDetector(
                onTap: onClose,
                child: Container(
                  margin: EdgeInsets.only(top: isKeyboardOpen ? 10 : 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 1)
                    ],
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingItem({
    required ThemeData theme, required IconData icon, required String label, 
    required Color color, required VoidCallback onTap, bool isCompact = false
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isCompact ? 52 : 60, // ✅ Ihindura size bitewe niba keyboard ihari
            height: isCompact ? 52 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withAlpha(200)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: isCompact ? 24 : 28),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label, 
              style: TextStyle(fontSize: isCompact ? 9 : 10.5, fontWeight: FontWeight.bold, color: Colors.white), 
              textAlign: TextAlign.center, 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis
            ),
          ),
        ],
      ),
    );
  }
}