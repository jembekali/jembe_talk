import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:jembe_talk/chat_screen.dart';
import 'package:jembe_talk/full_photo_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';

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

  void _printDebug(String message) {
    if (kDebugMode) {
      print("[CONTACT_INFO_DEBUG] $message");
    }
  }

  void _showFullImage(BuildContext context, String imagePathOrUrl, bool isLocal, String heroTag) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullPhotoScreen(
          imageUrl: imagePathOrUrl, 
          isLocalFile: isLocal,
          heroTag: heroTag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _printDebug("--- Kwubaka Page ya Contact Info ---");
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context); // Provider
    final heroTag = 'profile-pic-${widget.userID}';
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.userEmail),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(_auth.currentUser!.uid).snapshots(),
        builder: (context, currentUserSnapshot) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: DatabaseHelper.instance.getJembeContactById(widget.userID),
            builder: (context, localSnapshot) {
              return StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(widget.userID).snapshots(),
                builder: (context, firestoreSnapshot) {
                  
                  if (!firestoreSnapshot.hasData && !localSnapshot.hasData) {
                    return Center(child: CircularProgressIndicator(color: theme.colorScheme.secondary));
                  }

                  _printDebug("--- Gukurura amakuru y'umukoresha ---");
                  final firestoreData = firestoreSnapshot.hasData ? firestoreSnapshot.data!.data() as Map<String, dynamic>? : null;
                  final localData = localSnapshot.data;
                  _printDebug("Amakuru yo muri Firestore: $firestoreData");
                  _printDebug("Amakuru yo muri Local DB: $localData");
                  _printDebug("PhotoURL yaje na Widget: ${widget.photoUrl}");

                  final displayName = firestoreData?['displayName'] ?? localData?['displayName'] ?? widget.userEmail;
                  final phoneNumber = firestoreData?['phoneNumber'] ?? localData?['phoneNumber'] ?? lang.t('contact_no_number');
                  final aboutText = firestoreData?['about'] ?? lang.t('contact_default_about');
                  final photoUrl = firestoreData?['photoUrl'] ?? localData?['photoUrl'] ?? widget.photoUrl;
                  final localPhotoPath = localData?['localPhotoPath'] as String?;
                  
                  _printDebug("Final Photo URL used: $photoUrl");
                  _printDebug("Final Local Photo Path used: $localPhotoPath");
                  
                  final bool areNamesDifferent = displayName != widget.userEmail;
                  
                  ImageProvider? profileImageProvider;
                  String? imagePathForFullScreen;
                  bool isImageLocal = false;

                  if (localPhotoPath != null && File(localPhotoPath).existsSync()) {
                    _printDebug("Turiko dukoresha ifoto yo muri Local Path: $localPhotoPath");
                    profileImageProvider = FileImage(File(localPhotoPath));
                    imagePathForFullScreen = localPhotoPath;
                    isImageLocal = true;
                  } else if (photoUrl != null) {
                    _printDebug("Turiko dukoresha ifoto yo kuri Network: $photoUrl");
                    profileImageProvider = NetworkImage(photoUrl);
                    imagePathForFullScreen = photoUrl;
                    isImageLocal = false;
                  } else {
                    _printDebug("Nta foto ihari, turerekana Icon.");
                  }
                  
                  return AnimationLimiter(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: AnimationConfiguration.toStaggeredList(
                            duration: const Duration(milliseconds: 375),
                            childAnimationBuilder: (widget) => SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(child: widget),
                            ),
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: () { if (imagePathForFullScreen != null) _showFullImage(context, imagePathForFullScreen, isImageLocal, heroTag); },
                                    child: Hero(
                                      tag: heroTag,
                                      child: CircleAvatar(
                                        radius: 50,
                                        backgroundColor: theme.colorScheme.secondary,
                                        backgroundImage: profileImageProvider,
                                        child: profileImageProvider == null ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(widget.userEmail, style: TextStyle(fontSize: 22, color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis,),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 30),
                              
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildActionButton(context, Icons.chat, lang.t('contact_chat_btn'), () { // "Chat"
                                     Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (context) => ChatScreenWrapper(
                                        receiverEmail: widget.userEmail,
                                        receiverID: widget.userID)
                                      )
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 30),
                              const Divider(color: Colors.white24),
                              const SizedBox(height: 10),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration( color: theme.colorScheme.surface.withAlpha(100), borderRadius: BorderRadius.circular(12.0), ),
                                child: Column(
                                   crossAxisAlignment: CrossAxisAlignment.start,
                                   children: [
                                     if (areNamesDifferent) ...[
                                       Text(lang.t('contact_name_label'), style: TextStyle(color: theme.colorScheme.secondary, fontSize: 14, fontWeight: FontWeight.w500)), // "Izina ryo kuri Profile"
                                       const SizedBox(height: 8),
                                       Text(displayName, style: TextStyle(fontSize: 16, color: theme.textTheme.bodyLarge?.color)),
                                       const SizedBox(height: 20),
                                     ],
                                     Text(lang.t('contact_phone_label'), style: TextStyle(color: theme.colorScheme.secondary, fontSize: 14, fontWeight: FontWeight.w500)), // "Numero ya Telefone"
                                     const SizedBox(height: 8),
                                     Text(phoneNumber, style: TextStyle(fontSize: 16, color: theme.textTheme.bodyLarge?.color)),
                                     const SizedBox(height: 20),
                                     Text(lang.t('contact_about_label'), style: TextStyle(color: theme.colorScheme.secondary, fontSize: 14, fontWeight: FontWeight.w500)), // "About"
                                     const SizedBox(height: 8),
                                     Text(aboutText, style: TextStyle(fontSize: 16, color: theme.textTheme.bodyLarge?.color)),
                                   ]
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, VoidCallback onPressed) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.secondary),
            child: Icon(icon, color: theme.colorScheme.onSecondary, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text( label, style: TextStyle(color: theme.colorScheme.secondary, fontSize: 14), )
      ],
    );
  }
}