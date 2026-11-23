// lib/services/offline_p2p_service.dart
//
// Vindara — True Offline Peer-to-Peer (P2P) Emergency HELP Mesh
// Package: com.vindara.app
//
// Architectural Rules Followed:
//   Rule #1  — Offline-first: Operates via nearby BLE & Wi-Fi Direct clusters.
//   Rule #2  — Raw hardware GPS coordinates preserved with zero loss.
//   Rule #4  — Source of truth: Deduplicated by emergencyId, synced when online.
//   Rule #6  — Single broadcast streams; clean lifecycle in dispose().
//   Rule #7  — Collision-free IDs and deduplication sets.
//   Rule #8  — Local-first write to LocalEmergencyStore with 'pending' sync status.
//   Rule #10 — Strictly zero "SOS" labels; always "HELP".

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import '../models/emergency.dart';
import 'connectivity_service.dart';
import 'firestore_emergency_service.dart';
import 'local_emergency_store.dart';

// ---------------------------------------------------------------------------
// P2P Status Enum
// ---------------------------------------------------------------------------

/// Real-time status of the Offline P2P Mesh engine.
enum P2pMeshStatus {
  idle,
  advertising,
  discovering,
  connected,
  broadcasting,
  alertReceived,
}

// ---------------------------------------------------------------------------
// Compact JSON Byte Payload (Rule #4 & Teammate AI Contract)
// ---------------------------------------------------------------------------

/// Compact P2P payload for device-to-device emergency broadcasting.
/// Strictly excludes heavy media (camera / audio buffers) to fit well within
/// low-energy radio byte limits and respect victim privacy.
class P2pHelpPayload {
  final String emergencyId;
  final String victimName;
  final String? victimPhone;
  final String type;
  final String? severity;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String locationLabel;
  final String timestamp;
  final String source; // "p2p_offline"
  final List<String> recommendedSkills;
  final String? notes;
  final int version;

  const P2pHelpPayload({
    required this.emergencyId,
    required this.victimName,
    this.victimPhone,
    required this.type,
    this.severity,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.locationLabel,
    required this.timestamp,
    this.source = 'p2p_offline',
    this.recommendedSkills = const [],
    this.notes,
    this.version = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      'emergencyId': emergencyId,
      'victimName': victimName,
      if (victimPhone != null) 'victimPhone': victimPhone,
      'type': type,
      if (severity != null) 'severity': severity,
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'locationLabel': locationLabel,
      'timestamp': timestamp,
      'source': source,
      'recommendedSkills': recommendedSkills,
      if (notes != null) 'notes': notes,
      'version': version,
    };
  }

