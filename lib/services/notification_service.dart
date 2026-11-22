// lib/services/notification_service.dart
//
// Vindara — Single-Lifecycle FCM Notification Service & Deep-Linking
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #4 — Firestore is source of truth. Opening an alert navigates ONLY
//              using emergencyId; data payload is never treated as authoritative state.
//   Rule #5 — Full handling of foreground, background, and terminated cold-starts.
//              Honest handling of OS force-stop limitations.
//   Rule #6 — Single-lifecycle management; all subscriptions cancelled in dispose().
//   Rule #9 — Minimal payload handling without sensitive PII.

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level background isolate handler required by firebase_messaging (Rule #5).
/// Must be a top-level function with `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // If running in an unconfigured test harness, ignore
  }

  // Background messages wake the OS; minimal logging only.
  debugPrint(
      'FCM background message received: ID=${message.messageId}, data=${message.data}');
}

/// Incoming notification event for in-app heads-up banners or UI state.
class InAppAlertEvent {
  final String emergencyId;
  final String? type;
  final String title;
  final String body;

  const InAppAlertEvent({
    required this.emergencyId,
    this.type,
    required this.title,
    required this.body,
  });
}

/// Core notification service managing FCM tokens, message streams,
/// and deep-link routing targets.
class NotificationService {
  final FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin? _localNotifications;

  final StreamController<String> _deepLinkController =
      StreamController<String>.broadcast();
  final StreamController<InAppAlertEvent> _inAppAlertController =
      StreamController<InAppAlertEvent>.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  String? _fcmToken;

  NotificationService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  })  : _messaging = messaging,
        _localNotifications = localNotifications;

  /// Stream of route paths to navigate to (e.g. `/emergency/<id>`) on notification tap.
  Stream<String> get deepLinkStream => _deepLinkController.stream;

  /// Stream of in-app alert events triggered when a push arrives while app is in foreground.
  Stream<InAppAlertEvent> get inAppAlertStream => _inAppAlertController.stream;

  /// Current cached FCM token for this device.
  String? get fcmToken => _fcmToken;

  /// Initializes notification channels, permissions, and all message streams.
  /// Returns a pending deep-link emergencyId if launched from terminated cold-start.
  Future<String?> init() async {
    final messaging = _messaging ?? FirebaseMessaging.instance;
    final localNotifications =
        _localNotifications ?? FlutterLocalNotificationsPlugin();

    // 1. Request notification permissions (iOS & Android 13+)
    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e) {
      debugPrint('Notification permission request error: $e');
    }

    // 2. Initialize local notifications plugin for foreground heads-up banner
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _handlePayloadEmergencyId(payload);
          }
        },
      );

      // Create Android emergency notification channel
      const androidChannel = AndroidNotificationChannel(
        'emergency_alerts_channel',
        'Emergency Alerts',
        description: 'Urgent civilian emergency notifications near you.',
        importance: Importance.max,
        playSound: true,
      );

      await localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    } catch (e) {
      debugPrint('Local notifications initialization skipped or failed: $e');
    }

    // 3. Register background handler
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Background handler registration: $e');
    }

    // 4. Retrieve initial device token and listen for token refresh
    try {
      _fcmToken = await messaging.getToken();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
      });
    } catch (e) {
      debugPrint('FCM getToken error: $e');
    }

    // 5. Handle Foreground message (Rule #5 & #6)
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      final emergencyId = extractEmergencyId(message.data);
      if (emergencyId == null) return;

      final title = message.notification?.title ?? '🚨 HELP NEEDED NEAR YOU';
      final body = message.notification?.body ??
          'Someone nearby requested assistance. Tap to view details.';

      // Emit in-app alert event for reactive banner
      _inAppAlertController.add(
        InAppAlertEvent(
          emergencyId: emergencyId,
          type: message.data['type'] as String?,
          title: title,
          body: body,
        ),
      );

      // Show native heads-up banner if not suppressed
      _showLocalNotification(
        id: emergencyId.hashCode,
        title: title,
        body: body,
        payload: emergencyId,
      );
    });

    // 6. Handle Background Notification Tap (Rule #5)
    _openedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final emergencyId = extractEmergencyId(message.data);
      if (emergencyId != null) {
        _handlePayloadEmergencyId(emergencyId);
      }
    });

    // 7. Check Terminated Cold-Start message (Rule #5)
    try {
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final emergencyId = extractEmergencyId(initialMessage.data);
        return emergencyId;
      }
    } catch (e) {
      debugPrint('getInitialMessage error: $e');
    }

    return null;
  }

  void _handlePayloadEmergencyId(String emergencyId) {
    if (!_deepLinkController.isClosed) {
      _deepLinkController.add('/emergency/$emergencyId');
    }
  }

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      final local = _localNotifications ?? FlutterLocalNotificationsPlugin();
      const androidDetails = AndroidNotificationDetails(
        'emergency_alerts_channel',
        'Emergency Alerts',
        channelDescription:
            'Urgent civilian emergency notifications near you.',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await local.show(id, title, body, details, payload: payload);
    } catch (_) {
      // Local notification presentation is optional in non-mobile test harnesses
    }
  }

  /// Helper to safely extract and validate emergencyId from any FCM data payload (Rule #4 & #9).
  static String? extractEmergencyId(Map<String, dynamic>? data) {
    if (data == null) return null;
    final id = data['emergencyId'];
    if (id is String && id.trim().isNotEmpty) {
      return id.trim();
    }
    return null;
  }

  /// Cancels all active subscriptions and closes streams (Rule #6).
  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _deepLinkController.close();
    await _inAppAlertController.close();
  }
}

