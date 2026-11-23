import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants/app_constants.dart';
import '../models/emergency_model.dart';
import '../models/responder_model.dart';

class ResponderReliabilityMonitor {
  final FirebaseFirestore? _firestore;
  final int noProgressThresholdSeconds;
  final int locationStaleThresholdSeconds;
  final int connectionGracePeriodSeconds;
  final int primaryMonitorIntervalSeconds;

  Timer? _monitorTimer;
  String? _monitoredEmergencyId;
  double? _lastRecordedDistance;
  DateTime? _lastProgressTimestamp;

  ResponderReliabilityMonitor({
    FirebaseFirestore? firestore,
    this.noProgressThresholdSeconds = AppConstants.noProgressThresholdSeconds,
    this.locationStaleThresholdSeconds = AppConstants.locationStaleThresholdSeconds,
    this.connectionGracePeriodSeconds = AppConstants.connectionGracePeriodSeconds,
    this.primaryMonitorIntervalSeconds = AppConstants.primaryMonitorIntervalSeconds,
  }) : _firestore = firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Computes a priority score for a standby candidate based on role weight and distance:
  /// - Role weight: DOCTOR = +40.0, AMBULANCE_DRIVER = +35.0, POLICE_PCR = +30.0, CITIZEN/default = +10.0.
  /// - Proximity weight: linear decay from +50.0 at 0m to 0.0 at 5000m.
  /// Total score = role weight + proximity weight.
  static double scoreStandbyCandidate({
    required String? userRole,
    required double distanceMeters,
  }) {
    final double roleWeight;
    switch (userRole?.toUpperCase()) {
      case 'DOCTOR':
        roleWeight = 40.0;
        break;
      case 'AMBULANCE_DRIVER':
        roleWeight = 35.0;
        break;
      case 'POLICE_PCR':
        roleWeight = 30.0;
        break;
      case 'CITIZEN':
      default:
        roleWeight = 10.0;
        break;
    }

    final double clampedDistance = distanceMeters.clamp(0.0, 5000.0);
    final double proximityWeight = 50.0 * (1.0 - (clampedDistance / 5000.0));

    return roleWeight + proximityWeight;
  }

