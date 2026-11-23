import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/constants/app_constants.dart';
import '../models/emergency_model.dart';
import '../models/responder_model.dart';
import 'emergency_service.dart';
import 'offline_nearby_service.dart';
import 'local_database_service.dart';

class LocationService {
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<Position>? _emergencyPositionSubscription;
  Timer? _heartbeatTimer;
  final EmergencyService _emergencyService = EmergencyService();
  final OfflineNearbyService _offlineNearbyService = OfflineNearbyService();
  final LocalDatabaseService _localDb = LocalDatabaseService();

  Position? _cachedPosition;
  DateTime? _lastFetchTime;
  static final StreamController<Position> _positionBroadcastController =
      StreamController<Position>.broadcast();

  /// Reactive stream of live GPS position updates for UI subscribers
  Stream<Position> get onPositionChanged => _positionBroadcastController.stream;

  /// Get current speed in meters per second
  double get lastSpeedMps => _cachedPosition?.speed ?? 0.0;

  /// Check and request location permission from device
  Future<bool> checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get current GPS position with high accuracy
  Future<Position?> getCurrentLocation({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh && _cachedPosition != null && _lastFetchTime != null) {
        if (DateTime.now().difference(_lastFetchTime!).inSeconds < 3) {
          return _cachedPosition;
        }
      }

      bool hasPermission = await checkLocationPermission();
      if (!hasPermission) return null;

      // Fast-path: Check last known hardware position first for instantaneous coordinate availability
      if (_cachedPosition == null) {
        try {
          Position? lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            _cachedPosition = lastKnown;
            _lastFetchTime = DateTime.now();
            _positionBroadcastController.add(lastKnown);
          }
        } catch (_) {}
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 8),
      );

      _cachedPosition = pos;
      _lastFetchTime = DateTime.now();
      _positionBroadcastController.add(pos);
      return pos;
    } catch (_) {
      // If fine satellite lock timed out, return fast-path cached/lastKnown position if available
      return _cachedPosition;
    }
  }

  /// Start streaming live GPS updates while user is active
  void startLocationUpdates() async {
    stopLocationUpdates();

    bool hasPermission = await checkLocationPermission();
    if (!hasPermission) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _cachedPosition = position;
      _lastFetchTime = DateTime.now();
      _positionBroadcastController.add(position);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _updateUserLocationInFirestore(user.uid, position);
      }
    });
  }

  LocationTelemetryThrottler? _throttler;
  LocationTelemetryThrottler? get throttler => _throttler;
  bool _isPrimaryHelper = false;

  /// Update primary helper status dynamically if role changes during active session
  void setIsPrimary(bool isPrimary) {
    _isPrimaryHelper = isPrimary;
  }

  /// Start streaming live GPS updates to active emergency session with 1m high-precision updates.
  /// Supports both online (Firestore) and offline (Nearby Connections P2P) emergencies.
  void startEmergencyLocationUpdates({
    required String emergencyId,
    required bool isVictim,
    bool isPrimary = false,
  }) async {
    _isPrimaryHelper = isPrimary;

    // 1. Prevent duplicate streams: cancel any existing subscription and throttler first
    stopEmergencyLocationUpdates();

    bool hasPermission = await checkLocationPermission();
    if (!hasPermission) return;

    final user = FirebaseAuth.instance.currentUser;
    final bool isOfflineEmergency = emergencyId.startsWith('JS-OFF-');

    // Ensure initial cached position is available for heartbeat
    if (_cachedPosition == null) {
      try {
        _cachedPosition = await getCurrentLocation();
      } catch (_) {}
    }

    // Set up controlled telemetry publisher for online emergencies
    if (!isOfflineEmergency) {
      _throttler = LocationTelemetryThrottler(
        throttleInterval: const Duration(seconds: 3),
        heartbeatInterval: const Duration(seconds: 8),
        onPublish: (Position pos) async {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) return;
          await _emergencyService.publishRoutineTelemetry(
            emergencyId: emergencyId,
            userId: currentUser.uid,
            isVictim: isVictim,
            isPrimary: _isPrimaryHelper,
            position: pos,
          );
        },
      );

      // Start coordinated heartbeat (only publishes if no recent movement occurred in 8s)
      if (!isVictim) {
        _throttler!.startHeartbeat();
      }
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );

    _emergencyPositionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      // 1. Immediate local state update for map movement and distance display
      _cachedPosition = position;
      _lastFetchTime = DateTime.now();
      _positionBroadcastController.add(position);

      if (isOfflineEmergency) {
        // Offline: Publish coordinates via P2P Nearby Connections without touching Firestore
        try {
          await _offlineNearbyService.sendStatusUpdatePayload(
            emergencyId: emergencyId,
            status: isVictim ? 'SEARCHING' : 'RESPONDING',
            responderId: isVictim ? null : (user?.uid ?? 'offline_responder'),
            latitude: position.latitude,
            longitude: position.longitude,
          );

          // Update local database so local screens/streams immediately reflect coordinates
          EmergencyModel? localEm = await _localDb.getEmergencyById(emergencyId);
          if (localEm != null) {
            Map<String, dynamic> locData = {
              'latitude': position.latitude,
              'longitude': position.longitude,
              'updatedAt': DateTime.now().toIso8601String(),
            };

            EmergencyModel updatedEm;
            if (isVictim) {
              updatedEm = EmergencyModel(
                id: localEm.id,
                victimId: localEm.victimId,
                type: localEm.type,
                latitude: position.latitude,
                longitude: position.longitude,
                status: localEm.status,
                helperId: localEm.helperId,
                currentRadiusMeters: localEm.currentRadiusMeters,
                notifiedUserIds: localEm.notifiedUserIds,
                responders: localEm.responders,
                createdAt: localEm.createdAt,
                updatedAt: DateTime.now(),
                lastVictimLocation: locData,
                lastHelperLocation: localEm.lastHelperLocation,
              );
            } else {
              String respId = user?.uid ?? 'offline_responder';
              Map<String, ResponderModel> updatedResponders = Map.from(localEm.responders);
              if (updatedResponders.containsKey(respId)) {
                ResponderModel r = updatedResponders[respId]!;
                updatedResponders[respId] = ResponderModel(
                  userId: r.userId,
                  userName: r.userName,
                  phoneNumber: r.phoneNumber,
                  bloodGroup: r.bloodGroup,
                  role: r.role,
                  status: r.status,
                  latitude: position.latitude,
                  longitude: position.longitude,
                  acceptedAt: r.acceptedAt,
                  lastLocationUpdate: DateTime.now(),
                  assignedAt: r.assignedAt,
                  distanceToVictim: r.distanceToVictim,
                  etaText: r.etaText,
                  etaMinutes: r.etaMinutes,
                  problemReason: r.problemReason,
                );
              }
              updatedEm = EmergencyModel(
                id: localEm.id,
                victimId: localEm.victimId,
                type: localEm.type,
                latitude: localEm.latitude,
                longitude: localEm.longitude,
                status: localEm.status,
                helperId: localEm.helperId,
                currentRadiusMeters: localEm.currentRadiusMeters,
                notifiedUserIds: localEm.notifiedUserIds,
                responders: updatedResponders,
                createdAt: localEm.createdAt,
                updatedAt: DateTime.now(),
                lastVictimLocation: localEm.lastVictimLocation,
                lastHelperLocation: locData,
              );
            }
            await _localDb.saveEmergencyLocally(updatedEm);
          }
        } catch (_) {}
      } else {
        // Online: Route through throttled publisher to coalesce rapid GPS events
        // and enforce max 1 write every 3 seconds to Firestore
        _throttler?.handlePositionUpdate(position);
      }
    });
  }

  /// Stop emergency location updates and cancel all associated timers
  void stopEmergencyLocationUpdates() {
    _throttler?.dispose();
    _throttler = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _emergencyPositionSubscription?.cancel();
    _emergencyPositionSubscription = null;
  }

  /// Stop regular location updates
  void stopLocationUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }

  /// Safely dispose all active location subscriptions
  void dispose() {
    stopLocationUpdates();
    stopEmergencyLocationUpdates();
  }

  /// Update Firestore users/{userId} document
  Future<void> _updateUserLocationInFirestore(String uid, Position position) async {
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'locationAccuracy': position.accuracy,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'isOnline': true,
      });
    } catch (_) {}
  }
}

