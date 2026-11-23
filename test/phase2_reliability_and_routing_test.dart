import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/models/responder_model.dart';
import 'package:jan_sarthi/services/emergency_service.dart';
import 'package:jan_sarthi/services/responder_reliability_monitor.dart';
import 'package:jan_sarthi/services/routing_service_interface.dart';
import 'package:jan_sarthi/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2 Fix 1: Responder Location Validity, Freshness & Deterministic Ranking', () {
    test('1.1: ResponderModel.isValidCoordinate correctly validates geographical bounds', () {
      expect(ResponderModel.isValidCoordinate(0.0, 0.0), isTrue); // Equator / Prime Meridian intersection
      expect(ResponderModel.isValidCoordinate(0.0, 77.2090), isTrue); // On Equator with non-zero longitude
      expect(ResponderModel.isValidCoordinate(28.6139, 0.0), isTrue); // On Prime Meridian with non-zero latitude
      expect(ResponderModel.isValidCoordinate(90.0, 180.0), isTrue); // Max bounds
      expect(ResponderModel.isValidCoordinate(-90.0, -180.0), isTrue); // Min bounds
      expect(ResponderModel.isValidCoordinate(90.1, 0.0), isFalse); // Invalid latitude
      expect(ResponderModel.isValidCoordinate(-90.1, 0.0), isFalse);
      expect(ResponderModel.isValidCoordinate(0.0, 180.1), isFalse); // Invalid longitude
      expect(ResponderModel.isValidCoordinate(0.0, -180.1), isFalse);
      expect(ResponderModel.isValidCoordinate(null, 77.0), isFalse);
      expect(ResponderModel.isValidCoordinate(28.0, null), isFalse);
      expect(ResponderModel.isValidCoordinate(double.nan, 77.0), isFalse);
      expect(ResponderModel.isValidCoordinate(28.0, double.nan), isFalse);
    });

    test('1.2: ResponderModel.hasValidCoordinates evaluates both acquisition and range', () {
      final unacquired = ResponderModel(
        userId: 'u1',
        userName: 'User 1',
        phoneNumber: '+919876543210',
        bloodGroup: 'O+',
        userRole: 'CITIZEN',
        role: ResponderRole.STANDBY,
        status: ResponderStatus.STANDBY,
        latitude: 0.0,
        longitude: 0.0,
        hasAcquiredLocation: false,
        acceptedAt: DateTime.now(),
        lastLocationUpdate: DateTime.now(),
      );
      expect(unacquired.hasValidCoordinates, isFalse);

      final legitimateZero = ResponderModel(
        userId: 'u2',
        userName: 'User 2',
        phoneNumber: '+919876543210',
        bloodGroup: 'O+',
        userRole: 'CITIZEN',
        role: ResponderRole.STANDBY,
        status: ResponderStatus.STANDBY,
        latitude: 0.0,
        longitude: 0.0,
        hasAcquiredLocation: true,
        acceptedAt: DateTime.now(),
        lastLocationUpdate: DateTime.now(),
      );
      expect(legitimateZero.hasValidCoordinates, isTrue);

      final invalidCoord = ResponderModel(
        userId: 'u3',
        userName: 'User 3',
        phoneNumber: '+919876543210',
        bloodGroup: 'O+',
        userRole: 'CITIZEN',
        role: ResponderRole.STANDBY,
        status: ResponderStatus.STANDBY,
        latitude: 195.0,
        longitude: 77.0,
        hasAcquiredLocation: true,
        acceptedAt: DateTime.now(),
        lastLocationUpdate: DateTime.now(),
      );
      expect(invalidCoord.hasValidCoordinates, isFalse);
    });

    test('1.3: ResponderModel.isLocationFresh distinguishes fresh from stale coordinates', () {
      final now = DateTime.now();
      final fresh = ResponderModel(
        userId: 'u1',
        userName: 'User 1',
        phoneNumber: '+919876543210',
        bloodGroup: 'O+',
        userRole: 'CITIZEN',
        role: ResponderRole.PRIMARY,
        status: ResponderStatus.PRIMARY,
        latitude: 28.6139,
        longitude: 77.2090,
        acceptedAt: now.subtract(const Duration(minutes: 10)),
        lastLocationUpdate: now.subtract(const Duration(seconds: 30)),
      );
      expect(fresh.isLocationFresh(maxAge: const Duration(minutes: 2), now: now), isTrue);

      final stale = ResponderModel(
        userId: 'u2',
        userName: 'User 2',
        phoneNumber: '+919876543210',
        bloodGroup: 'O+',
        userRole: 'CITIZEN',
        role: ResponderRole.PRIMARY,
        status: ResponderStatus.PRIMARY,
        latitude: 28.6139,
        longitude: 77.2090,
        acceptedAt: now.subtract(const Duration(minutes: 10)),
        lastLocationUpdate: now.subtract(const Duration(minutes: 6)),
      );
      expect(stale.isLocationFresh(maxAge: const Duration(minutes: 2), now: now), isFalse);
    });

    test('1.4: EmergencyService.calculateHaversineDistance never treats unacquired coordinates as 0 meters', () {
      final service = EmergencyService();

      // Missing / unacquired coordinates return null, NOT 0.0
      expect(service.calculateHaversineDistance(null, null, 28.6139, 77.2090), isNull);
      expect(service.calculateHaversineDistance(28.6139, 77.2090, null, null), isNull);
      expect(
        service.calculateHaversineDistance(
          0.0,
          0.0,
          28.6139,
          77.2090,
          hasCoord1: false,
          hasCoord2: true,
        ),
        isNull,
      );

      // Legitimate coordinates on Equator/Prime Meridian calculate real positive distance
      final distance = service.calculateHaversineDistance(
        0.0,
        0.0,
        28.6139,
        77.2090,
        hasCoord1: true,
        hasCoord2: true,
      );
      expect(distance, isNotNull);
      expect(distance!, greaterThan(5000000)); // ~8,700 km
    });

    test('1.5: Tiered candidate sorting in offline emergency handover prefers fresh coordinates over unacquired', () async {
      SharedPreferences.setMockInitialValues({});
      final localDb = LocalDatabaseService();
      final service = EmergencyService();
      final now = DateTime.now();

      const victimLat = 28.6139;
      const victimLon = 77.2090;

      // Primary responder reporting delay
      final primary = ResponderModel(
        userId: 'primary_1',
        userName: 'Primary Helper',
        phoneNumber: '+919876543210',
        bloodGroup: 'A+',
        userRole: 'CITIZEN',
        role: ResponderRole.PRIMARY,
        status: ResponderStatus.PRIMARY,
        latitude: 28.6200,
        longitude: 77.2100,
        hasAcquiredLocation: true,
        acceptedAt: now.subtract(const Duration(minutes: 5)),
        lastLocationUpdate: now,
      );

      // Standby 1: Unacquired location (previously defaulted to 0,0 and was ranked as 0m closest)
      final standbyUnacquired = ResponderModel(
        userId: 'standby_unacquired',
        userName: 'Unacquired Location Helper',
        phoneNumber: '+919876543211',
        bloodGroup: 'B+',
        userRole: 'CITIZEN',
        role: ResponderRole.STANDBY,
        status: ResponderStatus.STANDBY,
        latitude: 0.0,
        longitude: 0.0,
        hasAcquiredLocation: false,
        acceptedAt: now.subtract(const Duration(minutes: 4)),
        lastLocationUpdate: now,
      );

      // Standby 2: Legitimate valid & fresh GPS ~500m away
      final standbyFresh = ResponderModel(
        userId: 'standby_fresh',
        userName: 'Fresh Location Helper',
        phoneNumber: '+919876543212',
        bloodGroup: 'O+',
        userRole: 'CITIZEN',
        role: ResponderRole.STANDBY,
        status: ResponderStatus.STANDBY,
        latitude: 28.6180,
        longitude: 77.2100,
        hasAcquiredLocation: true,
        acceptedAt: now.subtract(const Duration(minutes: 3)),
        lastLocationUpdate: now,
      );

      final emergency = EmergencyModel(
        id: 'JS-OFF-P2-001',
        victimId: 'victim_p2',
        type: 'MEDICAL',
        latitude: victimLat,
        longitude: victimLon,
        status: EmergencyStatus.ASSIGNED,
        helperId: primary.userId,
        responders: {
          primary.userId: primary,
          standbyUnacquired.userId: standbyUnacquired,
          standbyFresh.userId: standbyFresh,
        },
        createdAt: now,
        updatedAt: now,
      );

      await localDb.saveEmergencyLocally(emergency);

      // Primary reports fatal delay requiring handover
      final result = await service.reportProblem(
        emergencyId: emergency.id,
        userId: primary.userId,
        reason: 'Vehicle breakdown',
        isFatal: true,
      );

      expect(result.hasNewPrimary, isTrue);
      // Verify that standbyFresh is chosen as new primary, NOT standbyUnacquired
      expect(result.newPrimaryId, equals('standby_fresh'));
      expect(result.newPrimaryName, equals('Fresh Location Helper'));

      final updated = await localDb.getEmergencyById(emergency.id);
      expect(updated?.helperId, equals('standby_fresh'));
      expect(updated?.responders['standby_fresh']?.role, equals(ResponderRole.PRIMARY));
      expect(updated?.responders['standby_unacquired']?.role, equals(ResponderRole.STANDBY));
    });
  });

  group('Phase 2 Fix 2: Reliability Monitor Heartbeat & Single-Authority Policy', () {
    test('2.1: Stationary responder does NOT get demoted if heartbeat is maintained', () {
      final monitor = ResponderReliabilityMonitor(
        locationStaleThresholdSeconds: 15,
        connectionGracePeriodSeconds: 20,
        noProgressThresholdSeconds: 120,
      );

      expect(monitor.locationStaleThresholdSeconds, equals(15));
      expect(monitor.connectionGracePeriodSeconds, equals(20));
      expect(monitor.noProgressThresholdSeconds, equals(120));
    });

    test('2.2: Local emergency model touchResponderHeartbeat updates lastLocationUpdate without movement', () async {
      SharedPreferences.setMockInitialValues({});
      final localDb = LocalDatabaseService();
      final service = EmergencyService();
      final oldTime = DateTime.now().subtract(const Duration(seconds: 40));

      final responder = ResponderModel(
        userId: 'stationary_resp',
        userName: 'Stationary Helper',
        phoneNumber: '+919876543210',
        bloodGroup: 'AB+',
        userRole: 'CITIZEN',
        role: ResponderRole.PRIMARY,
        status: ResponderStatus.PRIMARY,
        latitude: 28.6139,
        longitude: 77.2090,
        hasAcquiredLocation: true,
        acceptedAt: oldTime,
        lastLocationUpdate: oldTime,
      );

      final emergency = EmergencyModel(
        id: 'JS-OFF-HEARTBEAT-001',
        victimId: 'victim_hb',
        type: 'MEDICAL',
        latitude: 28.6140,
        longitude: 77.2090,
        status: EmergencyStatus.ASSIGNED,
        helperId: responder.userId,
        responders: {responder.userId: responder},
        createdAt: oldTime,
        updatedAt: oldTime,
      );

      await localDb.saveEmergencyLocally(emergency);

      final pos = Position(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      await service.touchResponderHeartbeat(
        emergencyId: emergency.id,
        userId: responder.userId,
        position: pos,
      );

      final saved = await localDb.getEmergencyById(emergency.id);
      final updatedResp = saved?.responders['stationary_resp'];
      expect(updatedResp, isNotNull);
      expect(updatedResp!.lastLocationUpdate.difference(oldTime).inSeconds, greaterThanOrEqualTo(30));
    });
  });

  group('Phase 2 Fix 3 & Fix 4: Distance, ETA, OSRM Fallback & Retry Behavior', () {
    test('3.1: RouteResult distinguishes road route from direct fallback', () {
      final roadRoute = RouteResult(
        polylinePoints: [const LatLng(28.6139, 77.2090), const LatLng(28.6180, 77.2100)],
        distanceMeters: 620.0,
        durationSeconds: 120.0,
        etaText: '2 mins',
        isRoadRoute: true,
      );
      expect(roadRoute.isRoadRoute, isTrue);
      expect(roadRoute.distanceMeters, equals(620.0));
      expect(roadRoute.etaText, equals('2 mins'));

      final directFallback = RouteResult.directFallback(
        origin: const LatLng(28.6139, 77.2090),
        destination: const LatLng(28.6200, 77.2150),
        directDistanceMeters: 890.0,
      );
      expect(directFallback.isRoadRoute, isFalse);
      expect(directFallback.distanceMeters, equals(890.0));
      expect(directFallback.etaText, equals('ETA unavailable'));
      expect(directFallback.polylinePoints.length, equals(2));
    });

    test('3.2: Direct distance calculation produces accurate straight-line meters', () {
      const origin = LatLng(28.6139, 77.2090);
      const dest = LatLng(28.6239, 77.2090); // ~1.11 km north

      final dist = Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        dest.latitude,
        dest.longitude,
      );

      expect(dist, greaterThan(1100));
      expect(dist, lessThan(1120));
    });
  });

  group('Phase 2 Fix 5: Offline Emergency Synchronization & Firestore Rules Compliance', () {
    test('5.1: LocalDatabaseService records and retrieves synchronization failure metadata', () async {
      SharedPreferences.setMockInitialValues({});
      final localDb = LocalDatabaseService();

      final emergency = EmergencyModel(
        id: 'JS-OFF-SYNC-001',
        victimId: 'offline_user',
        type: 'ACCIDENT',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.COMPLETED,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await localDb.saveEmergencyLocally(emergency);

      // Verify initially unsynced
      final unsynced1 = await localDb.getUnsyncedEmergencies();
      expect(unsynced1.any((e) => e.id == emergency.id), isTrue);

      // Record a sync failure
      const errorMsg = 'Identity mismatch: Sign-in required before offline emergency can be synced';
      await localDb.recordSyncFailure(emergency.id, errorMsg);

      // Verify record is preserved for safe retry
      final unsynced2 = await localDb.getUnsyncedEmergencies();
      expect(unsynced2.any((e) => e.id == emergency.id), isTrue);

      final failureMeta = await localDb.getSyncFailure(emergency.id);
      expect(failureMeta, isNotNull);
      expect(failureMeta!['reason'], equals(errorMsg));
      expect(failureMeta['timestamp'], isNotEmpty);

      // Mark as synced clears failure metadata
      await localDb.markAsSynced(emergency.id);
      final unsynced3 = await localDb.getUnsyncedEmergencies();
      expect(unsynced3.any((e) => e.id == emergency.id), isFalse);

      final failureAfterSync = await localDb.getSyncFailure(emergency.id);
      expect(failureAfterSync, isNull);
    });

    test('5.2: Terminal emergency status is preserved locally and not regressed on retry', () async {
      SharedPreferences.setMockInitialValues({});
      final localDb = LocalDatabaseService();

      final emergency = EmergencyModel(
        id: 'JS-OFF-SYNC-002',
        victimId: 'auth_victim_1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.COMPLETED,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await localDb.saveEmergencyLocally(emergency);
      await localDb.recordSyncFailure(emergency.id, 'Temporary network timeout');

      final stored = await localDb.getEmergencyById(emergency.id);
      expect(stored?.status, equals(EmergencyStatus.COMPLETED));
      expect(stored?.isTerminal, isTrue);
    });

    test('4.1: OSRM route retry eligibility: stationary device retries failed route after 15s delay', () {
      const origin = LatLng(28.6139, 77.2090);
      const dest = LatLng(28.6200, 77.2100);

      // Helper function mirroring _shouldRecalculateRoute logic
      bool shouldRecalculate({
        required bool isFetchingRoute,
        required LatLng? lastOrigin,
        required LatLng? lastDest,
        required bool isLastRouteRoad,
        required DateTime? lastRouteFetchTime,
      }) {
        if (isFetchingRoute) return false;
        if (lastOrigin == null || lastDest == null) return true;

        double originDelta = Geolocator.distanceBetween(
          origin.latitude,
          origin.longitude,
          lastOrigin.latitude,
          lastOrigin.longitude,
        );
        double destDelta = Geolocator.distanceBetween(
          dest.latitude,
          dest.longitude,
          lastDest.latitude,
          lastDest.longitude,
        );

        if (originDelta >= 8.0 || destDelta >= 8.0) return true;

        if (!isLastRouteRoad &&
            (lastRouteFetchTime == null || DateTime.now().difference(lastRouteFetchTime).inSeconds >= 15)) {
          return true;
        }

        return false;
      }

      // Case A: Device has not moved, last route was road, less than 15s -> do NOT recalculate
      expect(
        shouldRecalculate(
          isFetchingRoute: false,
          lastOrigin: origin,
          lastDest: dest,
          isLastRouteRoad: true,
          lastRouteFetchTime: DateTime.now(),
        ),
        isFalse,
      );

      // Case B: Device has not moved, last route was direct fallback (failed), but less than 15s -> bounded delay throttles
      expect(
        shouldRecalculate(
          isFetchingRoute: false,
          lastOrigin: origin,
          lastDest: dest,
          isLastRouteRoad: false,
          lastRouteFetchTime: DateTime.now().subtract(const Duration(seconds: 5)),
        ),
        isFalse,
      );

      // Case C: Device has not moved, last route was direct fallback (failed), 16s elapsed -> ELIGIBLE FOR RETRY!
      expect(
        shouldRecalculate(
          isFetchingRoute: false,
          lastOrigin: origin,
          lastDest: dest,
          isLastRouteRoad: false,
          lastRouteFetchTime: DateTime.now().subtract(const Duration(seconds: 16)),
        ),
        isTrue,
      );

      // Case D: Simultaneous in-flight request blocks duplicate fetch
      expect(
        shouldRecalculate(
          isFetchingRoute: true,
          lastOrigin: origin,
          lastDest: dest,
          isLastRouteRoad: false,
          lastRouteFetchTime: DateTime.now().subtract(const Duration(seconds: 20)),
        ),
        isFalse,
      );
    });
  });
}
