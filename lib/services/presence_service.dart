// lib/services/presence_service.dart (VERSION YAKOSOWE - 100% REALTIME)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart'; // <<<--- Ingenzi kuri Firebase.app()
import 'package:firebase_database/firebase_database.dart';

class PresenceService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 1. GUHUZA DATABASE URL (Kugira ngo ihuze na Admin Panel)
  // Ibi bituma ubutumwa n'imikorere biba realtime nta gutinda
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: "https://jembe-talk-1-default-rtdb.firebaseio.com/",
  );

  void initialize() {
    final user = _auth.currentUser;
    if (user == null) return;

    final myStatusRef = _database.ref('status/${user.uid}');
    final connectedRef = _database.ref('.info/connected');

    connectedRef.onValue.listen((event) {
      if (event.snapshot.value == true) {
        
        // A. Iyo internet izimye nabi, Firebase Server imushyira Offline ako kanya
        myStatusRef.onDisconnect().set({
          'state': 'offline',
          'last_changed': ServerValue.timestamp,
        });

        // B. Iyo afunguye App, ahita aba Online ako kanya
        myStatusRef.set({
          'state': 'online',
          'last_changed': ServerValue.timestamp,
        });
      }
    });
  }

  // C. Ihita ikura umuntu online ako kanya (Nta Timer)
  // Ikenewe cyane kuri Delete Account cyangwa Logout
  void forceOffline() {
    final user = _auth.currentUser;
    if (user == null) return;
    _database.ref('status/${user.uid}').set({
      'state': 'offline',
      'last_changed': ServerValue.timestamp,
    });
  }

  // Mu buryo bushya bwa WhatsApp style, goOffline na forceOffline 
  // zikora kimwe (Ako kanya) kugira ngo imikorere yihute
  void goOffline() {
    forceOffline();
  }

  void goOnline() {
    final user = _auth.currentUser;
    if (user == null) return;
    _database.ref('status/${user.uid}').set({
      'state': 'online',
      'last_changed': ServerValue.timestamp,
    });
  }
}