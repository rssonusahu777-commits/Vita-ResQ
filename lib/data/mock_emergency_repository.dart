import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/emergency.dart';
import '../models/responder.dart';
import '../services/offline_p2p_service.dart';

/// Abstract contract for Emergency data operations.
/// Backend engineers can implement this with Firebase (Firestore, Auth, FCM)
/// without modifying any UI presentation code.
abstract class EmergencyRepository {
  /// Fetch list of currently active emergencies
  Future<List<Emergency>> getActiveEmergencies();

  /// Real-time stream of active emergencies
  Stream<List<Emergency>> watchActiveEmergencies();

  /// Retrieve a specific emergency by ID
  Future<Emergency?> getEmergencyById(String id);

  /// Real-time stream for a single emergency
  Stream<Emergency?> watchEmergency(String id);

  /// Dispatch a new emergency alert
  Future<Emergency> createEmergency({
    required String victimName,
    required double latitude,
    required double longitude,
    required String locationLabel,
    required EmergencyType type,
    required DetectionSource detectionSource,
    required CommunicationMode communicationMode,
    String? notes,
  });

  /// Cancel or dismiss an emergency (e.g., false alarm)
  Future<void> cancelEmergency(String id, {String? reason});

  /// Accept an emergency as the primary on-scene responder
  Future<void> acceptAsPrimary(String emergencyId, Responder responder);

  /// Accept an emergency in a secondary standby / backup capacity
  Future<void> acceptAsStandby(String emergencyId, Responder responder);

  /// Transition lifecycle status (e.g. alerting -> accepted -> inProgress -> resolved)
  Future<void> advanceEmergencyStatus(String emergencyId, EmergencyStatus nextStatus);

  /// Update an emergency directly (useful for testing state transitions)
  Future<void> updateEmergency(Emergency emergency);

  /// Toggle communication mode for testing (online vs offlineNearby)
  Future<void> toggleEmergencyCommunicationMode(String emergencyId);

  /// Toggle cloud sync state for testing
  Future<void> toggleEmergencyCloudSync(String emergencyId);

  /// Assign mock responders for testing failover and assignment slots
  Future<void> assignMockPrimaryResponder(String emergencyId);
  Future<void> assignMockStandbyResponder(String emergencyId);
  Future<void> clearEmergencyResponders(String emergencyId);

  /// Get the current authenticated user's responder profile
  Future<Responder> getCurrentUserResponder();

  /// Stream updates for current user responder profile
  Stream<Responder> watchCurrentUserResponder();

  /// Update current user's profile information
  Future<void> updateCurrentUserProfile({
    String? name,
    String? phoneNumber,
    String? bloodGroup,
    String? badgeLevel,
    String? emergencyNotes,
    String? knownAllergies,
  });

  /// Toggle current responder's availability to receive nearby broadcasts
  Future<void> updateCurrentUserAvailability(bool isAvailable);

  /// Release resources
  void dispose();
}

/// In-memory mock repository populated with realistic Indian emergency scenarios.
class MockEmergencyRepository implements EmergencyRepository {
  final List<Emergency> _emergencies = [];
  List<Emergency> get emergenciesSync => List<Emergency>.unmodifiable(_emergencies);
  late final StreamController<List<Emergency>> _emergenciesController;
  late final StreamController<Responder> _responderController;

  Responder _currentUserResponder = const Responder(
    id: 'RSP-IND-4091',
    name: 'Citizen Volunteer',
    distanceMeters: 0,
    etaMinutes: 0,
    isVerified: false,
    points: 0,
    badgeLevel: 'Citizen Volunteer',
    completedResponses: 0,
    isAvailable: true,
    phoneNumber: '',
  );

  MockEmergencyRepository() {
    _emergenciesController = StreamController<List<Emergency>>.broadcast();
    _responderController = StreamController<Responder>.broadcast();
    _seedInitialData();
    OfflineP2pService.instance.incomingHelpAlertsStream.listen((p2pEmergency) {
      final index = _emergencies.indexWhere((e) => e.id == p2pEmergency.id);
      if (index == -1) {
        _emergencies.insert(0, p2pEmergency);
        _emitEmergencies();
      }
    });
  }

