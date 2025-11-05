// lib/services/message_status_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class MessageStatusService {
  // Singleton pattern: Kugira habeho instance imwe gusa y'iyi service
  MessageStatusService._privateConstructor();
  static final MessageStatusService instance = MessageStatusService._privateConstructor();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _statusListener;

  // Iyi method izahamagarwa muri HomeScreen iyo umukoresha yinjiye
  void initialize(String currentUserId) {
    // Turetse kumva ibya kera kugira ngo bitavanga
    _statusListener?.cancel();

    // Ubu tugiye kumva ubutumwa BWOSE bwinjira muri application
    // aho bwakuriwe hose, igihe cyose bwinjiye.
    _statusListener = _firestore
        .collectionGroup('messages')
        .where('receiverID', isEqualTo: currentUserId) // Ubutumwa bwanje ngenewe
        .where('status', isEqualTo: 'sent') // Kandi bukiri 'sent'
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) {
        // Nta butumwa bushya bukirimo guhindurwa
        return;
      }
      
      // Twabonye ubutumwa bumwe canke bwinshi bukiri 'sent'
      // Tugiye kubuhindurira status rimwe tukoresheje "Batch"
      WriteBatch batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        debugPrint("SERVICE: Ubutumwa ${doc.id} buhinduwe 'delivered'");
        batch.update(doc.reference, {'status': 'delivered'});
      }
      
      // Turungika impinduka zose kuri Firestore
      batch.commit().catchError((e) {
        debugPrint("SERVICE ERROR: Habaye ikosa mu guhindura status mo 'delivered': $e");
      });
    });
  }

  // Iyi method izahamagarwa iyo umukoresha asohotse (logout)
  void dispose() {
    _statusListener?.cancel();
    _statusListener = null;
  }
}