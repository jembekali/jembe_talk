// lib/call_page.dart (CODE YA NYUMA KANDI YOROSHYE)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/constants.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

class CallPage extends StatelessWidget {
  final String callID;
  final String receiverName;
  final bool isVideoCall;

  const CallPage({
    super.key,
    required this.callID,
    required this.receiverName,
    required this.isVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text("Kugira ngo uhamagare, banza winjire."),
        ),
      );
    }

    // Iyi ni yo config yonyine dukeneye.
    // Irahitamo hagati ya Video na Audio, hanyuma package ikikora ibindi.
    final config = isVideoCall
        ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
        : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();

    return ZegoUIKitPrebuiltCall(
      appID: appID,
      appSign: appSign,
      userID: currentUser.uid,
      userName: currentUser.email ?? "Jembe User",
      callID: callID,
      config: config,
    );
  }
}