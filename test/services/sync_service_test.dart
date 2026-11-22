// test/services/sync_service_test.dart
//
// Vindara — SyncService unit tests
// Tests idempotent offline sync queue draining upon reachability transitions (Rules #7 & #8).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vindara/models/emergency.dart';
import 'package:vindara/services/connectivity_service.dart';
import 'package:vindara/services/firestore_emergency_service.dart';
import 'package:vindara/services/local_emergency_store.dart';
import 'package:vindara/services/sync_service.dart';

class MockFirestoreEmergencyService extends Mock
    implements FirestoreEmergencyService {}
class MockConnectivityService extends Mock implements ConnectivityService {}

void main() {
  late LocalEmergencyStore localStore;
  late MockFirestoreEmergencyService mockFirestore;
  late MockConnectivityService mockConnectivity;
  late StreamController<bool> onlineStreamController;
  late SyncService syncService;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(Emergency(
      id: 'EMG-2026-FALLBACK',
      victimId: 'vic',
      latitude: 0,
      longitude: 0,
      accuracyMeters: 0,
      type: EmergencyType.general,
      createdAt: DateTime.utc(2026),
      detectionSource: DetectionSource.manualHelp,
      status: EmergencyStatus.created,
      communicationMode: CommunicationMode.offline,
    ));
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vindara_sync_test_');
    Hive.init(tempDir.path);
    localStore = LocalEmergencyStore();
    await localStore.init();

    mockFirestore = MockFirestoreEmergencyService();
    mockConnectivity = MockConnectivityService();
    onlineStreamController = StreamController<bool>.broadcast();

    when(() => mockConnectivity.isOnline)
        .thenAnswer((_) => onlineStreamController.stream);
    when(() => mockConnectivity.isCurrentlyOnline).thenReturn(false);

    syncService = SyncService(
      localStore: localStore,
      firestoreService: mockFirestore,
      connectivityService: mockConnectivity,
    );
  });

  tearDown(() async {
    await syncService.dispose();
    await localStore.dispose();
    await Hive.close();
    await tempDir.delete(recursive: true);
    await onlineStreamController.close();
  });

  Emergency createTestEmergency(String id) {
    return Emergency(
      id: id,
      victimId: 'user-vic',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 10.0,
      type: EmergencyType.medical,
      createdAt: DateTime.utc(2026, 6, 1),
      detectionSource: DetectionSource.manualHelp,
      status: EmergencyStatus.created,
      communicationMode: CommunicationMode.offline,
      version: 1,
    );
  }

  group('SyncService — Rules #7 & #8 Idempotent Offline Sync', () {
    test('flushes pending emergencies when reachability transitions from false to true',
        () async {
      final e1 = createTestEmergency('EMG-2026-SYNC0001');
      final e2 = createTestEmergency('EMG-2026-SYNC0002');

      // Save records offline as pending
      await localStore.saveEmergency(e1, syncStatus: SyncStatus.pending);
      await localStore.saveEmergency(e2, syncStatus: SyncStatus.pending);

      expect(localStore.getPendingSyncEmergencies().length, equals(2));

      when(() => mockFirestore.upsertEmergency(any()))
          .thenAnswer((_) async => true);

      await syncService.init();

      // Trigger connectivity transition from false to true
      onlineStreamController.add(true);
      await pumpEventQueue();

      // Both should now be marked as synced
      expect(localStore.getPendingSyncEmergencies().length, equals(0));
      expect(localStore.getSyncStatus('EMG-2026-SYNC0001'), equals(SyncStatus.synced));
      expect(localStore.getSyncStatus('EMG-2026-SYNC0002'), equals(SyncStatus.synced));

      verify(() => mockFirestore.upsertEmergency(any(that: isA<Emergency>())))
          .called(2);
    });

    test('marks failed on error without blocking other emergencies', () async {
      final e1 = createTestEmergency('EMG-2026-ERR00001');
      final e2 = createTestEmergency('EMG-2026-OK000002');

      await localStore.saveEmergency(e1, syncStatus: SyncStatus.pending);
      await localStore.saveEmergency(e2, syncStatus: SyncStatus.pending);

      // e1 throws, e2 succeeds
      when(() => mockFirestore.upsertEmergency(any(
            that: isA<Emergency>().having((e) => e.id, 'id', 'EMG-2026-ERR00001'),
          ))).thenThrow(Exception('Firestore write failed'));
      when(() => mockFirestore.upsertEmergency(any(
            that: isA<Emergency>().having((e) => e.id, 'id', 'EMG-2026-OK000002'),
          ))).thenAnswer((_) async => true);

      final count = await syncService.syncPendingEmergencies();

      expect(count, equals(1));
      expect(localStore.getSyncStatus('EMG-2026-ERR00001'), equals(SyncStatus.failed));
      expect(localStore.getSyncStatus('EMG-2026-OK000002'), equals(SyncStatus.synced));
    });

    test('idempotent: running sync repeatedly when no pending items does nothing',
        () async {
      final count = await syncService.syncPendingEmergencies();
      expect(count, equals(0));
      verifyNever(() => mockFirestore.upsertEmergency(any()));
    });
  });
}
