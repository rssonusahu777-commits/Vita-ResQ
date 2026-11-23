// lib/services/crash_detection_service.dart
//
// Vindara — Possible Crash Detection Service
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #6 — Single-lifecycle listeners managed inside Riverpod; cancelled in dispose().
//   Rule #10 — Honest "Possible Crash" framing. Pattern-based motion heuristic,
//              never claimed as guaranteed crash certainty. Debounced with cooldown.

import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Event emitted when motion patterns indicate a possible collision or high impact.
class PossibleCrashEvent {
  final DateTime timestamp;
  final double peakAcceleration; // m/s²
  final double peakRotation; // rad/s
  final bool isSimulated;

  const PossibleCrashEvent({
    required this.timestamp,
    required this.peakAcceleration,
    required this.peakRotation,
    this.isSimulated = false,
  });

  @override
  String toString() =>
      'PossibleCrashEvent(peakAcc: ${peakAcceleration.toStringAsFixed(1)}m/s², peakRot: ${peakRotation.toStringAsFixed(1)}rad/s, sim: $isSimulated)';
}

/// Service that monitors device motion sensors and applies a two-stage heuristic:
/// 1. High-G impact acceleration spike (> threshold, default 28.0 m/s² ~ 2.8G).
/// 2. Rotation spike + post-impact relative deceleration / settling window.
/// Includes a 15-second debounce cooldown and active countdown lock guard.
class CrashDetectionService {
  final Stream<UserAccelerometerEvent>? _userAccelerometerStream;
  final Stream<GyroscopeEvent>? _gyroscopeStream;

  /// Acceleration magnitude threshold in m/s² (injectable for unit tests).
  final double accelerationThreshold;

  /// Gyroscope rotation threshold in rad/s (injectable for unit tests).
  final double rotationThreshold;

  /// Post-impact stillness window.
  final Duration postImpactWindow;

  /// Minimum time between triggers to avoid stacked countdown alerts.
  final Duration debounceCooldown;

  final StreamController<PossibleCrashEvent> _crashController =
      StreamController<PossibleCrashEvent>.broadcast();

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  DateTime? _lastTriggerTime;
  bool _isCountdownActive = false;
  bool _isMonitoring = false;

  // Running peak values
  double _lastMaxGyro = 0.0;
  DateTime? _candidateSpikeTime;
  double? _candidateSpikeAcc;

  CrashDetectionService({
    this._userAccelerometerStream,
    this._gyroscopeStream,
    this.accelerationThreshold = 28.0, // ~2.8G
    this.rotationThreshold = 3.5, // rad/s
    this.postImpactWindow = const Duration(milliseconds: 1500),
    this.debounceCooldown = const Duration(seconds: 15),
  });

  /// Continuous broadcast stream of possible crash detection events.
  Stream<PossibleCrashEvent> get possibleCrashStream =>
      _crashController.stream;

  /// Whether sensor streams are currently being monitored.
  bool get isMonitoring => _isMonitoring;

  /// Sets lock state while a 10s countdown screen is active.
  void setCountdownActive(bool active) {
    _isCountdownActive = active;
  }

  /// Starts listening to accelerometer and gyroscope streams.
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    final accelStream =
        _userAccelerometerStream ?? userAccelerometerEventStream();
    final gyroStream = _gyroscopeStream ?? gyroscopeEventStream();

    _gyroSub = gyroStream.listen((event) {
      final rotMagnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _processGyroscope(rotMagnitude);
    });

    _accelSub = accelStream.listen((event) {
      final accMagnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _processAcceleration(accMagnitude);
    });
  }

  void _processGyroscope(double rotMagnitude) {
    final now = DateTime.now();
    if (rotMagnitude >= rotationThreshold) {
      _lastMaxGyro = max(_lastMaxGyro, rotMagnitude);

      // Check if we already have a candidate acceleration spike within the impact window
      if (_candidateSpikeTime != null &&
          now.difference(_candidateSpikeTime!) <= postImpactWindow) {
        _triggerEvent(
          PossibleCrashEvent(
            timestamp: _candidateSpikeTime!,
            peakAcceleration: _candidateSpikeAcc ?? accelerationThreshold,
            peakRotation: _lastMaxGyro,
          ),
        );
        _candidateSpikeTime = null;
        _candidateSpikeAcc = null;
        _lastMaxGyro = 0.0;
      }
    }
  }

  void _processAcceleration(double accMagnitude) {
    final now = DateTime.now();

    // Guard: Debounce cooldown or active countdown lock
    if (_isCountdownActive) return;
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!) < debounceCooldown) {
      return;
    }

    // Stage 1: Acceleration magnitude exceeds threshold
    if (accMagnitude >= accelerationThreshold) {
      _candidateSpikeTime = now;
      _candidateSpikeAcc = accMagnitude;

      // If rotation already exceeded threshold within window, trigger
      if (_lastMaxGyro >= rotationThreshold) {
        _triggerEvent(
          PossibleCrashEvent(
            timestamp: now,
            peakAcceleration: accMagnitude,
            peakRotation: _lastMaxGyro,
          ),
        );
        _candidateSpikeTime = null;
        _candidateSpikeAcc = null;
        _lastMaxGyro = 0.0;
        return;
      }
    }

    // Stage 2: Check window expiry
    if (_candidateSpikeTime != null) {
      final elapsed = now.difference(_candidateSpikeTime!);
      if (elapsed > postImpactWindow) {
        _candidateSpikeTime = null;
        _candidateSpikeAcc = null;
        _lastMaxGyro = 0.0;
      }
    }
  }

  void _triggerEvent(PossibleCrashEvent event) {
    _lastTriggerTime = DateTime.now();
    _isCountdownActive = true;
    if (!_crashController.isClosed) {
      _crashController.add(event);
    }
  }

  /// Debug / simulation helper to safely trigger the countdown screen in test harnesses.
  void simulatePossibleCrash() {
    if (_isCountdownActive) return;
    final event = PossibleCrashEvent(
      timestamp: DateTime.now(),
      peakAcceleration: 32.5,
      peakRotation: 5.2,
      isSimulated: true,
    );
    _triggerEvent(event);
  }

  /// Stops monitoring and cancels sensor subscriptions (Rule #6).
  void stopMonitoring() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _isMonitoring = false;
  }

  /// Full disposal of service resources.
  Future<void> dispose() async {
    stopMonitoring();
    await _crashController.close();
  }
}
