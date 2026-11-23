import 'dart:math';
import 'responder.dart';

/// Status lifecycle for an emergency event
enum EmergencyStatus {
  created,
  alerting,
  accepted,
  inProgress,
  resolved,
  cancelled,
}

/// How the incident was triggered (strictly HELP-based, Rule #10)
enum DetectionSource {
  manualSos,
  manualHelp,
  possibleCrash,
}

/// Network connectivity mode at broadcast time
enum CommunicationMode {
  online,
  offlineNearby,
  offline,
}

/// Category of the critical emergency
enum EmergencyType {
  medical,
  roadAccident,
  accident,
  fire,
  personalSafety,
  safety,
  general,
  other,
}

/// Optional apparent severity estimation from multimodal AI background analysis
/// Framed strictly as apparent context estimation, NEVER guaranteed medical diagnosis.
enum EmergencySeverity {
  low,
  moderate,
  high,
  critical,
}

/// Immutable Core Emergency Model for Vindara
class Emergency {
  final String id;
  final String victimName;
  final String? victimId;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String locationLabel;
  final EmergencyType type;
  final DateTime createdAt;
  final DetectionSource detectionSource;
  final EmergencyStatus status;
  final CommunicationMode communicationMode;
  final bool isSyncedToCloud;
  final int version;
  final Responder? primaryResponder;
  final String? primaryResponderId;
  final Responder? standbyResponder;
  final String? standbyResponderId;
  final String? notes;
  final String? victimPhone;

  // Multimodal AI enrichment fields (Rule #1: asynchronous & non-blocking)
  final EmergencySeverity? severity;
  final double? responsivenessScore; // 0.0 (unresponsive) to 1.0 (fully responsive)
  final String? aiContextSummary;    // Apparent situation context estimation
  final List<String> recommendedSkills; // e.g. ['first_aid', 'cpr', 'rescue']

  const Emergency({
    required this.id,
    required this.victimName,
    this.victimId,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters = 5.0,
    required this.locationLabel,
    required this.type,
    required this.createdAt,
    required this.detectionSource,
    required this.status,
    required this.communicationMode,
    this.isSyncedToCloud = false,
    this.version = 1,
    this.primaryResponder,
    this.primaryResponderId,
    this.standbyResponder,
    this.standbyResponderId,
    this.notes,
    this.victimPhone,
    this.severity,
    this.responsivenessScore,
    this.aiContextSummary,
    this.recommendedSkills = const [],
  });

  String get effectiveVictimId => victimId ?? id;
  String? get effectivePrimaryResponderId => primaryResponder?.id ?? primaryResponderId;
  String? get effectiveStandbyResponderId => standbyResponder?.id ?? standbyResponderId;

  String get displayVictimPhone => victimPhone ?? '+91 7999279412';