/// Throttles and coalesces high-frequency GPS position events for Cloud Firestore
/// while coordinating with periodic heartbeats so they cannot produce overlapping routine writes.
class LocationTelemetryThrottler {
  final Duration throttleInterval;
  final Duration heartbeatInterval;
  final Future<void> Function(Position position) onPublish;

  DateTime? _lastPublishTime;
  Position? _latestPendingPosition;
  Position? _cachedPosition;
  Timer? _throttleTimer;
  Timer? _heartbeatTimer;
  bool _isPublishInFlight = false;

  int localEventCount = 0;
  int publishedCount = 0;

  LocationTelemetryThrottler({
    this.throttleInterval = const Duration(seconds: 3),
    this.heartbeatInterval = const Duration(seconds: 8),
    required this.onPublish,
  });

  DateTime? get lastPublishTime => _lastPublishTime;
  Position? get latestPendingPosition => _latestPendingPosition;
  Position? get cachedPosition => _cachedPosition;
  bool get isPublishInFlight => _isPublishInFlight;
  bool get isThrottleTimerActive => _throttleTimer?.isActive ?? false;

  /// Process incoming GPS position event from hardware.
  /// Increments local counter immediately and schedules or triggers publication.
  void handlePositionUpdate(Position position) {
    if (!ResponderModel.isValidCoordinate(position.latitude, position.longitude)) {
      return;
    }

    localEventCount++;
    _cachedPosition = position;
    _latestPendingPosition = position;

    final now = DateTime.now();
    final bool canPublishNow = !_isPublishInFlight &&
        (_lastPublishTime == null || now.difference(_lastPublishTime!) >= throttleInterval);

    if (canPublishNow) {
      _drainPendingPublish();
    } else if (_throttleTimer == null || !_throttleTimer!.isActive) {
      final elapsed = _lastPublishTime != null ? now.difference(_lastPublishTime!) : Duration.zero;
      final remainingMs = (throttleInterval.inMilliseconds - elapsed.inMilliseconds).clamp(0, throttleInterval.inMilliseconds);
      final remaining = Duration(milliseconds: remainingMs);
      _throttleTimer = Timer(remaining, _drainPendingPublish);
    }
  }

