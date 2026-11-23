import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jan_sarthi/core/theme/app_theme.dart';
import 'package:jan_sarthi/models/communication_mode.dart';
import 'package:jan_sarthi/screens/auth/login_screen.dart';
import 'package:jan_sarthi/services/auth_service.dart';
import 'package:jan_sarthi/services/communication_manager.dart';
import 'package:jan_sarthi/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2 — Guest / Logged-Out Offline Emergency Access Tests', () {
    const String initialProfileJson = '{"id":"saved_user_123","name":"Saved User","email":"saved@vitaresq.org","userRole":"CITIZEN"}';

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'local_user_profile_v2': initialProfileJson,
        'local_device_id_v1': 'dev_test_device_456',
      });
      LocalDatabaseService.setLocalDeviceIdForTesting('dev_test_device_456');
      AuthService.resetCacheForTesting();
    });

    tearDown(() {
      AuthService.resetCacheForTesting();
      LocalDatabaseService.setLocalDeviceIdForTesting(null);
    });

    test('a) enterGuestOfflineMode() sets guest flag, generates deterministic ID, and isolates user profile cache', () async {
      final authService = AuthService();
      final guestId = await authService.enterGuestOfflineMode();

      // Deterministic guest ID matching offline_guest_<deviceId>
      expect(guestId, 'offline_guest_dev_test_device_456');

      // Guest offline session flag active
      expect(await AuthService.isGuestOfflineSession(), isTrue);
      expect(AuthService.isGuestOfflineSessionSync, isTrue);

      // Verify Profile Cache Isolation: local_user_profile_v2 remains completely untouched
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('guest_offline_session_v1'), isTrue);
      expect(prefs.getString('local_user_profile_v2'), initialProfileJson);
    });

    test('b) exitGuestOfflineMode() cleanly clears guest state without touching stored profile', () async {
      final authService = AuthService();
      await authService.enterGuestOfflineMode();
      expect(AuthService.isGuestOfflineSessionSync, isTrue);

      await authService.exitGuestOfflineMode();

      expect(await AuthService.isGuestOfflineSession(), isFalse);
      expect(AuthService.isGuestOfflineSessionSync, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('guest_offline_session_v1'), isNull);
      expect(prefs.getString('local_user_profile_v2'), initialProfileJson);
    });

    test('c) In guest offline mode, CommunicationManager operates strictly in offline P2P and bypasses Firestore sync', () async {
      SharedPreferences.setMockInitialValues({
        'guest_offline_session_v1': true,
        'local_device_id_v1': 'dev_test_device_456',
      });
      AuthService.resetCacheForTesting();
      await AuthService.isGuestOfflineSession();

      final commManager = CommunicationManager();
      commManager.initialize();

      // Mode is strictly offline
      expect(commManager.activeMode, CommunicationMode.offline);

      // syncOfflineEmergencyToFirestore bypasses any Firestore network calls and completes immediately
      await expectLater(commManager.syncOfflineEmergencyToFirestore(), completes);
    });

    testWidgets('d) LoginScreen renders Continue Offline button without layout overflow on 360x640', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      AuthService.resetCacheForTesting();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(OutlinedButton, 'Continue Offline (Emergency Access)');
      expect(buttonFinder, findsOneWidget);

      final subtitleFinder = find.text('Send or receive nearby Bluetooth/Wi-Fi Direct alerts without signing in.');
      expect(subtitleFinder, findsOneWidget);

      final Size buttonSize = tester.getSize(buttonFinder);
      expect(buttonSize.height, greaterThanOrEqualTo(48.0));

      expect(tester.takeException(), isNull);
    });
  });
}

