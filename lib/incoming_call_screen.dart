// lib/incoming_call_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

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

    return ZegoUIKitPrebuiltCall(
      appID: 1533659828,
      appSign: "19e12086e41e57c8d9e26214152e93b455047b3b3a2777f98822080756775f0a",
      userID: currentUser.uid,
      userName: currentUser.email ?? "User",
      callID: callID,
      config: isVideoCall
          ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
          : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall(),
    );
  }
}