import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/services/online_communication_service.dart';
import 'package:jan_sarthi/services/offline_communication_service.dart';
import 'package:jan_sarthi/services/responder_mode_service.dart';
import 'package:jan_sarthi/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> notificationMethodCalls = [];

  group('Offline Stale Alert & Online Freshness Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      notificationMethodCalls.clear();
      NotificationService.resetProcessedNotifications();
      ResponderModeService.instance.resetProcessedEmergencyIds();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.jan_sarthi/notifications'),
        (MethodCall methodCall) async {
          notificationMethodCalls.add(methodCall);
          if (methodCall.method == 'isResponderForegroundServiceRunning') {
            return ResponderModeService.instance.isAvailable;
          }
          return true;
        },
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (MethodCall methodCall) async {
          return <int, int>{};
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.jan_sarthi/notifications'),
        null,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        null,
      );
    });

    test('a) 15-minute-old offline alert: isOfflineAlertFresh is true (within 60m clock skew) but age > 10m for sync guard', () {
      final now = DateTime.now();
      final fifteenMinutesAgo = now.subtract(const Duration(minutes: 15));

      // Direct P2P 60-minute freshness window remains preserved
      expect(OfflineCommunicationService.isOfflineAlertFresh(fifteenMinutesAgo, now: now), isTrue);

      // But for online upload, age difference is 15 minutes (900 seconds > 600 seconds)
      final ageSeconds = now.difference(fifteenMinutesAgo).inSeconds.abs();
      expect(ageSeconds > 600, isTrue);
    });

    test('b) 3-minute-old offline alert: is within 10-minute online sync threshold', () {
      final now = DateTime.now();
      final threeMinutesAgo = now.subtract(const Duration(minutes: 3));

      expect(OfflineCommunicationService.isOfflineAlertFresh(threeMinutesAgo, now: now), isTrue);
      final ageSeconds = now.difference(threeMinutesAgo).inSeconds.abs();
      expect(ageSeconds <= 600, isTrue);
    });

    test('c) OnlineCommunicationService.isOnlineAlertFresh enforces strictly 10 minutes', () {
      final now = DateTime.now();
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));
      final nineMinutesAgo = now.subtract(const Duration(minutes: 9));
      final elevenMinutesAgo = now.subtract(const Duration(minutes: 11));
      final futureDriftSafe = now.add(const Duration(seconds: 30));
      final futureDriftTooFar = now.add(const Duration(minutes: 2));

      expect(OnlineCommunicationService.isOnlineAlertFresh(fiveMinutesAgo, now: now), isTrue);
      expect(OnlineCommunicationService.isOnlineAlertFresh(nineMinutesAgo, now: now), isTrue);
      expect(OnlineCommunicationService.isOnlineAlertFresh(elevenMinutesAgo, now: now), isFalse);
      expect(OnlineCommunicationService.isOnlineAlertFresh(futureDriftSafe, now: now), isTrue);
      expect(OnlineCommunicationService.isOnlineAlertFresh(futureDriftTooFar, now: now), isFalse);
    });

    test('d) ResponderModeService drops online SEARCHING alerts older than 10 minutes but accepts offline P2P within 60 minutes', () async {
      final now = DateTime.now();

      final staleOnlineAlert = EmergencyModel(
        id: 'EMG-ONLINE-STALE',
        victimId: 'victim-1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        currentRadiusMeters: 1000.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: now.subtract(const Duration(minutes: 12)),
        updatedAt: now.subtract(const Duration(minutes: 12)),
      );

      final freshOnlineAlert = EmergencyModel(
        id: 'EMG-ONLINE-FRESH',
        victimId: 'victim-2',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        currentRadiusMeters: 1000.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: now.subtract(const Duration(minutes: 4)),
        updatedAt: now.subtract(const Duration(minutes: 4)),
      );

      final offlineP2pAlert = EmergencyModel(
        id: 'JS-OFF-P2P-30M',
        victimId: 'victim-3',
        type: 'CRASH',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        currentRadiusMeters: 1000.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: now.subtract(const Duration(minutes: 30)),
        updatedAt: now.subtract(const Duration(minutes: 30)),
      );

      final service = ResponderModeService.instance;

      // 1. Stale online alert: dropped without dispatching a notification
      await service.handleEmergencyAlert(
        staleOnlineAlert,
        userLat: 28.6139,
        userLon: 77.2090,
        currentUserId: 'responder-99',
      );
      final staleCalls = notificationMethodCalls.where(
        (c) => c.method == 'showEmergencyNotification',
      );
      expect(staleCalls, isEmpty);

      // 2. Fresh online alert: processed and triggers notification
      await service.handleEmergencyAlert(
        freshOnlineAlert,
        userLat: 28.6139,
        userLon: 77.2090,
        currentUserId: 'responder-99',
      );
      final freshCalls = notificationMethodCalls.where(
        (c) => c.method == 'showEmergencyNotification',
      );
      expect(freshCalls.length, equals(1));

      // Reset calls and processed tracking
      notificationMethodCalls.clear();
      NotificationService.resetProcessedNotifications();

      // 3. Offline P2P within 60 minutes: accepted and triggers notification
      await service.handleEmergencyAlert(
        offlineP2pAlert,
        userLat: 28.6139,
        userLon: 77.2090,
        currentUserId: 'responder-99',
      );
      final offlineCalls = notificationMethodCalls.where(
        (c) => c.method == 'showEmergencyNotification',
      );
      expect(offlineCalls.length, equals(1));
    });

    test('e) Local terminal emergency conclusion flags are correctly identified', () {
      final cancelled = EmergencyModel(
        id: 'JS-OFF-CANCELLED',
        victimId: 'v1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.CANCELLED,
        currentRadiusMeters: 1000,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
        updatedAt: DateTime.now(),
      );

      final completed = EmergencyModel(
        id: 'JS-OFF-COMPLETED',
        victimId: 'v1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.COMPLETED,
        currentRadiusMeters: 1000,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
        updatedAt: DateTime.now(),
      );

      expect(cancelled.isTerminal, isTrue);
      expect(completed.isTerminal, isTrue);
    });
  });
}