  void _seedInitialData() {
    _emergencies.addAll([
      Emergency(
        id: 'EMG-2026-781920',
        victimName: 'Karan',
        victimPhone: '+91 7999279412',
        latitude: 21.1619,
        longitude: 81.7869,
        locationLabel: 'Sector 4, Community Axis, Raipur',
        type: EmergencyType.medical,
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        detectionSource: DetectionSource.manualHelp,
        status: EmergencyStatus.alerting,
        communicationMode: CommunicationMode.online,
        isSyncedToCloud: true,
        primaryResponder: null,
        standbyResponder: null,
        notes: 'Severe acute breathing distress reported outside pharma store.',
      ),
      Emergency(
        id: 'EMG-2026-849201',
        victimName: 'Rahul Sharma',
        victimPhone: '+91 98201 11223',
        latitude: 21.1712,
        longitude: 81.7920,
        locationLabel: 'Ring Road Bypass, Raipur',
        type: EmergencyType.roadAccident,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        detectionSource: DetectionSource.possibleCrash,
        status: EmergencyStatus.accepted,
        communicationMode: CommunicationMode.online,
        isSyncedToCloud: true,
        primaryResponder: const Responder(
          id: 'RSP-IND-1002',
          name: 'Dr. Rajesh Sharma',
          distanceMeters: 450,
          etaMinutes: 3,
          isVerified: true,
          points: 2850,
          badgeLevel: 'Diamond Medic',
          completedResponses: 62,
          isAvailable: true,
          phoneNumber: '+91 98765 12345',
        ),
        standbyResponder: null,
        notes: 'Vehicular deceleration spike detected by sensor. Vehicle stationary.',
      ),
      Emergency(
        id: 'EMG-2026-194827',
        victimName: 'Pooja Deshmukh',
        victimPhone: '+91 98111 22334',
        latitude: 21.1580,
        longitude: 81.7750,
        locationLabel: 'Station Road Market, Raipur',
        type: EmergencyType.personalSafety,
        createdAt: DateTime.now().subtract(const Duration(minutes: 11)),
        detectionSource: DetectionSource.manualHelp,
        status: EmergencyStatus.alerting,
        communicationMode: CommunicationMode.offlineNearby,
        isSyncedToCloud: false,
        primaryResponder: null,
        standbyResponder: null,
        notes: 'Broadcasted via Local BLE / Wi-Fi Direct Mesh (Offline mode).',
      ),
    ]);

    _emitEmergencies();
  }

  void _emitEmergencies() {
    if (!_emergenciesController.isClosed) {
      _emergenciesController.add(List<Emergency>.unmodifiable(_emergencies));
    }
  }

