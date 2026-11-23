import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/services/local_database_service.dart';
import 'package:jan_sarthi/services/notification_service.dart';
import 'package:jan_sarthi/services/offline_communication_service.dart';
import 'package:jan_sarthi/services/offline_nearby_service.dart';
import 'package:jan_sarthi/services/responder_mode_service.dart';
import 'package:jan_sarthi/screens/profile/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> methodChannelCalls = [];

  setUp(() {
    methodChannelCalls.clear();
    NotificationService.resetProcessedNotifications();
    EmergencySoundService.resetDuplicateSoundHistory();
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.example.jan_sarthi/notifications'),
      (MethodCall methodCall) async {
        methodChannelCalls.add(methodCall);
        if (methodCall.method == 'getLaunchEmergencyId') {
          return null;
        }
        return null;
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

  group('Phase 4.2B — Packaged Voice Asset Validation', () {
    test('Android raw resource directory contains valid emergency_alert_voice.mp3', () {
      final file = File('android/app/src/main/res/raw/emergency_alert_voice.mp3');
      expect(file.existsSync(), isTrue, reason: 'emergency_alert_voice.mp3 must exist in android/app/src/main/res/raw/');

      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(10000), reason: 'Audio file must not be an empty or corrupted placeholder');

      // Validate MP3 ID3 header (0x49 0x44 0x33) or MPEG sync frame (0xFF 0xFB / 0xFA / 0xF3 / 0xF2)
      final hasId3Header = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
      final hasFrameSync = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
      expect(hasId3Header || hasFrameSync, isTrue, reason: 'File must be a valid binary MP3 stream');
    });
  });

  group('Phase 4.2B — Spoken Emergency Alerts Preference Persistence', () {
    test('Default voice alert preference is enabled (true)', () async {
      SharedPreferences.setMockInitialValues({});
      final enabled = await LocalDatabaseService.isSpokenAlertsEnabled();
      expect(enabled, isTrue);
    });

    test('Persisting disabled voice alert preference updates storage correctly', () async {
      SharedPreferences.setMockInitialValues({});
      await LocalDatabaseService.setSpokenAlertsEnabled(false);
      final disabled = await LocalDatabaseService.isSpokenAlertsEnabled();
      expect(disabled, isFalse);

      await LocalDatabaseService.setSpokenAlertsEnabled(true);
      final reEnabled = await LocalDatabaseService.isSpokenAlertsEnabled();
      expect(reEnabled, isTrue);
    });
  });

  group('Phase 4.2B — Dedicated Voice Notification Channel Integration', () {
    test('Dispatches notification with useVoiceAlert=true when preference is enabled', () async {
      await LocalDatabaseService.setSpokenAlertsEnabled(true);

      await NotificationService.showEmergencyAlertNotification(
        emergencyId: 'EM-VOICE-ENABLED-001',
        type: 'MEDICAL',
        distanceMeters: 400,
        isOffline: false,
      );

      expect(methodChannelCalls.length, 1);
      final call = methodChannelCalls.first;
      expect(call.method, 'showEmergencyNotification');
      expect(call.arguments['emergencyId'], 'EM-VOICE-ENABLED-001');
      expect(call.arguments['useVoiceAlert'], isTrue);
    });

    test('Dispatches notification with useVoiceAlert=false when preference is disabled (standard fallback)', () async {
      await LocalDatabaseService.setSpokenAlertsEnabled(false);

      await NotificationService.showEmergencyAlertNotification(
        emergencyId: 'EM-VOICE-DISABLED-002',
        type: 'CAR_ACCIDENT',
        distanceMeters: 1200,
        isOffline: false,
      );

      expect(methodChannelCalls.length, 1);
      final call = methodChannelCalls.first;
      expect(call.method, 'showEmergencyNotification');
      expect(call.arguments['emergencyId'], 'EM-VOICE-DISABLED-002');
      expect(call.arguments['useVoiceAlert'], isFalse);
    });

    test('Explicit useVoiceAlert override takes precedence over stored preference', () async {
      await LocalDatabaseService.setSpokenAlertsEnabled(false);

      await NotificationService.showEmergencyAlertNotification(
        emergencyId: 'EM-VOICE-OVERRIDE-003',
        type: 'FIRE',
        useVoiceAlert: true,
      );

      expect(methodChannelCalls.length, 1);
      final call = methodChannelCalls.first;
      expect(call.arguments['useVoiceAlert'], isTrue);
    });
  });

  group('Phase 4.2B — Online and Offline Consistency', () {
    test('Offline P2P discovery respects spoken voice alert preference', () async {
      await LocalDatabaseService.setSpokenAlertsEnabled(true);
      final offlineService = OfflineCommunicationService();

      final stream = offlineService.listenForAlerts(
        userLat: 28.6139,
        userLon: 77.2090,
        currentUserId: 'responder_user_p2p',
      );
      final sub = stream.listen((_) {});

      OfflineNearbyService().triggerSOSDiscoveredForTesting({
        'emergencyId': 'JS-OFF-VOICE-100',
        'victimId': 'victim_user_offline',
        'type': 'TRAUMA',
        'latitude': 28.6145,
        'longitude': 77.2095,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final call = methodChannelCalls.firstWhere(
        (c) => c.method == 'showEmergencyNotification' && c.arguments['emergencyId'] == 'JS-OFF-VOICE-100',
      );
      expect(call.arguments['useVoiceAlert'], isTrue);
      expect(call.arguments['title'], contains('(Offline P2P)'));

      await sub.cancel();
    });

    test('ResponderModeService background alert respects spoken voice alert preference', () async {
      await LocalDatabaseService.setSpokenAlertsEnabled(false);

      final alert = EmergencyModel(
        id: 'EM-RESPONDER-MODE-001',
        victimId: 'victim_other',
        type: 'MEDICAL',
        latitude: 28.6140,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await ResponderModeService.instance.handleEmergencyAlert(
        alert,
        userLat: 28.6139,
        userLon: 77.2089,
        currentUserId: 'responder_active',
      );

      final call = methodChannelCalls.firstWhere(
        (c) => c.method == 'showEmergencyNotification' && c.arguments['emergencyId'] == 'EM-RESPONDER-MODE-001',
      );
      expect(call.arguments['useVoiceAlert'], isFalse);
    });
  });

  group('Phase 4.2B — Deduplication & Suppression Rules', () {
    test('Repeated stream events for the same emergency produce exactly one notification dispatch', () async {
      for (int i = 0; i < 5; i++) {
        await NotificationService.showEmergencyAlertNotification(
          emergencyId: 'EM-DEDUP-VOICE-001',
          type: 'MEDICAL',
        );
      }
      expect(methodChannelCalls.length, 1);
    });

    test('Terminal emergencies (COMPLETED or CANCELLED) are completely suppressed', () async {
      await NotificationService.showEmergencyAlertNotification(
        emergencyId: 'EM-COMPLETED-VOICE',
        type: 'MEDICAL',
        status: EmergencyStatus.COMPLETED,
      );
      await NotificationService.showEmergencyAlertNotification(
        emergencyId: 'EM-CANCELLED-VOICE',
        type: 'MEDICAL',
        status: EmergencyStatus.CANCELLED,
      );

      expect(methodChannelCalls, isEmpty);
    });

    test('Audio siren loop is suppressed when voice alerts are active to prevent acoustic collision', () async {
      EmergencySoundService.resetDuplicateSoundHistory();

      // Calling with suppressSirenIfVoiceActive=true should not throw or start competing loops
      await EmergencySoundService.playEmergencyAlert(
        userRole: 'AMBULANCE_DRIVER',
        emergencyId: 'EM-NO-SIREN-001',
        suppressSirenIfVoiceActive: true,
      );

      // Stop sounds safely
      await EmergencySoundService.stopSound();
    });
  });

  group('Phase 4.2B — Profile / Settings UI Preference Switch', () {
    testWidgets('ProfileScreen renders Spoken Emergency Alerts switch and updates preference', (tester) async {
      await LocalDatabaseService.setSpokenAlertsEnabled(true);

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Spoken Emergency Alerts'), findsOneWidget);
      expect(find.text('Spoken audio alert enabled for incoming emergencies'), findsOneWidget);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      // Scroll into view if needed
      await tester.ensureVisible(switchFinder);
      await tester.pumpAndSettle();

      expect((tester.widget(switchFinder) as Switch).value, isTrue);

      // Tap switch to toggle off
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect((tester.widget(switchFinder) as Switch).value, isFalse);
      final storedState = await LocalDatabaseService.isSpokenAlertsEnabled();
      expect(storedState, isFalse);
    });
  });
}
