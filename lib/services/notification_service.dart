// lib/services/notification_service.dart (VERSION 11.6 - STABLE)

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/firebase_options.dart';

// 🔥 1. BACKGROUND HANDLER
// Iyi function isigaye gusa ikuraho notification cyangwa igafasha mu gufungura App
@pragma('vm:entry-point')
Future<void> notificationTapBackground(
    NotificationResponse notificationResponse) async {
  // Hano ubu nta kintu gihambaye gikorerwa inyuma kuko "Reply" twayikuyeho.
  // Ibi bituma nta bibazo bya SSL cyangwa Firestore byongera kubaho mu mizi.
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Iyo akanze kuri notification cyangwa kuri buto "INJIRA MURI CHAT"
        // Hano ushobora gushyira logic yo gufungura chat screen niba bikenewe
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  static Future<void> showChatNotification(RemoteMessage message) async {
    final data = message.data;
    final String roomId = data['roomId'] ?? "default";
    final String senderId = data['senderID'] ?? "";
    final String senderName = data['title'] ?? "Jembe Talk";
    final String content = data['body'] ?? '';

    // 🎨 MESSAGING STYLE (Kugira ngo hagaragare amateka y'ubutumwa)
    List<Message> history = [];
    try {
      final dbMsgs =
          await DatabaseHelper.instance.getMessagesForChatRoom(roomId);
      final recent = dbMsgs.reversed.take(5).toList().reversed;
      for (var m in recent) {
        bool isMe = m[DatabaseHelper.columnSenderID] != senderId;
        history.add(Message(
            m[DatabaseHelper.columnMessage] ?? "",
            DateTime.fromMillisecondsSinceEpoch(
                m[DatabaseHelper.columnTimestamp]),
            Person(
                name: isMe ? 'You' : senderName,
                key: m[DatabaseHelper.columnSenderID])));
      }
    } catch (_) {
      history.add(Message(
          content, DateTime.now(), Person(name: senderName, key: senderId)));
    }

    final messagingStyle = MessagingStyleInformation(
      const Person(name: 'You', key: 'me'),
      conversationTitle: senderName,
      messages: history,
    );

    // 🚀 ACTION BUTTONS - HANO HAKUWEHO "ISHURA"
    final actions = [
      const AndroidNotificationAction(
        'open_chat', 'INJIRA MURI CHAT',
        showsUserInterface: true, // Iyi buto izajya ifungura App
        cancelNotification: true,
      ),
    ];

    await _notificationsPlugin.show(
      roomId.hashCode,
      senderName,
      content,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'jembe_talk_chats_v4',
          'Chat Messages',
          styleInformation: messagingStyle,
          actions: actions, // Hasigayemo buto imwe gusa
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          groupKey: 'com.jembe.talk.CHAT_GROUP',
          color: const Color(0xFF1C2935),
          largeIcon: const DrawableResourceAndroidBitmap('ic_launcher'),
        ),
      ),
      payload: "$roomId|$senderId",
    );
  }

  static Future<void> showNotification(RemoteMessage message) async {
    await _notificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? "Jembe Talk",
      message.notification?.body ?? "",
      const NotificationDetails(
          android: AndroidNotificationDetails('jembe_talk_official', 'Updates',
              importance: Importance.max)),
    );
  }
}
