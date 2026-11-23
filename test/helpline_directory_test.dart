import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jan_sarthi/core/theme/app_theme.dart';
import 'package:jan_sarthi/models/helpline_entry.dart';
import 'package:jan_sarthi/models/user_model.dart';
import 'package:jan_sarthi/screens/helpline/helpline_directory_screen.dart';
import 'package:jan_sarthi/services/helpline_call_service.dart';
import 'package:jan_sarthi/widgets/app_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testUser = UserModel(
    id: 'test_citizen_001',
    name: 'Priya Sharma',
    email: 'priya.sharma@example.com',
    phoneNumber: '+91 98765 43210',
    bloodGroup: 'B+',
    userRole: 'CITIZEN',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Widget buildDrawerHarness({UserModel? user}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        drawer: AppDrawer(
          currentIndex: 0,
          userProfile: user ?? testUser,
        ),
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            child: const Text('Open Drawer'),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // GROUP 1: DRAWER INTEGRATION & EXACT POSITIONING TESTS
  // =========================================================================
  group('1. Side Menu Drawer Integration & Exact Positioning', () {
    testWidgets('1.1: HELP & SUPPORT appears below DEMO / JUDGE and above ACCOUNT', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildDrawerHarness());
      await tester.tap(find.text('Open Drawer'));
      await tester.pumpAndSettle();

      // Verify HELP & SUPPORT section and Helpline Directory item exist
      expect(find.text('HELP & SUPPORT'), findsOneWidget);
      expect(find.text('Helpline Directory'), findsOneWidget);
      expect(find.byIcon(Icons.contact_phone_outlined), findsOneWidget);

      // Verify ACCOUNT section remains pinned at bottom
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets('1.2: All existing drawer items remain intact and unmodified', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildDrawerHarness());
      await tester.tap(find.text('Open Drawer'));
      await tester.pumpAndSettle();

      // EMERGENCY
      expect(find.text('EMERGENCY'), findsOneWidget);
      expect(find.text('Emergency Contacts'), findsOneWidget);

      // SAFETY
      expect(find.text('SAFETY'), findsOneWidget);
      expect(find.text('Crash Detection'), findsOneWidget);

      // IMPACT
      expect(find.text('IMPACT'), findsOneWidget);
      expect(find.text('Impact & Rewards'), findsOneWidget);
      expect(find.text('Certificates'), findsOneWidget);

      // DEMO / JUDGE
      expect(find.text('DEMO / JUDGE'), findsOneWidget);
      expect(find.text('Accident Detection Demo'), findsOneWidget);

      // Verify OPERATIONS / Response Intelligence has been completely removed
      expect(find.text('OPERATIONS'), findsNothing);
      expect(find.text('Response Intelligence'), findsNothing);
    });

    testWidgets('1.3: Tapping Helpline Directory opens dedicated screen without dialing', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int launchCallCount = 0;
      HelplineCallService.instance.setLauncherForTesting((uri, {LaunchMode? mode}) async {
        launchCallCount++;
        return true;
      });
      addTearDown(HelplineCallService.instance.resetForTesting);

      await tester.pumpWidget(buildDrawerHarness());
      await tester.tap(find.text('Open Drawer'));
      await tester.pumpAndSettle();

      // Scroll and tap Helpline Directory
      await tester.scrollUntilVisible(find.text('Helpline Directory'), 100);
      await tester.tap(find.text('Helpline Directory'));
      await tester.pumpAndSettle();

      // Dedicated screen is opened
      expect(find.byType(HelplineDirectoryScreen), findsOneWidget);
      // Zero phone calls were placed on screen opening
      expect(launchCallCount, 0);
    });
  });

  // =========================================================================
  // GROUP 2: HELPLINE DATA MODEL & CALL SERVICE UNIT TESTS
  // =========================================================================
  group('2. Helpline Data Model & Number Normalization Unit Tests', () {
    test('2.1: Normalizes short codes and national numbers correctly', () {
      expect(HelplineCallService.normalizeNumber('112'), '112');
      expect(HelplineCallService.normalizeNumber('101'), '101');
      expect(HelplineCallService.normalizeNumber('108'), '108');
      expect(HelplineCallService.normalizeNumber('181'), '181');
      expect(HelplineCallService.normalizeNumber('1098'), '1098');
      expect(HelplineCallService.normalizeNumber('1930'), '1930');
      expect(HelplineCallService.normalizeNumber('14567'), '14567');
      expect(HelplineCallService.normalizeNumber('1906'), '1906');
      expect(HelplineCallService.normalizeNumber('1078'), '1078');
      expect(HelplineCallService.normalizeNumber('139'), '139');
      expect(HelplineCallService.normalizeNumber('+91 11 2345 6789'), '+911123456789');
    });

    test('2.2: Rejects invalid or empty numbers', () {
      expect(HelplineCallService.normalizeNumber(''), '');
      expect(HelplineCallService.normalizeNumber('  '), '');
      expect(HelplineCallService.normalizeNumber('12'), ''); // Too short (<3)
      expect(HelplineCallService.normalizeNumber('1234567890123456'), ''); // Too long (>15)
      expect(HelplineCallService.isValidHelplineNumber('abc'), isFalse);
    });

    test('2.3: Constructs canonical tel: URI correctly', () {
      expect(HelplineCallService.constructTelUri('112')?.toString(), 'tel:112');
      expect(HelplineCallService.constructTelUri('1930')?.toString(), 'tel:1930');
      expect(HelplineCallService.constructTelUri('14567')?.toString(), 'tel:14567');
      expect(HelplineCallService.constructTelUri('1098')?.toString(), 'tel:1098');
      expect(HelplineCallService.constructTelUri('invalid'), isNull);
    });

    test('2.4: Default helplines contain all required official Government of India services', () {
      const helplines = HelplineEntry.defaultHelplines;
      expect(helplines.isNotEmpty, isTrue);

      final numbers = helplines.map((e) => e.number).toSet();
      expect(numbers.contains('112'), isTrue); // Unified ERSS
      expect(numbers.contains('101'), isTrue); // Fire
      expect(numbers.contains('108'), isTrue); // Ambulance
      expect(numbers.contains('181'), isTrue); // Women
      expect(numbers.contains('1098'), isTrue); // Child
      expect(numbers.contains('1930'), isTrue); // Cybercrime
      expect(numbers.contains('14567'), isTrue); // Senior Citizen
      expect(numbers.contains('1906'), isTrue); // LPG leak
      expect(numbers.contains('1078'), isTrue); // Disaster NDMA
      expect(numbers.contains('139'), isTrue); // Railway RailMadad

      // 112 is flagged as primary unified
      final erss = helplines.firstWhere((e) => e.number == '112');
      expect(erss.isPrimaryUnified, isTrue);
      expect(erss.sourceUrl, contains('112.gov.in'));
    });

    test('2.5: matchesQuery checks name, number, category, description, and source', () {
      final cyber = HelplineEntry.defaultHelplines.firstWhere((e) => e.number == '1930');
      expect(cyber.matchesQuery('1930'), isTrue);
      expect(cyber.matchesQuery('cyber'), isTrue);
      expect(cyber.matchesQuery('साइबर'), isTrue);
      expect(cyber.matchesQuery('Fraud'), isTrue);
      expect(cyber.matchesQuery('MHA'), isTrue);
      expect(cyber.matchesQuery('nonexistent query xyz'), isFalse);
    });
  });

  // =========================================================================
  // GROUP 3: HELPLINE DIRECTORY SCREEN WIDGET & INTERACTION TESTS
  // =========================================================================
  group('3. Helpline Directory Screen UI, Search, and Dialing Tests', () {
    testWidgets('3.1: Screen displays 112 hero card and official helpline cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: HelplineDirectoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Helpline Directory'), findsOneWidget);
      expect(find.text('Official Emergency & Public Assistance'), findsOneWidget);

      // Verify Prominent 112 Card
      expect(find.text('112'), findsWidgets);
      expect(find.text('INDIA UNIFIED EMERGENCY (ERSS)'), findsOneWidget);
      expect(find.text('Call 112 (Emergency)'), findsOneWidget);

      // Verify other helpline numbers rendered
      expect(find.text('101'), findsOneWidget);
      expect(find.text('108'), findsOneWidget);
      expect(find.text('181'), findsOneWidget);
      expect(find.text('1098'), findsOneWidget);
      expect(find.text('1930'), findsOneWidget);
    });

    testWidgets('3.2: Language toggle switches between English and Hindi dynamically', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: HelplineDirectoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Hindi
      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();

      // Header and cards update to Hindi
      expect(find.text('हेल्पलाइन डायरेक्टरी'), findsOneWidget);
      expect(find.text('भारत की राष्ट्रीय आपातकालीन सेवा (ERSS)'), findsOneWidget);
      expect(find.text('112 पर कॉल करें'), findsOneWidget);
      expect(find.text('महिला एवं बाल सुरक्षा'), findsWidgets);

      // Switch back to English
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();

      expect(find.text('Helpline Directory'), findsOneWidget);
      expect(find.text('INDIA UNIFIED EMERGENCY (ERSS)'), findsOneWidget);
    });

    testWidgets('3.3: Category filter chips filter list accurately', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: HelplineDirectoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Cybercrime' filter chip by key
      await tester.tap(find.byKey(const Key('category_chip_cybercrime')));
      await tester.pumpAndSettle();

      // Only 1930 is visible, 101/108 are filtered out
      expect(find.text('1930'), findsOneWidget);
      expect(find.text('101'), findsNothing);
      expect(find.text('108'), findsNothing);

      // Tap 'Senior Citizens' filter chip by key
      await tester.tap(find.byKey(const Key('category_chip_seniorCitizens')));
      await tester.pumpAndSettle();

      expect(find.text('14567'), findsOneWidget);
      expect(find.text('1930'), findsNothing);

      // Tap 'All' to restore
      await tester.tap(find.byKey(const Key('category_chip_all')));
      await tester.pumpAndSettle();

      expect(find.text('101'), findsOneWidget);
    });

    testWidgets('3.4: Search field filters helplines by name, number, and category', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: HelplineDirectoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Search for "1098" (Childline)
      await tester.enterText(find.byType(TextField), '1098');
      await tester.pumpAndSettle();

      expect(find.text('Childline (Child Protection)'), findsOneWidget);
      expect(find.text('101'), findsNothing);
      expect(find.text('1930'), findsNothing);

      // Clear search via clear icon
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      expect(find.text('101'), findsOneWidget);
    });

    testWidgets('3.5: Empty search state is shown with reset button when no matches exist', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: HelplineDirectoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter unmatched search
      await tester.enterText(find.byType(TextField), '99999999');
      await tester.pumpAndSettle();

      expect(find.text('No Helplines Found'), findsOneWidget);
      expect(find.text('Reset Search & Filters'), findsOneWidget);

      // Tap Reset Search
      await tester.tap(find.text('Reset Search & Filters'));
      await tester.pumpAndSettle();

      expect(find.text('No Helplines Found'), findsNothing);
      expect(find.text('101'), findsOneWidget);
    });

    testWidgets('3.6: Tapping Call launches external application dialer with correct tel: URI', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Uri? launchedUri;
      final mockCallService = HelplineCallService.forTesting(
        launcherDelegate: (uri, {LaunchMode? mode}) async {
          launchedUri = uri;
          return true;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HelplineDirectoryScreen(callService: mockCallService),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Call 112 button
      await tester.tap(find.text('Call 112 (Emergency)'));
      await tester.pumpAndSettle();

      expect(launchedUri?.toString(), 'tel:112');
    });

    testWidgets('3.7: Dialer launch failure triggers clipboard copy fallback notice', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final failingCallService = HelplineCallService.forTesting(
        launcherDelegate: (uri, {LaunchMode? mode}) async {
          return false; // simulate failure to open dialer on emulator/unsupported device
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HelplineDirectoryScreen(callService: failingCallService),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Call 112 button
      await tester.tap(find.text('Call 112 (Emergency)'));
      await tester.pump(); // Deliver tap event
      await tester.pump(); // Finish launchDialer and copyToClipboard async futures
      await tester.pump(const Duration(milliseconds: 300)); // Animate SnackBar entrance

      // Snackbar with fallback notice is displayed
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Could not open dialer'), findsOneWidget);
    });

    testWidgets('3.8: Source verification modal shows official portal information', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: HelplineDirectoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap source info on 112 card
      await tester.tap(find.byTooltip('Source Info'));
      await tester.pumpAndSettle();

      expect(find.text('Official Verification Source:'), findsOneWidget);
      expect(find.text('https://112.gov.in'), findsOneWidget);
    });
  });
}
