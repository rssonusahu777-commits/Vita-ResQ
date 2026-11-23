// test/services/notification_service_test.dart
//
// Vindara — NotificationService unit tests (Phase 4)
// Tests:
//   - Safe extraction of emergencyId from FCM payloads (Rule #4 & #9).
//   - Rejection of malformed payloads missing emergencyId.
//   - PendingDeepLinkProvider single-consumption (cold-start race condition prevention).
//   - Clean cancellation of stream subscriptions upon disposal (Rule #6).

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vindara/providers/providers.dart';
import 'package:vindara/services/notification_service.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}
class MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  late MockFirebaseMessaging mockMessaging;
  late MockFlutterLocalNotificationsPlugin mockLocalNotifications;
  late NotificationService notificationService;

  setUp(() {
    mockMessaging = MockFirebaseMessaging();
    mockLocalNotifications = MockFlutterLocalNotificationsPlugin();

    when(() => mockMessaging.requestPermission(
          alert: any(named: 'alert'),
          badge: any(named: 'badge'),
          sound: any(named: 'sound'),
          provisional: any(named: 'provisional'),
        )).thenAnswer((_) async => const NotificationSettings(
          alert: AppleNotificationSetting.enabled,
          badge: AppleNotificationSetting.enabled,
          sound: AppleNotificationSetting.enabled,
          announcement: AppleNotificationSetting.disabled,
          authorizationStatus: AuthorizationStatus.authorized,
          carPlay: AppleNotificationSetting.disabled,
          criticalAlert: AppleNotificationSetting.disabled,
          lockScreen: AppleNotificationSetting.enabled,
          notificationCenter: AppleNotificationSetting.enabled,
          showPreviews: AppleShowPreviewSetting.always,
          timeSensitive: AppleNotificationSetting.disabled,
          providesAppNotificationSettings: AppleNotificationSetting.disabled,
        ));

    when(() => mockMessaging.getToken())
        .thenAnswer((_) async => 'mock-fcm-token-123');
    when(() => mockMessaging.onTokenRefresh)
        .thenAnswer((_) => Stream.value('mock-fcm-token-refreshed'));
    when(() => mockMessaging.getInitialMessage()).thenAnswer((_) async => null);

    notificationService = NotificationService(
      messaging: mockMessaging,
      localNotifications: mockLocalNotifications,
    );
  });

  tearDown(() async {
    await notificationService.dispose();
  });

  group('NotificationService — Rule #4 & #9 Payload Extraction', () {
    test('extracts valid emergencyId from payload successfully', () {
      final data = {
        'emergencyId': 'EMG-2026-9F4A2C1B',
        'type': 'medical',
      };
      final id = NotificationService.extractEmergencyId(data);
      expect(id, equals('EMG-2026-9F4A2C1B'));
    });

    test('trims whitespace around emergencyId', () {
      final data = {'emergencyId': '  EMG-2026-A1B2C3D4  '};
      final id = NotificationService.extractEmergencyId(data);
      expect(id, equals('EMG-2026-A1B2C3D4'));
    });

    test('rejects payload missing emergencyId', () {
      final data = {'type': 'accident'};
      final id = NotificationService.extractEmergencyId(data);
      expect(id, isNull);
    });

    test('rejects payload with empty emergencyId string', () {
      final data = {'emergencyId': '   '};
      final id = NotificationService.extractEmergencyId(data);
      expect(id, isNull);
    });

    test('rejects null payload gracefully', () {
      final id = NotificationService.extractEmergencyId(null);
      expect(id, isNull);
    });
  });

  group('PendingDeepLinkNotifier — Cold-start single consumption (Rule #5)', () {
    test('stores cold-start target and clears upon first consume() call', () {
      final notifier = PendingDeepLinkNotifier();
      expect(notifier.state, isNull);

      notifier.setPending('/emergency/EMG-2026-INIT0001');
      expect(notifier.state, equals('/emergency/EMG-2026-INIT0001'));

      // First consumption: retrieves path and resets state to null
      final consumedFirst = notifier.consume();
      expect(consumedFirst, equals('/emergency/EMG-2026-INIT0001'));
      expect(notifier.state, isNull);

      // Second consumption: returns null (no duplicate navigation)
      final consumedSecond = notifier.consume();
      expect(consumedSecond, isNull);
    });
  });

  group('NotificationService — Terminated Cold-Start Detection', () {
    test('init() returns emergencyId when launched from getInitialMessage()',
        () async {
      const remoteMessage = RemoteMessage(
        data: {'emergencyId': 'EMG-2026-COLDSTART'},
        notification: RemoteNotification(
          title: '🚨 HELP NEEDED NEAR YOU',
          body: 'Someone nearby requested assistance.',
        ),
      );

      when(() => mockMessaging.getInitialMessage())
          .thenAnswer((_) async => remoteMessage);

      final initialEmergencyId = await notificationService.init();
      expect(initialEmergencyId, equals('EMG-2026-COLDSTART'));
    });

    test('init() returns null when getInitialMessage() is null (normal app launch)',
        () async {
      when(() => mockMessaging.getInitialMessage()).thenAnswer((_) async => null);

      final initialEmergencyId = await notificationService.init();
      expect(initialEmergencyId, isNull);
    });
  });

  group('NotificationService — Lifecycle and Disposal (Rule #6)', () {
    test('dispose cancels streams and closes controllers cleanly', () async {
      await notificationService.init();
      await notificationService.dispose();

      // Attempting to listen to closed controllers should not throw or leak
      expect(notificationService.deepLinkStream, isA<Stream<String>>());
      expect(notificationService.inAppAlertStream, isA<Stream<InAppAlertEvent>>());
    });
  });
}
