// test/services/offline_p2p_service_test.dart
//
// Unit tests for Vindara Offline P2P Emergency Mesh (Feature 11)

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:vindara/models/emergency.dart';
import 'package:vindara/services/connectivity_service.dart';
import 'package:vindara/services/firestore_emergency_service.dart';
import 'package:vindara/services/local_emergency_store.dart';
import 'package:vindara/services/offline_p2p_service.dart';

class FakeLocalEmergencyStore extends LocalEmergencyStore {
  final List<Emergency> savedEmergencies = [];
  final List<String> syncedIds = [];

  @override
  Future<void> saveEmergency(
    Emergency emergency, {
    String syncStatus = SyncStatus.pending,
  }) async {
    savedEmergencies.add(emergency);
  }

  @override
  Future<void> markAsSynced(String id) async {
    syncedIds.add(id);
  }
}

class FakeFirestoreEmergencyService extends FirestoreEmergencyService {
  final List<Emergency> upserted = [];
  bool returnSuccess = true;

  @override
  Future<bool> upsertEmergency(Emergency emergency) async {
    if (returnSuccess) {
      upserted.add(emergency);
      return true;
    }
    return false;
  }
}

class FakeConnectivityService extends ConnectivityService {
  bool onlineState;
  FakeConnectivityService(this.onlineState);

  @override
  bool get isCurrentlyOnline => onlineState;
}