  @override
  Future<List<Emergency>> getActiveEmergencies() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return List<Emergency>.unmodifiable(_emergencies);
  }

  @override
  Stream<List<Emergency>> watchActiveEmergencies() async* {
    yield List<Emergency>.unmodifiable(_emergencies);
    yield* _emergenciesController.stream;
  }

  @override
  Future<Emergency?> getEmergencyById(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      return _emergencies.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Emergency?> watchEmergency(String id) async* {
    try {
      yield _emergencies.firstWhere((e) => e.id == id);
    } catch (_) {
      yield null;
    }
    yield* _emergenciesController.stream.map((list) {
      try {
        return list.firstWhere((e) => e.id == id);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<Emergency> createEmergency({
    required String victimName,
    required double latitude,
    required double longitude,
    required String locationLabel,
    required EmergencyType type,
    required DetectionSource detectionSource,
    required CommunicationMode communicationMode,
    String? notes,
  }) async {
    final newId = 'EMG-2026-${(DateTime.now().millisecondsSinceEpoch % 900000 + 100000)}';
    final emergency = Emergency(
      id: newId,
      victimName: victimName,
      latitude: latitude,
      longitude: longitude,
      locationLabel: locationLabel,
      type: type,
      createdAt: DateTime.now(),
      detectionSource: detectionSource,
      status: EmergencyStatus.alerting,
      communicationMode: communicationMode,
      isSyncedToCloud: communicationMode == CommunicationMode.online,
      notes: notes,
    );

    _emergencies.insert(0, emergency);
    _emitEmergencies();

    // Broadcast over Offline Nearby P2P Mesh (cluster)
    try {
      OfflineP2pService.instance.broadcastHelpEmergency(emergency);
    } catch (e) {
      debugPrint('MockEmergencyRepo P2P broadcast warning: $e');
    }

    return emergency;
  }

  @override
  Future<void> cancelEmergency(String id, {String? reason}) async {
    final index = _emergencies.indexWhere((e) => e.id == id);
    if (index != -1) {
      _emergencies[index] = _emergencies[index].copyWith(
        status: EmergencyStatus.cancelled,
        notes: reason != null ? '${_emergencies[index].notes ?? ""}\nCancelled: $reason' : null,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<void> acceptAsPrimary(String emergencyId, Responder responder) async {
    final index = _emergencies.indexWhere((e) => e.id == emergencyId);
    if (index != -1) {
      _emergencies[index] = _emergencies[index].copyWith(
        status: EmergencyStatus.accepted,
        primaryResponder: responder,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<void> acceptAsStandby(String emergencyId, Responder responder) async {
    final index = _emergencies.indexWhere((e) => e.id == emergencyId);
    if (index != -1) {
      _emergencies[index] = _emergencies[index].copyWith(
        standbyResponder: responder,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<void> advanceEmergencyStatus(String emergencyId, EmergencyStatus nextStatus) async {
    final index = _emergencies.indexWhere((e) => e.id == emergencyId);
    if (index != -1) {
      _emergencies[index] = _emergencies[index].copyWith(
        status: nextStatus,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<void> updateEmergency(Emergency emergency) async {
    final index = _emergencies.indexWhere((e) => e.id == emergency.id);
    if (index != -1) {
      _emergencies[index] = emergency;
      _emitEmergencies();
    }
  }

  @override
  Future<void> toggleEmergencyCommunicationMode(String emergencyId) async {
    final index = _emergencies.indexWhere((e) => e.id == emergencyId);
    if (index != -1) {
      final currentMode = _emergencies[index].communicationMode;
      final newMode = currentMode == CommunicationMode.online
          ? CommunicationMode.offlineNearby
          : CommunicationMode.online;
      _emergencies[index] = _emergencies[index].copyWith(
        communicationMode: newMode,
        isSyncedToCloud: newMode == CommunicationMode.online,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<void> toggleEmergencyCloudSync(String emergencyId) async {
    final index = _emergencies.indexWhere((e) => e.id == emergencyId);
    if (index != -1) {
      final currentSync = _emergencies[index].isSyncedToCloud;
      _emergencies[index] = _emergencies[index].copyWith(
        isSyncedToCloud: !currentSync,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<void> assignMockPrimaryResponder(String emergencyId) async {
    final index = _emergencies.indexWhere((e) => e.id == emergencyId);
    if (index != -1) {
      const mockPrimary = Responder(
        id: 'RSP-IND-1002',
        name: 'Dr. Rajesh Sharma',
        distanceMeters: 450,
        etaMinutes: 3,
        isVerified: true,
        points: 2850,
        badgeLevel: 'Diamond Medic',
        completedResponses: 62,
        isAvailable: true,
        phoneNumber: '+91 98765 12345',
      );
      _emergencies[index] = _emergencies[index].copyWith(
        primaryResponder: mockPrimary,
        status: _emergencies[index].status == EmergencyStatus.alerting
            ? EmergencyStatus.accepted
            : _emergencies[index].status,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<void> assignMockStandbyResponder(String emergencyId) async {
    final index = _emergencies.indexWhere((e) => e.id == emergencyId);
    if (index != -1) {
      const mockStandby = Responder(
        id: 'RSP-IND-2034',
        name: 'Priya Verma (Nurse)',
        distanceMeters: 620,
        etaMinutes: 5,
        isVerified: true,
        points: 1980,
        badgeLevel: 'Silver Samaritan',
        completedResponses: 41,
        isAvailable: true,
        phoneNumber: '+91 98111 54321',
      );
      _emergencies[index] = _emergencies[index].copyWith(
        standbyResponder: mockStandby,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<void> clearEmergencyResponders(String emergencyId) async {
    final index = _emergencies.indexWhere((e) => e.id == emergencyId);
    if (index != -1) {
      _emergencies[index] = Emergency(
        id: _emergencies[index].id,
        victimName: _emergencies[index].victimName,
        latitude: _emergencies[index].latitude,
        longitude: _emergencies[index].longitude,
        locationLabel: _emergencies[index].locationLabel,
        type: _emergencies[index].type,
        createdAt: _emergencies[index].createdAt,
        detectionSource: _emergencies[index].detectionSource,
        status: _emergencies[index].status,
        communicationMode: _emergencies[index].communicationMode,
        isSyncedToCloud: _emergencies[index].isSyncedToCloud,
        primaryResponder: null,
        standbyResponder: null,
        notes: _emergencies[index].notes,
      );
      _emitEmergencies();
    }
  }

  @override
  Future<Responder> getCurrentUserResponder() async {
    return _currentUserResponder;
  }

  @override
  Stream<Responder> watchCurrentUserResponder() async* {
    // Send immediate current state followed by subsequent updates
    yield _currentUserResponder;
    yield* _responderController.stream;
  }

  @override
  Future<void> updateCurrentUserProfile({
    String? name,
    String? phoneNumber,
    String? bloodGroup,
    String? badgeLevel,
    String? emergencyNotes,
    String? knownAllergies,
  }) async {
    _currentUserResponder = _currentUserResponder.copyWith(
      name: name,
      phoneNumber: phoneNumber,
      bloodGroup: bloodGroup,
      badgeLevel: badgeLevel,
      emergencyNotes: emergencyNotes,
      knownAllergies: knownAllergies,
    );
    if (!_responderController.isClosed) {
      _responderController.add(_currentUserResponder);
    }
  }

  @override
  Future<void> updateCurrentUserAvailability(bool isAvailable) async {
    _currentUserResponder = _currentUserResponder.copyWith(isAvailable: isAvailable);
    if (!_responderController.isClosed) {
      _responderController.add(_currentUserResponder);
    }
  }

  @override
  void dispose() {
    _emergenciesController.close();
    _responderController.close();
  }
}
