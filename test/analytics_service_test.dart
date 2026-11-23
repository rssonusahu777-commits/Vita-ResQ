import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jan_sarthi/services/analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AnalyticsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = AnalyticsService.instance;
    service.resetForTesting();
  });

  tearDown(() {
    service.resetForTesting();
  });

  group('AnalyticsService & Outbox Tests', () {
    test('1. AnalyticsEvent model serializes and deserializes accurately', () {
      final event = AnalyticsEvent(
        eventId: 'evt_test_123',
        emergencyId: 'emg_456',
        eventType: 'sos_created',
        category: 'lifecycle',
        emergencyType: 'MEDICAL',
        eventSource: 'online',
        timestamp: '2026-10-10T12:00:00.000Z',
        isOfflineCreated: false,
      );

      final jsonMap = event.toJson();
      expect(jsonMap['eventId'], 'evt_test_123');
      expect(jsonMap['emergencyId'], 'emg_456');
      expect(jsonMap['eventType'], 'sos_created');
      expect(jsonMap['emergencyType'], 'MEDICAL');
      expect(jsonMap['eventSource'], 'online');
      expect(jsonMap['isOfflineCreated'], false);

      final reconstructed = AnalyticsEvent.fromJson(jsonMap);
      expect(reconstructed.eventId, event.eventId);
      expect(reconstructed.emergencyId, event.emergencyId);
      expect(reconstructed.eventType, event.eventType);
    });

    test('2. Strict privacy compliance: No coordinates, names, phones, or tokens in event JSON', () {
      final event = AnalyticsEvent(
        eventId: service.generateEventId('sos'),
        emergencyId: 'emg_001',
        eventType: 'sos_created',
        category: 'lifecycle',
        emergencyType: 'MEDICAL',
        eventSource: 'online',
        timestamp: DateTime.now().toIso8601String(),
      );

      final jsonStr = jsonEncode(event.toJson());
      expect(jsonStr.contains('latitude'), isFalse);
      expect(jsonStr.contains('longitude'), isFalse);
      expect(jsonStr.contains('phoneNumber'), isFalse);
      expect(jsonStr.contains('userName'), isFalse);
      expect(jsonStr.contains('token'), isFalse);
    });

    test('3. Enqueue event saves durably to SharedPreferences outbox', () async {
      final prefs = await SharedPreferences.getInstance();
      service.setDependenciesForTesting(prefs: prefs);

      await service.trackSosCreated(
        emergencyId: 'emg_789',
        emergencyType: 'ACCIDENT',
        isOfflineCreated: false,
      );

      final queued = await service.getQueuedEvents();
      expect(queued.length, 1);
      expect(queued.first.emergencyId, 'emg_789');
      expect(queued.first.eventType, 'sos_created');
      expect(queued.first.emergencyType, 'ACCIDENT');
    });

    test('4A. Prioritized eviction preserves critical SOS lifecycle events when routing telemetry floods queue', () async {
      final prefs = await SharedPreferences.getInstance();
      service.setDependenciesForTesting(prefs: prefs, autoFlush: false);

      // 1. Put 1 critical SOS lifecycle event at index 0
      final initialQueue = <String>[
        jsonEncode({
          'eventId': 'evt_critical_sos_1',
          'emergencyId': 'emg_critical',
          'eventType': 'sos_created',
          'category': 'lifecycle',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ];

      // 2. Fill the remaining 499 slots with lower-priority routing telemetry
      for (int i = 1; i < 500; i++) {
        initialQueue.add(jsonEncode({
          'eventId': 'evt_route_$i',
          'emergencyId': 'emg_nav',
          'eventType': 'routing_telemetry',
          'category': 'routing',
          'timestamp': DateTime.now().toIso8601String(),
        }));
      }
      await prefs.setStringList('analytics_outbox_queue_v1', initialQueue);

      // 3. Enqueue one more routing telemetry event (queue is at 500)
      await service.trackRouteTelemetry(
        emergencyId: 'emg_nav_501',
        routeCategory: 'scene_navigation',
        latencyMs: 120,
        success: true,
      );

      final queued = await service.getQueuedEvents();
      expect(queued.length, 500);

      // CRITICAL VERIFICATION: The critical SOS lifecycle event at index 0 MUST NOT be evicted!
      // The oldest routing event (evt_route_1) should have been evicted instead.
      expect(queued.any((e) => e.eventId == 'evt_critical_sos_1'), isTrue);
      expect(queued.any((e) => e.eventId == 'evt_route_1'), isFalse);

      final diags = service.getDiagnostics();
      expect(diags['overflowEvictionsTotal'], 1);
      expect(diags['telemetryEvictionsCount'], 1);
      expect(diags['lifecycleEvictionsCount'], 0);
    });

    test('4B. Lifecycle events are evicted FIFO only when queue consists entirely of lifecycle events', () async {
      final prefs = await SharedPreferences.getInstance();
      service.setDependenciesForTesting(prefs: prefs, autoFlush: false);

      // Pre-fill queue with 500 lifecycle events
      final initialQueue = List.generate(500, (i) => jsonEncode({
        'eventId': 'evt_sos_$i',
        'emergencyId': 'emg_$i',
        'eventType': 'sos_created',
        'category': 'lifecycle',
        'timestamp': DateTime.now().toIso8601String(),
      }));
      await prefs.setStringList('analytics_outbox_queue_v1', initialQueue);

      // Enqueue one more lifecycle event
      await service.trackSosCreated(
        emergencyId: 'emg_new_501',
        emergencyType: 'FIRE',
        isOfflineCreated: false,
      );

      final queued = await service.getQueuedEvents();
      expect(queued.length, 500);
      expect(queued.last.emergencyId, 'emg_new_501');
      expect(queued.first.eventId, 'evt_sos_1'); // evt_sos_0 evicted FIFO

      final diags = service.getDiagnostics();
      expect(diags['overflowEvictionsTotal'], 1);
      expect(diags['telemetryEvictionsCount'], 0);
      expect(diags['lifecycleEvictionsCount'], 1);
    });

    test('5. Flush batches up to 50 events and sends valid Authorization header', () async {
      final prefs = await SharedPreferences.getInstance();

      int requestCount = 0;
      Map<String, String>? capturedHeaders;
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        requestCount++;
        capturedHeaders = request.headers;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;

        final events = capturedBody!['events'] as List<dynamic>;
        final acceptedIds = events.map((e) => e['eventId']).toList();

        return http.Response(
          jsonEncode({
            'status': 'success',
            'accepted': acceptedIds,
            'duplicates': [],
            'rejected': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      service.setDependenciesForTesting(
        httpClient: mockClient,
        prefs: prefs,
        baseUrl: 'http://localhost:3000',
        tokenProvider: () async => 'mock_valid_firebase_token',
        autoFlush: false,
      );

      // Enqueue 3 events
      await service.trackSosCreated(emergencyId: 'emg_1', emergencyType: 'MEDICAL', isOfflineCreated: false);
      await service.trackResponderAccepted(emergencyId: 'emg_1', emergencyType: 'MEDICAL', durationToAcceptanceMs: 45000);
      await service.trackEmergencyCompleted(emergencyId: 'emg_1', emergencyType: 'MEDICAL', totalDurationMs: 300000);

      final flushedCount = await service.flushOutbox();

      expect(flushedCount, 3);
      expect(requestCount, 1);
      expect(capturedHeaders?['authorization'], 'Bearer mock_valid_firebase_token');
      expect((capturedBody?['events'] as List).length, 3);

      // Outbox should now be empty after server acknowledgement
      final remaining = await service.getQueuedEvents();
      expect(remaining.isEmpty, isTrue);
    });

    test('6. Partial acknowledgement purges only acknowledged events and retains unacknowledged', () async {
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final events = body['events'] as List<dynamic>;

        // Acknowledge only the first event
        return http.Response(
          jsonEncode({
            'status': 'success',
            'accepted': [events[0]['eventId']],
            'duplicates': [],
            'rejected': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      service.setDependenciesForTesting(
        httpClient: mockClient,
        prefs: prefs,
        baseUrl: 'http://localhost:3000',
        tokenProvider: () async => 'mock_token',
        autoFlush: false,
      );

      await service.trackSosCreated(emergencyId: 'emg_a', emergencyType: 'MEDICAL', isOfflineCreated: false);
      await service.trackSosCreated(emergencyId: 'emg_b', emergencyType: 'ACCIDENT', isOfflineCreated: false);

      final flushedCount = await service.flushOutbox();
      expect(flushedCount, 1);

      final remaining = await service.getQueuedEvents();
      expect(remaining.length, 1);
      expect(remaining.first.emergencyId, 'emg_b');
    });

    test('7. Network error retains events in outbox for subsequent retry', () async {
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        return http.Response('Service Unavailable', 503);
      });

      service.setDependenciesForTesting(
        httpClient: mockClient,
        prefs: prefs,
        baseUrl: 'http://localhost:3000',
        tokenProvider: () async => 'mock_token',
        autoFlush: false,
      );

      await service.trackSosCreated(emergencyId: 'emg_retry_1', emergencyType: 'MEDICAL', isOfflineCreated: false);

      final flushedCount = await service.flushOutbox();
      expect(flushedCount, 0);

      final remaining = await service.getQueuedEvents();
      expect(remaining.length, 1);
      expect(remaining.first.emergencyId, 'emg_retry_1');
    });

    test('8. Missing duration values are preserved as null, not zero', () async {
      final prefs = await SharedPreferences.getInstance();
      service.setDependenciesForTesting(prefs: prefs);

      // Cancelled before acceptance -> acceptance duration is null
      await service.trackEmergencyCancelled(
        emergencyId: 'emg_unclaimed',
        emergencyType: 'MEDICAL',
        totalDurationMs: 12000,
        wasAccepted: false,
      );

      final queued = await service.getQueuedEvents();
      expect(queued.length, 1);
      expect(queued.first.durationToAcceptanceMs, isNull);
      expect(queued.first.totalDurationMs, 12000);
    });

    test('9. Distance bucket formatting classifies distances coarsely', () {
      expect(AnalyticsService.formatDistanceBucket(350), '<500m');
      expect(AnalyticsService.formatDistanceBucket(1200), '500m-2km');
      expect(AnalyticsService.formatDistanceBucket(3500), '2km-5km');
      expect(AnalyticsService.formatDistanceBucket(8500), '5km-10km');
      expect(AnalyticsService.formatDistanceBucket(15000), '>10km');
    });

    test('10. Routing and offline sync telemetry trackers produce valid schema', () async {
      final prefs = await SharedPreferences.getInstance();
      service.setDependenciesForTesting(prefs: prefs);

      await service.trackRouteTelemetry(
        emergencyId: 'nav_001',
        routeCategory: 'scene_navigation',
        latencyMs: 340,
        success: true,
        distanceBucket: '500m-2km',
      );

      await service.trackOfflineSyncTelemetry(
        emergencyId: 'JS-OFF-12345',
        retryCount: 0,
        syncLatencyMs: 820,
        success: true,
        terminalStatus: 'COMPLETED',
      );

      final queued = await service.getQueuedEvents();
      expect(queued.length, 2);

      final routeEvt = queued.firstWhere((e) => e.eventType == 'routing_telemetry');
      expect(routeEvt.routeCategory, 'scene_navigation');
      expect(routeEvt.latencyMs, 340);
      expect(routeEvt.success, isTrue);

      final syncEvt = queued.firstWhere((e) => e.eventType == 'offline_sync_telemetry');
      expect(syncEvt.retryCount, 0);
      expect(syncEvt.syncLatencyMs, 820);
      expect(syncEvt.terminalStatus, 'COMPLETED');
    });
  });
}
