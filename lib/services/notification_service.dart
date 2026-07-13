import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Request permission
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Fetch FCM Token
      String? token = await messaging.getToken();
      if (token != null) {
        await _uploadFcmToken(token);
      }

      // Listen for token refreshes
      messaging.onTokenRefresh.listen((newToken) async {
        await _uploadFcmToken(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint("Received foreground message: ${message.notification?.title}");
      });

      _initialized = true;
    } catch (e) {
      debugPrint("FCM initialization failed: $e");
    }
  }

  Future<void> _uploadFcmToken(String token) async {
    try {
      await ApiService.patch('/delivery/profile/', {
        'fcm_token': token,
      });
      debugPrint("FCM token successfully registered to backend.");
    } catch (e) {
      debugPrint("Failed to register FCM token: $e");
    }
  }
}
