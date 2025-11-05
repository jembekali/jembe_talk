// lib/models/call_data.dart (YAKOSOWE NEZA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jembe_talk/services/database_helper.dart';

class CallData {
  final String callId;
  final String callerId;
  final String callerName;
  final String receiverId;
  final String receiverName;
  final String status;
  final bool isVideo;
  final Timestamp timestamp;
  final bool seenByReceiver;

  CallData({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    required this.receiverName,
    required this.status,
    required this.isVideo,
    required this.timestamp,
    required this.seenByReceiver,
  });

  factory CallData.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return CallData(
      callId: doc.id,
      // Twakosoye 'callerID' na 'receiverID' kugira ngo bihure na Firebase
      callerId: data['callerId'] ?? '',
      callerName: data['callerName'] ?? '',
      receiverId: data['receiverId'] ?? '',
      receiverName: data['receiverName'] ?? '',
      status: data['status'] ?? 'unknown',
      isVideo: data['isVideo'] ?? false,
      timestamp: data['timestamp'] ?? Timestamp.now(),
      seenByReceiver: data['seenByReceiver'] ?? true,
    );
  }
  
  factory CallData.fromMap(Map<String, dynamic> map) {
    return CallData(
      callId: map[DatabaseHelper.colCallId],
      callerId: map[DatabaseHelper.colCallerId],
      callerName: map[DatabaseHelper.colCallerName],
      receiverId: map[DatabaseHelper.colReceiverId],
      receiverName: map[DatabaseHelper.colReceiverName],
      status: map[DatabaseHelper.colStatus],
      isVideo: map[DatabaseHelper.colIsVideo] == 1,
      timestamp: Timestamp.fromMillisecondsSinceEpoch(map[DatabaseHelper.columnTimestamp]),
      seenByReceiver: map[DatabaseHelper.colSeenByReceiver] == 1,
    );
  }

  // ==================================================================
  // <<<--- IKI GIKORWA CYA 'toMap' NI CYO TWONGEREYEMO ---<<<
  // ==================================================================
  Map<String, dynamic> toMap() {
    return {
      DatabaseHelper.colCallId: callId,
      DatabaseHelper.colCallerId: callerId,
      DatabaseHelper.colCallerName: callerName,
      DatabaseHelper.colReceiverId: receiverId,
      DatabaseHelper.colReceiverName: receiverName,
      DatabaseHelper.colStatus: status,
      DatabaseHelper.colIsVideo: isVideo ? 1 : 0,
      DatabaseHelper.columnTimestamp: timestamp.millisecondsSinceEpoch,
      DatabaseHelper.colSeenByReceiver: seenByReceiver ? 1 : 0,
    };
  }
}