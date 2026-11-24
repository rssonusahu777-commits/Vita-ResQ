import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'connectivity_service.dart';
import 'communication_service_interface.dart';
import 'online_communication_service.dart';
import 'offline_communication_service.dart';
import 'local_database_service.dart';
import 'p2p_diagnostics.dart';
import '../models/communication_mode.dart';
import '../models/emergency_model.dart';
import '../core/constants/app_constants.dart';
import 'analytics_service.dart';
import 'auth_service.dart';

class CommunicationManager {
  static final CommunicationManager _instance = CommunicationManager._internal();
  factory CommunicationManager() => _instance;
  CommunicationManager._internal();

  final ConnectivityService _connectivityService = ConnectivityService();
  final OnlineCommunicationService _onlineService = OnlineCommunicationService();
  final OfflineCommunicationService _offlineService = OfflineCommunicationService();
  final LocalDatabaseService _localDb = LocalDatabaseService();

  ICommunicationService? _activeService;
  CommunicationMode _activeMode = CommunicationMode.offline;
  StreamSubscription<CommunicationMode>? _modeSub;
  bool _isTransitioning = false;

  bool get _shouldForceOffline {
    if (!AuthService.isGuestOfflineSessionSync) return false;
    try {
      return FirebaseAuth.instance.currentUser == null;
    } catch (_) {
      return true;
    }
  }

  CommunicationMode get activeMode =>
      _shouldForceOffline ? CommunicationMode.offline : _activeMode;
  Stream<CommunicationMode> get modeStream => _connectivityService.modeStream;

  void initialize() {
    _connectivityService.initialize();
    _activeMode = _shouldForceOffline ? CommunicationMode.offline : _connectivityService.currentMode;
    _updateActiveService(_activeMode);

    _modeSub?.cancel();
    _modeSub = _connectivityService.modeStream.listen((newMode) {
      if (_shouldForceOffline) {
        if (_activeMode != CommunicationMode.offline) {
          _updateActiveService(CommunicationMode.offline);
        }
        return;
      }
      if (newMode != _activeMode) {
        _handleModeTransition(_activeMode, newMode);
      }
    });
  }

  void _updateActiveService(CommunicationMode mode) {
    _activeMode = mode;
    if (mode == CommunicationMode.online) {
      _activeService = _onlineService;
    } else {
      _activeService = _offlineService;
    }
  }

  Future<void> _handleModeTransition(
      CommunicationMode oldMode, CommunicationMode newMode) async {
    if (_shouldForceOffline) {
      _updateActiveService(CommunicationMode.offline);
      return;
    }
    if (_isTransitioning) return;
    _isTransitioning = true;

    try {
      // 1. Stop current active transport cleanly
      if (oldMode == CommunicationMode.online) {
        await _onlineService.stop();
      } else {
        await _offlineService.stop();
      }

      // 2. Switch mode
      _updateActiveService(newMode);

      // 3. If transitioning OFFLINE -> ONLINE, safely sync unsynchronized offline emergencies to Firestore
      if (oldMode == CommunicationMode.offline &&
          newMode == CommunicationMode.online) {
        await syncOfflineEmergencyToFirestore();
      }
    } finally {
      _isTransitioning = false;
    }
  }

  Future<String> broadcastSOS({
    required Position position,
    required String currentUserId,
  }) async {
    if (_shouldForceOffline) {
      _updateActiveService(CommunicationMode.offline);
      return await _offlineService.broadcastSOS(
        position: position,
        currentUserId: currentUserId,
      );
    }
    return await _activeService!
        .broadcastSOS(position: position, currentUserId: currentUserId);
  }

  Stream<List<EmergencyModel>> listenForAlerts({
    required double userLat,
    required double userLon,
    required String currentUserId,
  }) {
    if (_shouldForceOffline) {
      _updateActiveService(CommunicationMode.offline);
      return _offlineService.listenForAlerts(
        userLat: userLat,
        userLon: userLon,
        currentUserId: currentUserId,
      );
    }
    if (_activeService == null) {
      _activeMode = _connectivityService.currentMode;
      _updateActiveService(_activeMode);
    }

    if (_activeMode == CommunicationMode.online) {
      final bool canRelay = currentUserId.isNotEmpty &&
          currentUserId != 'offline_user' &&
          !currentUserId.startsWith('offline_guest') &&
          !AuthService.isGuestOfflineSessionSync;

      late StreamController<List<EmergencyModel>> relayStreamController;
      StreamSubscription<List<EmergencyModel>>? onlineAlertsSub;

      relayStreamController = StreamController<List<EmergencyModel>>.broadcast(
        onListen: () {
          if (canRelay) {
            _offlineService.startPassiveRelayDiscovery(currentUserId: currentUserId);
          }
          onlineAlertsSub = _onlineService
              .listenForAlerts(
                userLat: userLat,
                userLon: userLon,
                currentUserId: currentUserId,
              )
              .listen(
                (emergencies) {
                  if (!relayStreamController.isClosed) {
                    relayStreamController.add(emergencies);
                  }
                },
                onError: (err) {
                  if (!relayStreamController.isClosed) {
                    relayStreamController.addError(err);
                  }
                },
              );
        },
        onCancel: () {
          onlineAlertsSub?.cancel();
          if (canRelay) {
            _offlineService.stopPassiveRelayDiscovery();
          }
        },
      );

      return relayStreamController.stream;
    }

    return (_activeService ?? _onlineService).listenForAlerts(
        userLat: userLat, userLon: userLon, currentUserId: currentUserId);
  }

