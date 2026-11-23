import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';

/// Represents a privacy-compliant operational analytics event for Tiger Data / TimescaleDB.
/// Strict constraint: NEVER contains raw GPS coordinates, names, phone numbers, tokens, or PII.
class AnalyticsEvent {
  final String eventId;
  final String emergencyId;
  final String eventType;
  final String? category; // 'lifecycle', 'routing', 'offline_sync'
  final String? emergencyType; // 'MEDICAL', 'ACCIDENT', 'FIRE', etc.
  final String? eventSource; // 'online', 'offline_p2p'
  final String? transportMode;
  final String timestamp; // ISO-8601
  final int? durationToAcceptanceMs;
  final int? durationToArrivalMs;
  final int? totalDurationMs;
  final bool? isOfflineCreated;
  final String? routeCategory; // 'scene_navigation', 'hospital_transfer'
  final int? latencyMs;
  final String? distanceBucket; // '<500m', '500m-2km', etc.
  final bool? success;
  final String? failureCode;
  final int? retryCount;
  final int? syncLatencyMs;
  final String? terminalStatus;
  final String? errorCategory;

  AnalyticsEvent({
    required this.eventId,
    required this.emergencyId,
    required this.eventType,
    this.category,
    this.emergencyType,
    this.eventSource,
    this.transportMode,
    required this.timestamp,
    this.durationToAcceptanceMs,
    this.durationToArrivalMs,
    this.totalDurationMs,
    this.isOfflineCreated,
    this.routeCategory,
    this.latencyMs,
    this.distanceBucket,
    this.success,
    this.failureCode,
    this.retryCount,
    this.syncLatencyMs,
    this.terminalStatus,
    this.errorCategory,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'eventId': eventId,
      'emergencyId': emergencyId,
      'eventType': eventType,
      'timestamp': timestamp,
    };

    if (category != null) map['category'] = category;
    if (emergencyType != null) map['emergencyType'] = emergencyType;
    if (eventSource != null) map['eventSource'] = eventSource;
    if (transportMode != null) map['transportMode'] = transportMode;
    if (durationToAcceptanceMs != null) map['durationToAcceptanceMs'] = durationToAcceptanceMs;
    if (durationToArrivalMs != null) map['durationToArrivalMs'] = durationToArrivalMs;
    if (totalDurationMs != null) map['totalDurationMs'] = totalDurationMs;
    if (isOfflineCreated != null) map['isOfflineCreated'] = isOfflineCreated;
    if (routeCategory != null) map['routeCategory'] = routeCategory;
    if (latencyMs != null) map['latencyMs'] = latencyMs;
    if (distanceBucket != null) map['distanceBucket'] = distanceBucket;
    if (success != null) map['success'] = success;
    if (failureCode != null) map['failureCode'] = failureCode;
    if (retryCount != null) map['retryCount'] = retryCount;
    if (syncLatencyMs != null) map['syncLatencyMs'] = syncLatencyMs;
    if (terminalStatus != null) map['terminalStatus'] = terminalStatus;
    if (errorCategory != null) map['errorCategory'] = errorCategory;

    return map;
  }

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) {
    return AnalyticsEvent(
      eventId: json['eventId'] as String,
      emergencyId: json['emergencyId'] as String,
      eventType: json['eventType'] as String,
      category: json['category'] as String?,
      emergencyType: json['emergencyType'] as String?,
      eventSource: json['eventSource'] as String?,
      transportMode: json['transportMode'] as String?,
      timestamp: json['timestamp'] as String,
      durationToAcceptanceMs: json['durationToAcceptanceMs'] as int?,
      durationToArrivalMs: json['durationToArrivalMs'] as int?,
      totalDurationMs: json['totalDurationMs'] as int?,
      isOfflineCreated: json['isOfflineCreated'] as bool?,
      routeCategory: json['routeCategory'] as String?,
      latencyMs: json['latencyMs'] as int?,
      distanceBucket: json['distanceBucket'] as String?,
      success: json['success'] as bool?,
      failureCode: json['failureCode'] as String?,
      retryCount: json['retryCount'] as int?,
      syncLatencyMs: json['syncLatencyMs'] as int?,
      terminalStatus: json['terminalStatus'] as String?,
      errorCategory: json['errorCategory'] as String?,
    );
  }
}

