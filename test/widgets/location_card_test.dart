// test/widgets/location_card_test.dart
//
// Vindara — Hybrid Online OpenStreetMap / Offline Distance Card Tests (Phase 7)
// Design rules followed:
//   Rule #2 — Offline-independent GPS: Coordinates always functional without online tiles.
//   Online Mode (isOnline == true): Interactive OpenStreetMap preview.
//   Offline Mode (isOnline == false): Map widget hidden; displays "Offline GPS Coordinate Mode".

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vindara/models/emergency.dart';
import 'package:vindara/widgets/location_card.dart';

void main() {
  final testEmergency = Emergency(
    id: 'EMG-2026-LOC00001',
    victimId: 'victim-user-1',
    latitude: 19.076000,
    longitude: 72.877700,
    accuracyMeters: 4.5,
    type: EmergencyType.medical,
    createdAt: DateTime.utc(2026, 6, 1),
    detectionSource: DetectionSource.manualHelp,
    status: EmergencyStatus.alerting,
    communicationMode: CommunicationMode.offline,
    version: 1,
  );

  group('LocationCard — Rule #2 Offline-First Coordinates', () {
    testWidgets(
        'Offline Mode (isOnline == false) displays raw GPS and offline banner, hides FlutterMap',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LocationCard(
                emergency: testEmergency,
                isOnline: false,
                responderLatitude: 19.077000, // ~111m away
                responderLongitude: 72.877700,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // 1. Raw coordinates rendered (Rule #2)
      expect(find.text('Latitude:   19.076000'), findsOneWidget);
      expect(find.text('Longitude:  72.877700'), findsOneWidget);
      expect(find.text('Accuracy:   ±4.5 metres'), findsOneWidget);

      // 2. Offline GPS mode banner shown
      expect(find.text('Offline GPS Coordinate Mode'), findsOneWidget);
      expect(
        find.textContaining('Exact satellite GPS coordinates remain 100% active'),
        findsOneWidget,
      );

      // 3. FlutterMap is strictly HIDDEN
      expect(find.byType(FlutterMap), findsNothing);

      // 4. Action buttons present
      expect(find.text('Copy Coordinates'), findsOneWidget);
      expect(find.text('Open in Maps'), findsOneWidget);

      // 5. Offline Haversine distance rendered
      expect(find.textContaining('m away'), findsOneWidget);
    });

    testWidgets(
        'Online Mode (isOnline == true) displays FlutterMap alongside coordinates',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LocationCard(
                emergency: testEmergency,
                isOnline: true,
                responderLatitude: 19.077000,
                responderLongitude: 72.877700,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // 1. Raw coordinates still present (Rule #2)
      expect(find.text('Latitude:   19.076000'), findsOneWidget);
      expect(find.text('Longitude:  72.877700'), findsOneWidget);

      // 2. Offline banner is NOT shown
      expect(find.text('Offline GPS Coordinate Mode'), findsNothing);

      // 3. FlutterMap is active
      expect(find.byType(FlutterMap), findsOneWidget);

      // 4. Action buttons present
      expect(find.text('Copy Coordinates'), findsOneWidget);
      expect(find.text('Open in Maps'), findsOneWidget);
    });

    testWidgets('Tapping Copy Coordinates invokes callback',
        (WidgetTester tester) async {
      bool copied = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LocationCard(
                emergency: testEmergency,
                isOnline: false,
                onCoordinatesCopied: () {
                  copied = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      await tester.tap(find.text('Copy Coordinates'));
      await tester.pump();

      expect(copied, isTrue);
    });
  });
}