  /// Starts passive Nearby Connections discovery strictly to bridge incoming JS-OFF- alerts to Firestore.
  Future<void> startPassiveRelayDiscovery({required String currentUserId}) async {
    await _offlineService.startPassiveRelayDiscovery(currentUserId: currentUserId);
  }

  /// Stops passive Nearby Connections discovery.
  Future<void> stopPassiveRelayDiscovery() async {
    await _offlineService.stopPassiveRelayDiscovery();
  }

  /// Safely upload unsynchronized offline emergency records to Firestore
  Future<void> syncOfflineEmergencyToFirestore() async {
    // In unauthenticated guest offline mode, strictly skip Firestore sync
    if (_shouldForceOffline) {
      return;
    }
    List<EmergencyModel> unsynced = await _localDb.getUnsyncedEmergencies();
    final authUser = FirebaseAuth.instance.currentUser;

    for (var emergency in unsynced) {
      final syncStart = DateTime.now();
      try {
        // Case 1: Unauthenticated emergency or client not signed in
        if (authUser == null) {
          await _localDb.recordSyncFailure(
            emergency.id,
            'Unauthenticated: Sign-in required before offline emergency can be synced to Cloud Firestore',
          );
          unawaited(AnalyticsService.instance.trackOfflineSyncTelemetry(
            emergencyId: emergency.id,
            retryCount: 1,
            syncLatencyMs: DateTime.now().difference(syncStart).inMilliseconds,
            success: false,
            terminalStatus: emergency.isTerminal ? emergency.status.name : null,
            errorCategory: 'unauthenticated',
          ));
          continue;
        }

        if (emergency.victimId == 'offline_user' || emergency.victimId != authUser.uid) {
          await _localDb.recordSyncFailure(
            emergency.id,
            'Identity mismatch: Cannot sync emergency created with victimId=${emergency.victimId} under authenticated user ${authUser.uid} without backend adoption rule',
          );
          unawaited(AnalyticsService.instance.trackOfflineSyncTelemetry(
            emergencyId: emergency.id,
            retryCount: 1,
            syncLatencyMs: DateTime.now().difference(syncStart).inMilliseconds,
            success: false,
            terminalStatus: emergency.isTerminal ? emergency.status.name : null,
            errorCategory: 'identity_mismatch',
          ));
          continue;
        }

        // Case 2: Non-terminal, in-progress offline states (ASSIGNED / APPROACHING / ARRIVED)
        // Cannot be safely created directly under client rules without an intermediate SEARCHING,
        // which would reset responder state and trigger false alerts to online responders.
        // Retain local record and record an explicit sync status.
        if (emergency.status == EmergencyStatus.ASSIGNED ||
            emergency.status == EmergencyStatus.APPROACHING ||
            emergency.status == EmergencyStatus.ARRIVED) {
          await _localDb.recordSyncFailure(
            emergency.id,
            'Pending secure import: Offline emergency in ${emergency.status.name} state requires active responder reconciliation or terminal resolution before cloud synchronization.',
          );
          unawaited(AnalyticsService.instance.trackOfflineSyncTelemetry(
            emergencyId: emergency.id,
            retryCount: 1,
            syncLatencyMs: DateTime.now().difference(syncStart).inMilliseconds,
            success: false,
            terminalStatus: emergency.isTerminal ? emergency.status.name : null,
            errorCategory: 'pending_reconciliation',
          ));
          continue;
        }

        // Case 3: Authenticated victim emergency synchronization (SEARCHING or Terminal COMPLETED/CANCELLED)
        // Check for stale offline emergency: if older than 10 minutes (600s) and still SEARCHING,
        // do NOT upload it as active SEARCHING to Cloud Firestore. Mark it synced locally to preserve
        // it in local history and log a structured diagnostic entry.
        final ageSeconds = DateTime.now().difference(emergency.createdAt).inSeconds.abs();
        if (!emergency.isTerminal && emergency.status == EmergencyStatus.SEARCHING && ageSeconds > 600) {
          await _localDb.markAsSynced(emergency.id);
          P2PDiagnostics.log(emergency.id, 'SYNC_SKIPPED_STALE_OFFLINE_ALERT', {
            'ageSeconds': ageSeconds,
            'status': emergency.status.name,
          });
          unawaited(AnalyticsService.instance.trackOfflineSyncTelemetry(
            emergencyId: emergency.id,
            retryCount: 0,
            syncLatencyMs: DateTime.now().difference(syncStart).inMilliseconds,
            success: true,
            terminalStatus: 'STALE_SKIPPED',
          ));
          continue;
        }

        final docRef = FirebaseFirestore.instance
            .collection(AppConstants.emergenciesCollection)
            .doc(emergency.id);

        final docSnap = await docRef.get();

        if (!docSnap.exists) {
          // Document does not exist in Firestore.
          // Single-write creation:
          // Completed or cancelled emergencies are created directly in their terminal state
          // under the narrow firestore.rules exception for JS-OFF-* offline emergencies.
          // Active emergencies are created directly as SEARCHING (if fresh <= 10 min).
          // In NO CASE is an intermediate SEARCHING document created for an already terminal emergency.
          Map<String, dynamic> createMap = {
            'id': emergency.id,
            'victimId': authUser.uid,
            'type': emergency.type,
            'latitude': emergency.latitude,
            'longitude': emergency.longitude,
            'status': emergency.status.name,
            'currentRadiusMeters': emergency.currentRadiusMeters,
            'notifiedUserIds': emergency.notifiedUserIds,
            'responders': emergency.responders.map((k, v) => MapEntry(k, v.toMap())),
            'createdAt': emergency.createdAt.toIso8601String(),
            'updatedAt': emergency.updatedAt.toIso8601String(),
            if (emergency.originDeviceId != null) 'originDeviceId': emergency.originDeviceId,
            if (emergency.helperId != null) 'helperId': emergency.helperId,
            if (emergency.lastVictimLocation != null) 'lastVictimLocation': emergency.lastVictimLocation,
            if (emergency.lastHelperLocation != null) 'lastHelperLocation': emergency.lastHelperLocation,
          };

          await docRef.set(createMap);
        } else {
          // Document already exists in Firestore from previous sync or partial dispatch.
          final remoteData = docSnap.data();
          final remoteStatusStr = remoteData?['status'] as String?;

          // If remote is already terminal (COMPLETED/CANCELLED), do not regress or overwrite back to SEARCHING or any prior state
          if (remoteStatusStr == AppConstants.statusCompleted ||
              remoteStatusStr == AppConstants.statusCancelled) {
            await _localDb.markAsSynced(emergency.id);
            unawaited(AnalyticsService.instance.trackOfflineSyncTelemetry(
              emergencyId: emergency.id,
              retryCount: 0,
              syncLatencyMs: DateTime.now().difference(syncStart).inMilliseconds,
              success: true,
              terminalStatus: emergency.isTerminal ? emergency.status.name : null,
            ));
            continue;
          }

          // If local emergency is terminal, update remote to terminal state
          if (emergency.isTerminal) {
            Map<String, dynamic> updateMap = {
              'status': emergency.status.name,
              'helperId': emergency.helperId,
              'responders': emergency.responders.map((k, v) => MapEntry(k, v.toMap())),
              'updatedAt': emergency.updatedAt.toIso8601String(),
              if (emergency.lastVictimLocation != null) 'lastVictimLocation': emergency.lastVictimLocation,
              if (emergency.lastHelperLocation != null) 'lastHelperLocation': emergency.lastHelperLocation,
            };
            await docRef.update(updateMap);
          }
        }

        await _localDb.markAsSynced(emergency.id);
        unawaited(AnalyticsService.instance.trackOfflineSyncTelemetry(
          emergencyId: emergency.id,
          retryCount: 0,
          syncLatencyMs: DateTime.now().difference(syncStart).inMilliseconds,
          success: true,
          terminalStatus: emergency.isTerminal ? emergency.status.name : null,
        ));
      } catch (e) {
        await _localDb.recordSyncFailure(emergency.id, e.toString());
        unawaited(AnalyticsService.instance.trackOfflineSyncTelemetry(
          emergencyId: emergency.id,
          retryCount: 1,
          syncLatencyMs: DateTime.now().difference(syncStart).inMilliseconds,
          success: false,
          terminalStatus: emergency.isTerminal ? emergency.status.name : null,
          errorCategory: 'firestore_sync_error',
        ));
      }
    }
  }

  void dispose() {
    _modeSub?.cancel();
    _activeService?.stop();
    _connectivityService.dispose();
  }
}