  factory P2pHelpPayload.fromJson(Map<String, dynamic> json) {
    return P2pHelpPayload(
      emergencyId: json['emergencyId'] as String? ?? Emergency.generateId(),
      victimName: json['victimName'] as String? ?? 'Citizen Victim',
      victimPhone: json['victimPhone'] as String?,
      type: json['type'] as String? ?? 'medical',
      severity: json['severity'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 21.1619,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 81.7869,
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble() ?? 5.0,
      locationLabel: json['locationLabel'] as String? ?? 'Nearby Location',
      timestamp: json['timestamp'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      source: json['source'] as String? ?? 'p2p_offline',
      recommendedSkills: (json['recommendedSkills'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      notes: json['notes'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Uint8List toBytes() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  static P2pHelpPayload? fromBytes(Uint8List bytes) {
    try {
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return P2pHelpPayload.fromJson(map);
    } catch (e) {
      debugPrint('P2pHelpPayload decode failed: $e');
      return null;
    }
  }

  factory P2pHelpPayload.fromEmergency(Emergency emergency) {
    return P2pHelpPayload(
      emergencyId: emergency.id,
      victimName: emergency.victimName,
      victimPhone: emergency.victimPhone,
      type: emergency.type.name,
      severity: emergency.severity?.name,
      latitude: emergency.latitude,
      longitude: emergency.longitude,
      accuracyMeters: emergency.accuracyMeters,
      locationLabel: emergency.locationLabel,
      timestamp: emergency.createdAt.toUtc().toIso8601String(),
      source: 'p2p_offline',
      recommendedSkills: emergency.recommendedSkills,
      notes: emergency.notes,
      version: emergency.version,
    );
  }

  Emergency toEmergency() {
    EmergencyType parseType(String raw) {
      return EmergencyType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => EmergencyType.other,
      );
    }

    EmergencySeverity? parseSeverity(String? raw) {
      if (raw == null) return null;
      return EmergencySeverity.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => EmergencySeverity.moderate,
      );
    }

    final parsedCreatedAt = DateTime.tryParse(timestamp)?.toUtc() ?? DateTime.now().toUtc();

    return Emergency(
      id: emergencyId,
      victimId: emergencyId,
      victimName: victimName,
      victimPhone: victimPhone,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      locationLabel: locationLabel,
      type: parseType(type),
      createdAt: parsedCreatedAt,
      detectionSource: DetectionSource.manualHelp,
      status: EmergencyStatus.alerting,
      communicationMode: CommunicationMode.offlineNearby,
      isSyncedToCloud: false,
      version: version,
      severity: parseSeverity(severity),
      recommendedSkills: recommendedSkills,
      notes: notes != null
          ? '$notes [Received via Offline P2P Mesh]'
          : 'Dispatched via Offline Nearby P2P Mesh',
    );
  }
}

// ---------------------------------------------------------------------------
// Abstraction Layer for Nearby Connections (Testability & Safety)
// ---------------------------------------------------------------------------

/// Abstract client for Nearby Connections to allow unit test mocking
/// without invoking native Android/iOS platform channels.
abstract class NearbyClient {
  Future<bool> startAdvertising(
    String userNickName,
    Strategy strategy, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
    String serviceId,
  });

  Future<void> stopAdvertising();

  Future<bool> startDiscovery(
    String userNickName,
    Strategy strategy, {
    required OnEndpointFound onEndpointFound,
    required OnEndpointLost onEndpointLost,
    String serviceId,
  });

  Future<void> stopDiscovery();

  Future<void> stopAllEndpoints();

  Future<bool> requestConnection(
    String userNickName,
    String endpointId, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
  });

  Future<bool> acceptConnection(
    String endpointId, {
    required OnPayloadReceived onPayLoadRecieved,
    OnPayloadTransferUpdate? onPayloadTransferUpdate,
  });

  Future<void> sendBytesPayload(String endpointId, Uint8List bytes);
}

/// Production implementation backed by package:nearby_connections.
class DefaultNearbyClient implements NearbyClient {
  final Nearby _nearby = Nearby();

  @override
  Future<bool> startAdvertising(
    String userNickName,
    Strategy strategy, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
    String serviceId = "com.vindara.app.help",
  }) async {
    try {
      return await _nearby.startAdvertising(
        userNickName,
        strategy,
        onConnectionInitiated: onConnectionInitiated,
        onConnectionResult: onConnectionResult,
        onDisconnected: onDisconnected,
        serviceId: serviceId,
      );
    } on PlatformException catch (e) {
      debugPrint('DefaultNearbyClient startAdvertising exception: $e');
      return false;
    } catch (e) {
      debugPrint('DefaultNearbyClient startAdvertising error: $e');
      return false;
    }
  }

  @override
  Future<void> stopAdvertising() async {
    try {
      await _nearby.stopAdvertising();
    } catch (e) {
      debugPrint('DefaultNearbyClient stopAdvertising error: $e');
    }
  }

  @override
  Future<bool> startDiscovery(
    String userNickName,
    Strategy strategy, {
    required OnEndpointFound onEndpointFound,
    required OnEndpointLost onEndpointLost,
    String serviceId = "com.vindara.app.help",
  }) async {
    try {
      return await _nearby.startDiscovery(
        userNickName,
        strategy,
        onEndpointFound: onEndpointFound,
        onEndpointLost: onEndpointLost,
        serviceId: serviceId,
      );
    } on PlatformException catch (e) {
      debugPrint('DefaultNearbyClient startDiscovery exception: $e');
      return false;
    } catch (e) {
      debugPrint('DefaultNearbyClient startDiscovery error: $e');
      return false;
    }
  }

  @override
  Future<void> stopDiscovery() async {
    try {
      await _nearby.stopDiscovery();
    } catch (e) {
      debugPrint('DefaultNearbyClient stopDiscovery error: $e');
    }
  }

  @override
  Future<void> stopAllEndpoints() async {
    try {
      await _nearby.stopAllEndpoints();
    } catch (e) {
      debugPrint('DefaultNearbyClient stopAllEndpoints error: $e');
    }
  }

  @override
  Future<bool> requestConnection(
    String userNickName,
    String endpointId, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
  }) async {
    try {
      return await _nearby.requestConnection(
        userNickName,
        endpointId,
        onConnectionInitiated: onConnectionInitiated,
        onConnectionResult: onConnectionResult,
        onDisconnected: onDisconnected,
      );
    } on PlatformException catch (e) {
      debugPrint('DefaultNearbyClient requestConnection exception: $e');
      return false;
    } catch (e) {
      debugPrint('DefaultNearbyClient requestConnection error: $e');
      return false;
    }
  }

  @override
  Future<bool> acceptConnection(
    String endpointId, {
    required OnPayloadReceived onPayLoadRecieved,
    OnPayloadTransferUpdate? onPayloadTransferUpdate,
  }) async {
    try {
      return await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: onPayLoadRecieved,
        onPayloadTransferUpdate: onPayloadTransferUpdate,
      );
    } on PlatformException catch (e) {
      debugPrint('DefaultNearbyClient acceptConnection exception: $e');
      return false;
    } catch (e) {
      debugPrint('DefaultNearbyClient acceptConnection error: $e');
      return false;
    }
  }

