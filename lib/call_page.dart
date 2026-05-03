import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart'; // Yakuweho

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

    // Zego UIKit yakuweho by'agateganyo
    /*
    final config = isVideoCall
        ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
        : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();
    */

    return Scaffold(
      appBar: AppBar(title: Text(isVideoCall ? "Video Call" : "Voice Call")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.call_end, size: 100, color: Colors.red),
            const SizedBox(height: 20),
            Text("Guhamagara $receiverName ntibishoboka muri iyi Version."),
          ],
        ),
      ),
    );
  }
}