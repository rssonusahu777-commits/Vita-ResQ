// lib/services/nearby_relay_service.dart
//
// Vindara — Nearby Device-to-Device Offline Relay Service (Phase 7)
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #1 — Offline-first: Operates when ConnectivityService reports offline.
//   Rule #2 — Offline coordinates preserved exactly.
//   Rule #6 — Single-lifecycle subscriptions; clean cancellation in dispose().
//   Rule #7 — Deduplication by (id + version).
//   Rule #8 — Relayed packets saved with syncStatus = 'pending' for auto-drain when online.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/emergency.dart';
import 'local_emergency_store.dart';

/// Abstract transport contract for device-to-device communication (e.g. BLE, Wi-Fi Direct, Nearby Connections).
/// Allows mock injection in unit tests and platform-independent execution.
abstract class NearbyTransport {
  /// Stream of incoming payloads from nearby peers: (peerId, payloadString).
  Stream<NearbyPayload> get incomingPayloadStream;

  /// Starts advertising device presence to nearby peers.
  Future<void> startAdvertising(String endpointName);

  /// Stops advertising.
  Future<void> stopAdvertising();

  /// Starts discovering nearby peer devices.
  Future<void> startDiscovery();

  /// Stops discovering.
  Future<void> stopDiscovery();

  /// Broadcasts a payload string to all discovered/connected peers.
  Future<void> broadcastPayload(String payload);

  /// Whether advertising is currently active.
  bool get isAdvertising;

  /// Whether discovery is currently active.
  bool get isDiscovering;

  /// Closes transport resources.
  Future<void> dispose();
}

/// Represents an incoming payload from a peer device.
class NearbyPayload {
  final String peerId;
  final String content;
  final DateTime receivedAt;

  NearbyPayload({
    required this.peerId,
    required this.content,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();
}

/// In-memory default / testable implementation of NearbyTransport.
class DefaultNearbyTransport implements NearbyTransport {
  final StreamController<NearbyPayload> _payloadController =
      StreamController<NearbyPayload>.broadcast();

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  @override
  Stream<NearbyPayload> get incomingPayloadStream => _payloadController.stream;

  @override
  bool get isAdvertising => _isAdvertising;

  @override
  bool get isDiscovering => _isDiscovering;

  @override
  Future<void> startAdvertising(String endpointName) async {
    _isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    _isAdvertising = false;
  }

  @override
  Future<void> startDiscovery() async {
    _isDiscovering = true;
  }

  @override
  Future<void> stopDiscovery() async {
    _isDiscovering = false;
  }

  @override
  Future<void> broadcastPayload(String payload) async {
    // In local / loopback mode or simulated test mode, can feed directly
  }

  /// Inject an incoming payload (used by tests or platform message bridges).
  void simulateIncomingPayload(String peerId, String content) {
    if (!_payloadController.isClosed) {
      _payloadController.add(NearbyPayload(peerId: peerId, content: content));
    }
  }

  @override
  Future<void> dispose() async {
    _isAdvertising = false;
    _isDiscovering = false;
    await _payloadController.close();
  }
}

/// Service that coordinates device-to-device offline emergency relays.
class NearbyRelayService {
  final NearbyTransport _transport;
  final LocalEmergencyStore _localStore;

  StreamSubscription<NearbyPayload>? _transportSub;

  /// Seen emergency cache: emergencyId -> highest version observed.
  /// Prevents broadcast storms and duplicate processing (Rule #7).
  final Map<String, int> _seenVersions = {};

  final StreamController<Emergency> _relayedEmergenciesController =
      StreamController<Emergency>.broadcast();

  bool _isActive = false;

  NearbyRelayService({
    required this._transport,
    required this._localStore,
  });

  /// Stream of new or updated emergencies received from nearby peers.
  Stream<Emergency> get relayedEmergenciesStream =>
      _relayedEmergenciesController.stream;

  /// Whether relay advertising and discovery are active.
  bool get isActive => _isActive;

  /// Starts the peer-to-peer relay (listens, advertises, and discovers).
  Future<void> startRelay({String endpointName = 'VindaraPeer'}) async {
    if (_isActive) return;
    _isActive = true;

    _transportSub = _transport.incomingPayloadStream.listen(
      _handleIncomingPayload,
      onError: (err) {
        debugPrint('NearbyRelay transport error: $err');
      },
    );

    await _transport.startAdvertising(endpointName);
    await _transport.startDiscovery();
  }

  /// Stops advertising, discovery, and cancels listeners (Rule #6).
  Future<void> stopRelay() async {
    _isActive = false;
    await _transportSub?.cancel();
    _transportSub = null;
    await _transport.stopAdvertising();
    await _transport.stopDiscovery();
  }

  /// Broadcasts an active emergency to all nearby peers.
  /// Preserves exact EMG-2026-XXXXXXXX ID and version (Rule #7).
  Future<void> broadcastEmergency(Emergency emergency) async {
    final offlineEmergency = emergency.copyWith(
      communicationMode: CommunicationMode.offline,
      version: emergency.version,
    );

    _seenVersions[offlineEmergency.id] = offlineEmergency.version;

    final packet = {
      'protocol': 'VINDARA_D2D_V1',
      'emergencyId': offlineEmergency.id,
      'version': offlineEmergency.version,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'payload': offlineEmergency.toJson(),
    };

    final rawJson = jsonEncode(packet);
    await _transport.broadcastPayload(rawJson);
  }

  /// Handles incoming peer payload with deduplication and version merging.
  Future<void> _handleIncomingPayload(NearbyPayload payload) async {
    try {
      final Map<String, dynamic> data = jsonDecode(payload.content);
      if (data['protocol'] != 'VINDARA_D2D_V1') return;

      final emergencyId = data['emergencyId'] as String?;
      final version = data['version'] as int?;
      final rawEmergency = data['payload'] as Map<String, dynamic>?;

      if (emergencyId == null || version == null || rawEmergency == null) return;

      // 1. Deduplication Guard: Ignore if we have seen this or higher version
      final knownVersion = _seenVersions[emergencyId];
      if (knownVersion != null && knownVersion >= version) {
        return; // Already processed this or newer version
      }

      // Check local store existing version
      final existing = _localStore.getEmergencyById(emergencyId);
      if (existing != null && existing.version >= version) {
        _seenVersions[emergencyId] = existing.version;
        return;
      }

      // 2. Deserialize authoritative emergency entity
      final emergency = Emergency.fromJson(rawEmergency);

      // Record highest version seen
      _seenVersions[emergencyId] = emergency.version;

      // 3. Rule #8: Persist to LocalEmergencyStore with syncStatus = 'pending'
      // Whichever device regains internet access first auto-syncs to Cloud Firestore!
      await _localStore.saveEmergency(
        emergency.copyWith(
          communicationMode: CommunicationMode.offline,
          version: emergency.version,
        ),
        syncStatus: 'pending',
      );

      // 4. Emit to stream
      if (!_relayedEmergenciesController.isClosed) {
        _relayedEmergenciesController.add(emergency);
      }
    } catch (e) {
      debugPrint('Error parsing relayed emergency packet: $e');
    }
  }

  /// Check whether an emergency version is already known.
  bool hasSeenVersion(String emergencyId, int version) {
    final known = _seenVersions[emergencyId];
    return known != null && known >= version;
  }

  /// Clean disposal of service and transport (Rule #6).
  Future<void> dispose() async {
    await stopRelay();
    await _transport.dispose();
    await _relayedEmergenciesController.close();
  }
}