  /// Generates a collision-resistant emergency ID: EMG-2026-XXXXXXXX (Rule #7)
  static String generateId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(4, (_) => rng.nextInt(256));
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return 'EMG-2026-$hex';
  }

  /// State machine rule: can transition to [nextStatus]
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

      case EmergencyStatus.resolved:
      case EmergencyStatus.cancelled:
        return false;
    }
  }

  Emergency copyWith({
    String? id,
    String? victimName,
    String? victimId,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? locationLabel,
    EmergencyType? type,
    DateTime? createdAt,
    DetectionSource? detectionSource,
    EmergencyStatus? status,
    CommunicationMode? communicationMode,
    bool? isSyncedToCloud,
    int? version,
    Responder? primaryResponder,
    String? primaryResponderId,
    bool clearPrimaryResponderId = false,
    Responder? standbyResponder,
    String? standbyResponderId,
    bool clearStandbyResponderId = false,
    String? notes,
    String? victimPhone,
    EmergencySeverity? severity,
    double? responsivenessScore,
    String? aiContextSummary,
    List<String>? recommendedSkills,
  }) {
    return Emergency(
      id: id ?? this.id,
      victimName: victimName ?? this.victimName,
      victimId: victimId ?? this.victimId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      locationLabel: locationLabel ?? this.locationLabel,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      detectionSource: detectionSource ?? this.detectionSource,
      status: status ?? this.status,
      communicationMode: communicationMode ?? this.communicationMode,
      isSyncedToCloud: isSyncedToCloud ?? this.isSyncedToCloud,
      version: version ?? (this.version + 1),
      primaryResponder: clearPrimaryResponderId
          ? null
          : (primaryResponder ?? this.primaryResponder),
      primaryResponderId: clearPrimaryResponderId
          ? null
          : (primaryResponderId ?? this.primaryResponderId),
      standbyResponder: clearStandbyResponderId
          ? null
          : (standbyResponder ?? this.standbyResponder),
      standbyResponderId: clearStandbyResponderId
          ? null
          : (standbyResponderId ?? this.standbyResponderId),
      notes: notes ?? this.notes,
      victimPhone: victimPhone ?? this.victimPhone,
      severity: severity ?? this.severity,
      responsivenessScore: responsivenessScore ?? this.responsivenessScore,
      aiContextSummary: aiContextSummary ?? this.aiContextSummary,
      recommendedSkills: recommendedSkills ?? this.recommendedSkills,
    );
  }

  /// Formatted GPS coordinates for high-contrast tabular readout
  String get formattedCoordinates =>
      '${latitude.toStringAsFixed(5)}° N, ${longitude.toStringAsFixed(5)}° E';

  /// Human-readable label for emergency type
  String get typeDisplayName {
    switch (type) {
      case EmergencyType.roadAccident:
      case EmergencyType.accident:
        return 'Road Crash / Accident';
      case EmergencyType.medical:
        return 'Medical Emergency';
      case EmergencyType.fire:
        return 'Fire Emergency';
      case EmergencyType.personalSafety:
      case EmergencyType.safety:
        return 'Personal Safety';
      case EmergencyType.general:
      case EmergencyType.other:
        return 'Critical Incident';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'victimId': victimId,
      'victimName': victimName,
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'locationLabel': locationLabel,
      'type': type.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'detectionSource': detectionSource.name,
      'status': status.name,
      'primaryResponderId': primaryResponderId,
      'standbyResponderId': standbyResponderId,
      'communicationMode': communicationMode.name,
      'isSyncedToCloud': isSyncedToCloud,
      'version': version,
      'notes': notes,
      'victimPhone': victimPhone,
      if (severity != null) 'severity': severity!.name,
      if (responsivenessScore != null) 'responsivenessScore': responsivenessScore,
      if (aiContextSummary != null) 'aiContextSummary': aiContextSummary,
      if (recommendedSkills.isNotEmpty) 'recommendedSkills': recommendedSkills,
    };
  }

  factory Emergency.fromJson(Map<String, dynamic> json) {
    EmergencyType parseType(String raw) {
      return EmergencyType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => EmergencyType.other,
      );
    }

    DetectionSource parseSource(String raw) {
      return DetectionSource.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => DetectionSource.manualHelp,
      );
    }

    EmergencyStatus parseStatus(String raw) {
      return EmergencyStatus.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => EmergencyStatus.created,
      );
    }

    CommunicationMode parseMode(String raw) {
      return CommunicationMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => CommunicationMode.online,
      );
    }

    EmergencySeverity? parseSeverity(String? raw) {
      if (raw == null) return null;
      return EmergencySeverity.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => EmergencySeverity.moderate,
      );
    }

    final id = json['id'] as String? ?? Emergency.generateId();
    final vId = json['victimId'] as String? ?? id;
    final vName = json['victimName'] as String? ?? 'Citizen Victim';
    final lat = (json['latitude'] as num?)?.toDouble() ?? 21.1619;
    final lng = (json['longitude'] as num?)?.toDouble() ?? 81.7869;
    final accuracy = (json['accuracyMeters'] as num?)?.toDouble() ?? 5.0;
    final label = json['locationLabel'] as String? ?? 'Incident Location';
    final createdAtStr = json['createdAt'] as String?;
    final createdAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr)?.toUtc() ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();

    return Emergency(
      id: id,
      victimId: vId,
      victimName: vName,
      latitude: lat,
      longitude: lng,
      accuracyMeters: accuracy,
      locationLabel: label,
      type: parseType(json['type'] as String? ?? 'medical'),
      createdAt: createdAt,
      detectionSource: parseSource(json['detectionSource'] as String? ?? 'manualHelp'),
      status: parseStatus(json['status'] as String? ?? 'created'),
      primaryResponderId: json['primaryResponderId'] as String?,
      standbyResponderId: json['standbyResponderId'] as String?,
      communicationMode: parseMode(json['communicationMode'] as String? ?? 'online'),
      isSyncedToCloud: json['isSyncedToCloud'] as bool? ?? false,
      version: (json['version'] as num?)?.toInt() ?? 1,
      notes: json['notes'] as String?,
      victimPhone: json['victimPhone'] as String?,
      severity: parseSeverity(json['severity'] as String?),
      responsivenessScore: (json['responsivenessScore'] as num?)?.toDouble(),
      aiContextSummary: json['aiContextSummary'] as String?,
      recommendedSkills: (json['recommendedSkills'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

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
    return 'Emergency(id: $id, victim: $victimName, type: $type, status: $status, severity: $severity, location: $locationLabel)';
  }
}