  @override
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes) async {
    try {
      await _nearby.sendBytesPayload(endpointId, bytes);
    } on PlatformException catch (e) {
      debugPrint('DefaultNearbyClient sendBytesPayload exception: $e');
    } catch (e) {
      debugPrint('DefaultNearbyClient sendBytesPayload error: $e');
    }
  }
}

/// In-memory mock for unit tests to verify P2P mesh behavior deterministically.
class MockNearbyClient implements NearbyClient {
  bool isAdvertising = false;
  bool isDiscovering = false;
  final Set<String> connectedEndpoints = {};
  final List<Uint8List> sentPayloads = [];

  OnConnectionInitiated? advertConnectionInitiated;
  OnConnectionResult? advertConnectionResult;
  OnDisconnected? advertDisconnected;

  OnEndpointFound? endpointFound;
  OnEndpointLost? endpointLost;

  OnConnectionInitiated? discoverConnectionInitiated;
  OnConnectionResult? discoverConnectionResult;
  OnDisconnected? discoverDisconnected;

  OnPayloadReceived? payloadReceived;

  @override
  Future<bool> startAdvertising(
    String userNickName,
    Strategy strategy, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
    String serviceId = "com.vindara.app.help",
  }) async {
    isAdvertising = true;
    advertConnectionInitiated = onConnectionInitiated;
    advertConnectionResult = onConnectionResult;
    advertDisconnected = onDisconnected;
    return true;
  }

  @override
  Future<void> stopAdvertising() async {
    isAdvertising = false;
  }

  @override
  Future<bool> startDiscovery(
    String userNickName,
    Strategy strategy, {
    required OnEndpointFound onEndpointFound,
    required OnEndpointLost onEndpointLost,
    String serviceId = "com.vindara.app.help",
  }) async {
    isDiscovering = true;
    endpointFound = onEndpointFound;
    endpointLost = onEndpointLost;
    return true;
  }

  @override
  Future<void> stopDiscovery() async {
    isDiscovering = false;
  }

  @override
  Future<void> stopAllEndpoints() async {
    for (final ep in connectedEndpoints.toList()) {
      advertDisconnected?.call(ep);
      discoverDisconnected?.call(ep);
    }
    connectedEndpoints.clear();
  }

  @override
  Future<bool> requestConnection(
    String userNickName,
    String endpointId, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
  }) async {
    discoverConnectionInitiated = onConnectionInitiated;
    discoverConnectionResult = onConnectionResult;
    discoverDisconnected = onDisconnected;
    return true;
  }

  @override
  Future<bool> acceptConnection(
    String endpointId, {
    required OnPayloadReceived onPayLoadRecieved,
    OnPayloadTransferUpdate? onPayloadTransferUpdate,
  }) async {
    payloadReceived = onPayLoadRecieved;
    connectedEndpoints.add(endpointId);
    return true;
  }

  @override
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes) async {
    sentPayloads.add(bytes);
  }

  /// Test helper to simulate peer discovery and connection
  void simulatePeerFound(String endpointId, String peerName) {
    endpointFound?.call(endpointId, peerName, "com.vindara.app.help");
  }

  /// Test helper to simulate incoming connection initiation
  void simulateConnectionInitiated(String endpointId, String peerName) {
    advertConnectionInitiated?.call(
      endpointId,
      ConnectionInfo(peerName, "token-123", true),
    );
  }

  /// Test helper to simulate connection established
  void simulateConnected(String endpointId) {
    connectedEndpoints.add(endpointId);
    advertConnectionResult?.call(endpointId, Status.CONNECTED);
    discoverConnectionResult?.call(endpointId, Status.CONNECTED);
  }

  /// Test helper to simulate incoming byte payload from peer
  void simulatePayload(String endpointId, Uint8List bytes) {
    payloadReceived?.call(
      endpointId,
      Payload(id: 1, bytes: bytes, type: PayloadType.BYTES),
    );
  }
}

