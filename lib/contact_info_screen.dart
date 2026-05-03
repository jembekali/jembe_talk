// lib/contact_info_screen.dart (VERSION 2.4 - FIXED NAVIGATION & CLEAN MEDIA)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/full_photo_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jembe_talk/widgets/chat/chat_media_widgets.dart';

class ContactInfoScreen extends StatefulWidget {
  final String userID;
  final String userEmail;
  final String? photoUrl;

  const ContactInfoScreen({
    super.key,
    required this.userID,
    required this.userEmail,
    this.photoUrl,
  });

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _getChatRoomID() {
    List<String> ids = [_auth.currentUser!.uid, widget.userID];
    ids.sort();
    return ids.join('_');
  }

  void _showFullImage(BuildContext context, String imagePathOrUrl, bool isLocal, String heroTag) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => FullPhotoScreen(imageUrl: imagePathOrUrl, isLocalFile: isLocal, heroTag: heroTag)));
  }

  void _openVideo(String? url, String? localPath) {
    String? path = (localPath != null && File(localPath).existsSync()) ? localPath : url;
    if (path != null) {
      if (path.startsWith('http')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download this video in chat first to view."), behavior: SnackBarBehavior.floating));
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (c) => FullScreenVideoPlayer(videoUrl: path, startAt: Duration.zero)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);
    final heroTag = 'profile-pic-${widget.userID}';
    
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(widget.userID).snapshots(),
      builder: (context, firestoreSnapshot) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: DatabaseHelper.instance.getJembeContactById(widget.userID),
          builder: (context, localSnapshot) {
            
            final firestoreData = firestoreSnapshot.hasData ? firestoreSnapshot.data!.data() as Map<String, dynamic>? : null;
            final localData = localSnapshot.data;
            final displayName = firestoreData?['displayName'] ?? localData?['displayName'] ?? widget.userEmail;
            
            final phoneNumber = firestoreData?['phoneNumber'] ?? localData?['phoneNumber'] ?? "No phone number";
            final aboutText = firestoreData?['about'] ?? "Hey there! I am using Jembe Talk.";
            final photoUrl = firestoreData?['photoUrl'] ?? localData?['photoUrl'] ?? widget.photoUrl;
            final localPhotoPath = localData?['localPhotoPath'] as String?;
            
            ImageProvider? profileImageProvider;
            String? imagePathForFullScreen;
            bool isImageLocal = false;

            if (localPhotoPath != null && File(localPhotoPath).existsSync()) {
              profileImageProvider = FileImage(File(localPhotoPath));
              imagePathForFullScreen = localPhotoPath;
              isImageLocal = true;
            } else if (photoUrl != null && photoUrl.isNotEmpty) {
              profileImageProvider = CachedNetworkImageProvider(photoUrl);
              imagePathForFullScreen = photoUrl;
              isImageLocal = false;
            }

            return Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              appBar: AppBar(
                title: Text(displayName, style: const TextStyle(fontSize: 18)),
                backgroundColor: theme.appBarTheme.backgroundColor,
                elevation: 0,
              ),
              body: (!firestoreSnapshot.hasData && !localSnapshot.hasData)
                  ? Center(child: CircularProgressIndicator(color: theme.colorScheme.secondary))
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          // --- 1. Profile Section ---
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            width: double.infinity,
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () { if (imagePathForFullScreen != null) _showFullImage(context, imagePathForFullScreen, isImageLocal, heroTag); },
                                  child: Hero(
                                    tag: heroTag,
                                    child: CircleAvatar(
                                      radius: 65,
                                      backgroundColor: theme.colorScheme.secondary.withOpacity(0.2),
                                      backgroundImage: profileImageProvider,
                                      child: profileImageProvider == null ? const Icon(Icons.person, size: 65, color: Colors.grey) : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Text(displayName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 5),
                                Text(phoneNumber, style: TextStyle(fontSize: 15, color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
                                const SizedBox(height: 25),
                                
                                // ✅ KOSORA NAVIGATION: Pop aho gupushinga indi screen
                                ElevatedButton.icon(
                                  onPressed: () => Navigator.pop(context), 
                                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                                  label: Text(lang.t('contact_chat_btn') ?? "Message"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 45, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    elevation: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Divider(indent: 30, endIndent: 30, color: Colors.white12),

                          // --- 2. Information Section ---
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoTile("About", aboutText, Icons.info_outline, theme),
                                const SizedBox(height: 15),
                                _buildInfoTile("Phone", phoneNumber, Icons.phone_android_rounded, theme),
                              ],
                            ),
                          ),

                          // --- 3. Shared Media Section ---
                          Container(
                            padding: const EdgeInsets.all(16),
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Media, Links, and Docs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 15),
                                FutureBuilder<List<Map<String, dynamic>>>(
                                  future: DatabaseHelper.instance.getMediaMessages(_getChatRoomID(), limit: 40),
                                  builder: (context, mediaSnap) {
                                    if (!mediaSnap.hasData || mediaSnap.data!.isEmpty) {
                                      return Container(
                                        height: 80, alignment: Alignment.center,
                                        child: const Text("No photos or videos shared yet", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                      );
                                    }

                                    final mediaList = mediaSnap.data!;
                                    return GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: mediaList.length,
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 5, mainAxisSpacing: 5),
                                      itemBuilder: (context, index) {
                                        final msg = mediaList[index];
                                        final type = msg['messageType'];
                                        final String? lp = msg['localPath'];
                                        final String? url = msg['fileUrl'] ?? msg['onlineUrl'];
                                        final String? thumb = msg['thumbnailLocalPath'] ?? msg['thumbnailUrl'];

                                        if (lp == null && url == null && thumb == null) return const SizedBox.shrink();

                                        return GestureDetector(
                                          onTap: () {
                                            if (type == 'image') {
                                              _showFullImage(context, (lp != null && File(lp).existsSync()) ? lp : url!, (lp != null && File(lp).existsSync()), "media-$index");
                                            } else if (type == 'video') {
                                              _openVideo(url, lp);
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              color: Colors.black26,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  _buildThumbnail(type, lp, thumb, url),
                                                  if (type == 'video') const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 30)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 50),
                        ],
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildThumbnail(String type, String? lp, String? thumb, String? url) {
    if (type == 'image' && lp != null && File(lp).existsSync()) return Image.file(File(lp), fit: BoxFit.cover);
    if (thumb != null && thumb.isNotEmpty) {
      return thumb.startsWith('http') 
          ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (c,u,e) => _fallback(url))
          : Image.file(File(thumb), fit: BoxFit.cover, errorBuilder: (c,u,e) => _fallback(url));
    }
    return _fallback(url);
  }

  Widget _fallback(String? url) {
    if (url != null && url.isNotEmpty && url.startsWith('http')) return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, placeholder: (c,u) => Container(color: Colors.black12));
    return Container(color: Colors.black12, child: const Icon(Icons.image_not_supported_outlined, color: Colors.white10, size: 20));
  }

  Widget _buildInfoTile(String label, String value, IconData icon, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.secondary.withOpacity(0.8), size: 22),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}