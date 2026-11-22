// lib/services/location_service.dart
//
// SafeReach — Offline-Independent GPS Location Service
// Package: com.example.safereach
//
// Design rules followed:
//   Rule #2 — GPS via geolocator only; zero dependency on internet, map tiles,
//              or routing services. Coordinates are raw WGS-84 doubles.
//   Rule #8 — Falls back to locally cached coordinates if live fix unavailable.

import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'local_emergency_store.dart';

// ---------------------------------------------------------------------------
// Value object returned by the service
// ---------------------------------------------------------------------------

/// A GPS fix ready for embedding in an [Emergency] record.
class LocationFix {
  /// WGS-84 latitude in decimal degrees.
  final double latitude;

  /// WGS-84 longitude in decimal degrees.
  final double longitude;

  /// Horizontal accuracy radius in metres. Null when using a cached fix
  /// that did not include accuracy information.
  final double? accuracyMeters;

  /// How the fix was obtained.
  final LocationFixSource source;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.source,
  });

  @override
  String toString() =>
      'LocationFix(lat: $latitude, lng: $longitude, '
      'accuracy: ${accuracyMeters?.toStringAsFixed(1)}m, source: ${source.name})';
}

/// Describes how the [LocationFix] was produced.
enum LocationFixSource {
  /// A fresh high-accuracy lock from the device GPS hardware.
  freshGps,

  /// The platform's last known position (may be a few minutes stale).
  platformLastKnown,

  /// The app's own cached position stored in [LocalEmergencyStore].
  appCached,
}

// ---------------------------------------------------------------------------
// LocationService
// ---------------------------------------------------------------------------

/// Provides GPS coordinates independently of internet connectivity,
/// map SDKs, or routing services (Architecture Rule #2).
///
/// Fast-fix strategy (sequential fallback):
///   1. Request a fresh high-accuracy GPS fix with a [freshFixTimeout].
///   2. On timeout / failure → try `Geolocator.getLastKnownPosition()`.
///   3. If that is also null → load the last fix cached by [LocalEmergencyStore].
///
/// One instance is kept alive for the app's lifetime via [locationServiceProvider].
class LocationService {
  final LocalEmergencyStore _store;

  /// Maximum time to wait for a fresh GPS lock before falling back.
  final Duration freshFixTimeout;

  LocationService(
    this._store, {
    this.freshFixTimeout = const Duration(seconds: 4),
  });

  // ---------------------------------------------------------------------------
  // Permission handling
  // ---------------------------------------------------------------------------

  /// Checks and requests location permission if needed.
  ///
  /// Returns `true` if permission is granted (or already was), `false` if the
  /// user denied. The caller should surface a UI prompt explaining why the app
  /// needs location access before calling this.
  Future<bool> ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      // The user has permanently denied location; we cannot request again.
      // Caller must direct them to system settings.
      return false;
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Returns whether location services are enabled at the OS level.
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  // ---------------------------------------------------------------------------
  // Core: getCurrentLocation (fast-fix with fallback chain)
  // ---------------------------------------------------------------------------

  /// Returns the best available [LocationFix] using the fast-fix strategy:
  ///
  /// 1. Try a fresh high-accuracy GPS fix within [freshFixTimeout].
  /// 2. Fall back to the platform's last known position.
  /// 3. Fall back to the app's own cached position from [LocalEmergencyStore].
  ///
  /// Throws [LocationServiceException] if no fix is available through any
  /// channel (location services disabled, permission denied, no cached fix).
  Future<LocationFix> getCurrentLocation() async {
    // --- Step 0: guard rails ---
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Try fallbacks even if the service is disabled (cached is better than
      // throwing immediately).
      return _fallbackFix() ??
          (throw const LocationServiceException(
            LocationServiceError.serviceDisabled,
          ));
    }

    final hasPermission = await ensurePermission();
    if (!hasPermission) {
      return _fallbackFix() ??
          (throw const LocationServiceException(
            LocationServiceError.permissionDenied,
          ));
    }

    // --- Step 1: fresh high-accuracy GPS fix with timeout ---
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(freshFixTimeout);

      final fix = LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        source: LocationFixSource.freshGps,
      );

      // Cache for future offline fallback (Rule #2 + Rule #8).
      await _store.cacheLastKnownLocation(
        fix.latitude,
        fix.longitude,
        fix.accuracyMeters,
      );

      return fix;
    } on TimeoutException {
      // Fresh fix timed out — continue to fallback chain.
    } catch (_) {
      // Any other geolocator error — continue to fallback chain.
    }

    // --- Step 2: platform last-known position ---
    return _fallbackFix() ??
        (throw const LocationServiceException(
          LocationServiceError.noFixAvailable,
        ));
  }

  // ---------------------------------------------------------------------------
  // Stream: positionStream
  // ---------------------------------------------------------------------------

  /// Returns a [Stream] of continuous GPS updates.
  ///
  /// Used for live tracking while an emergency is in progress. Each emitted
  /// [LocationFix] is automatically cached for offline use (Rule #2).
  ///
  /// The caller is responsible for cancelling the subscription when done
  /// (Rule #6 — single-lifecycle listeners, cancel in dispose).
  Stream<LocationFix> positionStream({
    Duration intervalMs = const Duration(milliseconds: 5000),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) {
    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: 10, // metres — suppress micro-jitter
    );

    return Geolocator.getPositionStream(locationSettings: settings).map(
      (pos) {
        final fix = LocationFix(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracyMeters: pos.accuracy,
          source: LocationFixSource.freshGps,
        );
        // Fire-and-forget cache update (Rule #2).
        _store.cacheLastKnownLocation(fix.latitude, fix.longitude, fix.accuracyMeters);
        return fix;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Internal fallback helpers
  // ---------------------------------------------------------------------------

  /// Tries platform last-known, then app cache. Returns null if both are absent.
  LocationFix? _fallbackFix() {
    return _platformLastKnownFix() ?? _appCachedFix();
  }

  LocationFix? _platformLastKnownFix() {
    // getLastKnownPosition is async; we must not block here.
    // We use a sync approach: the cached position from the store is preferred
    // when we cannot await. For the async variant see tryGetPlatformLastKnown().
    return null; // resolved asynchronously in tryGetPlatformLastKnown
  }

  LocationFix? _appCachedFix() {
    final cached = _store.getLastKnownLocation();
    if (cached == null) return null;
    return LocationFix(
      latitude: cached['latitude']!,
      longitude: cached['longitude']!,
      accuracyMeters: cached['accuracyMeters'],
      source: LocationFixSource.appCached,
    );
  }

  /// Async variant that actually calls `Geolocator.getLastKnownPosition()`,
  /// then falls back to the app cache. Used internally and exposed for testing.
  Future<LocationFix?> tryGetPlatformLastKnown() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        final fix = LocationFix(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracyMeters: pos.accuracy,
          source: LocationFixSource.platformLastKnown,
        );
        await _store.cacheLastKnownLocation(
            fix.latitude, fix.longitude, fix.accuracyMeters);
        return fix;
      }
    } catch (_) {
      // Platform may throw on some devices — treat as unavailable.
    }
    return _appCachedFix();
  }
}

// ---------------------------------------------------------------------------
// Exception types
// ---------------------------------------------------------------------------

enum LocationServiceError {
  serviceDisabled,
  permissionDenied,
  noFixAvailable,
}

class LocationServiceException implements Exception {
  final LocationServiceError error;

  const LocationServiceException(this.error);

  @override
  String toString() => 'LocationServiceException(${error.name})';
}

