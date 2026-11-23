// lib/services/live_location_tracker_service.dart
//
// Vindara — Live GPS Location Broadcasting Service
// Package: com.vindara.app
//
// Streams live GPS coordinates for:
// 1. Victims during active emergency dispatch (throttled ~3-5s / 5m movement).
// 2. Responders actively navigating to a victim after atomic claim acceptance.
//
// Architectural Rules:
// - Rule #2: Raw coordinates via geolocator; zero dependency on map tiles.
// - Rule #6: Single-lifecycle subscriptions with mandatory clean cancellation.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../data/mock_emergency_repository.dart';

class LiveLocationTrackerService {
  static LiveLocationTrackerService? _instance;
  static LiveLocationTrackerService get instance =>
      _instance ??= LiveLocationTrackerService();

  @visibleForTesting
  static void setMockInstance(LiveLocationTrackerService mock) {
    _instance = mock;
  }

  StreamSubscription<Position>? _victimSub;
  String? _activeVictimEmergencyId;
  DateTime? _lastVictimUploadTime;

  StreamSubscription<Position>? _responderSub;
  String? _activeResponderEmergencyId;
  DateTime? _lastResponderUploadTime;

  static const int throttleSeconds = 3;
  static const int distanceFilterMeters = 5;

  /// Starts streaming victim's live GPS position to Firestore/repository
  Future<void> startVictimTracking({
    required String emergencyId,
    required EmergencyRepository repository,
  }) async {
    // Clean up any existing stream first (Rule #6)
    await stopVictimTracking();
    _activeVictimEmergencyId = emergencyId;

    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) return;

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      );

      _victimSub = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen(
        (position) async {
          if (_activeVictimEmergencyId != emergencyId) return;

          final now = DateTime.now();
          if (_lastVictimUploadTime == null ||
              now.difference(_lastVictimUploadTime!).inSeconds >= throttleSeconds) {
            _lastVictimUploadTime = now;
            await repository.updateVictimLocation(
              emergencyId,
              position.latitude,
              position.longitude,
            );
          }
        },
        onError: (err) {
          debugPrint('LiveLocationTracker victim stream warning: $err');
        },
      );
    } catch (e) {
      debugPrint('LiveLocationTracker startVictimTracking error: $e');
    }
  }

  /// Stops victim live location streaming
  Future<void> stopVictimTracking() async {
    await _victimSub?.cancel();
    _victimSub = null;
    _activeVictimEmergencyId = null;
    _lastVictimUploadTime = null;
  }

  /// Starts streaming responder's live GPS position to Firestore/repository
  Future<void> startResponderTracking({
    required String emergencyId,
    required EmergencyRepository repository,
  }) async {
    // Clean up any existing stream first (Rule #6)
    await stopResponderTracking();
    _activeResponderEmergencyId = emergencyId;

    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) return;

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      );

      _responderSub = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen(
        (position) async {
          if (_activeResponderEmergencyId != emergencyId) return;

          final now = DateTime.now();
          if (_lastResponderUploadTime == null ||
              now.difference(_lastResponderUploadTime!).inSeconds >= throttleSeconds) {
            _lastResponderUploadTime = now;
            await repository.updateResponderLocation(
              emergencyId,
              position.latitude,
              position.longitude,
            );
          }
        },
        onError: (err) {
          debugPrint('LiveLocationTracker responder stream warning: $err');
        },
      );
    } catch (e) {
      debugPrint('LiveLocationTracker startResponderTracking error: $e');
    }
  }

  /// Stops responder live location streaming
  Future<void> stopResponderTracking() async {
    await _responderSub?.cancel();
    _responderSub = null;
    _activeResponderEmergencyId = null;
    _lastResponderUploadTime = null;
  }

  Future<bool> _checkLocationPermission() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return false;

      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Release all streams
  Future<void> dispose() async {
    await stopVictimTracking();
    await stopResponderTracking();
  }
}
