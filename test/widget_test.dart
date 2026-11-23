import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vindara/data/mock_emergency_repository.dart';
import 'package:vindara/main.dart';
import 'package:vindara/screens/active_emergency_screen.dart';
import 'package:vindara/screens/auth_screen.dart';
import 'package:vindara/screens/emergency_contacts_screen.dart';
import 'package:vindara/screens/navigating_to_victim_screen.dart';
import 'package:vindara/screens/notifications_screen.dart';
import 'package:vindara/screens/responder_alerts_screen.dart';

void main() {
  testWidgets('VindaraApp light theme navigation smoke test', (WidgetTester tester) async {
    final mockRepo = MockEmergencyRepository();

    // Pump widget with explicit frames to prevent hanging
    await tester.pumpWidget(VindaraApp(repository: mockRepo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify app title & navigation destinations
    expect(find.text('Vindara'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Verify Home SOS Hub core elements
    expect(find.text('Need emergency help?'), findsOneWidget);
    expect(find.text('Citizen Responder'), findsOneWidget);
    expect(find.text('HELP'), findsOneWidget);

    // Switch to History tab
    await tester.tap(find.text('History'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Emergency History'), findsOneWidget);
    expect(find.text('Help Asked'), findsOneWidget);
    expect(find.text('Victims Helped'), findsOneWidget);

    // Switch to Profile tab
    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('Citizen Volunteer'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    mockRepo.dispose();
  });

  testWidgets('ActiveEmergencyScreen smoke test', (WidgetTester tester) async {
    final mockRepo = MockEmergencyRepository();
    final sampleEmergency = mockRepo.emergenciesSync.first;

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveEmergencyScreen(
          initialEmergency: sampleEmergency,
          repository: mockRepo,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Live Assistance'), findsOneWidget);
    expect(find.text('Your request is active.'), findsOneWidget);
    expect(find.text('PRIMARY RESPONDER'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    mockRepo.dispose();
  });

  testWidgets('ResponderAlertsScreen and NavigatingToVictimScreen smoke test', (WidgetTester tester) async {
    final mockRepo = MockEmergencyRepository();
    final sampleEmergency = mockRepo.emergenciesSync.first;

    // Test ResponderAlertsScreen
    await tester.pumpWidget(
      MaterialApp(
        home: ResponderAlertsScreen(repository: mockRepo),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Nearby Emergency Alerts'), findsOneWidget);
    expect(find.text('SIMULATE INCOMING PUSH ALERT'), findsOneWidget);
    expect(find.text('Responder Status: Available'), findsOneWidget);

    // Test NavigatingToVictimScreen
    await tester.pumpWidget(
      MaterialApp(
        home: NavigatingToVictimScreen(
          emergency: sampleEmergency,
          isPrimary: true,
          repository: mockRepo,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Navigating to Victim'), findsWidgets);
    expect(find.text('Proceed to emergency location'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    mockRepo.dispose();
  });

  testWidgets('AuthScreen smoke test', (WidgetTester tester) async {
    final mockRepo = MockEmergencyRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(repository: mockRepo),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Vindara'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Sign In & Enter Vindara'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    mockRepo.dispose();
  });

  testWidgets('NotificationsScreen smoke test', (WidgetTester tester) async {
    final mockRepo = MockEmergencyRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(repository: mockRepo),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Incoming Emergency Alert Nearby'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    mockRepo.dispose();
  });

  testWidgets('EmergencyContactsScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmergencyContactsScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Emergency Contacts (Auto-SMS)'), findsOneWidget);
    expect(find.text('Add Emergency Contact'), findsOneWidget);
  });
}
