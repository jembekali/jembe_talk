// lib/services/presence_service.dart

import 'dart:async'; // <<< ONGERAMO IYI IMPORT
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class PresenceService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  Timer? _offlineTimer; // <<< IYI NI ISaha NSHASHA

  void initialize() {
    final user = _auth.currentUser;
    if (user == null) return;

    final myStatusRef = _database.ref('status/${user.uid}');
    final connectedRef = _database.ref('.info/connected');

    connectedRef.onValue.listen((event) {
      if (event.snapshot.value == true) {
        final conStatus = {
          'state': 'online',
          'last_changed': ServerValue.timestamp,
        };
        myStatusRef.set(conStatus);

        myStatusRef.onDisconnect().set({
          'state': 'offline',
          'last_changed': ServerValue.timestamp,
        });
      }
    });
  }

  void goOffline() {
    // Aho guhita twandika "offline", dutanguza isaha y'iminota ibiri
    _offlineTimer?.cancel();
    _offlineTimer = Timer(const Duration(minutes: 2), () {
      final user = _auth.currentUser;
      if (user == null) return;
      
      final myStatusRef = _database.ref('status/${user.uid}');
      myStatusRef.set({
        'state': 'offline',
        'last_changed': ServerValue.timestamp,
      });
    });
  }

  void goOnline() {
    // Niba hari isaha yari yatanguye kubara, turayihagarika
    _offlineTimer?.cancel();

    final user = _auth.currentUser;
    if (user == null) return;
    
    final myStatusRef = _database.ref('status/${user.uid}');
    myStatusRef.set({
      'state': 'online',
      'last_changed': ServerValue.timestamp,
    });
  }
}