// test/services/firestore_emergency_service_test.dart
//
// Vindara — FirestoreEmergencyService unit tests
// Tests atomic responder claims (Rule #3), role releases, and version-guarded upserts.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vindara/models/emergency.dart';
import 'package:vindara/services/firestore_emergency_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}
class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}
class MockTransaction extends Mock implements Transaction {}

void main() {
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockCollection;
  late MockDocumentReference mockDocRef;
  late MockDocumentSnapshot mockSnapshot;
  late MockTransaction mockTransaction;
  late FirestoreEmergencyService firestoreService;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockCollection = MockCollectionReference();
    mockDocRef = MockDocumentReference();
    mockSnapshot = MockDocumentSnapshot();
    mockTransaction = MockTransaction();

    when(() => mockFirestore.collection('emergencies')).thenReturn(mockCollection);
    when(() => mockCollection.doc(any())).thenReturn(mockDocRef);

    firestoreService = FirestoreEmergencyService(firestore: mockFirestore);
  });

  Emergency makeEmergency({
    String id = 'EMG-2026-CLAIM001',
    EmergencyStatus status = EmergencyStatus.alerting,
    String? primaryResponderId,
    String? standbyResponderId,
    int version = 1,
  }) {
    return Emergency(
      id: id,
      victimId: 'user-vic',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 5.0,
      type: EmergencyType.medical,
      createdAt: DateTime.utc(2026, 6, 1),
      detectionSource: DetectionSource.manualHelp,
      status: status,
      primaryResponderId: primaryResponderId,
      standbyResponderId: standbyResponderId,
      communicationMode: CommunicationMode.online,
      version: version,
    );
  }

  group('FirestoreEmergencyService — Atomic Responder Claims (Rule #3)', () {
    test('first claim makes responder the primaryResponderId and transitions to accepted',
        () async {
      final initial = makeEmergency(status: EmergencyStatus.alerting);

      when(() => mockFirestore.runTransaction<ClaimResult>(any()))
          .thenAnswer((invocation) async {
        final callback =
            invocation.positionalArguments[0] as TransactionHandler<ClaimResult>;
        when(() => mockTransaction.get(mockDocRef))
            .thenAnswer((_) async => mockSnapshot);
        when(() => mockSnapshot.exists).thenReturn(true);
        when(() => mockSnapshot.data()).thenReturn(initial.toJson());
        when(() => mockTransaction.update(mockDocRef, any()))
            .thenReturn(mockTransaction);

        return await callback(mockTransaction);
      });

      final result = await firestoreService.claimEmergency(
          'EMG-2026-CLAIM001', 'responder-primary');

      expect(result, isA<ClaimPrimarySuccess>());
      final success = result as ClaimPrimarySuccess;
      expect(success.emergency.primaryResponderId, equals('responder-primary'));
      expect(success.emergency.standbyResponderId, isNull);
      expect(success.emergency.status, equals(EmergencyStatus.accepted));
      expect(success.emergency.version, equals(initial.version + 1));
    });

    test('second concurrent claim assigns second responder to standbyResponderId',
        () async {
      final claimed = makeEmergency(
        status: EmergencyStatus.accepted,
        primaryResponderId: 'responder-1',
        version: 2,
      );

      when(() => mockFirestore.runTransaction<ClaimResult>(any()))
          .thenAnswer((invocation) async {
        final callback =
            invocation.positionalArguments[0] as TransactionHandler<ClaimResult>;
        when(() => mockTransaction.get(mockDocRef))
            .thenAnswer((_) async => mockSnapshot);
        when(() => mockSnapshot.exists).thenReturn(true);
        when(() => mockSnapshot.data()).thenReturn(claimed.toJson());
        when(() => mockTransaction.update(mockDocRef, any()))
            .thenReturn(mockTransaction);

        return await callback(mockTransaction);
      });

      final result = await firestoreService.claimEmergency(
          'EMG-2026-CLAIM001', 'responder-2');

      expect(result, isA<ClaimStandbySuccess>());
      final standby = result as ClaimStandbySuccess;
      expect(standby.emergency.primaryResponderId, equals('responder-1'));
      expect(standby.emergency.standbyResponderId, equals('responder-2'));
      expect(standby.emergency.version, equals(claimed.version + 1));
    });

    test('third claim returns AlreadyClaimedResult when both primary and standby exist',
        () async {
      final fullyClaimed = makeEmergency(
        status: EmergencyStatus.accepted,
        primaryResponderId: 'responder-1',
        standbyResponderId: 'responder-2',
        version: 3,
      );

      when(() => mockFirestore.runTransaction<ClaimResult>(any()))
          .thenAnswer((invocation) async {
        final callback =
            invocation.positionalArguments[0] as TransactionHandler<ClaimResult>;
        when(() => mockTransaction.get(mockDocRef))
            .thenAnswer((_) async => mockSnapshot);
        when(() => mockSnapshot.exists).thenReturn(true);
        when(() => mockSnapshot.data()).thenReturn(fullyClaimed.toJson());

        return await callback(mockTransaction);
      });

      final result = await firestoreService.claimEmergency(
          'EMG-2026-CLAIM001', 'responder-3');

      expect(result, isA<AlreadyClaimedResult>());
    });

    test('releasePrimaryRole promotes standbyResponderId to primaryResponderId',
        () async {
      final docWithStandby = makeEmergency(
        status: EmergencyStatus.accepted,
        primaryResponderId: 'responder-1',
        standbyResponderId: 'responder-2',
        version: 3,
      );

      when(() => mockFirestore.runTransaction<Emergency?>(any()))
          .thenAnswer((invocation) async {
        final callback =
            invocation.positionalArguments[0] as TransactionHandler<Emergency?>;
        when(() => mockTransaction.get(mockDocRef))
            .thenAnswer((_) async => mockSnapshot);
        when(() => mockSnapshot.exists).thenReturn(true);
        when(() => mockSnapshot.data()).thenReturn(docWithStandby.toJson());
        when(() => mockTransaction.update(mockDocRef, any()))
            .thenReturn(mockTransaction);

        return await callback(mockTransaction);
      });

      final updated = await firestoreService.releasePrimaryRole(
          'EMG-2026-CLAIM001', 'responder-1');

      expect(updated, isNotNull);
      expect(updated!.primaryResponderId, equals('responder-2'));
      expect(updated.standbyResponderId, isNull);
      expect(updated.status, equals(EmergencyStatus.accepted));
      expect(updated.version, equals(4));
    });

    test('releasePrimaryRole resets to alerting when no standby responder exists',
        () async {
      final docNoStandby = makeEmergency(
        status: EmergencyStatus.accepted,
        primaryResponderId: 'responder-1',
        standbyResponderId: null,
        version: 2,
      );

      when(() => mockFirestore.runTransaction<Emergency?>(any()))
          .thenAnswer((invocation) async {
        final callback =
            invocation.positionalArguments[0] as TransactionHandler<Emergency?>;
        when(() => mockTransaction.get(mockDocRef))
            .thenAnswer((_) async => mockSnapshot);
        when(() => mockSnapshot.exists).thenReturn(true);
        when(() => mockSnapshot.data()).thenReturn(docNoStandby.toJson());
        when(() => mockTransaction.update(mockDocRef, any()))
            .thenReturn(mockTransaction);

        return await callback(mockTransaction);
      });

      final updated = await firestoreService.releasePrimaryRole(
          'EMG-2026-CLAIM001', 'responder-1');

      expect(updated, isNotNull);
      expect(updated!.primaryResponderId, isNull);
      expect(updated.status, equals(EmergencyStatus.alerting));
      expect(updated.version, equals(3));
    });
  });
}
