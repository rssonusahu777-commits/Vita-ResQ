// test/services/nearby_relay_service_test.dart
//
// Vindara — Nearby Device-to-Device Offline Relay Service Tests (Phase 7)
// Design rules followed:
//   Rule #1 — Offline peer relay without internet dependency.
//   Rule #6 — Single-lifecycle streams & cancellation in dispose().
//   Rule #7 — Deduplication by (id + version).
//   Rule #8 — Relayed packets saved with syncStatus = 'pending' for auto-sync.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vindara/models/emergency.dart';
import 'package:vindara/services/local_emergency_store.dart';
import 'package:vindara/services/nearby_relay_service.dart';

void main() {
  late Directory tempDir;
  late LocalEmergencyStore localStore;
  late DefaultNearbyTransport transport;
  late NearbyRelayService relayService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vindara_relay_test_');
    Hive.init(tempDir.path);
    localStore = LocalEmergencyStore();
    await localStore.init();

    transport = DefaultNearbyTransport();
    relayService = NearbyRelayService(
      transport: transport,
      localStore: localStore,
    );
  });

  tearDown(() async {
    await relayService.dispose();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  final testEmergencyV1 = Emergency(
    id: 'EMG-2026-RELAY001',
    victimId: 'victim-peer-1',
    latitude: 19.0760,
    longitude: 72.8777,
    accuracyMeters: 4.0,
    type: EmergencyType.medical,
    createdAt: DateTime.utc(2026, 6, 1),
    detectionSource: DetectionSource.manualHelp,
    status: EmergencyStatus.alerting,
    communicationMode: CommunicationMode.offline,
    version: 1,
  );

  group('NearbyRelayService', () {
    test('startRelay and stopRelay manage active lifecycle cleanly (Rule #6)',
        () async {
      expect(relayService.isActive, isFalse);
      expect(transport.isAdvertising, isFalse);
      expect(transport.isDiscovering, isFalse);

      await relayService.startRelay(endpointName: 'TestPeer');
      expect(relayService.isActive, isTrue);
      expect(transport.isAdvertising, isTrue);
      expect(transport.isDiscovering, isTrue);

      await relayService.stopRelay();
      expect(relayService.isActive, isFalse);
      expect(transport.isAdvertising, isFalse);
      expect(transport.isDiscovering, isFalse);
    });

    test('broadcastEmergency encodes VINDARA_D2D_V1 packet and caches version',
        () async {
      await relayService.startRelay();

      await relayService.broadcastEmergency(testEmergencyV1);

      // Verify cached version
      expect(relayService.hasSeenVersion(testEmergencyV1.id, 1), isTrue);
    });

    test(
        'Incoming relayed packet saves to LocalEmergencyStore with syncStatus pending (Rule #8)',
        () async {
      await relayService.startRelay();

      Emergency? receivedEmergency;
      final sub = relayService.relayedEmergenciesStream.listen((emg) {
        receivedEmergency = emg;
      });

      final packet = {
        'protocol': 'VINDARA_D2D_V1',
        'emergencyId': testEmergencyV1.id,
        'version': 1,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': testEmergencyV1.toJson(),
      };

      transport.simulateIncomingPayload('peer-100', jsonEncode(packet));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(receivedEmergency, isNotNull);
      expect(receivedEmergency!.id, equals(testEmergencyV1.id));
      expect(receivedEmergency!.version, equals(1));

      // Rule #8: Must be in local store with syncStatus == 'pending'
      final stored = localStore.getEmergencyById(testEmergencyV1.id);
      expect(stored, isNotNull);
      final pendingList = localStore.getPendingSyncEmergencies();
      expect(pendingList.any((e) => e.id == testEmergencyV1.id), isTrue);

      await sub.cancel();
    });

    test('Deduplication: Repeated packet with same or lower version is ignored (Rule #7)',
        () async {
      await relayService.startRelay();

      int emissionCount = 0;
      final sub = relayService.relayedEmergenciesStream.listen((_) {
        emissionCount++;
      });

      final packetV1 = {
        'protocol': 'VINDARA_D2D_V1',
        'emergencyId': testEmergencyV1.id,
        'version': 1,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': testEmergencyV1.toJson(),
      };

      // 1st receive -> processed
      transport.simulateIncomingPayload('peer-100', jsonEncode(packetV1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissionCount, equals(1));

      // 2nd receive of identical version -> dropped / ignored
      transport.simulateIncomingPayload('peer-101', jsonEncode(packetV1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissionCount, equals(1));

      await sub.cancel();
    });

    test('Version Merging: Newer version (v2) updates local store and emits',
        () async {
      await relayService.startRelay();

      final receivedList = <Emergency>[];
      final sub = relayService.relayedEmergenciesStream.listen(receivedList.add);

      final packetV1 = {
        'protocol': 'VINDARA_D2D_V1',
        'emergencyId': testEmergencyV1.id,
        'version': 1,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': testEmergencyV1.toJson(),
      };

      // 1. Process v1
      transport.simulateIncomingPayload('peer-100', jsonEncode(packetV1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedList.length, equals(1));

      // 2. Prepare v2 transition to inProgress
      final testEmergencyV2 = testEmergencyV1.copyWith(
        version: 2,
        status: EmergencyStatus.inProgress,
        primaryResponderId: 'responder-hero-1',
      );

      final packetV2 = {
        'protocol': 'VINDARA_D2D_V1',
        'emergencyId': testEmergencyV2.id,
        'version': 2,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': testEmergencyV2.toJson(),
      };

      // 3. Process v2
      transport.simulateIncomingPayload('peer-102', jsonEncode(packetV2));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(receivedList.length, equals(2));
      expect(receivedList.last.version, equals(2));
      expect(receivedList.last.status, equals(EmergencyStatus.inProgress));

      // Verify local store updated to v2
      final updatedStored = localStore.getEmergencyById(testEmergencyV1.id);
      expect(updatedStored!.version, equals(2));
      expect(updatedStored.status, equals(EmergencyStatus.inProgress));

      await sub.cancel();
    });
  });
}

