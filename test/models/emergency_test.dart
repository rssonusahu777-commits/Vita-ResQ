// test/models/emergency_test.dart
//
// SafeReach — Emergency model unit tests (Phase 1)
// Run with: flutter test test/models/emergency_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:vindara/models/emergency.dart';

void main() {
  // -------------------------------------------------------------------------
  // ID Generation
  // -------------------------------------------------------------------------
  group('Emergency.generateId()', () {
    test('produces the correct EMG-2026-XXXXXXXX format', () {
      final id = Emergency.generateId();
      final pattern = RegExp(r'^EMG-2026-[0-9A-F]{8}$');
      expect(pattern.hasMatch(id), isTrue,
          reason: 'Got: $id');
    });

    test('generates unique IDs across 1000 calls', () {
      final ids = List.generate(1000, (_) => Emergency.generateId()).toSet();
      expect(ids.length, equals(1000));
    });
  });

  // -------------------------------------------------------------------------
  // State Machine — canTransitionTo
  // -------------------------------------------------------------------------
  group('Emergency.canTransitionTo()', () {
    Emergency makeEmergency(EmergencyStatus status) => Emergency(
          id: 'EMG-2026-TESTTEST',
          victimId: 'user-1',
          latitude: 12.9716,
          longitude: 77.5946,
          accuracyMeters: 10.0,
          type: EmergencyType.general,
          createdAt: DateTime.utc(2026, 1, 1),
          detectionSource: DetectionSource.manualHelp,
          status: status,
          communicationMode: CommunicationMode.online,
          version: 1,
        );

    // created
    test('created → alerting is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.created)
            .canTransitionTo(EmergencyStatus.alerting),
        isTrue,
      );
    });
    test('created → cancelled is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.created)
            .canTransitionTo(EmergencyStatus.cancelled),
        isTrue,
      );
    });
    test('created → accepted is NOT allowed', () {
      expect(
        makeEmergency(EmergencyStatus.created)
            .canTransitionTo(EmergencyStatus.accepted),
        isFalse,
      );
    });

    // alerting
    test('alerting → accepted is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.alerting)
            .canTransitionTo(EmergencyStatus.accepted),
        isTrue,
      );
    });
    test('alerting → cancelled is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.alerting)
            .canTransitionTo(EmergencyStatus.cancelled),
        isTrue,
      );
    });
    test('alerting → inProgress is NOT allowed', () {
      expect(
        makeEmergency(EmergencyStatus.alerting)
            .canTransitionTo(EmergencyStatus.inProgress),
        isFalse,
      );
    });

    // accepted
    test('accepted → inProgress is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.accepted)
            .canTransitionTo(EmergencyStatus.inProgress),
        isTrue,
      );
    });
    test('accepted → alerting (responder drop) is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.accepted)
            .canTransitionTo(EmergencyStatus.alerting),
        isTrue,
      );
    });
    test('accepted → cancelled is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.accepted)
            .canTransitionTo(EmergencyStatus.cancelled),
        isTrue,
      );
    });
    test('accepted → resolved is NOT allowed', () {
      expect(
        makeEmergency(EmergencyStatus.accepted)
            .canTransitionTo(EmergencyStatus.resolved),
        isFalse,
      );
    });

    // inProgress
    test('inProgress → resolved is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.inProgress)
            .canTransitionTo(EmergencyStatus.resolved),
        isTrue,
      );
    });
    test('inProgress → cancelled is allowed', () {
      expect(
        makeEmergency(EmergencyStatus.inProgress)
            .canTransitionTo(EmergencyStatus.cancelled),
        isTrue,
      );
    });
    test('inProgress → alerting is NOT allowed', () {
      expect(
        makeEmergency(EmergencyStatus.inProgress)
            .canTransitionTo(EmergencyStatus.alerting),
        isFalse,
      );
    });

    // terminal states
    test('resolved → (anything) is NOT allowed', () {
      final e = makeEmergency(EmergencyStatus.resolved);
      for (final next in EmergencyStatus.values) {
        expect(e.canTransitionTo(next), isFalse,
            reason: 'resolved should be terminal; tried → ${next.name}');
      }
    });
    test('cancelled → (anything) is NOT allowed', () {
      final e = makeEmergency(EmergencyStatus.cancelled);
      for (final next in EmergencyStatus.values) {
        expect(e.canTransitionTo(next), isFalse,
            reason: 'cancelled should be terminal; tried → ${next.name}');
      }
    });
  });

  // -------------------------------------------------------------------------
  // Serialization round-trip
  // -------------------------------------------------------------------------
  group('Emergency toJson / fromJson', () {
    test('round-trips correctly with all fields set', () {
      final original = Emergency(
        id: 'EMG-2026-AABBCCDD',
        victimId: 'user-abc',
        latitude: 28.6139,
        longitude: 77.2090,
        accuracyMeters: 5.5,
        type: EmergencyType.medical,
        createdAt: DateTime.utc(2026, 6, 15, 10, 30),
        detectionSource: DetectionSource.possibleCrash,
        status: EmergencyStatus.alerting,
        primaryResponderId: 'responder-1',
        standbyResponderId: null,
        communicationMode: CommunicationMode.offline,
        version: 3,
      );

      final json = original.toJson();
      final restored = Emergency.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.victimId, equals(original.victimId));
      expect(restored.latitude, equals(original.latitude));
      expect(restored.longitude, equals(original.longitude));
      expect(restored.accuracyMeters, equals(original.accuracyMeters));
      expect(restored.type, equals(original.type));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.detectionSource, equals(original.detectionSource));
      expect(restored.status, equals(original.status));
      expect(restored.primaryResponderId, equals(original.primaryResponderId));
      expect(restored.standbyResponderId, isNull);
      expect(restored.communicationMode, equals(original.communicationMode));
      expect(restored.version, equals(original.version));
    });

    test('fromJson throws ArgumentError for unknown EmergencyType', () {
      final json = {
        'id': 'EMG-2026-XXXXXXXX',
        'victimId': 'u',
        'latitude': 0.0,
        'longitude': 0.0,
        'accuracyMeters': 0.0,
        'type': 'unknown_type',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'detectionSource': 'manualHelp',
        'status': 'created',
        'communicationMode': 'online',
        'version': 1,
      };
      expect(() => Emergency.fromJson(json), throwsArgumentError);
    });
  });

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------
  group('Emergency.copyWith()', () {
    final base = Emergency(
      id: 'EMG-2026-BASE0001',
      victimId: 'user-1',
      latitude: 0.0,
      longitude: 0.0,
      accuracyMeters: 10.0,
      type: EmergencyType.general,
      createdAt: DateTime.utc(2026, 1, 1),
      detectionSource: DetectionSource.manualHelp,
      status: EmergencyStatus.created,
      communicationMode: CommunicationMode.online,
      version: 1,
    );

    test('preserves unchanged fields', () {
      final copy = base.copyWith(status: EmergencyStatus.alerting);
      expect(copy.id, equals(base.id));
      expect(copy.victimId, equals(base.victimId));
      expect(copy.latitude, equals(base.latitude));
    });

    test('applies changed fields', () {
      final copy = base.copyWith(status: EmergencyStatus.alerting);
      expect(copy.status, equals(EmergencyStatus.alerting));
    });

    test('auto-increments version when version is not supplied', () {
      final copy = base.copyWith(status: EmergencyStatus.alerting);
      expect(copy.version, equals(base.version + 1));
    });

    test('clearPrimaryResponderId sets it to null', () {
      final withResponder = base.copyWith(primaryResponderId: 'r-1');
      final cleared = withResponder.copyWith(clearPrimaryResponderId: true);
      expect(cleared.primaryResponderId, isNull);
    });
  });
}

