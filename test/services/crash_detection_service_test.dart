// test/services/crash_detection_service_test.dart
//
// Vindara — Possible Crash Detection Service Unit Tests (Phase 6)
// Rules followed:
//   Rule #6 — Single-lifecycle streams & cancellation in dispose().
//   Rule #10 — Honest "Possible Crash" framing, pattern-based motion heuristics,
//              15-second debounce cooldown, active countdown lock.

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vindara/services/crash_detection_service.dart';

void main() {
  group('CrashDetectionService', () {
    late StreamController<UserAccelerometerEvent> accelController;
    late StreamController<GyroscopeEvent> gyroController;
    late CrashDetectionService service;

    setUp(() {
      accelController = StreamController<UserAccelerometerEvent>.broadcast();
      gyroController = StreamController<GyroscopeEvent>.broadcast();

      service = CrashDetectionService(
        userAccelerometerStream: accelController.stream,
        gyroscopeStream: gyroController.stream,
        accelerationThreshold: 28.0,
        rotationThreshold: 3.5,
        postImpactWindow: const Duration(milliseconds: 1500),
        debounceCooldown: const Duration(seconds: 15),
      );
    });

    tearDown(() async {
      await service.dispose();
      await accelController.close();
      await gyroController.close();
    });

    test('isMonitoring is initially false and becomes true when started', () {
      expect(service.isMonitoring, isFalse);
      service.startMonitoring();
      expect(service.isMonitoring, isTrue);
      service.stopMonitoring();
      expect(service.isMonitoring, isFalse);
    });

    test('Normal sub-threshold motion does not trigger possible crash event',
        () async {
      service.startMonitoring();
      bool triggered = false;
      final sub = service.possibleCrashStream.listen((_) {
        triggered = true;
      });

      // Sub-threshold events (normal car driving or walking)
      final now = DateTime.now();
      accelController.add(UserAccelerometerEvent(2.0, 3.0, 4.0, now));
      gyroController.add(GyroscopeEvent(0.5, 0.2, 0.1, now));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(triggered, isFalse);

      await sub.cancel();
    });

    test('Acceleration spike alone without rotation does not trigger event',
        () async {
      service.startMonitoring();
      bool triggered = false;
      final sub = service.possibleCrashStream.listen((_) {
        triggered = true;
      });

      // Acceleration spike > 28 m/s² (resultant magnitude = 30.0)
      final now = DateTime.now();
      accelController.add(UserAccelerometerEvent(30.0, 0.0, 0.0, now));
      // Gyro remains below threshold (resultant magnitude = 1.0 < 3.5)
      gyroController.add(GyroscopeEvent(1.0, 0.0, 0.0, now));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(triggered, isFalse);

      await sub.cancel();
    });

    test(
        'Acceleration spike + rotation spike within impact window triggers PossibleCrashEvent',
        () async {
      service.startMonitoring();
      PossibleCrashEvent? receivedEvent;
      final sub = service.possibleCrashStream.listen((event) {
        receivedEvent = event;
      });

      // High-G impact acceleration spike (magnitude = 30.0 m/s² > 28.0)
      final now = DateTime.now();
      accelController.add(UserAccelerometerEvent(30.0, 0.0, 0.0, now));

      // Accompanied by rotation spike (magnitude = 4.0 rad/s > 3.5) within window
      gyroController.add(GyroscopeEvent(4.0, 0.0, 0.0, now));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.peakAcceleration, greaterThanOrEqualTo(28.0));
      expect(receivedEvent!.peakRotation, greaterThanOrEqualTo(3.5));
      expect(receivedEvent!.isSimulated, isFalse);

      await sub.cancel();
    });

    test('Debounce cooldown prevents duplicate triggers within 15 seconds',
        () async {
      service.startMonitoring();
      int triggerCount = 0;
      final sub = service.possibleCrashStream.listen((_) {
        triggerCount++;
      });

      // 1st Spike -> Triggers
      final now = DateTime.now();
      accelController.add(UserAccelerometerEvent(30.0, 0.0, 0.0, now));
      gyroController.add(GyroscopeEvent(4.0, 0.0, 0.0, now));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(triggerCount, equals(1));

      // 2nd Immediate Spike within debounce cooldown -> Must be ignored
      accelController.add(UserAccelerometerEvent(35.0, 0.0, 0.0, now));
      gyroController.add(GyroscopeEvent(5.0, 0.0, 0.0, now));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(triggerCount, equals(1));

      await sub.cancel();
    });

    test('Active countdown lock suppresses new crash triggers', () async {
      service.startMonitoring();
      service.setCountdownActive(true);

      bool triggered = false;
      final sub = service.possibleCrashStream.listen((_) {
        triggered = true;
      });

      // Spike occurs while countdown is locked
      final now = DateTime.now();
      accelController.add(UserAccelerometerEvent(40.0, 0.0, 0.0, now));
      gyroController.add(GyroscopeEvent(6.0, 0.0, 0.0, now));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(triggered, isFalse);

      await sub.cancel();
    });

    test('simulatePossibleCrash emits simulated event', () async {
      PossibleCrashEvent? simulatedEvent;
      final sub = service.possibleCrashStream.listen((event) {
        simulatedEvent = event;
      });

      service.simulatePossibleCrash();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(simulatedEvent, isNotNull);
      expect(simulatedEvent!.isSimulated, isTrue);
      expect(simulatedEvent!.peakAcceleration, greaterThan(28.0));
      expect(simulatedEvent!.peakRotation, greaterThan(3.5));

      await sub.cancel();
    });

    test('stopMonitoring cancels stream subscriptions', () async {
      service.startMonitoring();
      expect(service.isMonitoring, isTrue);

      service.stopMonitoring();
      expect(service.isMonitoring, isFalse);

      bool triggered = false;
      final sub = service.possibleCrashStream.listen((_) {
        triggered = true;
      });

      // Events added after stopMonitoring should not trigger
      final now = DateTime.now();
      accelController.add(UserAccelerometerEvent(50.0, 0.0, 0.0, now));
      gyroController.add(GyroscopeEvent(10.0, 0.0, 0.0, now));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(triggered, isFalse);

      await sub.cancel();
    });
  });
}

