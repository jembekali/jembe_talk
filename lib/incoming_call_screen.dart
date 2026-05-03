import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart'; // Yakuweho

class IncomingCallScreen extends StatelessWidget {
  final String callID;
  final String callerName;
  final bool isVideoCall;

  const IncomingCallScreen({
    super.key,
    required this.callID,
    required this.callerName,
    required this.isVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Nturi muri konte")));
    }

    // Zego UIKit yakuweho muri V1
    return Scaffold(
      body: Center(
        child: Text("Iihamagara rivuye kuri $callerName rirahagaritswe."),
      ),
    );
  }
}