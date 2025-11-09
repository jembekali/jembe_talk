// lib/contact_info_screen.dart (VERSION NSHYA YIHUTA KANDI IKORA NEZA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

  void _showFullImage(BuildContext context, String imageUrl, String heroTag) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullPhotoScreen(
          imageUrl: imageUrl, 
          heroTag: heroTag
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heroTag = 'profile-pic-${widget.userID}';
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.userEmail),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: DatabaseHelper.instance.getJembeContactById(widget.userID),
        builder: (context, localSnapshot) {
          
          final localData = localSnapshot.data;
          
          // Tugiye kugenzura impande zose: uwo ndiko ndaba yaramfunze, canke jewe naramufunze
          return StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('users').doc(_auth.currentUser!.uid).snapshots(),
            builder: (context, currentUserSnapshot) {
              return StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(widget.userID).snapshots(),
                builder: (context, firestoreSnapshot) {
                  
                  if (!firestoreSnapshot.hasData && !localSnapshot.hasData) {
                    return Center(child: CircularProgressIndicator(color: theme.colorScheme.secondary));
                  }

                  final firestoreData = firestoreSnapshot.hasData ? firestoreSnapshot.data!.data() as Map<String, dynamic>? : null;
                  
                  // =========================================================================
                  // ----> IMPINDUKA NSHYA IRI HANO GUSA <----
                  // =========================================================================

                  bool amIBlockedByThisUser = false;
                  if (firestoreData != null) {
                      final blockedUsers = firestoreData['blockedUsers'] as List<dynamic>? ?? [];
                      if (blockedUsers.contains(_auth.currentUser!.uid)) {
                          amIBlockedByThisUser = true;
                      }
                  }

                  bool iHaveBlockedThisUser = false;
                  if (currentUserSnapshot.hasData) {
                    final currentUserData = currentUserSnapshot.data!.data() as Map<String, dynamic>?;
                    final myBlockedUsers = currentUserData?['blockedUsers'] as List<dynamic>? ?? [];
                    if (myBlockedUsers.contains(widget.userID)) {
                      iHaveBlockedThisUser = true;
                    }
                  }

                  final displayName = firestoreData?['displayName'] ?? localData?['displayName'] ?? widget.userEmail;
                  // Twerekana ifoto gusa nimba ata n'umwe yafunze uwundi
                  final photoUrl = (amIBlockedByThisUser || iHaveBlockedThisUser)
                      ? null 
                      : (firestoreData?['photoUrl'] ?? localData?['photoUrl'] ?? widget.photoUrl);
                  
                  // =========================================================================

                  final phoneNumber = firestoreData?['phoneNumber'] ?? localData?['phoneNumber'] ?? "Numero ntiraboneka";
                  final aboutText = firestoreData?['about'] ?? "Hey there! I am using Jembe Talk.";
                  
                  final bool areNamesDifferent = displayName != widget.userEmail;

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
                                    onTap: () { if (photoUrl != null) _showFullImage(context, photoUrl, heroTag); },
                                    child: Hero(
                                      tag: heroTag,
                                      child: CircleAvatar(
                                        radius: 50,
                                        backgroundColor: theme.colorScheme.secondary,
                                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                        child: photoUrl == null ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(widget.userEmail, style: TextStyle(fontSize: 22, color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis,),
                                        const SizedBox(height: 8),
                                        Text(phoneNumber, style: TextStyle(fontSize: 16, color: theme.textTheme.bodyMedium?.color),),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 30),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildActionButton(context, Icons.chat, "Chat", () {
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
                                       Text("Izina ryo kuri Profile", style: TextStyle(color: theme.colorScheme.secondary, fontSize: 14, fontWeight: FontWeight.w500)),
                                       const SizedBox(height: 8),
                                       Text(displayName, style: TextStyle(fontSize: 16, color: theme.textTheme.bodyLarge?.color)),
                                       const SizedBox(height: 20),
                                     ],
                                     Text("About", style: TextStyle(color: theme.colorScheme.secondary, fontSize: 14, fontWeight: FontWeight.w500)),
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.secondary,
            ),
            child: Icon(icon, color: theme.colorScheme.onSecondary, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text( label, style: TextStyle(color: theme.colorScheme.secondary, fontSize: 14), )
      ],
    );
  }
}