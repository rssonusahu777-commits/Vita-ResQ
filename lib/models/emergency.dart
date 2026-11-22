// lib/models/emergency.dart
//
// SafeReach — Core Emergency Domain Model
// Package: com.example.safereach
//
// Phase 1: Domain model only. No Firebase, no UI, no network calls.
// ID format: EMG-2026-XXXXXXXX  (8 uppercase hex chars, client-generated)

import 'dart:math';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The nature / category of the emergency.
enum EmergencyType {
  /// Medical emergency (cardiac, injury, illness, etc.)
  medical,

  /// Vehicle or workplace accident.
  accident,

  /// Personal safety threat (assault, stalking, etc.)
  safety,

  /// Catch-all for emergencies that don't fit the above.
  general,
}

/// How the emergency was initiated.
enum DetectionSource {
  /// User deliberately pressed the HELP button.
  manualHelp,

  /// Sensor heuristics (accelerometer) suggested a possible crash.
  /// UI must frame this as "Possible Crash" — never as a definitive "Crash".
  possibleCrash,
}

/// Lifecycle state of an emergency.
/// Transitions are enforced by [Emergency.canTransitionTo].
enum EmergencyStatus {
  /// Emergency record created; not yet broadcast to responders.
  created,

  /// Broadcast sent; waiting for a responder to accept.
  alerting,

  /// A primary responder has claimed the emergency (atomic transaction).
  accepted,

  /// Responder has confirmed they are on scene.
  inProgress,

  /// Emergency is over; responder or system marked it resolved.
  resolved,

  /// Cancelled by the victim, responder, or system timeout.
  cancelled,
}

/// Whether this emergency is being coordinated online or offline.
enum CommunicationMode {
  /// Full internet reachability confirmed (not just link-layer).
  online,

  /// No confirmed internet reachability; using local DB + sync queue.
  offline,
}

// ---------------------------------------------------------------------------
// Emergency
// ---------------------------------------------------------------------------

/// Central entity representing a single emergency event.
///
/// Design rules (see docs/ARCHITECTURE.md for full detail):
/// - [id] is always generated client-side via [Emergency.generateId()].
/// - GPS coordinates are independent of any map SDK or tile server.
/// - [status] transitions must be validated with [canTransitionTo] before any DB write.
/// - [version] is an optimistic concurrency counter; increment on every write.
class Emergency {
  /// Unique collision-resistant ID in the format `EMG-2026-XXXXXXXX`.
  final String id;

  /// UID of the person who triggered this emergency.
  final String victimId;

  /// WGS-84 latitude in decimal degrees.
  final double latitude;

  /// WGS-84 longitude in decimal degrees.
  final double longitude;

  /// GPS fix accuracy in metres (lower is better).
  final double accuracyMeters;

  /// Category of the emergency.
  final EmergencyType type;

  /// UTC timestamp when the emergency record was first created on-device.
  final DateTime createdAt;

  /// How this emergency was initiated.
  final DetectionSource detectionSource;

  /// Current lifecycle state.
  final EmergencyStatus status;

  /// UID of the responder who accepted and is handling this emergency.
  /// Null until a responder claims it via an atomic Firestore transaction.
  final String? primaryResponderId;

  /// UID of a backup responder who is on standby.
  final String? standbyResponderId;

  /// Whether this emergency is being tracked online or offline.
  final CommunicationMode communicationMode;

  /// Optimistic concurrency version. Must be incremented on every mutation.
  /// Callers must verify their local version matches remote before writing.
  final int version;

  const Emergency({
    required this.id,
    required this.victimId,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.type,
    required this.createdAt,
    required this.detectionSource,
    required this.status,
    this.primaryResponderId,
    this.standbyResponderId,
    required this.communicationMode,
    this.version = 1,
  });

  // -------------------------------------------------------------------------
  // ID Generation
  // -------------------------------------------------------------------------

