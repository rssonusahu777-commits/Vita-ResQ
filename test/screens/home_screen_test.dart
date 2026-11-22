// test/screens/home_screen_test.dart
//
// Vindara — HomeScreen widget tests (Phase 5)
// Tests:
//   - Zero "SOS" labels in UI (strictly "HELP").
//   - "Call 112 (Official Emergency)" button present.
//   - Live connectivity pill rendered.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vindara/models/user_profile.dart';
import 'package:vindara/providers/providers.dart';
import 'package:vindara/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen displays HELP, no SOS, and official 112 button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isOnlineStreamProvider.overrideWith((ref) => Stream.value(true)),
          currentUserProfileProvider.overrideWith(() => MockUserProfileNotifier()),
          allEmergenciesProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Pump frames to complete build without infinite animation timeout
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify "HELP" text is prominently present
    expect(find.text('HELP'), findsOneWidget);

    // 2. Strict UX Rule: Zero occurrences of "SOS"
    expect(find.textContaining('SOS'), findsNothing);

    // 3. Official 112 emergency services layer present
    expect(find.text('Call 112 (Official Emergency)'), findsOneWidget);
    expect(find.text('Official Emergency Services'), findsOneWidget);

    // 4. Online connectivity pill displayed
    expect(find.text('Online'), findsOneWidget);

    // 5. Quick category buttons
    expect(find.text('Medical'), findsOneWidget);
    expect(find.text('Accident'), findsOneWidget);
    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
  });
}

class MockUserProfileNotifier extends CurrentUserProfileNotifier {
  @override
  Future<UserProfile?> build() async {
    return const UserProfile(
      uid: 'test-user-1',
      displayName: 'Aarav Patel',
      isVerifiedResponder: true,
      isAvailable: true,
      reputationPoints: 250,
    );
  }
}