  /// Start periodic heartbeat to maintain freshness when stationary
  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      final now = DateTime.now();
      // If location was published within heartbeatInterval, Firestore timestamp is already fresh
      if (_lastPublishTime != null && now.difference(_lastPublishTime!) < heartbeatInterval) {
        return;
      }

      // Responder is stationary: publish latest cached position through same pipeline
      if (_cachedPosition != null && !_isPublishInFlight) {
        _latestPendingPosition = _cachedPosition;
        _drainPendingPublish();
      }
    });
  }

  Future<void> _drainPendingPublish() async {
    _throttleTimer?.cancel();
    _throttleTimer = null;

    if (_isPublishInFlight || _latestPendingPosition == null) return;

    final positionToPublish = _latestPendingPosition!;
    _latestPendingPosition = null;
    _isPublishInFlight = true;

    try {
      await onPublish(positionToPublish);
      _lastPublishTime = DateTime.now();
      publishedCount++;
    } catch (_) {
      // Failed publish: preserve as pending if no newer position arrived
      _latestPendingPosition ??= positionToPublish;
    } finally {
      _isPublishInFlight = false;
      // If a newer position arrived during the in-flight publish, schedule it
      if (_latestPendingPosition != null && (_throttleTimer == null || !_throttleTimer!.isActive)) {
        final now = DateTime.now();
        final elapsed = _lastPublishTime != null ? now.difference(_lastPublishTime!) : Duration.zero;
        final remainingMs = (throttleInterval.inMilliseconds - elapsed.inMilliseconds).clamp(0, throttleInterval.inMilliseconds);
        final remaining = Duration(milliseconds: remainingMs);
        _throttleTimer = Timer(remaining, _drainPendingPublish);
      }
    }
  }

  /// Cancel all timers and clear pending state
  void dispose() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _latestPendingPosition = null;
    _isPublishInFlight = false;
  }
}
