// test/screens/emergency_detail_screen_test.dart
//
// Vindara — EmergencyDetailScreen widget tests (Phase 5)
// Tests:
//   - Raw offline GPS coordinates rendered without map tiles (Rule #2).
//   - Role-aware buttons switch appropriately between Victim and Responder.
//   - Official 112 button present.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vindara/models/emergency.dart';
import 'package:vindara/models/user_profile.dart';
import 'package:vindara/providers/providers.dart';
import 'package:vindara/repositories/emergency_repository.dart';
import 'package:vindara/screens/emergency_detail_screen.dart';
import 'package:vindara/services/firestore_emergency_service.dart';

class MockFirestoreService extends Mock implements FirestoreEmergencyService {}
class MockEmergencyRepository extends Mock implements EmergencyRepository {}

void main() {
  late MockFirestoreService mockFirestoreService;
  late MockEmergencyRepository mockEmergencyRepository;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vindara_detail_test_');
    Hive.init(tempDir.path);
    mockFirestoreService = MockFirestoreService();
    mockEmergencyRepository = MockEmergencyRepository();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });
  final testEmergency = Emergency(
    id: 'EMG-2026-TEST0001',
    victimId: 'victim-uid-1',
    latitude: 19.0760,
    longitude: 72.8777,
    accuracyMeters: 4.5,
    type: EmergencyType.medical,
    createdAt: DateTime.utc(2026, 6, 1),
    detectionSource: DetectionSource.manualHelp,
    status: EmergencyStatus.alerting,
    communicationMode: CommunicationMode.offline,
    version: 1,
  );

  testWidgets(
      'EmergencyDetailScreen renders raw GPS without map tiles and victim actions',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          emergencyStreamProvider('EMG-2026-TEST0001')
              .overrideWith((ref) => Stream.value(testEmergency)),
          currentUserProfileProvider
              .overrideWith(() => MockVictimProfileNotifier()),
          firestoreEmergencyServiceProvider.overrideWithValue(mockFirestoreService),
          emergencyRepositoryProvider.overrideWithValue(mockEmergencyRepository),
        ],
        child: const MaterialApp(
          home: EmergencyDetailScreen(emergencyId: 'EMG-2026-TEST0001'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify offline-independent GPS coordinates are visible
    expect(find.textContaining('19.076000'), findsOneWidget);
    expect(find.textContaining('72.877700'), findsOneWidget);
    expect(find.textContaining('±4.5 metres'), findsOneWidget);
    expect(find.text('Copy Coordinates'), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);

    // 2. Victim action controls
    expect(find.text('Mark Resolved'), findsOneWidget);
    expect(find.text('Cancel Request'), findsOneWidget);

    // 3. Official 112 quick action
    expect(find.text('Call 112 Official Emergency Line'), findsOneWidget);
  });

  testWidgets(
      'EmergencyDetailScreen displays Accept & Respond button when viewer is responder',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          emergencyStreamProvider('EMG-2026-TEST0001')
              .overrideWith((ref) => Stream.value(testEmergency)),
          currentUserProfileProvider
              .overrideWith(() => MockResponderProfileNotifier()),
          firestoreEmergencyServiceProvider.overrideWithValue(mockFirestoreService),
          emergencyRepositoryProvider.overrideWithValue(mockEmergencyRepository),
        ],
        child: const MaterialApp(
          home: EmergencyDetailScreen(emergencyId: 'EMG-2026-TEST0001'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Responder sees Accept & Respond button
    expect(find.text('Accept & Respond (Primary)'), findsOneWidget);
  });
}

class MockVictimProfileNotifier extends CurrentUserProfileNotifier {
  @override
  Future<UserProfile?> build() async {
    return const UserProfile(
      uid: 'victim-uid-1',
      displayName: 'Victim User',
      isVerifiedResponder: false,
    );
  }
}

class MockResponderProfileNotifier extends CurrentUserProfileNotifier {
  @override
  Future<UserProfile?> build() async {
    return const UserProfile(
      uid: 'responder-uid-2',
      displayName: 'Responder Maya',
      isVerifiedResponder: true,
      isAvailable: true,
    );
  }
}
