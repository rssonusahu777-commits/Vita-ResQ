import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/services/auth_service.dart';
import 'package:jan_sarthi/services/community_relay_service.dart';
import 'package:jan_sarthi/services/p2p_payload_integrity.dart';

class MockRelayFirestoreWriter implements IRelayFirestoreWriter {
  final Map<String, Map<String, dynamic>> store = {};
  int writeCount = 0;
  int readCount = 0;

  @override
  Future<bool> documentExists(String documentPath) async {
    readCount++;
    return store.containsKey(documentPath);
  }

  @override
  Future<void> writeDocument(String documentPath, Map<String, dynamic> data) async {
    writeCount++;
    store[documentPath] = Map<String, dynamic>.from(data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 — Community Cloud Gateway Relay Tests', () {
    late MockRelayFirestoreWriter mockWriter;
    late CommunityRelayService relayService;
    final DateTime fixedNow = DateTime(2026, 11, 24, 12, 0, 0);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AuthService.resetCacheForTesting();
      mockWriter = MockRelayFirestoreWriter();
      relayService = CommunityRelayService(
        firestoreWriter: mockWriter,
        clock: () => fixedNow,
      );
    });

    tearDown(() {
      AuthService.resetCacheForTesting();
    });

    test('a) Fresh (< 10 min), validly signed JS-OFF- alert relays once to Firestore with isRelayedOffline: true and relayedByUid', () async {
      final createdAt = fixedNow.subtract(const Duration(minutes: 2));
      final alert = EmergencyModel(
        id: 'JS-OFF-1001',
        victimId: 'offline_victim_888',
        originDeviceId: 'dev_victim_phone_1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final signedPayload = P2PPayloadIntegrity.signPayload({
        'eventType': 'SOS_BROADCAST',
        'emergencyId': 'JS-OFF-1001',
        'victimId': 'offline_victim_888',
        'originDeviceId': 'dev_victim_phone_1',
        'type': 'MEDICAL',
        'latitude': 28.6139,
        'longitude': 77.2090,
        'timestamp': createdAt.millisecondsSinceEpoch,
      });

      final success = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: 'bystander_volunteer_777',
        isOnline: true,
        now: fixedNow,
      );

      expect(success, isTrue);
      expect(mockWriter.writeCount, 1);
      expect(mockWriter.readCount, 1);