void main() {
  group('P2pHelpPayload Serialization & Rules', () {
    test('Encodes and decodes compact byte payload accurately', () {
      final now = DateTime.now().toUtc();
      final payload = P2pHelpPayload(
        emergencyId: 'EMG-2026-TESTP2P1',
        victimName: 'Citizen Victim A',
        victimPhone: '+91 9988776655',
        type: 'medical',
        severity: 'high',
        latitude: 21.1619,
        longitude: 81.7869,
        accuracyMeters: 4.5,
        locationLabel: 'Sector 4, Community Axis',
        timestamp: now.toIso8601String(),
        source: 'p2p_offline',
        recommendedSkills: ['cpr', 'first_aid'],
        notes: 'Victim unresponsive near entrance.',
        version: 2,
      );

      final bytes = payload.toBytes();
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);

      final decoded = P2pHelpPayload.fromBytes(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.emergencyId, equals('EMG-2026-TESTP2P1'));
      expect(decoded.victimName, equals('Citizen Victim A'));
      expect(decoded.victimPhone, equals('+91 9988776655'));
      expect(decoded.type, equals('medical'));
      expect(decoded.severity, equals('high'));
      expect(decoded.latitude, closeTo(21.1619, 0.0001));
      expect(decoded.longitude, closeTo(81.7869, 0.0001));
      expect(decoded.accuracyMeters, closeTo(4.5, 0.1));
      expect(decoded.locationLabel, equals('Sector 4, Community Axis'));
      expect(decoded.source, equals('p2p_offline'));
      expect(decoded.recommendedSkills, equals(['cpr', 'first_aid']));
      expect(decoded.notes, equals('Victim unresponsive near entrance.'));
      expect(decoded.version, equals(2));
    });

    test('Converts to Emergency model preserving offlineNearby mode', () {
      final payload = P2pHelpPayload(
        emergencyId: 'EMG-2026-CONV01',
        victimName: 'Karan',
        type: 'roadAccident',
        severity: 'critical',
        latitude: 21.2000,
        longitude: 81.8000,
        accuracyMeters: 3.2,
        locationLabel: 'Bypass Expressway',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        recommendedSkills: ['extrication'],
      );

      final emergency = payload.toEmergency();
      expect(emergency.id, equals('EMG-2026-CONV01'));
      expect(emergency.victimName, equals('Karan'));
      expect(emergency.type, equals(EmergencyType.roadAccident));
      expect(emergency.severity, equals(EmergencySeverity.critical));
      expect(emergency.communicationMode, equals(CommunicationMode.offlineNearby));
      expect(emergency.isSyncedToCloud, isFalse);
      expect(emergency.status, equals(EmergencyStatus.alerting));
      expect(emergency.recommendedSkills, contains('extrication'));
    });

    test('fromEmergency converts accurately with strictly zero media buffers', () {
      final emergency = Emergency(
        id: 'EMG-2026-NO-MEDIA',
        victimName: 'Rahul',
        victimPhone: '+91 9123456789',
        latitude: 21.1500,
        longitude: 81.7500,
        accuracyMeters: 5.0,
        locationLabel: 'City Center',
        type: EmergencyType.fire,
        createdAt: DateTime.now().toUtc(),
        detectionSource: DetectionSource.manualHelp,
        status: EmergencyStatus.alerting,
        communicationMode: CommunicationMode.offlineNearby,
        severity: EmergencySeverity.high,
        recommendedSkills: ['burn_treatment'],
        notes: 'Smoke visible on second floor',
      );

      final payload = P2pHelpPayload.fromEmergency(emergency);
      final jsonMap = payload.toJson();

      // Teammate AI Contract & Rule #4: Strictly zero raw media buffers in payload
      expect(jsonMap.containsKey('rawAudioBuffer'), isFalse);
      expect(jsonMap.containsKey('rawImageBuffer'), isFalse);
      expect(jsonMap['emergencyId'], equals('EMG-2026-NO-MEDIA'));
      expect(jsonMap['type'], equals('fire'));
      expect(jsonMap['severity'], equals('high'));
    });

    test('Returns null on malformed / corrupted bytes without throwing', () {
      final corrupted = Uint8List.fromList(utf8.encode('{invalid-json-content!'));
      final decoded = P2pHelpPayload.fromBytes(corrupted);
      expect(decoded, isNull);
    });
  });

  group('OfflineP2pService Mesh & Deduplication', () {
    late MockNearbyClient mockClient;
    late FakeLocalEmergencyStore fakeStore;
    late FakeFirestoreEmergencyService fakeFirestore;
    late FakeConnectivityService fakeConnectivity;
    late OfflineP2pService service;

    setUp(() {
      mockClient = MockNearbyClient();
      fakeStore = FakeLocalEmergencyStore();
      fakeFirestore = FakeFirestoreEmergencyService();
      fakeConnectivity = FakeConnectivityService(false);

      service = OfflineP2pService(
        client: mockClient,
        localStore: fakeStore,
        firestoreService: fakeFirestore,
        connectivityService: fakeConnectivity,
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('startMesh initiates advertising and discovery on P2P_CLUSTER', () async {
      await service.startMesh(nickname: 'TestVindara');

      expect(mockClient.isAdvertising, isTrue);
      expect(mockClient.isDiscovering, isTrue);
    });

    test('broadcastHelpEmergency sends bytes payload to connected peers', () async {
      // Connect a mock peer
      mockClient.connectedEndpoints.add('peer-endpoint-01');

      final emergency = Emergency(
        id: 'EMG-2026-BCAST01',
        victimName: 'Victim Citizen',
        latitude: 21.1619,
        longitude: 81.7869,
        locationLabel: 'Sector 4',
        type: EmergencyType.medical,
        createdAt: DateTime.now().toUtc(),
        detectionSource: DetectionSource.manualHelp,
        status: EmergencyStatus.alerting,
        communicationMode: CommunicationMode.offlineNearby,
      );

      await service.broadcastHelpEmergency(emergency);

      expect(service.currentStatus, equals(P2pMeshStatus.broadcasting));
      expect(mockClient.sentPayloads.length, equals(1));

      final decoded = P2pHelpPayload.fromBytes(mockClient.sentPayloads.first);
      expect(decoded, isNotNull);
      expect(decoded!.emergencyId, equals('EMG-2026-BCAST01'));
    });

    test('handleIncomingBytes deduplicates duplicate emergency packets', () async {
      final payload = P2pHelpPayload(
        emergencyId: 'EMG-2026-DEDUP01',
        victimName: 'Duplicate Test Victim',
        type: 'medical',
        latitude: 21.1619,
        longitude: 81.7869,
        accuracyMeters: 5.0,
        locationLabel: 'Test Landmark',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );
      final bytes = payload.toBytes();

      final emittedAlerts = <Emergency>[];
      final sub = service.incomingHelpAlertsStream.listen(emittedAlerts.add);

      // First packet received: should be processed and emitted
      await service.handleIncomingBytes('ep-1', bytes);
      expect(fakeStore.savedEmergencies.length, equals(1));
      expect(emittedAlerts.length, equals(1));
      expect(service.seenEmergencyIds.contains('EMG-2026-DEDUP01'), isTrue);

      // Duplicate packet received (same emergencyId): must be dropped
      await service.handleIncomingBytes('ep-1', bytes);
      expect(fakeStore.savedEmergencies.length, equals(1)); // Still 1
      expect(emittedAlerts.length, equals(1)); // Still 1

      await sub.cancel();
    });

    test('Cloud relay hook: relays to Firestore and marks synced when device is online', () async {
      fakeConnectivity.onlineState = true; // Device has verified internet

      final payload = P2pHelpPayload(
        emergencyId: 'EMG-2026-RELAY01',
        victimName: 'Offline Citizen',
        type: 'medical',
        latitude: 21.1619,
        longitude: 81.7869,
        accuracyMeters: 4.0,
        locationLabel: 'Central Market',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      await service.handleIncomingBytes('ep-2', payload.toBytes());

      // Saved locally first (Rule #8)
      expect(fakeStore.savedEmergencies.length, equals(1));
      // Successfully relayed to Firestore
      expect(fakeFirestore.upserted.length, equals(1));
      expect(fakeFirestore.upserted.first.id, equals('EMG-2026-RELAY01'));
      // Marked as synced in LocalEmergencyStore
      expect(fakeStore.syncedIds, contains('EMG-2026-RELAY01'));
    });

    test('Cloud relay hook: remains offline pending when device has no internet', () async {
      fakeConnectivity.onlineState = false; // Device is offline

      final payload = P2pHelpPayload(
        emergencyId: 'EMG-2026-OFFLINE01',
        victimName: 'Offline Citizen',
        type: 'medical',
        latitude: 21.1619,
        longitude: 81.7869,
        accuracyMeters: 4.0,
        locationLabel: 'Remote Outpost',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      await service.handleIncomingBytes('ep-3', payload.toBytes());

      // Saved locally
      expect(fakeStore.savedEmergencies.length, equals(1));
      // Not relayed to Firestore yet
      expect(fakeFirestore.upserted.isEmpty, isTrue);
      // Not marked synced
      expect(fakeStore.syncedIds.isEmpty, isTrue);
    });

    test('stopMesh cleans up connected endpoints and resets status to idle', () async {
      mockClient.connectedEndpoints.add('ep-10');
      mockClient.connectedEndpoints.add('ep-11');

      await service.stopMesh();

      expect(mockClient.isAdvertising, isFalse);
      expect(mockClient.isDiscovering, isFalse);
      expect(service.connectedEndpoints.isEmpty, isTrue);
      expect(service.currentStatus, equals(P2pMeshStatus.idle));
    });
  });
}

