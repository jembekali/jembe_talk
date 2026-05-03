// lib/services/notification_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Iteguze Android Settings (Hano hashizwe izina rya icon ririndwi rya ic_notification)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_notification'); 

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );

    await _notificationsPlugin.initialize(initializationSettings);

    // 2. CHANNEL YA BROADCAST (ADMIN)
    const AndroidNotificationChannel officialChannel = AndroidNotificationChannel(
      'jembe_talk_official',
      'Official Updates', 
      importance: Importance.max,
      playSound: true,
    );

    // 3. CHANNEL YA CHATS (IYI NI YO YAGIYEHO IKIBAZO)
    const AndroidNotificationChannel chatChannel = AndroidNotificationChannel(
      'jembe_talk_chats',
      'Direct Messages',
      importance: Importance.max,
      playSound: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(officialChannel);
      await androidImplementation.createNotificationChannel(chatChannel);
    }
  }

  static void showNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      _notificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'jembe_talk_official',
            'Official Updates',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  }
}