// ---------------------------------------------------------------------------
// Offline P2P Service (Singleton & Service Core)
// ---------------------------------------------------------------------------

/// Core service managing peer-to-peer offline emergency HELP mesh.
/// Uses Nearby Connections (P2P_CLUSTER) for multi-peer broadcasting and discovery.
class OfflineP2pService {
  static OfflineP2pService? _instance;

  static OfflineP2pService get instance {
    _instance ??= OfflineP2pService();
    return _instance!;
  }

  @visibleForTesting
  static void setMockInstance(OfflineP2pService mock) {
    _instance = mock;
  }

  static const String defaultServiceId = 'com.vindara.app.help';
  static const Strategy meshStrategy = Strategy.P2P_CLUSTER;

  final NearbyClient _client;
  LocalEmergencyStore? _localStore;
  FirestoreEmergencyService? _firestoreService;
  ConnectivityService? _connectivityService;

  P2pMeshStatus _status = P2pMeshStatus.idle;
  final Set<String> _seenEmergencyIds = {};
  final Set<String> _connectedEndpoints = {};
  final Map<String, P2pHelpPayload> _activeBroadcasts = {};

  final StreamController<P2pMeshStatus> _statusController =
      StreamController<P2pMeshStatus>.broadcast();
  final StreamController<Emergency> _incomingAlertsController =
      StreamController<Emergency>.broadcast();

  OfflineP2pService({
    NearbyClient? client,
    LocalEmergencyStore? localStore,
    FirestoreEmergencyService? firestoreService,
    ConnectivityService? connectivityService,
  }) : _client = client ?? DefaultNearbyClient() {
    _localStore = localStore;
    _firestoreService = firestoreService;
    _connectivityService = connectivityService;
  }

  /// Update dependencies dynamically (e.g. once LocalEmergencyStore / Firebase is ready)
  void configureDependencies({
    LocalEmergencyStore? localStore,
    FirestoreEmergencyService? firestoreService,
    ConnectivityService? connectivityService,
  }) {
    if (localStore != null) _localStore = localStore;
    if (firestoreService != null) _firestoreService = firestoreService;
    if (connectivityService != null) _connectivityService = connectivityService;
  }