  /// Generates a collision-resistant emergency ID in the format
  /// `EMG-2026-XXXXXXXX` where XXXXXXXX is 8 uppercase hexadecimal characters
  /// derived from 4 cryptographically random bytes.
  ///
  /// Uses [Random.secure()] to ensure independence from timestamp or device ID,
  /// making offline-generated IDs safe to merge into Firestore without renaming.
  ///
  /// Example output: `EMG-2026-9F4A2C1B`
  static String generateId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(4, (_) => rng.nextInt(256));
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return 'EMG-2026-$hex';
  }

  // -------------------------------------------------------------------------
  // State Machine
  // -------------------------------------------------------------------------

  /// Returns `true` if transitioning from the current [status] to [nextStatus]
  /// is a valid move in the SafeReach emergency lifecycle state machine.
  ///
  /// Callers MUST check this before writing any status change to the local DB
  /// or Firestore. An invalid transition indicates a bug or a race condition.
  ///
  /// Allowed transitions:
  /// ```
  /// created   → alerting, cancelled
  /// alerting  → accepted, cancelled
  /// accepted  → inProgress, cancelled, alerting
  /// inProgress→ resolved, cancelled
  /// resolved  → (none — terminal)
  /// cancelled → (none — terminal)
  /// ```
  bool canTransitionTo(EmergencyStatus nextStatus) {
    switch (status) {
      case EmergencyStatus.created:
        return nextStatus == EmergencyStatus.alerting ||
            nextStatus == EmergencyStatus.cancelled;

      case EmergencyStatus.alerting:
        return nextStatus == EmergencyStatus.accepted ||
            nextStatus == EmergencyStatus.cancelled;

      case EmergencyStatus.accepted:
        return nextStatus == EmergencyStatus.inProgress ||
            nextStatus == EmergencyStatus.cancelled ||
            nextStatus == EmergencyStatus.alerting;

      case EmergencyStatus.inProgress:
        return nextStatus == EmergencyStatus.resolved ||
            nextStatus == EmergencyStatus.cancelled;

      // Terminal states — no outgoing transitions.
      case EmergencyStatus.resolved:
      case EmergencyStatus.cancelled:
        return false;
    }
  }

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------

  /// Returns a new [Emergency] with the specified fields replaced.
  /// Increments [version] automatically unless a specific version is supplied.
  Emergency copyWith({
    String? id,
    String? victimId,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    EmergencyType? type,
    DateTime? createdAt,
    DetectionSource? detectionSource,
    EmergencyStatus? status,
    String? primaryResponderId,
    bool clearPrimaryResponderId = false,
    String? standbyResponderId,
    bool clearStandbyResponderId = false,
    CommunicationMode? communicationMode,
    int? version,
  }) {
    return Emergency(
      id: id ?? this.id,
      victimId: victimId ?? this.victimId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      detectionSource: detectionSource ?? this.detectionSource,
      status: status ?? this.status,
      primaryResponderId: clearPrimaryResponderId
          ? null
          : (primaryResponderId ?? this.primaryResponderId),
      standbyResponderId: clearStandbyResponderId
          ? null
          : (standbyResponderId ?? this.standbyResponderId),
      communicationMode: communicationMode ?? this.communicationMode,
      version: version ?? (this.version + 1),
    );
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  /// Converts this [Emergency] to a JSON-serialisable [Map].
  /// Suitable for Firestore documents, Hive boxes, and SQLite rows.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'victimId': victimId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'type': type.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'detectionSource': detectionSource.name,
      'status': status.name,
      'primaryResponderId': primaryResponderId,
      'standbyResponderId': standbyResponderId,
      'communicationMode': communicationMode.name,
      'version': version,
    };
  }

  /// Creates an [Emergency] from a JSON map (Firestore document, local DB row,
  /// or decoded HTTP response body).
  ///
  /// Throws [ArgumentError] if any required field is missing or has an
  /// unexpected enum value.
  factory Emergency.fromJson(Map<String, dynamic> json) {
    EmergencyType parseType(String raw) {
      return EmergencyType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () =>
            throw ArgumentError('Unknown EmergencyType value: "$raw"'),
      );
    }

    DetectionSource parseSource(String raw) {
      return DetectionSource.values.firstWhere(
        (e) => e.name == raw,
        orElse: () =>
            throw ArgumentError('Unknown DetectionSource value: "$raw"'),
      );
    }

    EmergencyStatus parseStatus(String raw) {
      return EmergencyStatus.values.firstWhere(
        (e) => e.name == raw,
        orElse: () =>
            throw ArgumentError('Unknown EmergencyStatus value: "$raw"'),
      );
    }

    CommunicationMode parseMode(String raw) {
      return CommunicationMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () =>
            throw ArgumentError('Unknown CommunicationMode value: "$raw"'),
      );
    }

    return Emergency(
      id: json['id'] as String,
      victimId: json['victimId'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num).toDouble(),
      type: parseType(json['type'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      detectionSource: parseSource(json['detectionSource'] as String),
      status: parseStatus(json['status'] as String),
      primaryResponderId: json['primaryResponderId'] as String?,
      standbyResponderId: json['standbyResponderId'] as String?,
      communicationMode: parseMode(json['communicationMode'] as String),
      version: (json['version'] as num).toInt(),
    );
  }

  // -------------------------------------------------------------------------
  // Equality & Debug
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Emergency &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => Object.hash(id, version);

  @override
  String toString() {
    return 'Emergency('
        'id: $id, '
        'victimId: $victimId, '
        'type: ${type.name}, '
        'status: ${status.name}, '
        'detectionSource: ${detectionSource.name}, '
        'communicationMode: ${communicationMode.name}, '
        'version: $version'
        ')';
  }
}

