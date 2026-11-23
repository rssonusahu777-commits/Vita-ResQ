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
    expect(find.text('SOS'), findsOneWidget);

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
    expect(find.text('ayush patnayak'), findsOneWidget);

    mockRepo.dispose();
  });

  testWidgets('ActiveEmergencyScreen smoke test', (WidgetTester tester) async {
    final mockRepo = MockEmergencyRepository();
    final emergencies = await mockRepo.getActiveEmergencies();
    final sampleEmergency = emergencies.first;

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
    expect(find.text('Cancel Emergency'), findsOneWidget);
    expect(find.text('Demo State Switcher'), findsOneWidget);

    mockRepo.dispose();
  });

  testWidgets('ResponderAlertsScreen and NavigatingToVictimScreen smoke test', (WidgetTester tester) async {
    final mockRepo = MockEmergencyRepository();
    final emergencies = await mockRepo.getActiveEmergencies();
    final sampleEmergency = emergencies.first;

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

    expect(find.text('Navigating to Victim'), findsNWidgets(2));
    expect(find.text('Proceed to emergency location'), findsOneWidget);
    expect(find.text('Nearby Hospitals (Standby)'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Report Problem'), findsOneWidget);
    expect(find.text('I HAVE ARRIVED'), findsOneWidget);

    // Test Call dialog
    await tester.tap(find.text('Call'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Victim Phone Number:'), findsOneWidget);
    expect(find.text('+91 7999279412'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);

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
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('Contextual Permissions'), findsOneWidget);

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
    expect(find.text('Incoming Emergency Request'), findsOneWidget);

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

    expect(find.text('Emergency Contacts'), findsOneWidget);
    expect(find.text('Auto-SMS Dispatch (Offline Fallback)'), findsOneWidget);
    expect(find.text('Add Contact'), findsOneWidget);
  });
}
