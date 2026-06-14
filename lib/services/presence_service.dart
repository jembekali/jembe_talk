// lib/services/presence_service.dart (VERSION 4.3 - BUG FIXED & SECURITY REINFORCED)

import 'dart:async';
import 'dart:io'; 
import 'package:device_info_plus/device_info_plus.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class PresenceService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Database instance ihuje na URL yawe
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: "https://jembe-talk-1-default-rtdb.firebaseio.com/",
  );

  // Streams zo kumenyesha MyApp ibiri kuba
  final StreamController<bool> _banStatusController = StreamController<bool>.broadcast();
  Stream<bool> get banStatusStream => _banStatusController.stream;

  final StreamController<bool> _deviceConflictController = StreamController<bool>.broadcast();
  Stream<bool> get deviceConflictStream => _deviceConflictController.stream;

  // StreamSubscription kugira ngo dushobore kuzifunga neza
  StreamSubscription? _deviceSubscription;
  StreamSubscription? _banSubscription;

  void initialize() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final myStatusRef = _database.ref('status/${user.uid}');
    
    // 🔥 KUGIRA NGO DATABASE IHORE IFITE AMAKURU MASHYA (REAL-TIME)
    await myStatusRef.keepSynced(true);

    // 1. FATA ID Y'IYI TELEFONE
    String currentDeviceId = await _getDeviceId();

    // 2. TEGA AMATWI KURI DEVICE ID IRI MURI DATABASE
    _deviceSubscription?.cancel();
    _deviceSubscription = myStatusRef.child('last_device_id').onValue.listen((event) {
      if (event.snapshot.exists) {
        String? storedId = event.snapshot.value?.toString();
        
        // Niba ID itandukanye n'iy'iyi telefone, menyesha App ngo isohoke
        if (storedId != null && storedId != currentDeviceId) {
          _deviceConflictController.add(true);
        }
      }
    });

    // 3. WANDIKE ID Y'IYI TELEFONE MURI DATABASE
    await myStatusRef.update({
      'last_device_id': currentDeviceId,
      'last_active': ServerValue.timestamp,
    });

    // 4. GENZURA BAN STATUS (Real-time)
    _banSubscription?.cancel();
    _banSubscription = myStatusRef.child('is_blocked').onValue.listen((event) {
      if (event.snapshot.exists) {
        bool isBlocked = (event.snapshot.value == true);
        _banStatusController.add(isBlocked);
      } else {
        _banStatusController.add(false);
      }
    });

    // 5. ONLINE / OFFLINE LOGIC
    _database.ref('.info/connected').onValue.listen((event) {
      if (event.snapshot.value == true) {
        myStatusRef.onDisconnect().update({
          'state': 'offline',
          'last_changed': ServerValue.timestamp,
        });

        myStatusRef.update({
          'state': 'online',
          'last_changed': ServerValue.timestamp,
        });
      }
    });
  }

  // Uburyo bwizewe bwo gufata ID yihariye ya telefone
  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Fingerprint + ID bituma telefone imenya ko ariyo ntakibazo
        return "${androidInfo.model}_${androidInfo.id}"; 
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // HANO HAKOSOWE: Twakoresheje _auth.currentUser aho gukoresha 'user' itariho
        return iosInfo.identifierForVendor ?? "ios_${_auth.currentUser?.uid}";
      }
    } catch (e) {
      return "device_${_auth.currentUser?.uid}";
    }
    return "unknown";
  }

  void forceOffline() {
    final user = _auth.currentUser;
    if (user == null) return;
    _database.ref('status/${user.uid}').update({
      'state': 'offline',
      'last_changed': ServerValue.timestamp,
    });
  }

  void goOffline() {
    forceOffline();
  }

  void goOnline() {
    final user = _auth.currentUser;
    if (user == null) return;
    _database.ref('status/${user.uid}').update({
      'state': 'online',
      'last_changed': ServerValue.timestamp,
    });
  }

  void dispose() {
    _deviceSubscription?.cancel();
    _banSubscription?.cancel();
    _banStatusController.close();
    _deviceConflictController.close();
  }
}

// Instance imwe rukumbi ikoreshwa muri App yose
final presenceService = PresenceService();