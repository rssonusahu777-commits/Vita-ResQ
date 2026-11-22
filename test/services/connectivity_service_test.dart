// test/services/connectivity_service_test.dart
//
// Vindara — ConnectivityService unit tests
// Tests real reachability probing vs captive portal / broken routers (Rule #1).

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vindara/services/connectivity_service.dart';

class MockConnectivity extends Mock implements Connectivity {}
class MockReachabilityProbe extends Mock implements NetworkReachabilityProbe {}

void main() {
  late MockConnectivity mockConnectivity;
  late MockReachabilityProbe mockProbe;
  late StreamController<List<ConnectivityResult>> connectivityStreamController;
  late ConnectivityService connectivityService;

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 3));
  });

  setUp(() {
    mockConnectivity = MockConnectivity();
    mockProbe = MockReachabilityProbe();
    connectivityStreamController =
        StreamController<List<ConnectivityResult>>.broadcast();

    when(() => mockConnectivity.onConnectivityChanged)
        .thenAnswer((_) => connectivityStreamController.stream);
    when(() => mockConnectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
  });

  tearDown(() async {
    await connectivityService.dispose();
    await connectivityStreamController.close();
  });

  group('ConnectivityService — Rule #1 Real Reachability vs No-Wi-Fi', () {
    test('returns false when interface is connected (Wi-Fi) but probe fails/times out (captive portal)',
        () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => mockProbe.probe(timeout: any(named: 'timeout')))
          .thenAnswer((_) async => false);

      connectivityService = ConnectivityService(
        connectivity: mockConnectivity,
        probe: mockProbe,
        periodicInterval: Duration.zero,
      );

      final isOnline = await connectivityService.checkReachability();
      expect(isOnline, isFalse);

      await connectivityService.init();
      expect(connectivityService.isCurrentlyOnline, isFalse);
    });

    test('returns true when interface is connected and probe succeeds',
        () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.mobile]);
      when(() => mockProbe.probe(timeout: any(named: 'timeout')))
          .thenAnswer((_) async => true);

      connectivityService = ConnectivityService(
        connectivity: mockConnectivity,
        probe: mockProbe,
        periodicInterval: Duration.zero,
      );

      final isOnline = await connectivityService.checkReachability();
      expect(isOnline, isTrue);

      await connectivityService.init();
      expect(connectivityService.isCurrentlyOnline, isTrue);
    });

    test('returns false immediately when interface is none without probing',
        () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);

      connectivityService = ConnectivityService(
        connectivity: mockConnectivity,
        probe: mockProbe,
        periodicInterval: Duration.zero,
      );

      final isOnline = await connectivityService.checkReachability();
      expect(isOnline, isFalse);
      verifyNever(() => mockProbe.probe(timeout: any(named: 'timeout')));
    });

    test('emits reachability changes on stream when interface transitions occur',
        () async {
      when(() => mockProbe.probe(timeout: any(named: 'timeout')))
          .thenAnswer((_) async => true);

      connectivityService = ConnectivityService(
        connectivity: mockConnectivity,
        probe: mockProbe,
        periodicInterval: Duration.zero,
      );

      await connectivityService.init();

      final emitted = <bool>[];
      final sub = connectivityService.isOnline.listen(emitted.add);

      // Transition to none -> false
      connectivityStreamController.add([ConnectivityResult.none]);
      await pumpEventQueue();

      // Transition to wifi with successful probe -> true
      connectivityStreamController.add([ConnectivityResult.wifi]);
      await pumpEventQueue();

      expect(emitted, containsAllInOrder([false, true]));
      await sub.cancel();
    });
  });
}
