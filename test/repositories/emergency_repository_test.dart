// test/repositories/emergency_repository_test.dart
//
// SafeReach — EmergencyRepository unit tests (state machine + local-first writes)
// Run: flutter test test/repositories/emergency_repository_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:vindara/models/emergency.dart';
import 'package:vindara/repositories/emergency_repository.dart';
import 'package:vindara/services/local_emergency_store.dart';
import 'package:vindara/services/location_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockLocationService extends Mock implements LocationService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _fixedFix = LocationFix(
  latitude: 28.6139,
  longitude: 77.2090,
  accuracyMeters: 10.0,
  source: LocationFixSource.freshGps,
);

void main() {
  late LocalEmergencyStore store;
  late MockLocationService mockLocation;
  late EmergencyRepository repo;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('safereach_repo_test_');
    Hive.init(tempDir.path);
    store = LocalEmergencyStore();
    await store.init();

    mockLocation = MockLocationService();
    when(() => mockLocation.getCurrentLocation())
        .thenAnswer((_) async => _fixedFix);

    repo = EmergencyRepository(
      store: store,
      locationService: mockLocation,
    );
  });

  tearDown(() async {
    await store.dispose();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // -------------------------------------------------------------------------
  // createEmergency
  // -------------------------------------------------------------------------
  group('createEmergency', () {
    test('creates an emergency with generated EMG-2026-XXXXXXXX id', () async {
      final e = await repo.createEmergency(
        victimId: 'u-1',
        type: EmergencyType.medical,
      );
      final idPattern = RegExp(r'^EMG-2026-[0-9A-F]{8}$');
      expect(idPattern.hasMatch(e.id), isTrue);
    });

    test('initial status is always created', () async {
      final e = await repo.createEmergency(
        victimId: 'u-1',
        type: EmergencyType.safety,
      );
      expect(e.status, equals(EmergencyStatus.created));
    });

    test('GPS coordinates come from LocationService', () async {
      final e = await repo.createEmergency(
        victimId: 'u-1',
        type: EmergencyType.general,
      );
      expect(e.latitude, closeTo(28.6139, 0.0001));
      expect(e.longitude, closeTo(77.2090, 0.0001));
    });

    test('persisted locally with pending sync status', () async {
      final e = await repo.createEmergency(
        victimId: 'u-1',
        type: EmergencyType.general,
      );
      expect(store.getSyncStatus(e.id), equals(SyncStatus.pending));
    });

    test('uses locationOverride when supplied', () async {
      const override = LocationFix(
        latitude: 51.5074,
        longitude: -0.1278,
        accuracyMeters: 5.0,
        source: LocationFixSource.appCached,
      );
      final e = await repo.createEmergency(
        victimId: 'u-1',
        type: EmergencyType.general,
        locationOverride: override,
      );
      expect(e.latitude, closeTo(51.5074, 0.0001));
      // LocationService.getCurrentLocation should NOT have been called.
      verifyNever(() => mockLocation.getCurrentLocation());
    });
  });

  // -------------------------------------------------------------------------
  // transitionStatus — valid transitions
  // -------------------------------------------------------------------------
  group('transitionStatus — valid transitions', () {
    Future<Emergency> createTestEmergency() => repo.createEmergency(
          victimId: 'u',
          type: EmergencyType.general,
        );

    test('created → alerting succeeds', () async {
      final e = await createTestEmergency();
      final result = await repo.transitionStatus(e.id, EmergencyStatus.alerting);
      expect(result, isA<TransitionSuccess>());
      final success = result as TransitionSuccess;
      expect(success.emergency.status, equals(EmergencyStatus.alerting));
    });

    test('created → cancelled succeeds', () async {
      final e = await createTestEmergency();
      final result = await repo.transitionStatus(e.id, EmergencyStatus.cancelled);
      expect(result, isA<TransitionSuccess>());
    });

    test('alerting → accepted succeeds', () async {
      final e = await createTestEmergency();
      await repo.transitionStatus(e.id, EmergencyStatus.alerting);
      final result = await repo.transitionStatus(e.id, EmergencyStatus.accepted);
      expect(result, isA<TransitionSuccess>());
    });

    test('accepted → inProgress succeeds', () async {
      final e = await createTestEmergency();
      await repo.transitionStatus(e.id, EmergencyStatus.alerting);
      await repo.transitionStatus(e.id, EmergencyStatus.accepted);
      final result = await repo.transitionStatus(e.id, EmergencyStatus.inProgress);
      expect(result, isA<TransitionSuccess>());
    });

    test('inProgress → resolved succeeds', () async {
      final e = await createTestEmergency();
      await repo.transitionStatus(e.id, EmergencyStatus.alerting);
      await repo.transitionStatus(e.id, EmergencyStatus.accepted);
      await repo.transitionStatus(e.id, EmergencyStatus.inProgress);
      final result = await repo.transitionStatus(e.id, EmergencyStatus.resolved);
      expect(result, isA<TransitionSuccess>());
    });

    test('accepted → alerting (responder drop) succeeds', () async {
      final e = await createTestEmergency();
      await repo.transitionStatus(e.id, EmergencyStatus.alerting);
      await repo.transitionStatus(e.id, EmergencyStatus.accepted);
      final result = await repo.transitionStatus(e.id, EmergencyStatus.alerting);
      expect(result, isA<TransitionSuccess>());
    });

    test('version is incremented on each successful transition', () async {
      final e = await createTestEmergency();
      final v1 = e.version;
      final r1 = await repo.transitionStatus(e.id, EmergencyStatus.alerting);
      final v2 = (r1 as TransitionSuccess).emergency.version;
      expect(v2, equals(v1 + 1));
    });
  });

  // -------------------------------------------------------------------------
  // transitionStatus — invalid transitions
  // -------------------------------------------------------------------------
  group('transitionStatus — invalid / rejected transitions', () {
    test('created → inProgress is rejected', () async {
      final e = await repo.createEmergency(
        victimId: 'u',
        type: EmergencyType.general,
      );
      final result =
          await repo.transitionStatus(e.id, EmergencyStatus.inProgress);
      expect(result, isA<TransitionRejected>());
    });

    test('resolved → anything is rejected (terminal state)', () async {
      final e = await repo.createEmergency(
        victimId: 'u',
        type: EmergencyType.general,
      );
      await repo.transitionStatus(e.id, EmergencyStatus.alerting);
      await repo.transitionStatus(e.id, EmergencyStatus.accepted);
      await repo.transitionStatus(e.id, EmergencyStatus.inProgress);
      await repo.transitionStatus(e.id, EmergencyStatus.resolved);

      for (final next in EmergencyStatus.values) {
        final result = await repo.transitionStatus(e.id, next);
        expect(result, isA<TransitionRejected>(),
            reason: 'resolved → ${next.name} should be rejected');
      }
    });

    test('cancelled → anything is rejected (terminal state)', () async {
      final e = await repo.createEmergency(
        victimId: 'u',
        type: EmergencyType.general,
      );
      await repo.cancelEmergency(e.id);

      for (final next in EmergencyStatus.values) {
        final result = await repo.transitionStatus(e.id, next);
        expect(result, isA<TransitionRejected>(),
            reason: 'cancelled → ${next.name} should be rejected');
      }
    });

    test('unknown id returns TransitionNotFound', () async {
      final result = await repo.transitionStatus(
        'EMG-2026-NOEXIST',
        EmergencyStatus.alerting,
      );
      expect(result, isA<TransitionNotFound>());
    });
  });

  // -------------------------------------------------------------------------
  // Sync helpers
  // -------------------------------------------------------------------------
  group('markSynced / markFailed', () {
    test('markSynced updates syncStatus to synced', () async {
      final e = await repo.createEmergency(
        victimId: 'u',
        type: EmergencyType.general,
      );
      await repo.markSynced(e.id);
      expect(store.getSyncStatus(e.id), equals(SyncStatus.synced));
    });

    test('markFailed updates syncStatus to failed', () async {
      final e = await repo.createEmergency(
        victimId: 'u',
        type: EmergencyType.general,
      );
      await repo.markFailed(e.id);
      expect(store.getSyncStatus(e.id), equals(SyncStatus.failed));
    });
  });
}