      final written = mockWriter.store['emergencies/JS-OFF-1001'];
      expect(written, isNotNull);
      expect(written!['isRelayedOffline'], isTrue);
      expect(written['relayedByUid'], 'bystander_volunteer_777');
      expect(written['status'], 'SEARCHING');
      expect(written['currentRadiusMeters'], 500.0);
      expect(written['victimId'], 'offline_victim_888');
    });

    test('b) Stale (15 min old) JS-OFF- alert is rejected before any Firestore write', () async {
      final createdAt = fixedNow.subtract(const Duration(minutes: 15));
      final alert = EmergencyModel(
        id: 'JS-OFF-1002',
        victimId: 'offline_victim_888',
        originDeviceId: 'dev_victim_phone_1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final signedPayload = P2PPayloadIntegrity.signPayload({
        'eventType': 'SOS_BROADCAST',
        'emergencyId': 'JS-OFF-1002',
        'timestamp': createdAt.millisecondsSinceEpoch,
      });

      final success = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: 'bystander_volunteer_777',
        isOnline: true,
        now: fixedNow,
      );

      expect(success, isFalse);
      expect(mockWriter.writeCount, 0);
      expect(mockWriter.readCount, 0); // Gate 3 rejects before Firestore read
    });

    test('c) Tampered SHA-256 payload is rejected before any Firestore write', () async {
      final createdAt = fixedNow.subtract(const Duration(minutes: 1));
      final alert = EmergencyModel(
        id: 'JS-OFF-1003',
        victimId: 'offline_victim_888',
        originDeviceId: 'dev_victim_phone_1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final signedPayload = P2PPayloadIntegrity.signPayload({
        'eventType': 'SOS_BROADCAST',
        'emergencyId': 'JS-OFF-1003',
        'latitude': 28.6139,
        'longitude': 77.2090,
        'timestamp': createdAt.millisecondsSinceEpoch,
      });

      // Tamper with payload after signing
      signedPayload['latitude'] = 12.3456;

      final success = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: 'bystander_volunteer_777',
        isOnline: true,
        now: fixedNow,
      );

      expect(success, isFalse);
      expect(mockWriter.writeCount, 0);
      expect(mockWriter.readCount, 0); // Gate 1 rejects before Firestore read
    });

    test('d) Terminal (CANCELLED / COMPLETED) alert is rejected before any Firestore write', () async {
      final createdAt = fixedNow.subtract(const Duration(minutes: 1));
      final completedAlert = EmergencyModel(
        id: 'JS-OFF-1004',
        victimId: 'offline_victim_888',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.COMPLETED,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final signedPayload = P2PPayloadIntegrity.signPayload({
        'eventType': 'SOS_BROADCAST',
        'emergencyId': 'JS-OFF-1004',
        'timestamp': createdAt.millisecondsSinceEpoch,
      });

      final success = await relayService.relayOfflineAlertIfEligible(
        alert: completedAlert,
        rawPayload: signedPayload,
        currentUserId: 'bystander_volunteer_777',
        isOnline: true,
        now: fixedNow,
      );

      expect(success, isFalse);
      expect(mockWriter.writeCount, 0);
      expect(mockWriter.readCount, 0); // Gate 2 rejects before Firestore read
    });

    test('e) If emergencies/JS-OFF-... already exists in Firestore (active or terminal), relay skips without overwriting', () async {
      final createdAt = fixedNow.subtract(const Duration(minutes: 3));
      final alert = EmergencyModel(
        id: 'JS-OFF-1005',
        victimId: 'offline_victim_888',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      // Pre-seed Firestore store with existing document
      mockWriter.store['emergencies/JS-OFF-1005'] = {
        'id': 'JS-OFF-1005',
        'status': 'ASSIGNED',
        'helperId': 'earlier_responder_999',
      };

      final signedPayload = P2PPayloadIntegrity.signPayload({
        'eventType': 'SOS_BROADCAST',
        'emergencyId': 'JS-OFF-1005',
        'timestamp': createdAt.millisecondsSinceEpoch,
      });

      final success = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: 'bystander_volunteer_777',
        isOnline: true,
        now: fixedNow,
      );

      expect(success, isFalse);
      expect(mockWriter.readCount, 1);
      expect(mockWriter.writeCount, 0); // Did not write/overwrite
      expect(mockWriter.store['emergencies/JS-OFF-1005']?['status'], 'ASSIGNED');
    });

    test('f) Guest / offline user never attempts a Firestore relay write', () async {
      final createdAt = fixedNow.subtract(const Duration(minutes: 1));
      final alert = EmergencyModel(
        id: 'JS-OFF-1006',
        victimId: 'offline_victim_888',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final signedPayload = P2PPayloadIntegrity.signPayload({
        'eventType': 'SOS_BROADCAST',
        'emergencyId': 'JS-OFF-1006',
        'timestamp': createdAt.millisecondsSinceEpoch,
      });

      // 1. Offline user (no internet)
      final offlineRes = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: 'bystander_volunteer_777',
        isOnline: false,
        now: fixedNow,
      );
      expect(offlineRes, isFalse);

      // 2. Guest user ID prefix
      final guestIdRes = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: 'offline_guest_dev_123',
        isOnline: true,
        now: fixedNow,
      );
      expect(guestIdRes, isFalse);

      // 3. Unauthenticated generic 'offline_user'
      final unauthRes = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: 'offline_user',
        isOnline: true,
        now: fixedNow,
      );
      expect(unauthRes, isFalse);

      // 4. Empty user ID
      final emptyUserRes = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: '',
        isOnline: true,
        now: fixedNow,
      );
      expect(emptyUserRes, isFalse);

      // 5. Guest session active in AuthService
      final authService = AuthService();
      await authService.enterGuestOfflineMode();
      final guestModeRes = await relayService.relayOfflineAlertIfEligible(
        alert: alert,
        rawPayload: signedPayload,
        currentUserId: 'bystander_volunteer_777',
        isOnline: true,
        now: fixedNow,
      );
      expect(guestModeRes, isFalse);

      expect(mockWriter.writeCount, 0);
      expect(mockWriter.readCount, 0);
    });
  });
}

