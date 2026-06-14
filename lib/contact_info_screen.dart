// lib/contact_info_screen.dart (VERSION 2.9 - FIXED SAVE CONTACT METHOD)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/full_photo_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jembe_talk/widgets/chat/chat_media_widgets.dart';
// Twakuyeho url_launcher kuko tutacyikoresha hano
import 'package:flutter_contacts/flutter_contacts.dart';

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
  
  late Future<List<Map<String, dynamic>>> _mediaFuture;
  late Future<Map<String, dynamic>?> _localContactFuture;

  @override
  void initState() {
    super.initState();
    _mediaFuture = DatabaseHelper.instance.getMediaMessages(_getChatRoomID(), limit: 40);
    _localContactFuture = DatabaseHelper.instance.getJembeContactById(widget.userID);
  }

  String _getChatRoomID() {
    List<String> ids = [_auth.currentUser!.uid, widget.userID];
    ids.sort();
    return ids.join('_');
  }

  // 🔥 FIXED SAVE CONTACT METHOD
  Future<void> _saveToContacts(String displayName, String phone) async {
    try {
      if (await FlutterContacts.requestPermission()) {
        final newContact = Contact()
          ..name.first = displayName
          ..phones = [Phone(phone)];

        // KOSORA HANO: openExternalInsert niyo izina rikwiye
        await FlutterContacts.openExternalInsert(newContact);
        
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Permission denied.")),
          );
        }
      }
    } catch (e) {
      debugPrint("Save Contact Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);
    final heroTag = 'profile-pic-${widget.userID}';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: const Text("Contact Info", style: TextStyle(fontSize: 18)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(widget.userID).snapshots(),
        builder: (context, firestoreSnapshot) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: _localContactFuture,
            builder: (context, localSnapshot) {
              
              final firestoreData = firestoreSnapshot.data?.data() as Map<String, dynamic>?;
              final localData = localSnapshot.data;

              final displayName = firestoreData?['displayName'] ?? localData?['displayName'] ?? widget.userEmail;
              final phoneNumber = firestoreData?['phoneNumber'] ?? localData?['phoneNumber'] ?? "...";
              final aboutText = firestoreData?['about'] ?? "Hey there! I am using Jembe Talk.";
              final photoUrl = firestoreData?['photoUrl'] ?? localData?['photoUrl'] ?? widget.photoUrl;
              final localPhotoPath = localData?['localPhotoPath'] as String?;

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        _buildProfileHeader(photoUrl, localPhotoPath, displayName, phoneNumber, heroTag, theme, lang),
                        const Divider(indent: 30, endIndent: 30, color: Colors.white10, height: 40),
                        _buildInfoSection(aboutText, phoneNumber, theme),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Text("Media, Links, and Docs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _mediaFuture,
                      builder: (context, mediaSnap) {
                        if (!mediaSnap.hasData || mediaSnap.data!.isEmpty) {
                          return const SliverToBoxAdapter(child: Center(child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text("No media shared", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          )));
                        }
                        final mediaList = mediaSnap.data!;
                        return SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, crossAxisSpacing: 5, mainAxisSpacing: 5,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final msg = mediaList[index];
                              return RepaintBoundary(child: _MediaTile(msg: msg, index: index));
                            },
                            childCount: mediaList.length,
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 50)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(String? url, String? path, String name, String phone, String hero, ThemeData theme, LanguageProvider lang) {
    ImageProvider? img;
    if (path != null && path.isNotEmpty) {
      img = ResizeImage(FileImage(File(path)), width: 350, height: 350);
    } else if (url != null && url.isNotEmpty) {
      img = ResizeImage(CachedNetworkImageProvider(url), width: 350, height: 350);
    }

    return Column(
      children: [
        GestureDetector(
          onTap: () { 
            if (img != null) {
              Navigator.push(context, MaterialPageRoute(builder: (c) => FullPhotoScreen(
                imageUrl: (path != null && path.isNotEmpty) ? path : url!, 
                isLocalFile: path != null && path.isNotEmpty, 
                heroTag: hero
              ))); 
            }
          },
          child: Hero(
            tag: hero, 
            child: CircleAvatar(
              radius: 65, 
              backgroundColor: theme.colorScheme.surface,
              backgroundImage: img, 
              child: img == null ? const Icon(Icons.person, size: 60) : null
            )
          ),
        ),
        const SizedBox(height: 15),
        Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(phone, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _actionBtn(Icons.chat_bubble_outline, lang.t('contact_chat_btn') ?? "Message", () => Navigator.pop(context), theme),
            const SizedBox(width: 12),
            _actionBtn(Icons.person_add_alt, "Save", () => _saveToContacts(name, phone), theme, isOutlined: true),
          ],
        ),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback tap, ThemeData theme, {bool isOutlined = false}) {
    return ElevatedButton.icon(
      onPressed: tap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isOutlined ? Colors.transparent : theme.colorScheme.primary,
        foregroundColor: isOutlined ? theme.colorScheme.primary : Colors.white,
        side: isOutlined ? BorderSide(color: theme.colorScheme.primary) : null,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      ),
    );
  }

  Widget _buildInfoSection(String about, String phone, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _infoRow(Icons.info_outline, about, "About"),
          const SizedBox(height: 15),
          _infoRow(Icons.phone_android, phone, "Phone"),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String val, String label) {
    return Row(children: [
      Icon(icon, color: Colors.teal, size: 22),
      const SizedBox(width: 15),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(val, style: const TextStyle(fontSize: 15)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      )
    ]);
  }
}

class _MediaTile extends StatelessWidget {
  final Map<String, dynamic> msg;
  final int index;
  const _MediaTile({required this.msg, required this.index});

  @override
  Widget build(BuildContext context) {
    final type = msg['messageType'];
    final String? lp = msg['localPath'];
    final String? url = msg['fileUrl'] ?? msg['onlineUrl'];
    final String? thumb = msg['thumbnailLocalPath'] ?? msg['thumbnailUrl'];

    return GestureDetector(
      onTap: () {
        if (type == 'image') {
          Navigator.push(context, MaterialPageRoute(builder: (c) => FullPhotoScreen(imageUrl: (lp != null) ? lp : url!, isLocalFile: lp != null, heroTag: "media-$index")));
        } else if (type == 'video') {
          String? path = (lp != null) ? lp : url;
          if (path != null) {
            Navigator.push(context, MaterialPageRoute(builder: (c) => FullScreenVideoPlayer(videoUrl: path, startAt: Duration.zero)));
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(lp, thumb, url),
            if (type == 'video') const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 30)),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String? lp, String? thumb, String? url) {
    if (lp != null && lp.isNotEmpty) return Image.file(File(lp), fit: BoxFit.cover, errorBuilder: (c,e,s) => _net(url), cacheWidth: 200);
    if (thumb != null && thumb.isNotEmpty) {
      return thumb.startsWith('http') ? _net(thumb) : Image.file(File(thumb), fit: BoxFit.cover, errorBuilder: (c,e,s) => _net(url), cacheWidth: 200);
    }
    return _net(url);
  }

  Widget _net(String? url) {
    if (url == null || url.isEmpty) return Container(color: Colors.black12);
    return CachedNetworkImage(
      imageUrl: url, 
      fit: BoxFit.cover, 
      memCacheWidth: 200,
      placeholder: (c,u) => Container(color: Colors.white.withOpacity(0.1))
    );
  }
}