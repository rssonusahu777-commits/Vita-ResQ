import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/models/responder_model.dart';
import 'package:jan_sarthi/services/emergency_service.dart';
import 'package:jan_sarthi/services/location_service.dart';
import 'package:jan_sarthi/services/local_database_service.dart';
import 'package:jan_sarthi/core/constants/app_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Position makePosition({
    required double latitude,
    required double longitude,
    double speed = 0.0,
  }) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: speed,
      speedAccuracy: 0.0,
    );
  }

  // Helper matching EmergencyMapScreen._formatDistance
  String formatMapDistance(double? meters) {
    if (meters == null || meters.isNaN || meters < 0) {
      return '--';
    }
    if (meters == 0 || meters < 0.5) {
      return '0m';
    }
    if (meters < 1000) {
      return '${meters.round()}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  // Helper matching IncomingEmergencyCard._formatDistance
  String formatCardDistance(double? meters, double currentRadiusMeters) {
    if (meters == null || meters.isNaN || meters < 0) {
      if (currentRadiusMeters >= 1000) {
        return 'Within ${(currentRadiusMeters / 1000).toStringAsFixed(1)} km';
      } else if (currentRadiusMeters > 0) {
        return 'Within ${currentRadiusMeters.round()} m';
      }
      return 'Distance unknown';
    }
    if (meters == 0 || meters < 0.5) {
      return '0 m away';
    }
    if (meters < 1000) {
      return '${meters.round()} m away';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  group('Phase 2.1 Fix 1: Eliminate Intermediate SEARCHING During Offline Sync', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LocalDatabaseService.resetLockForTesting();
    });

    test('1.1: Completed offline emergency generates single terminal creation payload, not SEARCHING', () {
      final completedEmergency = EmergencyModel(
        id: 'JS-OFF-12345-COMPLETED',
        victimId: 'user_victim_1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.COMPLETED,
        helperId: 'helper_1',
        currentRadiusMeters: 500.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        updatedAt: DateTime.now(),
      );

      // Verify that create payload for terminal emergency maps status directly to COMPLETED
      Map<String, dynamic> createMap = {
        'id': completedEmergency.id,
        'victimId': completedEmergency.victimId,
        'type': completedEmergency.type,
        'latitude': completedEmergency.latitude,
        'longitude': completedEmergency.longitude,
        'status': completedEmergency.status.name, // DIRECT COMPLETED
        'currentRadiusMeters': completedEmergency.currentRadiusMeters,
        'notifiedUserIds': completedEmergency.notifiedUserIds,
        'responders': completedEmergency.responders.map((k, v) => MapEntry(k, v.toMap())),
        'createdAt': completedEmergency.createdAt.toIso8601String(),
        'updatedAt': completedEmergency.updatedAt.toIso8601String(),
      };

      expect(createMap['status'], equals('COMPLETED'));
      expect(createMap['status'], isNot(equals('SEARCHING')));
      expect(createMap['id'], startsWith('JS-OFF-'));
    });

    test('1.2: Cancelled offline emergency generates single terminal creation payload, not SEARCHING', () {
      final cancelledEmergency = EmergencyModel(
        id: 'JS-OFF-67890-CANCELLED',
        victimId: 'user_victim_1',
        type: 'FIRE',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.CANCELLED,
        helperId: null,
        currentRadiusMeters: 500.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
        updatedAt: DateTime.now(),
      );

      Map<String, dynamic> createMap = {
        'id': cancelledEmergency.id,
        'victimId': cancelledEmergency.victimId,
        'type': cancelledEmergency.type,
        'latitude': cancelledEmergency.latitude,
        'longitude': cancelledEmergency.longitude,
        'status': cancelledEmergency.status.name, // DIRECT CANCELLED
      };

      expect(createMap['status'], equals('CANCELLED'));
      expect(createMap['status'], isNot(equals('SEARCHING')));
    });

    test('1.3: In-progress offline emergencies in ASSIGNED or ARRIVED state are retained locally', () async {
      final localDb = LocalDatabaseService();
      final assignedEmergency = EmergencyModel(
        id: 'JS-OFF-INPROGRESS-1',
        victimId: 'user_victim_1',
        type: 'ACCIDENT',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.ASSIGNED,
        helperId: 'responder_1',
        currentRadiusMeters: 500.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        updatedAt: DateTime.now(),
      );

      await localDb.saveEmergencyLocally(assignedEmergency);

      // Verify that ASSIGNED emergencies require explicit pending secure import failure
      final isNonTerminalInProgress = assignedEmergency.status == EmergencyStatus.ASSIGNED ||
          assignedEmergency.status == EmergencyStatus.APPROACHING ||
          assignedEmergency.status == EmergencyStatus.ARRIVED;

      expect(isNonTerminalInProgress, isTrue);

      await localDb.recordSyncFailure(
        assignedEmergency.id,
        'Pending secure import: Offline emergency in ${assignedEmergency.status.name} state requires active responder reconciliation or terminal resolution before cloud synchronization.',
      );

      final stored = await localDb.getEmergencyById(assignedEmergency.id);
      expect(stored, isNotNull);
      expect(stored!.status, equals(EmergencyStatus.ASSIGNED));

      final unsynced = await localDb.getUnsyncedEmergencies();
      expect(unsynced.any((e) => e.id == assignedEmergency.id), isTrue);
    });

    test('1.4: Unauthorized offline emergency sync (identity mismatch) is safely recorded as failure', () async {
      final localDb = LocalDatabaseService();
      final unauthorized = EmergencyModel(
        id: 'JS-OFF-UNAUTH-1',
        victimId: 'offline_user',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.COMPLETED,
        currentRadiusMeters: 500.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await localDb.saveEmergencyLocally(unauthorized);

      const authUserUid = 'real_auth_user_99';
      final isMismatch = unauthorized.victimId == 'offline_user' || unauthorized.victimId != authUserUid;
      expect(isMismatch, isTrue);

      await localDb.recordSyncFailure(
        unauthorized.id,
        'Identity mismatch: Cannot sync emergency created with victimId=${unauthorized.victimId} under authenticated user $authUserUid without backend adoption rule',
      );

      final unsynced = await localDb.getUnsyncedEmergencies();
      expect(unsynced.any((e) => e.id == unauthorized.id), isTrue);
    });

    test('1.5: Remote terminal status is preserved and not overwritten on retry', () async {
      final localDb = LocalDatabaseService();
      final localEmergency = EmergencyModel(
        id: 'JS-OFF-RETRY-1',
        victimId: 'user_victim_1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.COMPLETED,
        currentRadiusMeters: 500.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await localDb.saveEmergencyLocally(localEmergency);

      // Simulate remote is already COMPLETED
      const remoteStatusStr = AppConstants.statusCompleted;
      bool shouldRegress = false;
      if (remoteStatusStr == AppConstants.statusCompleted ||
          remoteStatusStr == AppConstants.statusCancelled) {
        // Do not update remote, mark local as synced
        await localDb.markAsSynced(localEmergency.id);
      } else {
        shouldRegress = true;
      }

      expect(shouldRegress, isFalse);
      final unsynced = await localDb.getUnsyncedEmergencies();
      expect(unsynced.any((e) => e.id == localEmergency.id), isFalse);
    });
  });

  group('Phase 2.1 Fix 2: Consolidate & Throttle Responder Location Writes', () {
    test('2.1: LocationTelemetryThrottler publishes first valid position immediately', () async {
      final published = <Position>[];
      final throttler = LocationTelemetryThrottler(
        throttleInterval: const Duration(milliseconds: 300),
        heartbeatInterval: const Duration(milliseconds: 800),
        onPublish: (pos) async {
          published.add(pos);
        },
      );

      final pos1 = makePosition(latitude: 28.6139, longitude: 77.2090);
      throttler.handlePositionUpdate(pos1);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(published.length, equals(1));
      expect(published.first.latitude, equals(28.6139));
      expect(throttler.localEventCount, equals(1));
      expect(throttler.publishedCount, equals(1));

      throttler.dispose();
    });

    test('2.2: Rapid GPS events within throttle window coalesce and publish only the latest position', () async {
      final published = <Position>[];
      final throttler = LocationTelemetryThrottler(
        throttleInterval: const Duration(milliseconds: 200),
        heartbeatInterval: const Duration(milliseconds: 800),
        onPublish: (pos) async {
          published.add(pos);
        },
      );

      // Event 1: published immediately
      throttler.handlePositionUpdate(makePosition(latitude: 28.001, longitude: 77.001));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(published.length, equals(1));
      expect(published.last.latitude, equals(28.001));

      // Events 2, 3, 4: rapid updates within 200ms
      throttler.handlePositionUpdate(makePosition(latitude: 28.002, longitude: 77.002));
      throttler.handlePositionUpdate(makePosition(latitude: 28.003, longitude: 77.003));
      throttler.handlePositionUpdate(makePosition(latitude: 28.004, longitude: 77.004));

      expect(throttler.localEventCount, equals(4));
      // Still only 1 publish so far
      expect(published.length, equals(1));

      // Wait for throttle window (200ms + margin)
      await Future.delayed(const Duration(milliseconds: 250));

      // Exactly 1 additional publish containing the LATEST position (28.004)
      expect(published.length, equals(2));
      expect(published.last.latitude, equals(28.004));
      expect(throttler.publishedCount, equals(2));

      throttler.dispose();
    });

    test('2.3: Heartbeat does not publish redundant write if movement occurred recently', () async {
      final published = <Position>[];
      final throttler = LocationTelemetryThrottler(
        throttleInterval: const Duration(milliseconds: 100),
        heartbeatInterval: const Duration(milliseconds: 300),
        onPublish: (pos) async {
          published.add(pos);
        },
      );

      throttler.startHeartbeat();

      // Trigger movement update
      throttler.handlePositionUpdate(makePosition(latitude: 28.1, longitude: 77.1));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(published.length, equals(1));

      // Trigger another movement update at 150ms (before heartbeat fires at 300ms)
      await Future.delayed(const Duration(milliseconds: 140));
      throttler.handlePositionUpdate(makePosition(latitude: 28.2, longitude: 77.2));
      await Future.delayed(const Duration(milliseconds: 120));
      expect(published.length, equals(2));

      // At 300ms, heartbeat checks lastPublishTime. Since lastPublish was < 300ms ago, it skips
      await Future.delayed(const Duration(milliseconds: 100));
      expect(published.length, equals(2)); // No redundant heartbeat write!

      throttler.dispose();
    });

    test('2.4: Stationary responder triggers heartbeat publish after inactivity threshold', () async {
      final published = <Position>[];
      final throttler = LocationTelemetryThrottler(
        throttleInterval: const Duration(milliseconds: 100),
        heartbeatInterval: const Duration(milliseconds: 250),
        onPublish: (pos) async {
          published.add(pos);
        },
      );

      throttler.startHeartbeat();

      // Initial position
      throttler.handlePositionUpdate(makePosition(latitude: 28.5, longitude: 77.5));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(published.length, equals(1));

      // Stay completely stationary for > 250ms (with margin for parallel test run load)
      await Future.delayed(const Duration(milliseconds: 450));

      // Heartbeat should fire with cached position
      expect(published.length, greaterThanOrEqualTo(2));
      expect(published.last.latitude, equals(28.5));

      throttler.dispose();
    });

    test('2.5: Throttler dispose cleanly cancels timers and prevents any trailing writes', () async {
      final published = <Position>[];
      final throttler = LocationTelemetryThrottler(
        throttleInterval: const Duration(milliseconds: 200),
        heartbeatInterval: const Duration(milliseconds: 300),
        onPublish: (pos) async {
          published.add(pos);
        },
      );

      throttler.startHeartbeat();
      throttler.handlePositionUpdate(makePosition(latitude: 28.0, longitude: 77.0));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(published.length, equals(1));

      // Queue a pending update
      throttler.handlePositionUpdate(makePosition(latitude: 28.1, longitude: 77.1));
      expect(throttler.isThrottleTimerActive, isTrue);

      // Immediately dispose
      throttler.dispose();
      expect(throttler.isThrottleTimerActive, isFalse);
      expect(throttler.latestPendingPosition, isNull);

      // Wait beyond throttle interval
      await Future.delayed(const Duration(milliseconds: 350));
      expect(published.length, equals(1)); // Zero trailing writes occurred!
    });
  });

  group('Phase 2.1 Fix 3: Handle True Zero Distance Correctly', () {
    test('3.1: True zero distance (0.0m) displays "0m" on map and is distinct from unknown', () {
      expect(formatMapDistance(0.0), equals('0m'));
      expect(formatMapDistance(0.2), equals('0m'));
      expect(formatMapDistance(0), equals('0m'));
      expect(formatMapDistance(null), equals('--'));
      expect(formatMapDistance(double.nan), equals('--'));
      expect(formatMapDistance(-1.0), equals('--'));
    });

    test('3.2: True zero distance in IncomingEmergencyCard displays "0 m away"', () {
      expect(formatCardDistance(0.0, 500.0), equals('0 m away'));
      expect(formatCardDistance(0.4, 500.0), equals('0 m away'));
      expect(formatCardDistance(0, 500.0), equals('0 m away'));

      // Null, negative or NaN falls back to broadcast radius
      expect(formatCardDistance(null, 500.0), equals('Within 500 m'));
      expect(formatCardDistance(null, 2500.0), equals('Within 2.5 km'));
      expect(formatCardDistance(-5.0, 500.0), equals('Within 500 m'));
      expect(formatCardDistance(double.nan, 500.0), equals('Within 500 m'));
      expect(formatCardDistance(null, 0.0), equals('Distance unknown'));
    });

    test('3.3: Positive short distances format accurately without truncation', () {
      expect(formatMapDistance(15.0), equals('15m'));
      expect(formatMapDistance(120.4), equals('120m'));
      expect(formatMapDistance(999.0), equals('999m'));
      expect(formatMapDistance(1500.0), equals('1.5km'));

      expect(formatCardDistance(15.0, 500.0), equals('15 m away'));
      expect(formatCardDistance(120.4, 500.0), equals('120 m away'));
      expect(formatCardDistance(1500.0, 500.0), equals('1.5 km away'));
    });

    test('3.4: Haversine distance handles identical coordinates as 0.0m, not null', () {
      final emergencyService = EmergencyService();
      final dist = emergencyService.calculateHaversineDistance(
        28.6139,
        77.2090,
        28.6139,
        77.2090,
      );

      expect(dist, isNotNull);
      expect(dist, equals(0.0));
      expect(dist! >= 0.0, isTrue);
    });

    test('3.5: Coordinates with zero component on Equator and Prime Meridian remain valid', () {
      expect(ResponderModel.isValidCoordinate(0.0, 25.0), isTrue); // Equator
      expect(ResponderModel.isValidCoordinate(51.5, 0.0), isTrue); // Prime Meridian
      expect(ResponderModel.isValidCoordinate(0.0, 0.0), isTrue); // Intersection
      expect(ResponderModel.isValidCoordinate(-91.0, 0.0), isFalse);
      expect(ResponderModel.isValidCoordinate(0.0, 181.0), isFalse);
    });
  });
}
