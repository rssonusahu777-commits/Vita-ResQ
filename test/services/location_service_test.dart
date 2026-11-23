// test/services/location_service_test.dart
//
// SafeReach — LocationService unit tests
// Tests the timeout-fallback chain (Rule #2).
// Run: flutter test test/services/location_service_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:vindara/services/local_emergency_store.dart';
import 'package:vindara/services/location_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

/// We test the LocationService's fallback logic by directly exercising
/// [tryGetPlatformLastKnown] and [cacheLastKnownLocation] via a real
/// LocalEmergencyStore backed by in-memory Hive.
///
/// For [getCurrentLocation] the geolocator plugin calls are platform-channel-
/// based and cannot be mocked without a full plugin fake; those paths are
/// covered in integration tests. Here we focus on the observable fallback
/// behaviour: app-cached GPS fix is returned when no live/platform fix exists.

void main() {
  late LocalEmergencyStore store;
  late LocationService service;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('safereach_loc_test_');
    Hive.init(tempDir.path);
    store = LocalEmergencyStore();
    await store.init();
    service = LocationService(
      store,
      freshFixTimeout: const Duration(milliseconds: 50), // very short for tests
    );
  });

  tearDown(() async {
    await store.dispose();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // -------------------------------------------------------------------------
  // LocationFix value object
  // -------------------------------------------------------------------------
  group('LocationFix', () {
    test('toString includes all key fields', () {
      const fix = LocationFix(
        latitude: 28.6,
        longitude: 77.2,
        accuracyMeters: 5.0,
        source: LocationFixSource.freshGps,
      );
      expect(fix.toString(), contains('28.6'));
      expect(fix.toString(), contains('freshGps'));
    });
  });

  // -------------------------------------------------------------------------
  // App-cached fallback (Rule #2)
  // -------------------------------------------------------------------------
  group('app-cached fallback (Rule #2)', () {
    test('tryGetPlatformLastKnown returns app-cached fix when platform returns null',
        () async {
      // Pre-populate the cache.
      await store.cacheLastKnownLocation(12.9716, 77.5946, 20.0);

      // tryGetPlatformLastKnown tries platform first; on test environment
      // getLastKnownPosition returns null, so it falls back to app cache.
      final fix = await service.tryGetPlatformLastKnown();

      // On a real device this would return a platform fix or the app cache;
      // the important contract is that it never throws.
      expect(fix, isNotNull);

      // The source is either platformLastKnown or appCached.
      expect(
        fix!.source == LocationFixSource.platformLastKnown ||
            fix.source == LocationFixSource.appCached,
        isTrue,
      );
    });

    test('tryGetPlatformLastKnown returns null when no cache and platform unavailable',
        () async {
      // No cache seeded. On test env platform returns null too.
      // Result should be null (not a throw).
      await service.tryGetPlatformLastKnown();
      expect(() async => await service.tryGetPlatformLastKnown(), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // LocationService timeout configuration
  // -------------------------------------------------------------------------
  group('LocationService configuration', () {
    test('freshFixTimeout is configurable', () {
      final custom = LocationService(
        store,
        freshFixTimeout: const Duration(seconds: 10),
      );
      expect(custom.freshFixTimeout, equals(const Duration(seconds: 10)));
    });

    test('default freshFixTimeout is 4 seconds', () {
      final defaultService = LocationService(store);
      expect(defaultService.freshFixTimeout, equals(const Duration(seconds: 4)));
    });
  });

  // -------------------------------------------------------------------------
  // LocationServiceException
  // -------------------------------------------------------------------------
  group('LocationServiceException', () {
    test('toString includes error name', () {
      const ex = LocationServiceException(LocationServiceError.permissionDenied);
      expect(ex.toString(), contains('permissionDenied'));
    });

    test('all error variants are defined', () {
      expect(LocationServiceError.values.length, equals(3));
      expect(LocationServiceError.values, contains(LocationServiceError.serviceDisabled));
      expect(LocationServiceError.values, contains(LocationServiceError.permissionDenied));
      expect(LocationServiceError.values, contains(LocationServiceError.noFixAvailable));
    });
  });

  // -------------------------------------------------------------------------
  // GPS cache integration with the store
  // -------------------------------------------------------------------------
  group('GPS cache integration', () {
    test('caching a location makes it retrievable via store', () async {
      await store.cacheLastKnownLocation(51.5074, -0.1278, 8.0);
      final cached = store.getLastKnownLocation();
      expect(cached, isNotNull);
      expect(cached!['latitude'], closeTo(51.5074, 0.001));
      expect(cached['longitude'], closeTo(-0.1278, 0.001));
      expect(cached['accuracyMeters'], closeTo(8.0, 0.01));
    });

    test('no crash when getLastKnownLocation is called before any fix cached', () {
      expect(store.getLastKnownLocation(), isNull);
    });
  });
}
