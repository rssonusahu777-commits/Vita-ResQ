// test/screens/crash_countdown_screen_test.dart
//
// Vindara — CrashCountdownScreen Widget Tests (Phase 6)
// Rules followed:
//   Rule #6 — Single-lifecycle streams & proper disposal.
//   Rule #10 — Honest "Possible Crash" framing, strictly ZERO "SOS" strings.
//              10s circular countdown, massive "I'M SAFE — CANCEL", and "SEND HELP NOW".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vindara/models/emergency.dart';
import 'package:vindara/models/user_profile.dart';
import 'package:vindara/providers/providers.dart';
import 'package:vindara/repositories/emergency_repository.dart';
import 'package:vindara/screens/crash_countdown_screen.dart';

class MockEmergencyRepository extends Mock implements EmergencyRepository {}

void main() {
  late MockEmergencyRepository mockRepository;

  setUpAll(() {
    registerFallbackValue(EmergencyType.accident);
    registerFallbackValue(DetectionSource.possibleCrash);
    registerFallbackValue(EmergencyStatus.alerting);
  });

  setUp(() {
    mockRepository = MockEmergencyRepository();
  });

  final testEmergency = Emergency(
    id: 'EMG-2026-CRASH001',
    victimId: 'victim-test-uid',
    latitude: 19.0760,
    longitude: 72.8777,
    accuracyMeters: 5.0,
    type: EmergencyType.accident,
    createdAt: DateTime.utc(2026, 6, 1),
    detectionSource: DetectionSource.possibleCrash,
    status: EmergencyStatus.created,
    communicationMode: CommunicationMode.offline,
    version: 1,
  );

  testWidgets(
      'CrashCountdownScreen displays Possible Crash UI and zero SOS strings',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProfileProvider.overrideWith(() => MockUserProfileNotifier()),
          emergencyRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const MaterialApp(
          home: CrashCountdownScreen(initialSeconds: 10),
        ),
      ),
    );

    await tester.pump();

    // 1. Honest "Possible Crash" framing (Rule #10)
    expect(find.text('⚠️ Possible Crash Detected'), findsOneWidget);
    expect(
      find.text('Are you safe? Sending a HELP alert automatically in 10s...'),
      findsOneWidget,
    );

    // 2. Strict UX Rule: Zero occurrences of "SOS"
    expect(find.textContaining('SOS'), findsNothing);

    // 3. Buttons present
    expect(find.text("I'M SAFE — CANCEL"), findsOneWidget);
    expect(find.text('SEND HELP NOW'), findsOneWidget);

    // 4. Initial countdown seconds displayed
    expect(find.text('10'), findsOneWidget);

    // Cancel timer by tapping "I'M SAFE — CANCEL"
    await tester.tap(find.text("I'M SAFE — CANCEL"));
    await tester.pump();
  });

  testWidgets('Pressing "I\'M SAFE — CANCEL" cancels countdown',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProfileProvider.overrideWith(() => MockUserProfileNotifier()),
          emergencyRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CrashCountdownScreen(initialSeconds: 10),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('10'), findsOneWidget);

    // Tap cancel
    await tester.tap(find.text("I'M SAFE — CANCEL"));
    await tester.pump();

    // Verify no emergency was created
    verifyNever(() => mockRepository.createEmergency(
          victimId: any(named: 'victimId'),
          type: any(named: 'type'),
          detectionSource: any(named: 'detectionSource'),
        ));
  });

  testWidgets('Pressing "SEND HELP NOW" immediately creates emergency',
      (WidgetTester tester) async {
    when(() => mockRepository.createEmergency(
          victimId: any(named: 'victimId'),
          type: EmergencyType.accident,
          detectionSource: DetectionSource.possibleCrash,
        )).thenAnswer((_) async => testEmergency);

    when(() => mockRepository.transitionStatus(
          testEmergency.id,
          EmergencyStatus.alerting,
        )).thenAnswer((_) async => TransitionSuccess(testEmergency.copyWith(status: EmergencyStatus.alerting)));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProfileProvider.overrideWith(() => MockUserProfileNotifier()),
          emergencyRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CrashCountdownScreen(initialSeconds: 10),
          ),
        ),
      ),
    );

    await tester.pump();

    // Tap SEND HELP NOW
    await tester.tap(find.text('SEND HELP NOW'));
    await tester.pump();

    // Verify emergency created with Rule #10 semantics
    verify(() => mockRepository.createEmergency(
          victimId: any(named: 'victimId'),
          type: EmergencyType.accident,
          detectionSource: DetectionSource.possibleCrash,
        )).called(1);

    verify(() => mockRepository.transitionStatus(
          testEmergency.id,
          EmergencyStatus.alerting,
        )).called(1);
  });

  testWidgets('Countdown auto-triggers HELP when timer reaches 0',
      (WidgetTester tester) async {
    when(() => mockRepository.createEmergency(
          victimId: any(named: 'victimId'),
          type: EmergencyType.accident,
          detectionSource: DetectionSource.possibleCrash,
        )).thenAnswer((_) async => testEmergency);

    when(() => mockRepository.transitionStatus(
          testEmergency.id,
          EmergencyStatus.alerting,
        )).thenAnswer((_) async => TransitionSuccess(testEmergency.copyWith(status: EmergencyStatus.alerting)));

    // Start with 1 second countdown so we can advance it without long delay
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProfileProvider.overrideWith(() => MockUserProfileNotifier()),
          emergencyRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CrashCountdownScreen(initialSeconds: 1),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    // Advance 1 second to trigger expiration
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // Verify emergency created automatically
    verify(() => mockRepository.createEmergency(
          victimId: any(named: 'victimId'),
          type: EmergencyType.accident,
          detectionSource: DetectionSource.possibleCrash,
        )).called(1);

    verify(() => mockRepository.transitionStatus(
          testEmergency.id,
          EmergencyStatus.alerting,
        )).called(1);
  });
}

class MockUserProfileNotifier extends CurrentUserProfileNotifier {
  @override
  Future<UserProfile?> build() async {
    return const UserProfile(
      uid: 'victim-test-uid',
      displayName: 'Test Victim',
      isVerifiedResponder: false,
      isAvailable: true,
      reputationPoints: 100,
    );
  }
}