  P2pMeshStatus get currentStatus => _status;
  Stream<P2pMeshStatus> get statusStream => _statusController.stream;
  Stream<Emergency> get incomingHelpAlertsStream => _incomingAlertsController.stream;
  Set<String> get seenEmergencyIds => Set.unmodifiable(_seenEmergencyIds);
  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);

  void _updateStatus(P2pMeshStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (!_statusController.isClosed) {
        _statusController.add(newStatus);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Advertising & Discovery
  // ---------------------------------------------------------------------------

  /// Starts advertising presence to nearby peers.
  Future<bool> startAdvertising({String nickname = 'VindaraPeer'}) async {
    final success = await _client.startAdvertising(
      nickname,
      meshStrategy,
      serviceId: defaultServiceId,
      onConnectionInitiated: (endpointId, connectionInfo) async {
        debugPrint('P2P connection initiated from: $endpointId (${connectionInfo.endpointName})');
        // Auto-accept connection on both sides
        await _client.acceptConnection(
          endpointId,
          onPayLoadRecieved: (epId, payload) => _handlePayloadReceived(epId, payload),
        );
      },
      onConnectionResult: (endpointId, status) {
        if (status == Status.CONNECTED) {
          _connectedEndpoints.add(endpointId);
          _updateStatus(P2pMeshStatus.connected);
          _flushActiveBroadcastsToEndpoint(endpointId);
        } else {
          _connectedEndpoints.remove(endpointId);
        }
      },
      onDisconnected: (endpointId) {
        _connectedEndpoints.remove(endpointId);
        if (_connectedEndpoints.isEmpty && _status == P2pMeshStatus.connected) {
          _updateStatus(P2pMeshStatus.advertising);
        }
      },
    );

    if (success) {
      _updateStatus(P2pMeshStatus.advertising);
    }
    return success;
  }

  /// Starts discovering nearby peer devices.
  Future<bool> startDiscovery({String nickname = 'VindaraPeer'}) async {
    final success = await _client.startDiscovery(
      nickname,
      meshStrategy,
      serviceId: defaultServiceId,
      onEndpointFound: (endpointId, endpointName, serviceId) async {
        debugPrint('P2P endpoint found: $endpointId ($endpointName)');
        // Automatically request connection to discovered peer
        await _client.requestConnection(
          nickname,
          endpointId,
          onConnectionInitiated: (epId, connectionInfo) async {
            await _client.acceptConnection(
              epId,
              onPayLoadRecieved: (pEpId, payload) => _handlePayloadReceived(pEpId, payload),
            );
          },
          onConnectionResult: (epId, status) {
            if (status == Status.CONNECTED) {
              _connectedEndpoints.add(epId);
              _updateStatus(P2pMeshStatus.connected);
              _flushActiveBroadcastsToEndpoint(epId);
            } else {
              _connectedEndpoints.remove(epId);
            }
          },
          onDisconnected: (epId) {
            _connectedEndpoints.remove(epId);
            if (_connectedEndpoints.isEmpty && _status == P2pMeshStatus.connected) {
              _updateStatus(P2pMeshStatus.discovering);
            }
          },
        );
      },
      onEndpointLost: (endpointId) {
        if (endpointId != null) {
          _connectedEndpoints.remove(endpointId);
        }
      },
    );

    if (success) {
      _updateStatus(P2pMeshStatus.discovering);
    }
    return success;
  }

  /// Starts full P2P cluster mesh (both advertising and discovering).
  Future<void> startMesh({String nickname = 'VindaraPeer'}) async {
    await startAdvertising(nickname: nickname);
    await startDiscovery(nickname: nickname);
  }

  // ---------------------------------------------------------------------------
  // Broadcast Emergency Alert (Rule #1 & Rule #10)
  // ---------------------------------------------------------------------------

  /// Broadcasts an active HELP emergency alert to all nearby connected peers.
  /// Deduplicates locally, converts to compact byte payload, and dispatches via P2P.
  Future<void> broadcastHelpEmergency(Emergency emergency) async {
    final payload = P2pHelpPayload.fromEmergency(emergency);
    _seenEmergencyIds.add(emergency.id);
    _activeBroadcasts[emergency.id] = payload;

    // Ensure mesh is active
    await startMesh();

    _updateStatus(P2pMeshStatus.broadcasting);

    final bytes = payload.toBytes();
    for (final endpointId in _connectedEndpoints) {
      try {
        await _client.sendBytesPayload(endpointId, bytes);
      } catch (e) {
        debugPrint('Failed to send P2P byte payload to $endpointId: $e');
      }
    }
  }

  void _flushActiveBroadcastsToEndpoint(String endpointId) {
    for (final payload in _activeBroadcasts.values) {
      try {
        _client.sendBytesPayload(endpointId, payload.toBytes());
      } catch (e) {
        debugPrint('Error flushing broadcast to $endpointId: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Payload Handling & Cloud Relay Hook (Rule #4 & Rule #8)
  // ---------------------------------------------------------------------------

  /// Handles incoming byte payloads from nearby peer devices.
  void _handlePayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) {
      return;
    }

    handleIncomingBytes(endpointId, payload.bytes!);
  }

  /// Process incoming byte buffer: deserializes, deduplicates, saves to local store,
  /// surfaces to UI stream, and triggers cloud relay if online.
  Future<void> handleIncomingBytes(String endpointId, Uint8List bytes) async {
    final p2pPayload = P2pHelpPayload.fromBytes(bytes);
    if (p2pPayload == null) return;

    // Rule #7: Deduplication check
    if (_seenEmergencyIds.contains(p2pPayload.emergencyId)) {
      debugPrint('P2P alert ${p2pPayload.emergencyId} already processed. Dropping duplicate.');
      return;
    }

    _seenEmergencyIds.add(p2pPayload.emergencyId);
    final emergency = p2pPayload.toEmergency();

    // 1. Save to local-first Hive store with pending sync status (Rule #8)
    if (_localStore != null) {
      try {
        await _localStore!.saveEmergency(
          emergency,
          syncStatus: SyncStatus.pending,
        );
      } catch (e) {
        debugPrint('Failed to save P2P emergency to LocalEmergencyStore: $e');
      }
    }

    // 2. Surface to UI stream
    if (!_incomingAlertsController.isClosed) {
      _incomingAlertsController.add(emergency);
    }
    _updateStatus(P2pMeshStatus.alertReceived);

    // 3. Cloud Relay Hook: If this receiving device has active internet, sync to Firestore
    final isOnline = _connectivityService?.isCurrentlyOnline ?? false;
    if (isOnline && _firestoreService != null) {
      try {
        final success = await _firestoreService!.upsertEmergency(emergency);
        if (success && _localStore != null) {
          await _localStore!.markAsSynced(emergency.id);
          debugPrint('P2P alert ${emergency.id} successfully relayed to Cloud Firestore!');
        }
      } catch (e) {
        debugPrint('Cloud relay sync attempt failed for ${emergency.id}: $e');
      }
    }

    // 4. Mesh Gossip / Relay: Forward packet to other connected peers (avoiding echo)
    final forwardBytes = p2pPayload.toBytes();
    for (final otherEp in _connectedEndpoints) {
      if (otherEp != endpointId) {
        try {
          await _client.sendBytesPayload(otherEp, forwardBytes);
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle & Cleanup (Rule #6)
  // ---------------------------------------------------------------------------

  /// Stops advertising.
  Future<void> stopAdvertising() async {
    await _client.stopAdvertising();
    if (_status == P2pMeshStatus.advertising) {
      _updateStatus(P2pMeshStatus.idle);
    }
  }

  /// Stops discovery.
  Future<void> stopDiscovery() async {
    await _client.stopDiscovery();
    if (_status == P2pMeshStatus.discovering) {
      _updateStatus(P2pMeshStatus.idle);
    }
  }

  /// Stops all active P2P mesh operations and disconnects endpoints.
  Future<void> stopMesh() async {
    await _client.stopAdvertising();
    await _client.stopDiscovery();
    await _client.stopAllEndpoints();
    _connectedEndpoints.clear();
    _activeBroadcasts.clear();
    _updateStatus(P2pMeshStatus.idle);
  }

  /// Disposes stream controllers and shuts down mesh.
  Future<void> dispose() async {
    await stopMesh();
    await _statusController.close();
    await _incomingAlertsController.close();
  }
}