/// Durable, privacy-preserving Analytics Service for Vita ResQ.
/// Enforces local outbox persistence, batching, idempotency, and isolated execution.
///
/// Strict Rule: Analytics operations NEVER block or roll back core emergency workflows.
class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._internal();

  AnalyticsService._internal();
  factory AnalyticsService() => instance;

  static const String _outboxPrefKey = 'analytics_outbox_queue_v1';
  static const int _maxQueueCapacity = 500;
  static const int _maxBatchSize = 50;

  http.Client? _httpClient;
  SharedPreferences? _prefs;
  String _baseUrl = AppConstants.defaultAnalyticsBackendBaseUrl;
  Future<String?> Function()? _testTokenProvider;

  bool _isFlushing = false;
  bool _autoFlush = true;
  Future<void> _queueLock = Future.value();

  String get baseUrl => _baseUrl;
  set baseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
  }

  void setDependenciesForTesting({
    http.Client? httpClient,
    SharedPreferences? prefs,
    String? baseUrl,
    Future<String?> Function()? tokenProvider,
    bool? autoFlush,
  }) {
    if (httpClient != null) _httpClient = httpClient;
    if (prefs != null) _prefs = prefs;
    if (baseUrl != null) _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (tokenProvider != null) _testTokenProvider = tokenProvider;
    if (autoFlush != null) _autoFlush = autoFlush;
  }

  int _overflowEvictionsTotal = 0;
  int _telemetryEvictionsCount = 0;
  int _lifecycleEvictionsCount = 0;

  void resetForTesting() {
    _httpClient = null;
    _prefs = null;
    _baseUrl = AppConstants.defaultAnalyticsBackendBaseUrl;
    _testTokenProvider = null;
    _autoFlush = true;
    _isFlushing = false;
    _queueLock = Future.value();
    _overflowEvictionsTotal = 0;
    _telemetryEvictionsCount = 0;
    _lifecycleEvictionsCount = 0;
  }

  Future<SharedPreferences> _getPrefs() async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  http.Client _getClient() {
    return _httpClient ?? http.Client();
  }

  /// Generate a stable, collision-resistant event identifier
  String generateEventId(String prefix) {
    final random = math.Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final r = random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'evt_${prefix}_${timestamp}_$r';
  }

  // ---------------------------------------------------------------------------
  // Outbox Queue Management & Diagnostics
  // ---------------------------------------------------------------------------

  /// Returns queue overflow and retention diagnostics
  Map<String, int> getDiagnostics() {
    return {
      'overflowEvictionsTotal': _overflowEvictionsTotal,
      'telemetryEvictionsCount': _telemetryEvictionsCount,
      'lifecycleEvictionsCount': _lifecycleEvictionsCount,
    };
  }

  /// Enqueue an event into durable storage with prioritized retention.
  /// Lifecycle events (SOS, acceptance, arrival, completion, cancellation) are
  /// strictly preserved over lower-priority routing and sync telemetry when the queue fills.
  Future<void> enqueueEvent(AnalyticsEvent event) async {
    try {
      final completer = Completer<void>();
      _queueLock = _queueLock.then((_) async {
        try {
          final prefs = await _getPrefs();
          List<String> queue = prefs.getStringList(_outboxPrefKey) ?? [];

          // Enforce prioritized capacity management
          if (queue.length >= _maxQueueCapacity) {
            _overflowEvictionsTotal++;

            // 1. Find oldest non-lifecycle event to evict first
            int evictIndex = -1;
            for (int i = 0; i < queue.length; i++) {
              try {
                final map = jsonDecode(queue[i]) as Map<String, dynamic>;
                final category = map['category'] as String?;
                if (category != 'lifecycle') {
                  evictIndex = i;
                  break;
                }
              } catch (_) {
                evictIndex = i; // Malformed item can be safely evicted
                break;
              }
            }

            if (evictIndex != -1) {
              queue.removeAt(evictIndex);
              _telemetryEvictionsCount++;
            } else {
              // 2. All 500 events are lifecycle events — evict oldest lifecycle event FIFO
              queue.removeAt(0);
              _lifecycleEvictionsCount++;
            }
          }

          queue.add(jsonEncode(event.toJson()));
          await prefs.setStringList(_outboxPrefKey, queue);
          completer.complete();
        } catch (e) {
          completer.complete();
        }
      }).catchError((_) {
        completer.complete();
      });

      await completer.future;

      // Asynchronously trigger flush without awaiting in critical caller path
      if (_autoFlush) {
        unawaited(flushOutbox());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ANALYTICS] Enqueue error (isolated): $e');
      }
    }
  }

  /// Returns current list of queued events (for inspection/testing)
  Future<List<AnalyticsEvent>> getQueuedEvents() async {
    try {
      final prefs = await _getPrefs();
      final list = prefs.getStringList(_outboxPrefKey) ?? [];
      return list.map((item) {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        return AnalyticsEvent.fromJson(decoded);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Flush up to 50 queued events to the backend batch ingestion endpoint.
  Future<int> flushOutbox() async {
    if (_isFlushing) return 0;
    _isFlushing = true;

    int ackCount = 0;

    try {
      final prefs = await _getPrefs();
      List<String> rawQueue = prefs.getStringList(_outboxPrefKey) ?? [];
      if (rawQueue.isEmpty) {
        _isFlushing = false;
        return 0;
      }

      // 1. Take up to 50 events for batch
      final batchRaw = rawQueue.take(_maxBatchSize).toList();
      final List<AnalyticsEvent> batchEvents = [];
      for (final raw in batchRaw) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          batchEvents.add(AnalyticsEvent.fromJson(map));
        } catch (_) {}
      }

      if (batchEvents.isEmpty) {
        _isFlushing = false;
        return 0;
      }

      // 2. Obtain auth token
      String? token;
      if (_testTokenProvider != null) {
        token = await _testTokenProvider!();
      } else {
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            token = await user.getIdToken();
          }
        } catch (_) {
          token = null;
        }
      }

      if (token == null || token.isEmpty) {
        // Not authenticated yet — retain events in outbox for subsequent retry
        _isFlushing = false;
        return 0;
      }

      // 3. Send batch request
      final client = _getClient();
      final url = Uri.parse('$_baseUrl/api/analytics/events/batch');
      final payload = jsonEncode({
        'events': batchEvents.map((e) => e.toJson()).toList(),
      });

      final response = await client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: payload,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> accepted = body['accepted'] as List<dynamic>? ?? [];
        final List<dynamic> duplicates = body['duplicates'] as List<dynamic>? ?? [];
        final Set<String> ackedIds = {...accepted, ...duplicates}.cast<String>();

        ackCount = ackedIds.length;

        // 4. Remove acknowledged events from queue
        final completer = Completer<void>();
        _queueLock = _queueLock.then((_) async {
          try {
            List<String> current = prefs.getStringList(_outboxPrefKey) ?? [];
            current.removeWhere((raw) {
              try {
                final map = jsonDecode(raw) as Map<String, dynamic>;
                return ackedIds.contains(map['eventId']);
              } catch (_) {
                return false;
              }
            });
            await prefs.setStringList(_outboxPrefKey, current);
          } finally {
            completer.complete();
          }
        });
        await completer.future;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ANALYTICS] Flush error (retained for retry): $e');
      }
    } finally {
      _isFlushing = false;
    }

    return ackCount;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle Telemetry Trackers
  // ---------------------------------------------------------------------------

  /// Track SOS creation
  Future<void> trackSosCreated({
    required String emergencyId,
    required String emergencyType,
    required bool isOfflineCreated,
    DateTime? timestamp,
  }) async {
    final event = AnalyticsEvent(
      eventId: generateEventId('sos'),
      emergencyId: emergencyId,
      eventType: 'sos_created',
      category: 'lifecycle',
      emergencyType: emergencyType,
      eventSource: isOfflineCreated ? 'offline_p2p' : 'online',
      isOfflineCreated: isOfflineCreated,
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
    );
    await enqueueEvent(event);
  }

  /// Track responder claim/acceptance
  Future<void> trackResponderAccepted({
    required String emergencyId,
    required String emergencyType,
    required int? durationToAcceptanceMs,
    String? transportMode,
    bool isOffline = false,
    DateTime? timestamp,
  }) async {
    final event = AnalyticsEvent(
      eventId: generateEventId('acc'),
      emergencyId: emergencyId,
      eventType: 'responder_accepted',
      category: 'lifecycle',
      emergencyType: emergencyType,
      eventSource: isOffline ? 'offline_p2p' : 'online',
      transportMode: transportMode,
      durationToAcceptanceMs: durationToAcceptanceMs,
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
    );
    await enqueueEvent(event);
  }

  /// Track responder arrival at scene
  Future<void> trackResponderArrived({
    required String emergencyId,
    required String emergencyType,
    required int? durationToArrivalMs,
    bool isOffline = false,
    DateTime? timestamp,
  }) async {
    final event = AnalyticsEvent(
      eventId: generateEventId('arr'),
      emergencyId: emergencyId,
      eventType: 'responder_arrived',
      category: 'lifecycle',
      emergencyType: emergencyType,
      eventSource: isOffline ? 'offline_p2p' : 'online',
      durationToArrivalMs: durationToArrivalMs,
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
    );
    await enqueueEvent(event);
  }

  /// Track emergency completion
  Future<void> trackEmergencyCompleted({
    required String emergencyId,
    required String emergencyType,
    required int? totalDurationMs,
    bool isOffline = false,
    DateTime? timestamp,
  }) async {
    final event = AnalyticsEvent(
      eventId: generateEventId('comp'),
      emergencyId: emergencyId,
      eventType: 'emergency_completed',
      category: 'lifecycle',
      emergencyType: emergencyType,
      eventSource: isOffline ? 'offline_p2p' : 'online',
      totalDurationMs: totalDurationMs,
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
    );
    await enqueueEvent(event);
  }

  /// Track emergency cancellation
  Future<void> trackEmergencyCancelled({
    required String emergencyId,
    required String emergencyType,
    required int? totalDurationMs,
    required bool wasAccepted,
    bool isOffline = false,
    DateTime? timestamp,
  }) async {
    final event = AnalyticsEvent(
      eventId: generateEventId('canc'),
      emergencyId: emergencyId,
      eventType: 'emergency_cancelled',
      category: 'lifecycle',
      emergencyType: emergencyType,
      eventSource: isOffline ? 'offline_p2p' : 'online',
      totalDurationMs: totalDurationMs,
      // Distinguish missing duration from zero: if never accepted, acceptance duration is strictly null
      durationToAcceptanceMs: wasAccepted ? null : null,
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
    );
    await enqueueEvent(event);
  }

  // ---------------------------------------------------------------------------
  // Routing & Offline Sync Telemetry Trackers
  // ---------------------------------------------------------------------------

  /// Helper to convert distance in meters to a coarse privacy bucket
  static String formatDistanceBucket(double meters) {
    if (meters < 500) return '<500m';
    if (meters < 2000) return '500m-2km';
    if (meters < 5000) return '2km-5km';
    if (meters < 10000) return '5km-10km';
    return '>10km';
  }

  /// Track routing request latency and outcome
  Future<void> trackRouteTelemetry({
    required String emergencyId,
    required String routeCategory,
    required int latencyMs,
    required bool success,
    String? distanceBucket,
    String? failureCode,
    DateTime? timestamp,
  }) async {
    final event = AnalyticsEvent(
      eventId: generateEventId('route'),
      emergencyId: emergencyId,
      eventType: 'routing_telemetry',
      category: 'routing',
      routeCategory: routeCategory,
      latencyMs: latencyMs,
      distanceBucket: distanceBucket,
      success: success,
      failureCode: failureCode,
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
    );
    await enqueueEvent(event);
  }

  /// Track offline synchronization outcome and latency
  Future<void> trackOfflineSyncTelemetry({
    required String emergencyId,
    required int retryCount,
    required int syncLatencyMs,
    required bool success,
    String? terminalStatus,
    String? errorCategory,
    DateTime? timestamp,
  }) async {
    final event = AnalyticsEvent(
      eventId: generateEventId('sync'),
      emergencyId: emergencyId,
      eventType: 'offline_sync_telemetry',
      category: 'offline_sync',
      retryCount: retryCount,
      syncLatencyMs: syncLatencyMs,
      terminalStatus: terminalStatus,
      success: success,
      errorCategory: errorCategory,
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
    );
    await enqueueEvent(event);
  }
}