  /// Start monitoring reliability for an active emergency session
  void startMonitoring(String emergencyId) {
    _monitoredEmergencyId = emergencyId;
    _lastProgressTimestamp = DateTime.now();
    _lastRecordedDistance = null;

    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      Duration(seconds: primaryMonitorIntervalSeconds),
      (_) => _evaluatePrimaryReliability(),
    );
  }

  /// Stop reliability monitor
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitoredEmergencyId = null;
  }

  Future<void> _evaluatePrimaryReliability() async {
    if (_monitoredEmergencyId == null) return;

    DocumentSnapshot snap = await _db
        .collection(AppConstants.emergenciesCollection)
        .doc(_monitoredEmergencyId)
        .get();

    if (!snap.exists) return;
    var emergency = EmergencyModel.fromMap(snap.data() as Map<String, dynamic>, snap.id);

    // Only monitor active emergencies with assigned Primary Helper
    if (emergency.status == EmergencyStatus.COMPLETED ||
        emergency.status == EmergencyStatus.CANCELLED ||
        emergency.helperId == null) {
      return;
    }

    ResponderModel? primary = emergency.primaryResponder;
    if (primary == null) return;

    DateTime now = DateTime.now();

    // 1. Separate heartbeat staleness from physical movement
    int secondsSinceLastUpdate = now.difference(primary.lastLocationUpdate).inSeconds;
    bool isHeartbeatStale = secondsSinceLastUpdate > locationStaleThresholdSeconds;
    bool isSustainedDead = secondsSinceLastUpdate > (locationStaleThresholdSeconds + connectionGracePeriodSeconds);

    // 2. Check Progress toward Victim (evaluates actual movement towards victim coordinates)
    double currentDistance = _calculateDistance(
      primary.latitude,
      primary.longitude,
      emergency.latitude,
      emergency.longitude,
    );

    if (_lastRecordedDistance == null || currentDistance < (_lastRecordedDistance! - 5.0)) {
      _lastRecordedDistance = currentDistance;
      _lastProgressTimestamp = now;
    }

    int secondsWithoutProgress = _lastProgressTimestamp != null
        ? now.difference(_lastProgressTimestamp!).inSeconds
        : 0;

    // A responder is considered stalled if no progress has been made for >= noProgressThresholdSeconds (120s)
    bool isNoProgress = secondsWithoutProgress > noProgressThresholdSeconds;

    // 3. Mark AT_RISK if heartbeat is stale or stalled, but do NOT demote solely for stationary pause
    if (isHeartbeatStale || isNoProgress) {
      if (primary.status != ResponderStatus.AT_RISK) {
        await _markPrimaryAtRisk(_monitoredEmergencyId!, primary.userId);
      }
    }

    // 4. Only initiate automatic handover / demotion if sustained dead or stalled without progress
    if (isSustainedDead || isNoProgress) {
      await promoteStandbyToPrimary(_monitoredEmergencyId!);
    }
  }

  /// Mark current Primary as AT_RISK
  Future<void> _markPrimaryAtRisk(String emergencyId, String primaryUserId) async {
    DocumentReference emergencyRef = _db
        .collection(AppConstants.emergenciesCollection)
        .doc(emergencyId);

    await _db.runTransaction((transaction) async {
      DocumentSnapshot snap = await transaction.get(emergencyRef);
      if (!snap.exists) return;

      var data = snap.data() as Map<String, dynamic>;
      Map<String, dynamic> responders =
          data['responders'] != null ? Map<String, dynamic>.from(data['responders']) : {};

      if (responders.containsKey(primaryUserId)) {
        var pData = Map<String, dynamic>.from(responders[primaryUserId]);
        pData['status'] = ResponderStatus.AT_RISK.name;
        responders[primaryUserId] = pData;

        transaction.update(emergencyRef, {
          'responders': responders,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Promote nearest suitable Standby responder to Primary
  Future<bool> promoteStandbyToPrimary(String emergencyId) async {
    DocumentReference emergencyRef = _db
        .collection(AppConstants.emergenciesCollection)
        .doc(emergencyId);

    bool promoted = false;

    try {
      await _db.runTransaction((transaction) async {
        DocumentSnapshot snap = await transaction.get(emergencyRef);
        if (!snap.exists) return;

        var data = snap.data() as Map<String, dynamic>;
        var emergency = EmergencyModel.fromMap(data, snap.id);

        String? oldPrimaryId = emergency.helperId;

        // Idempotency check: if another client or process already promoted, exit cleanly
        if (emergency.status != EmergencyStatus.ASSIGNED && emergency.status != EmergencyStatus.APPROACHING) {
          return;
        }

        Map<String, dynamic> responders = Map<String, dynamic>.from(data['responders'] ?? {});
        List<ResponderModel> standbyList = emergency.standbyResponders;

        if (standbyList.isEmpty) {
          // No standby responder available -> Demote old primary to STANDBY / AT_RISK and reset emergency to SEARCHING
          if (oldPrimaryId != null && responders.containsKey(oldPrimaryId)) {
            var oldData = Map<String, dynamic>.from(responders[oldPrimaryId]);
            oldData['role'] = ResponderRole.STANDBY.name;
            oldData['status'] = ResponderStatus.AT_RISK.name;
            responders[oldPrimaryId] = oldData;
          }

          transaction.update(emergencyRef, {
            'helperId': '',
            'status': AppConstants.statusSearching,
            'responders': responders,
            'lastHelperLocation': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }

        // Rank standby candidates by role-weighted priority score descending,
        // with deterministic userId ascending tie-breaking.
        standbyList.sort((a, b) {
          final double distA = (a.hasValidCoordinates && ResponderModel.isValidCoordinate(emergency.latitude, emergency.longitude))
              ? Geolocator.distanceBetween(a.latitude, a.longitude, emergency.latitude, emergency.longitude)
              : 5000.0;
          final double distB = (b.hasValidCoordinates && ResponderModel.isValidCoordinate(emergency.latitude, emergency.longitude))
              ? Geolocator.distanceBetween(b.latitude, b.longitude, emergency.latitude, emergency.longitude)
              : 5000.0;

          final double scoreA = scoreStandbyCandidate(userRole: a.userRole, distanceMeters: distA);
          final double scoreB = scoreStandbyCandidate(userRole: b.userRole, distanceMeters: distB);

          // Higher score wins (descending)
          final scoreCmp = scoreB.compareTo(scoreA);
          if (scoreCmp != 0) return scoreCmp;

          // Deterministic tie-breaker: userId ascending
          return a.userId.compareTo(b.userId);
        });

        ResponderModel bestCandidate = standbyList.first;

        // Demote old Primary to STANDBY
        if (oldPrimaryId != null && responders.containsKey(oldPrimaryId)) {
          var oldData = Map<String, dynamic>.from(responders[oldPrimaryId]);
          oldData['role'] = ResponderRole.STANDBY.name;
          oldData['status'] = ResponderStatus.REPLACED.name;
          responders[oldPrimaryId] = oldData;
        }

        // Promote candidate to PRIMARY
        var candidateData = Map<String, dynamic>.from(responders[bestCandidate.userId]);
        candidateData['role'] = ResponderRole.PRIMARY.name;
        candidateData['status'] = ResponderStatus.RESPONDING.name;
        candidateData['assignedAt'] = Timestamp.now();
        responders[bestCandidate.userId] = candidateData;

        transaction.update(emergencyRef, {
          'helperId': bestCandidate.userId,
          'status': AppConstants.statusAssigned,
          'responders': responders,
          'lastHelperLocation': {
            'latitude': bestCandidate.latitude,
            'longitude': bestCandidate.longitude,
            'hasAcquiredLocation': bestCandidate.hasAcquiredLocation,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });

        promoted = true;
      });

      return promoted;
    } catch (e) {
      return false;
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    if (!ResponderModel.isValidCoordinate(lat1, lon1) ||
        !ResponderModel.isValidCoordinate(lat2, lon2)) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }
}
