// lib/models/home_models.dart
import 'package:flutter/material.dart';

class TabItem {
  final String id;
  final String label;
  final IconData icon;
  final Widget screen;
  TabItem({required this.id, required this.label, required this.icon, required this.screen});
}

class ChatData {
  final String userId;
  final String displayName;
  final String? photoUrl, localPhotoPath, phoneNumber, lastMessageContent, lastMessageType, lastMessageStatus, lastMessageSenderId;
  final int lastMessageTimestamp;
  final List<dynamic> blockedUsers;
  final int unreadCount; // ✅ Twongeyemo iyi kuko UI iyikenera

  ChatData({
    required this.userId, 
    required this.displayName, 
    this.photoUrl, 
    this.localPhotoPath, 
    required this.lastMessageTimestamp, 
    this.phoneNumber, 
    this.blockedUsers = const [],
    this.lastMessageContent, 
    this.lastMessageType, 
    this.lastMessageStatus, 
    this.lastMessageSenderId,
    this.unreadCount = 0,
  });

  // ✅ Iyi niyo ikura amakuru muri SQL iyashyira muri uyu model
  factory ChatData.fromSqlMap(Map<String, dynamic> map, {int unread = 0}) {
    return ChatData(
      userId: map['userId']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? 'User',
      photoUrl: map['photoUrl'],
      localPhotoPath: map['localPhotoPath'],
      phoneNumber: map['phoneNumber'],
      lastMessageTimestamp: map['timestamp'] ?? 0,
      unreadCount: unread,
    );
  }
}